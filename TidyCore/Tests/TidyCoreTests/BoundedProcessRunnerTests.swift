import Darwin
import Foundation
import Testing
@testable import TidyCore

private enum FixtureError: Error { case observationIncomplete, markerMissing }
private func fixtureEnvironment(root: URL) throws -> [String: String] {
    guard let inheritedHome = ProcessInfo.processInfo.environment["HOME"],
          !inheritedHome.isEmpty, inheritedHome.hasPrefix("/"), !inheritedHome.utf8.contains(0) else {
        throw FixtureError.observationIncomplete
    }
    return ["HOME": inheritedHome, "PATH": "/usr/bin:/bin", "TMPDIR": root.path]
}
private func requireOwnedStatus(_ session: ProcessSession) async throws -> Int32 {
    switch await session.observeOwnedExit(within: .seconds(6)) {
    case .reaped(let identity, let raw):
        try #require(session.identity == identity)
        return raw
    case .reapedWithoutIdentity(let pid, let raw):
        try #require(session.identity == nil && pid > 0)
        return raw
    case .unproven: throw FixtureError.observationIncomplete
    }
}
private func expectNormalExit(_ raw: Int32, code: Int32) {
    #expect((raw & 0x7f) == 0)
    #expect(((raw >> 8) & 0xff) == code)
}
private final class FoundationExitWitness: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var status: Int32?
    init(executable: URL, root: URL) throws {
        process.executableURL = executable
        process.arguments = ["coexist-seven", root.path]
        process.environment = try fixtureEnvironment(root: root)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Retain witness/process until real Foundation termination; timeout never kills it.
        process.terminationHandler = { [self] child in
            lock.lock()
            status = child.terminationReason == .exit ? child.terminationStatus : -1
            lock.unlock()
            child.terminationHandler = nil
        }
        do { try process.run() }
        catch { process.terminationHandler = nil; throw error }
    }
    func observed() -> Int32? { lock.lock(); defer { lock.unlock() }; return status }
    func exit(within timeout: Duration) async throws -> Int32 {
        let until = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < until {
            if let value = observed() { return value }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FixtureError.observationIncomplete
    }
}

