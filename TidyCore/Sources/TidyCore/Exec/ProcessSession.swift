import Darwin
import Dispatch
import Foundation

enum ProcessJobKind: Sendable { case readOnly, mutation }
struct ProcessRequest: Sendable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let kind: ProcessJobKind
    let deadline: Duration
}
enum ProcessEnd: Equatable, Sendable {
    case exited(Int32), cancelledBeforeStart, readOnlyTimedOut, uncertainAndPossiblyRunning
}
struct CapturedStream: Sendable {
    let bytes: Data
    let truncated: Bool
    let eofObserved: Bool
}
struct BoundedProcessOutput: Sendable {
    let end: ProcessEnd
    let stdout: CapturedStream
    let stderr: CapturedStream
    let identity: ProcessInstanceIdentity?
}
enum OwnedProcessExit: Equatable, Sendable {
    case reaped(ProcessInstanceIdentity, Int32)
    case reapedWithoutIdentity(pid: Int32, status: Int32)
    case unproven
}
enum ProcessIdentityCapture: Sendable { case system, failClosed }
struct ProcessSessionObservation: Sendable {
    let ownedExit: OwnedProcessExit
    let signalAttempts: Int
    let consumingReapCount: Int
}

/// A detected foreign/auto reaper makes subsequent dispatch unsupported.
private final class ChildWaitCompatibility: @unchecked Sendable {
    static let shared = ChildWaitCompatibility()
    private let lock = NSLock()
    private var lostOwnership = false
    func recordLoss() { lock.lock(); lostOwnership = true; lock.unlock() }
    func validate() throws {
        lock.lock(); let lost = lostOwnership; lock.unlock()
        guard !lost else { throw POSIXError(.ECHILD) }
        var action = sigaction()
        guard sigaction(SIGCHLD, nil, &action) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handler = unsafeBitCast(action.__sigaction_u.__sa_handler, to: UInt.self)
        guard handler != 1, action.sa_flags & SA_NOCLDWAIT == 0 else {
            throw POSIXError(.ENOTSUP)
        }
    }
}

/// The sole consuming wait and sole signal site share this synchronous lock.
/// waitid observes without consuming and never holds this lock while blocking.
private final class DirectChildOwnership: @unchecked Sendable {
    let pid: Int32
    let identity: ProcessInstanceIdentity?
    private let lock = NSLock()
    private var exit: OwnedProcessExit = .unproven
    private var observedExit = false
    private var ownershipError = false
    private var reapCount = 0
    private var signals = 0
    private var controlFD: Int32

    init(pid: Int32, identity: ProcessInstanceIdentity?, controlFD: Int32) {
        self.pid = pid; self.identity = identity; self.controlFD = controlFD
    }

    func observeAndReap() -> Int32? {
        var info = siginfo_t()
        var result: Int32
        repeat {
            info = siginfo_t()
            result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT)
        } while result == -1 && errno == EINTR
        lock.lock()
        defer { lock.unlock() }
        guard result == 0, info.si_pid == pid, info.si_pid > 0,
              [CLD_EXITED, CLD_KILLED, CLD_DUMPED].contains(info.si_code) else {
            ownershipError = true
            ChildWaitCompatibility.shared.recordLoss()
            return nil
        }
        observedExit = true
        var raw: Int32 = 0
        var consumed: pid_t
        repeat { consumed = waitpid(pid, &raw, WNOHANG) } while consumed == -1 && errno == EINTR
        guard consumed == pid else {
            ownershipError = true
            ChildWaitCompatibility.shared.recordLoss()
            return nil
        }
        reapCount += 1
        if let identity { exit = .reaped(identity, raw) }
        else { exit = .reapedWithoutIdentity(pid: pid, status: raw) }
        return raw
    }

    func terminateReadOnlyIfOwned() {
        lock.lock()
        defer { lock.unlock() }
        guard reapCount == 0, !observedExit, !ownershipError, signals == 0,
              let identity, (try? ChildWaitCompatibility.shared.validate()) != nil,
              ProcessIdentity.matches(identity) else { return }
        // The unreaped direct child reserves its PID even if it exits during
        // the identity probe. The observer cannot consume it until unlock.
        signals += 1
        _ = kill(identity.pid, SIGTERM)
    }

    func releaseStartByte() throws {
        lock.lock()
        defer { lock.unlock() }
        guard controlFD >= 0, reapCount == 0, !observedExit, !ownershipError else {
            throw POSIXError(.EPIPE)
        }
        var byte: UInt8 = 71
        let written = write(controlFD, &byte, 1)
        guard written == 1 else {
            // No queued/deferred retry: this exact release either happened or failed.
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        close(controlFD); controlFD = -1
    }

    func closeControl() {
        lock.lock()
        if controlFD >= 0 { close(controlFD); controlFD = -1 }
        lock.unlock()
    }

    func snapshot() -> ProcessSessionObservation {
        lock.lock(); defer { lock.unlock() }
        return ProcessSessionObservation(ownedExit: exit, signalAttempts: signals,
                                         consumingReapCount: reapCount)
    }
}