private final class FixtureExitWatch {
    let identity: ProcessInstanceIdentity
    private let queue: Int32
    init(pid: Int32, executable: URL, parent: ProcessInstanceIdentity) throws {
        let captured = try ProcessIdentity.capture(pid: pid)
        guard captured.executablePath == executable.path, ProcessIdentity.matches(parent),
              try ProcessIdentity.parentPID(of: captured) == parent.pid else {
            throw FixtureError.observationIncomplete
        }
        let fd = kqueue()
        guard fd >= 0 else { throw FixtureError.observationIncomplete }
        var registration = Darwin.kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT), fflags: NOTE_EXIT, data: 0, udata: nil)
        guard kevent(fd, &registration, 1, nil, 0, nil) == 0,
              ProcessIdentity.matches(captured) else {
            close(fd); throw FixtureError.observationIncomplete
        }
        queue = fd
        identity = captured
    }
    deinit { close(queue) }
    func observeExit(within timeout: Duration) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            var result = Darwin.kevent()
            var immediate = timespec(tv_sec: 0, tv_nsec: 0)
            let count = kevent(queue, nil, 0, &result, 1, &immediate)
            if count == 1 {
                return result.ident == UInt(identity.pid) && result.filter == Int16(EVFILT_PROC)
                    && result.fflags & NOTE_EXIT != 0 && result.flags & UInt16(EV_ERROR) == 0
            }
            if count < 0 { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
private final class ProcessScratch: @unchecked Sendable {
    let root: URL
    let binary: URL
    private let inheritedHome: String
    private let lock = NSLock()
    private var sessions: [ProcessSession] = []
    private var watchers: [FixtureExitWatch] = []
    private var ambiguousLaunch = false
    private var unobservedDescendants = 0
    init() async throws {
        // Canonicalize only the known existing temporary base before UUID
        // allocation. Do not dilute production O_NOFOLLOW handling because
        // Foundation's resolvingSymlinksInPath can retain /var/folders.
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(canonical) }
        let artifactRoot = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
            .appendingPathComponent("tidy-t04-process-\(UUID())", isDirectory: true)
        root = artifactRoot.appendingPathComponent("run")
        let build = artifactRoot.appendingPathComponent("build")
        binary = build.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/T04ProcessFixture.c")
        let buildEnvironment = try fixtureEnvironment(root: build)
        inheritedHome = buildEnvironment["HOME"]!
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: ["-O0", "-Wall", source.path, "-o", binary.path],
            environment: buildEnvironment,
            kind: .readOnly, deadline: .seconds(30))
        let compiler = try await ProcessSession.launch(request, gate: ProcessJobGate(limit: 1))
        let output = await compiler.collect()
        // Evidence only; successful writes do not replace compiler/reap checks.
        // On any write error the root stays intact and the production session
        // retains its exact-child owner independently of this initializer.
        do {
            try output.stdout.bytes.write(to: build.appendingPathComponent("stdout.bin"))
            try output.stderr.bytes.write(to: build.appendingPathComponent("stderr.bin"))
        } catch {
            print("Compiler evidence write failed; preserved scratch: \(artifactRoot.path)")
            throw error
        }
        guard output.end == .exited(0) else {
            Issue.record("Fixture compilation failed; preserved scratch: \(artifactRoot.path)")
            throw CocoaError(.executableLoad)
        }
        print("Retained compiler artifacts (descendant tree not proven): \(build.path)")
    }
    private func add(_ session: ProcessSession, orphan: Bool) {
        lock.lock(); sessions.append(session)
        if orphan { unobservedDescendants += 1 }; lock.unlock()
    }
    private func markAmbiguousLaunch() { lock.lock(); ambiguousLaunch = true; lock.unlock() }
    func launch(_ request: ProcessRequest, gate: ProcessJobGate,
                identityCapture: ProcessIdentityCapture = .system) async throws -> ProcessSession {
        do {
            let session = try await ProcessSession.launch(request, gate: gate,
                                                          identityCapture: identityCapture)
            add(session, orphan: request.arguments.first == "orphan")
            return session
        } catch is CancellationError {
            throw CancellationError() // contract: only before actual spawn
        } catch { markAmbiguousLaunch(); throw error }
    }
    func registerOrphanBeforeParentExit(_ session: ProcessSession) async throws {
        try await waitFor("descendant.pid")
        let text = try String(contentsOf: root.appendingPathComponent("descendant.pid"), encoding: .utf8)
        guard let pid = Int32(text), pid > 0 else { throw FixtureError.observationIncomplete }
        let parent = try #require(session.identity)
        let watch = try FixtureExitWatch(pid: pid, executable: binary, parent: parent)
        retain(watch)
        try Data("observing".utf8).write(to: root.appendingPathComponent("descendant-observed"))
    }
    private func retain(_ watch: FixtureExitWatch) {
        lock.lock(); watchers.append(watch); unobservedDescendants -= 1; lock.unlock()
    }
    func preserveOnIncomplete() { markAmbiguousLaunch() }
    func environment(for root: URL) -> [String: String] {
        ["HOME": inheritedHome, "PATH": "/usr/bin:/bin", "TMPDIR": root.path]
    }
    func request(_ mode: String, _ kind: ProcessJobKind, seconds: Double = 5) -> ProcessRequest {
        ProcessRequest(executable: binary, arguments: [mode, root.path],
            environment: environment(for: root),
            kind: kind, deadline: .seconds(seconds))
    }
    func has(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }
    func waitFor(_ name: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !has(name), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard has(name) else { throw FixtureError.markerMissing }
    }
    private func tracked() -> ([ProcessSession], [FixtureExitWatch], Bool) {
        lock.lock(); defer { lock.unlock() }
        return (sessions, watchers, ambiguousLaunch || unobservedDescendants != 0)
    }
    func dispose() async throws {
        let (owned, descendants, incomplete) = tracked()
        var proven = !incomplete
        for session in owned {
            do { _ = try await requireOwnedStatus(session) }
            catch { proven = false }
        }
        for watch in descendants {
            let exited = (try? await watch.observeExit(within: .seconds(6))) ?? false
            proven = proven && exited
        }
        guard proven else {
            Issue.record("Fixture exit not proven; preserved run scratch: \(root.path)")
            throw FixtureError.observationIncomplete
        }
        try FileManager.default.removeItem(at: root)
    }
}
private func withProcessScratch(_ body: (ProcessScratch) async throws -> Void) async throws {
    let s = try await ProcessScratch()
    do { try await body(s) } catch { try await s.dispose(); throw error }
    try await s.dispose()
}
private actor QueueReceipt {
    enum Result: Equatable, Sendable { case granted(UUID), launched, cancelled, failed }
    private var result: Result?
    func record(_ value: Result) { result = value }
    func value() -> Result? { result }
}
private func waitForQueued(_ gate: ProcessJobGate, count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while ContinuousClock.now < deadline {
        if await gate.snapshot().queued == count { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw FixtureError.observationIncomplete
}
private func waitForReceipt(_ receipt: QueueReceipt) async throws -> QueueReceipt.Result {
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while ContinuousClock.now < deadline {
        if let value = await receipt.value() { return value }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw FixtureError.observationIncomplete
}
@Suite(.serialized) struct BoundedProcessRunnerTests {
    @Test func bothStreamsDrainWithBoundedRetention() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("flood", .readOnly),
                                                         gate: ProcessJobGate(limit: 1))
            let out = await session.collect()
            #expect(out.end == .exited(0))
            #expect(out.stdout.bytes.count == 1_048_576)
            #expect(out.stderr.bytes.count == 1_048_576)
            #expect(out.stdout.truncated && out.stderr.truncated)
            #expect(out.stdout.eofObserved && out.stderr.eofObserved)
        }
    }
    @Test func descendantOutlivesCLIAndPipeDeadline() async throws {
        try await withProcessScratch { s in
            let start = ContinuousClock.now
            let session = try await s.launch(s.request("orphan", .mutation, seconds: 0.4),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.registerOrphanBeforeParentExit(session)
            let out = await session.collect()
            #expect(out.end == .uncertainAndPossiblyRunning)
            #expect(start.duration(to: .now) < .seconds(1))
            #expect(!out.stdout.eofObserved || !out.stderr.eofObserved)
            try await s.waitFor("done") // real descendant survived its CLI, no signal
        }
    }
    @Test func mutatingTimeoutLeavesActualChildRunning() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("slow", .mutation, seconds: 0.2),
                                                         gate: ProcessJobGate(limit: 1))
            let out = await session.collect()
            #expect(out.end == .uncertainAndPossiblyRunning)
            #expect(session.observationSnapshot().signalAttempts == 0)
            // First executable entry need not occur within the command's
            // 200ms deadline. Observe actual post-timeout liveness separately.
            try await s.waitFor("alive")
            #expect(s.has("alive") && !s.has("done"))
            let identity = try #require(session.identity)
            #expect(ProcessIdentity.matches(identity))
            try await s.waitFor("done")
            expectNormalExit(try await requireOwnedStatus(session), code: 0)
            #expect(session.observationSnapshot().signalAttempts == 0)
        }
    }
    @Test func abandonmentBeforeReleaseDoesNotPerformFixtureEffect() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("gated", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.waitFor("ready")
            #expect(!s.has("effect"))
            session.abandonWithoutSignal()
            expectNormalExit(try await requireOwnedStatus(session), code: 96)
            #expect(!s.has("effect"))
        }
    }
    @Test func abandonmentAfterReleaseDoesNotEraseSurvivingEffect() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("gated", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.waitFor("ready")
            try session.releaseStartByte()
            try await s.waitFor("effect")
            session.abandonWithoutSignal()
            try await s.waitFor("done")
            #expect(s.has("effect"))
        }
    }
    @Test func realSurvivingChildKeepsReopenedCoordinatorBlocked() async throws {
        try await withProcessScratch { s in
            let directory = s.root.appendingPathComponent("journal")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let store = try MutationAdmissionStore(directory: directory)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: directory))
            let run = UUID(), operation = UUID()
            try journal.append(JournalEvent(runID: run, sequence: 1, phase: .planned,
                operationID: nil, status: nil, reason: nil))
            try journal.append(JournalEvent(runID: run, sequence: 2, phase: .confirmed,
                operationID: nil, status: nil, reason: nil))
            var metadata = stat()
            guard lstat(s.binary.path, &metadata) == 0 else { throw CocoaError(.fileReadUnknown) }
            let boot = try ProcessIdentity.capture(pid: getpid()).bootID
            try journal.persistIntent(PendingEffectIntent(runID: run, operationID: operation,
                adapterID: "untrusted-fixture-not-a-capability", bootID: boot,
                executablePath: s.binary.path, executableDevice: UInt64(metadata.st_dev),
                executableInode: UInt64(metadata.st_ino), childPID: nil, childStartSeconds: nil,
                childStartMicroseconds: nil, phase: .prepared))
            let session = try await s.launch(s.request("gated", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.waitFor("ready")
            let child = try #require(session.identity)
            try journal.recordChild(PendingEffectIntent(runID: run, operationID: operation,
                adapterID: "untrusted-fixture-not-a-capability", bootID: child.bootID,
                executablePath: child.executablePath, executableDevice: child.executableDevice,
                executableInode: child.executableInode, childPID: child.pid,
                childStartSeconds: child.startSeconds, childStartMicroseconds: child.startMicroseconds,
                phase: .prepared))
            try session.releaseStartByte()
            try await s.waitFor("effect")
            session.abandonWithoutSignal()
            store.release() // simulate owner loss; real child has not completed
            let coordinator = ExecutionCoordinator(environment: CleanEnvironment(
                homeDirectory: s.root.path, detectedTools: [], protectedRoots: []),
                journalDirectory: directory)
            #expect(await coordinator.mutationAdmission() == .uncertainAndPossiblyRunning)
            try await s.waitFor("done")
            // Even actual completion/PID disappearance cannot clear an unknown adapter.
            #expect(await coordinator.mutationAdmission() == .uncertainAndPossiblyRunning)
        }
    }
    @Test func queuedCancellationNeverLaunchesChild() async throws {
        try await withProcessScratch { s in
            let gate = try ProcessJobGate(limit: 1)
            let reservation = try await gate.acquire()
            let receipt = QueueReceipt()
            let queued = Task {
                do {
                    _ = try await s.launch(s.request("slow", .readOnly), gate: gate)
                    await receipt.record(.launched)
                } catch is CancellationError {
                    // Pre-spawn only; the held first lease and absent marker
                    // below exercise this exact no-child contract.
                    await receipt.record(.cancelled)
                }
                catch { await receipt.record(.failed) }
            }
            do {
                try await waitForQueued(gate, count: 1) // prove it actually queued
                queued.cancel()
                let result = try await waitForReceipt(receipt)
                try #require(result == .cancelled)
                await queued.value // first reservation is STILL held
                #expect(await gate.snapshot().queued == 0)
                #expect(await gate.snapshot().active == 1)
                #expect(!s.has("alive"))
                await gate.release(reservation)
                let next = try await s.launch(s.request("slow", .readOnly), gate: gate)
                #expect(await next.collect().end == .exited(0))
            } catch {
                s.preserveOnIncomplete()
                queued.cancel()
                await gate.release(reservation)
                throw error
            }
        }
    }
    @Test func releasedSlotIsTransferredBeforeWaiterResumes() async throws {
        let gate = try ProcessJobGate(limit: 1)
        let first = try await gate.acquire()
        let queued = Task { try await gate.acquire() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await gate.snapshot().queued != 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await gate.snapshot().queued == 1)
        await gate.release(first)
        let newcomer = Task { try await gate.acquire() }
        let second = try await queued.value
        let nextDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await gate.snapshot().queued != 1, ContinuousClock.now < nextDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await gate.snapshot().active == 1)
        #expect(await gate.snapshot().queued == 1)
        await gate.release(second)
        let third = try await newcomer.value
        await gate.release(third)
        #expect(await gate.snapshot().active == 0)
    }
    @Test func transferRacingCancellationDoesNotLeakOrDuplicateReservation() async throws {
        let gate = try ProcessJobGate(limit: 1)
        for _ in 0..<25 {
            let first = try await gate.acquire()
            let receipt = QueueReceipt()
            let queued = Task {
                do { await receipt.record(.granted(try await gate.acquire())) }
                catch is CancellationError { await receipt.record(.cancelled) }
                catch { await receipt.record(.failed) }
            }
            try await waitForQueued(gate, count: 1)
            let release = Task { await gate.release(first) }
            let cancel = Task { queued.cancel() }
            await release.value; await cancel.value
            let result = try await waitForReceipt(receipt)
            await queued.value
            switch result {
            case .granted(let reservation): await gate.release(reservation)
            case .cancelled: break
            case .launched, .failed: Issue.record("Invalid acquisition outcome")
            }
            #expect(await gate.snapshot().active == 0)
            #expect(await gate.snapshot().queued == 0)
            let next = try await gate.acquire()
            await gate.release(next)
        }
    }
    @Test func existingPublicRunnerUsesAggregateReplacementGate() async throws {
        let jobs = (0..<4).map { _ in
            Task {
                try await ProcessRunner.run(
                    executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["0.25"], timeout: 2)
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            let snapshot = await ProcessRunner.jobSnapshot()
            if snapshot.queued > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let snapshot = await ProcessRunner.jobSnapshot()
        #expect(snapshot.active >= 1 && snapshot.active <= 2)
        #expect(snapshot.queued >= 1)
        for job in jobs { #expect(try await job.value.succeeded) }
        // Global quiescence is intentionally not asserted here: unrelated
        // declared timeout/discovery readers may still own this same gate.
        // Exact 20-cycle lease/descriptor return is isolated in
        // ProcessBudgetIntegrationTests.
    }
    @Test func reusedPIDShapeCannotMatchActualIdentity() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("slow", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            let actual = try #require(session.identity)
            let mismatched = ProcessInstanceIdentity(bootID: actual.bootID, pid: actual.pid,
                startSeconds: actual.startSeconds + 1, startMicroseconds: actual.startMicroseconds,
                executablePath: actual.executablePath, executableDevice: actual.executableDevice,
                executableInode: actual.executableInode)
            #expect(ProcessIdentity.matches(actual))
            #expect(!ProcessIdentity.matches(mismatched))
            _ = await session.collect()
        }
    }
    @Test(arguments: [("exit-zero", Int32(0)), ("exit-seven", Int32(7))])
    func identityCaptureFailureStillReapsActualFastChild(_ item: (String, Int32)) async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request(item.0, .readOnly),
                gate: ProcessJobGate(limit: 1), identityCapture: .failClosed)
            #expect(session.identity == nil)
            let output = await session.collect()
            #expect(output.identity == nil && output.end == .exited(item.1))
            let first = await session.observeOwnedExit(within: .seconds(6))
            guard case .reapedWithoutIdentity(let pid, let raw) = first else {
                throw FixtureError.observationIncomplete
            }
            #expect(pid > 0)
            expectNormalExit(raw, code: item.1)
            #expect(await session.observeOwnedExit(within: .zero) == first)
            #expect(session.observationSnapshot().consumingReapCount == 1)
            #expect(session.observationSnapshot().signalAttempts == 0)
        }
    }
    @Test func identityCaptureFailureCannotSignalAtDeadline() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("slow", .readOnly, seconds: 0.2),
                gate: ProcessJobGate(limit: 1), identityCapture: .failClosed)
            let output = await session.collect()
            #expect(output.end == .readOnlyTimedOut && output.identity == nil)
            #expect(session.observationSnapshot().signalAttempts == 0)
            try await s.waitFor("done")
            expectNormalExit(try await requireOwnedStatus(session), code: 0)
            #expect(session.observationSnapshot().signalAttempts == 0)
            #expect(session.observationSnapshot().consumingReapCount == 1)
        }
    }
    @Test(arguments: [("exit-zero", Int32(0)), ("exit-seven", Int32(7))])
    func actualFastExitIsCached(_ item: (String, Int32)) async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request(item.0, .readOnly), gate: ProcessJobGate(limit: 1))
            let output = await session.collect()
            #expect(output.end == .exited(item.1))
            #expect(output.identity == session.identity)
            #expect(output.stdout.eofObserved && output.stderr.eofObserved)
            #expect(output.stdout.bytes.isEmpty && output.stderr.bytes.isEmpty)
            #expect(!output.stdout.truncated && !output.stderr.truncated)
            let first = await session.observeOwnedExit(within: .seconds(6))
            expectNormalExit(try await requireOwnedStatus(session), code: item.1)
            #expect(await session.observeOwnedExit(within: .zero) == first)
            let snapshot = session.observationSnapshot()
            #expect(snapshot.ownedExit == first && snapshot.consumingReapCount == 1)
            #expect(snapshot.signalAttempts == 0)
            let legacy = ProcessRunner.legacyOutput(output)
            #expect(legacy.exitCode == item.1 && legacy.outputComplete && !legacy.timedOut)
            #expect(legacy.succeeded == (item.1 == 0))
        }
    }
    @Test func reapedChildCannotSignalAtLaterDeadline() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("exit-zero", .readOnly, seconds: 0.5),
                                             gate: ProcessJobGate(limit: 1))
            #expect(await session.collect().end == .exited(0))
            _ = try await requireOwnedStatus(session)
            let before = session.observationSnapshot()
            try #require(before.consumingReapCount == 1)
            session.abandonWithoutSignal()
            try await Task.sleep(for: .milliseconds(600))
            #expect(await session.observeOwnedExit(within: .zero) == before.ownedExit)
            let after = session.observationSnapshot()
            #expect(after.consumingReapCount == 1 && after.signalAttempts == 0)
            #expect(await session.collect().end == .exited(0))
        }
    }
    @Test(arguments: ["text", "invalid-stdout", "invalid-stderr", "flood"])
    func realOutputIsBoundedAndTruthful(_ mode: String) async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request(mode, .readOnly, seconds: 15),
                                             gate: ProcessJobGate(limit: 1))
            let captured = await session.collect()
            #expect(captured.end == .exited(0))
            #expect(captured.stdout.eofObserved && captured.stderr.eofObserved)
            #expect(captured.stdout.bytes.count <= 1_048_576 && captured.stderr.bytes.count <= 1_048_576)
            let output = ProcessRunner.legacyOutput(captured)
            #expect(output.exitCode == 0 && !output.timedOut)
            if mode == "text" {
                #expect(output.outputComplete && output.succeeded)
                #expect(output.standardOutput == "out\n" && output.standardError == "err\n")
            } else {
                #expect(!output.outputComplete && !output.succeeded)
                #expect(output.standardOutput.isEmpty && output.standardError.isEmpty)
            }
            if mode == "flood" {
                #expect(captured.stdout.bytes.count == 1_048_576 && captured.stderr.bytes.count == 1_048_576)
                #expect(captured.stdout.truncated && captured.stderr.truncated)
            } else { #expect(!captured.stdout.truncated && !captured.stderr.truncated) }
            if mode == "invalid-stdout" { #expect(captured.stdout.bytes == Data([0xC3, 0x28])) }
            if mode == "invalid-stderr" { #expect(captured.stderr.bytes == Data([0xFF])) }
            expectNormalExit(try await requireOwnedStatus(session), code: 0)
        }
    }
    @Test func inheritedPipeDeadlineIsNotCommandTimeout() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("orphan", .readOnly, seconds: 8),
                                             gate: ProcessJobGate(limit: 1))
            try await s.registerOrphanBeforeParentExit(session)
            let start = ContinuousClock.now
            let captured = await session.collect()
            #expect(start.duration(to: .now) < .seconds(1))
            #expect(captured.end == .exited(0))
            #expect(!captured.stdout.eofObserved || !captured.stderr.eofObserved)
            let output = ProcessRunner.legacyOutput(captured)
            #expect(!output.outputComplete && !output.succeeded && !output.timedOut)
            #expect(output.standardOutput.isEmpty && output.standardError.isEmpty)
            try await s.waitFor("done") // dispose still requires registered NOTE_EXIT
        }
    }
    @Test func publicRunnerUsesTruthfulMappingForDeclaredDirectChildren() async throws {
        let text = try await ProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["out"], timeout: 5)
        #expect(text.succeeded && text.outputComplete && text.exitCode == 0)
        #expect(text.standardOutput == "out\n" && text.standardError.isEmpty)

        let failure = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], timeout: 5)
        #expect(!failure.succeeded && failure.outputComplete && failure.exitCode != 0)
    }
    @Test func actualCommandDeadlineIsTimedOut() async throws {
        let start = ContinuousClock.now
        let output = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"], timeout: 0.2)
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(output.timedOut && !output.succeeded)
        // No assertion that timeout kills a process tree or implies missing EOF.
    }
    @Test(arguments: [true, false])
    func foundationAndPOSIXChildrenKeepDistinctExitOwnership(foundationFirst: Bool) async throws {
        let s = try await ProcessScratch()
        defer { print("Retained Foundation coexistence evidence: \(s.root.path)") }
        try ProcessSession.validateChildWaitDisposition()
        let foundation: FoundationExitWitness
        let session: ProcessSession
        if foundationFirst {
            foundation = try FoundationExitWitness(executable: s.binary, root: s.root)
            try ProcessSession.validateChildWaitDisposition()
            session = try await s.launch(s.request("slow", .readOnly, seconds: 8),
                                         gate: ProcessJobGate(limit: 1))
        } else {
            session = try await s.launch(s.request("slow", .readOnly, seconds: 8),
                                         gate: ProcessJobGate(limit: 1))
            try ProcessSession.validateChildWaitDisposition()
            foundation = try FoundationExitWitness(executable: s.binary, root: s.root)
        }
        #expect(await session.collect().end == .exited(0))
        expectNormalExit(try await requireOwnedStatus(session), code: 0)
        #expect(try await foundation.exit(within: .seconds(6)) == 7)
        let snapshot = session.observationSnapshot()
        #expect(snapshot.consumingReapCount == 1 && snapshot.signalAttempts == 0)
        try ProcessSession.validateChildWaitDisposition()
        // No wait-any, no direct consuming wait outside the production owner.
    }
    @Test func incompleteMappingNeverFabricatesTimeout() {
        // Pure representation test: NOT executed-child or recovery evidence.
        let empty = CapturedStream(bytes: Data(), truncated: false, eofObserved: true)
        let cases = [
            CapturedStream(bytes: Data("prefix".utf8), truncated: false, eofObserved: false),
            CapturedStream(bytes: Data("prefix".utf8), truncated: true, eofObserved: true),
            CapturedStream(bytes: Data([0xFF]), truncated: false, eofObserved: true)
        ]
        for stream in cases {
            for stdout in [true, false] {
                let output = ProcessRunner.legacyOutput(BoundedProcessOutput(end: .exited(0),
                    stdout: stdout ? stream : empty, stderr: stdout ? empty : stream, identity: nil))
                #expect(!output.outputComplete && !output.timedOut && !output.succeeded)
                #expect(output.standardOutput.isEmpty && output.standardError.isEmpty)
            }
        }
        let timed = ProcessRunner.legacyOutput(BoundedProcessOutput(end: .readOnlyTimedOut,
            stdout: empty, stderr: empty, identity: nil))
        #expect(timed.timedOut && !timed.succeeded && timed.outputComplete)
    }

}