/// Internal process mechanism, not an effect-registration or cleanup API.
final class ProcessSession: @unchecked Sendable {
    private final class Stream {
        var fd: Int32
        var source: DispatchSourceRead?
        var bytes = Data()
        var truncated = false
        var eof = false
        var cancelled = false
        var closed = false
        init(fd: Int32) { self.fd = fd }
        var captured: CapturedStream {
            CapturedStream(bytes: bytes, truncated: truncated, eofObserved: eof)
        }
    }
    private struct ExitWaiter {
        let continuation: CheckedContinuation<OwnedProcessExit, Never>
        let timeout: DispatchWorkItem
    }
    private let owner: DirectChildOwnership
    private let kind: ProcessJobKind
    private let gate: ProcessJobGate
    private let reservation: UUID
    private let queue = DispatchQueue(label: "Tidy.process.observation", qos: .utility)
    private let stdout: Stream
    private let stderr: Stream
    // Everything below is confined to queue. Self retention is intentional:
    // callers/cancelled collectors cannot discard unreaped or uncertain work.
    private var retainedSession: ProcessSession?
    private var end: ProcessEnd?
    private var output: BoundedProcessOutput?
    private var collectors: [CheckedContinuation<BoundedProcessOutput, Never>] = []
    private var exitWaiters: [UUID: ExitWaiter] = [:]
    private var deadlineWork: DispatchWorkItem?
    private var drainWork: DispatchWorkItem?
    private var reservationReleased = false
    private var releaseCompleted = false

    var identity: ProcessInstanceIdentity? { owner.identity }

    private init(pid: Int32, identity: ProcessInstanceIdentity?, kind: ProcessJobKind,
                 controlFD: Int32, stdoutFD: Int32, stderrFD: Int32,
                 gate: ProcessJobGate, reservation: UUID) {
        owner = DirectChildOwnership(pid: pid, identity: identity, controlFD: controlFD)
        self.kind = kind; self.gate = gate; self.reservation = reservation
        stdout = Stream(fd: stdoutFD); stderr = Stream(fd: stderrFD)
    }

    static func validateChildWaitDisposition() throws { try ChildWaitCompatibility.shared.validate() }

    static func launch(_ request: ProcessRequest, gate: ProcessJobGate,
                       identityCapture: ProcessIdentityCapture = .system) async throws -> ProcessSession {
        let reservation = try await gate.acquire()
        do {
            try Task.checkCancellation()
            let session = try spawn(request, gate: gate, reservation: reservation,
                                    identityCapture: identityCapture)
            // Once spawned there is no throwing path: ownership must reach the
            // caller even when cancellation raced with spawn or fast exit.
            if Task.isCancelled { session.abandonWithoutSignal() }
            return session
        } catch {
            await gate.release(reservation)
            throw error
        }
    }

    private static func spawn(_ request: ProcessRequest, gate: ProcessJobGate, reservation: UUID,
                              identityCapture: ProcessIdentityCapture) throws -> ProcessSession {
        guard request.executable.isFileURL, request.executable.path.hasPrefix("/"),
              !request.executable.path.utf8.contains(0),
              request.arguments.allSatisfy({ !$0.utf8.contains(0) }),
              request.environment.allSatisfy({ !$0.key.isEmpty && !$0.key.contains("=")
                  && !$0.key.utf8.contains(0) && !$0.value.utf8.contains(0) }) else {
            throw POSIXError(.EINVAL)
        }
        try validateChildWaitDisposition()
        var ownedFDs: [Int32] = []
        defer { for fd in ownedFDs { close(fd) } }
        func checked(_ result: Int32) throws {
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
        }
        func pipePair() throws -> (Int32, Int32) {
            var pair: [Int32] = [-1, -1]
            guard pipe(&pair) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            ownedFDs.append(contentsOf: pair)
            for index in pair.indices {
                if pair[index] < 3 {
                    let replacement = fcntl(pair[index], F_DUPFD_CLOEXEC, 3)
                    guard replacement >= 3 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    let old = pair[index]
                    ownedFDs.removeAll { $0 == old }; close(old)
                    pair[index] = replacement; ownedFDs.append(replacement)
                }
                guard fcntl(pair[index], F_SETFD, FD_CLOEXEC) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            return (pair[0], pair[1])
        }
        let control = try pipePair(), out = try pipePair(), err = try pipePair()
        for fd in [control.1, out.0, err.0] {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        guard fcntl(control.1, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var actions: posix_spawn_file_actions_t?
        try checked(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        for (source, destination) in [(control.0, STDIN_FILENO), (out.1, STDOUT_FILENO), (err.1, STDERR_FILENO)] {
            try checked(posix_spawn_file_actions_adddup2(&actions, source, destination))
        }
        for fd in ownedFDs { try checked(posix_spawn_file_actions_addclose(&actions, fd)) }
        var attributes: posix_spawnattr_t?
        try checked(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)))
        let strings = [request.executable.path] + request.arguments
        let environment = request.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var argv = strings.map { strdup($0) }
        var envp = environment.map { strdup($0) }
        defer { for pointer in argv { free(pointer) }; for pointer in envp { free(pointer) } }
        guard argv.allSatisfy({ $0 != nil }), envp.allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        argv.append(nil); envp.append(nil)
        try Task.checkCancellation()
        var pid: pid_t = 0
        let spawned = request.executable.withUnsafeFileSystemRepresentation { path in
            posix_spawn(&pid, path!, &actions, &attributes, &argv, &envp)
        }
        try checked(spawned)
        // From here on all paths return retained ownership, never throw.
        for fd in [control.0, out.1, err.1] { close(fd) }
        ownedFDs.removeAll()
        let identity = identityCapture == .system ? try? ProcessIdentity.capture(pid: pid) : nil
        let session = ProcessSession(pid: pid, identity: identity, kind: request.kind,
            controlFD: control.1, stdoutFD: out.0, stderrFD: err.0, gate: gate, reservation: reservation)
        session.start(deadline: request.deadline)
        return session
    }

    private static func dispatchDelay(_ duration: Duration) -> Double {
        let parts = duration.components
        return max(0, Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }

    private func start(deadline: Duration) {
        queue.sync {
            retainedSession = self
            install(stdout); install(stderr)
            let timer = DispatchWorkItem { [weak self] in self?.deadlineReached() }
            deadlineWork = timer
            queue.asyncAfter(deadline: .now() + Self.dispatchDelay(deadline), execute: timer)
        }
        // A private blocking observer per admitted job, not the cooperative
        // executor and not a periodic polling thread. It retains this session.
        DispatchQueue(label: "Tidy.process.owned-exit", qos: .utility).async { [self] in
            let raw = owner.observeAndReap()
            queue.async { [self] in childObservationFinished(raw) }
        }
    }

    private func install(_ stream: Stream) {
        let source = DispatchSource.makeReadSource(fileDescriptor: stream.fd, queue: queue)
        stream.source = source
        source.setEventHandler { [weak self] in self?.drain(stream) }
        source.setCancelHandler { [self] in
            // Only cancellation owns close: no event handler can still read
            // this descriptor when it is freed for reuse by another session.
            close(stream.fd); stream.fd = -1; stream.closed = true; stream.source = nil
            finishIfReady()
        }
        source.resume()
    }

    private func drain(_ stream: Stream) {
        guard !stream.cancelled else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var remaining = 65_536
        for _ in 0..<4 {
            let count = read(stream.fd, &buffer, min(buffer.count, remaining))
            if count > 0 {
                let available = 1_048_576 - stream.bytes.count
                stream.bytes.append(contentsOf: buffer.prefix(min(available, count)))
                if count > available { stream.truncated = true }
                remaining -= count
                if remaining == 0 { return }
            } else if count == 0 {
                stream.eof = true; cancel(stream); return
            } else if errno == EAGAIN || errno == EWOULDBLOCK { return }
            else if errno != EINTR { cancel(stream); return }
        }
    }

    private func cancel(_ stream: Stream) {
        guard !stream.cancelled else { return }
        stream.cancelled = true; stream.source?.cancel()
    }

    private func scheduleDrainDeadline() {
        guard drainWork == nil else { return }
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cancel(self.stdout); self.cancel(self.stderr)
            self.finishIfReady()
        }
        drainWork = timer
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: timer)
    }

    private func childObservationFinished(_ raw: Int32?) {
        let exit = owner.snapshot().ownedExit
        for waiter in exitWaiters.values {
            waiter.timeout.cancel(); waiter.continuation.resume(returning: exit)
        }
        exitWaiters.removeAll()
        if end == nil {
            if kind == .readOnly, let raw {
                end = .exited(raw & 0x7f == 0 ? (raw >> 8) & 0xff : -1)
            } else { end = .uncertainAndPossiblyRunning }
        }
        deadlineWork?.cancel(); deadlineWork = nil
        scheduleDrainDeadline()
        finishIfReady()
    }

    private func deadlineReached() {
        guard end == nil, output == nil else { return }
        // An already consumed exit may be waiting for its queue callback.
        if owner.snapshot().consumingReapCount == 1 { return }
        if kind == .readOnly {
            end = .readOnlyTimedOut
            owner.terminateReadOnlyIfOwned()
            scheduleDrainDeadline()
        } else {
            end = .uncertainAndPossiblyRunning
            cancel(stdout); cancel(stderr)
        }
        owner.closeControl()
        finishIfReady()
    }

    private func finishIfReady() {
        guard let end, stdout.closed, stderr.closed else { return }
        deadlineWork?.cancel(); deadlineWork = nil
        drainWork?.cancel(); drainWork = nil
        owner.closeControl()
        if output == nil {
            output = BoundedProcessOutput(end: end, stdout: stdout.captured,
                                          stderr: stderr.captured, identity: identity)
        }
        // A timeout/abandon does not release an unreaped child. Mutation
        // reservations intentionally remain held pending higher recovery.
        if kind == .readOnly, owner.snapshot().consumingReapCount == 1, !reservationReleased {
            reservationReleased = true
            let pending = collectors; collectors.removeAll()
            let completed = output!
            Task { [self] in
                await gate.release(reservation)
                queue.async { [self] in
                    releaseCompleted = true
                    retainedSession = nil
                    for continuation in pending { continuation.resume(returning: completed) }
                    for continuation in collectors { continuation.resume(returning: completed) }
                    collectors.removeAll()
                }
            }
        } else if !reservationReleased || releaseCompleted {
            for continuation in collectors { continuation.resume(returning: output!) }
            collectors.removeAll()
        }
    }

    func collect() async -> BoundedProcessOutput {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    if let output, !reservationReleased || releaseCompleted {
                        continuation.resume(returning: output)
                    }
                    else { collectors.append(continuation) }
                }
            }
        } onCancel: { self.abandonWithoutSignal() }
    }

    func releaseStartByte() throws { try owner.releaseStartByte() }

    func abandonWithoutSignal() {
        owner.closeControl()
        queue.async { [self] in
            guard output == nil else { return }
            if end == nil { end = .uncertainAndPossiblyRunning }
            deadlineWork?.cancel(); deadlineWork = nil
            cancel(stdout); cancel(stderr)
            finishIfReady()
        }
    }

    func observeOwnedExit(within timeout: Duration) async -> OwnedProcessExit {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let snapshot = owner.snapshot()
                if snapshot.consumingReapCount == 1 || timeout <= .zero {
                    continuation.resume(returning: snapshot.ownedExit)
                    return
                }
                let id = UUID()
                let timer = DispatchWorkItem { [weak self] in
                    guard let self, let waiter = self.exitWaiters.removeValue(forKey: id) else { return }
                    waiter.continuation.resume(returning: self.owner.snapshot().ownedExit)
                }
                exitWaiters[id] = ExitWaiter(continuation: continuation, timeout: timer)
                queue.asyncAfter(deadline: .now() + Self.dispatchDelay(timeout), execute: timer)
            }
        }
    }

    func observationSnapshot() -> ProcessSessionObservation { owner.snapshot() }
}
