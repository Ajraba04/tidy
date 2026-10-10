import Darwin
import Foundation
import CryptoKit

/// An observation from an owned fake peer, never provider acceptance. Only the
/// protocol below can construct it; the journal verifier separately validates
/// its complete binding before persisting any terminal proof.
struct BoundDockerServiceReceipt: Sendable {
    enum Kind: String, Codable, Sendable { case removed, refused, alreadyAbsent }
    let binding: ManualServiceEffectBinding
    let runID: UUID
    let operationID: UUID
    let kind: Kind
    let requestDigest: Data
    let responseStatus: Int
    let responseBodyDigest: Data
    let responseMessage: String?
    let postconditionStatus: Int?
    let postconditionBodyDigest: Data?
    let postconditionMessage: String?
    let observedPeer: ProcessInstanceIdentity
    let observedSocket: LocalSocketApproval

    fileprivate init(permit: ManualServiceDispatchPermit, kind: Kind, request: Data,
                     response: DockerHTTPResponse, responseMessage: String?,
                     postcondition: DockerHTTPResponse?, postconditionMessage: String?,
                     peer: ProcessInstanceIdentity, socket: LocalSocketApproval) {
        binding = permit.binding; runID = permit.runID; operationID = permit.operationID
        self.kind = kind; requestDigest = Data(SHA256.hash(data: request))
        responseStatus = response.status; responseBodyDigest = Data(SHA256.hash(data: response.body))
        self.responseMessage = responseMessage; postconditionStatus = postcondition?.status
        postconditionBodyDigest = postcondition.map { Data(SHA256.hash(data: $0.body)) }
        self.postconditionMessage = postconditionMessage
        observedPeer = peer; observedSocket = socket
    }
}

/// Typed reads only. Neither a connected socket nor a response grants service
/// provider acceptance, mutation authority, or a durable effect permit.
enum LocalDockerReadQuery: Sendable {
    case version
    case info(apiVersion: String)
    case inspectContainer(apiVersion: String, id: String)

    fileprivate func encoded() throws -> Data {
        switch self {
        case .version: return DockerHTTPRequest.version()
        case .info(let version): return try DockerHTTPRequest.info(apiVersion: version)
        case .inspectContainer(let version, let id):
            return try DockerHTTPRequest.inspectContainer(apiVersion: version, id: id)
        }
    }
}

enum LocalDockerTransportError: Error, Equatable {
    case busy, closed, cancelled, deadline, invalidDeadline
    case socketIdentityChanged, peerIdentityChanged, connectionFailed
    case disconnected, truncated, unsolicitedBytes, invalidResponse
}

actor LocalDockerHTTPConnection {
    private let worker: LocalDockerSocketWorker
    private var inFlight = false
    private var closed = false
    private var removalAttempted = false

    private init(worker: LocalDockerSocketWorker) { self.worker = worker }

    /// Internal fixture entry only. No production provider factory exists yet.
    /// Matching this identity proves the local peer instance, not that it is
    /// an accepted Docker provider. Tests use an owned same-process Unix server.
    static func connectForTesting(approval: LocalSocketApproval,
                                  expectedPeer: ProcessInstanceIdentity,
                                  timeout: Duration = .seconds(2)) async throws -> LocalDockerHTTPConnection {
        // This factory is deliberately incapable of binding an actual Docker
        // daemon, even when its socket and peer metadata otherwise validate.
        guard expectedPeer.pid == getpid() else { throw LocalDockerTransportError.peerIdentityChanged }
        let worker = LocalDockerSocketWorker(approval: approval, expectedPeer: expectedPeer)
        do {
            try await withTaskCancellationHandler {
                try await worker.connect(timeout: timeout)
                try Task.checkCancellation()
            } onCancel: { worker.requestCancellation() }
            return LocalDockerHTTPConnection(worker: worker)
        } catch {
            await worker.close()
            throw error
        }
    }

    func query(_ query: LocalDockerReadQuery,
               timeout: Duration = .seconds(2)) async throws -> DockerHTTPResponse {
        guard !closed else { throw LocalDockerTransportError.closed }
        guard !inFlight else { throw LocalDockerTransportError.busy }
        // Invalid input is rejected before reserving work or writing bytes.
        let request = try query.encoded()
        let deadline = try DockerTransportDeadline(timeout)
        inFlight = true
        defer { inFlight = false }
        let worker = self.worker
        do {
            let response = try await withTaskCancellationHandler {
                try await worker.query(request, deadline: deadline)
            } onCancel: { worker.requestCancellation() }
            guard !closed, !Task.isCancelled else {
                throw LocalDockerTransportError.cancelled
            }
            if response.connectionWillClose { closed = true }
            return response
        } catch {
            closed = true
            await worker.close()
            throw error
        }
    }

    func close() async {
        closed = true
        worker.requestCancellation()
        // The worker closes only after its current syscall/poll slice returns.
        // Another task never closes or reuses its live descriptor.
        await worker.close()
    }

    func removeContainerForTesting(submission: ManualServiceSubmission,
                                   timeout: Duration = .seconds(2)) async throws -> BoundDockerServiceReceipt {
        guard !closed else { throw LocalDockerTransportError.closed }
        guard !inFlight, !removalAttempted else { throw LocalDockerTransportError.busy }
        try Task.checkCancellation()
        let deadline = try DockerTransportDeadline(timeout)
        inFlight = true; removalAttempted = true
        defer { inFlight = false }
        let boundary = DockerRemovalCancellationBoundary()
        let worker = self.worker
        do {
            // A cancelled initiating task cannot throw away a submitted request's
            // reply. The worker continues on the retained connection until this
            // one deadline; no resend or reconnect is ever attempted.
            return try await withTaskCancellationHandler {
                try await worker.removeContainer(submission: submission, deadline: deadline, boundary: boundary)
            } onCancel: {
                if boundary.cancelBeforeSubmission() { worker.requestCancellation() }
            }
        } catch {
            closed = true
            await worker.close()
            throw error
        }
    }

    func ownedDescriptorCountForTesting() async -> Int { await worker.descriptorCount() }
}

private final class DockerRemovalCancellationBoundary: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var possiblySubmitted = false

    func cancelBeforeSubmission() -> Bool {
        lock.withLock {
            guard !possiblySubmitted else { return false }
            cancelled = true
            return true
        }
    }

    func begin(_ submission: ManualServiceSubmission) throws -> ManualServiceDispatchPermit {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, !possiblySubmitted else { throw LocalDockerTransportError.cancelled }
        possiblySubmitted = true
        return try submission.beginSubmission()
    }
}

private struct DockerTransportDeadline: Sendable {
    let end: UInt64

    init(_ duration: Duration) throws {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        guard seconds.isFinite, seconds > 0, seconds <= 30 else {
            throw LocalDockerTransportError.invalidDeadline
        }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        let (value, overflow) = DispatchTime.now().uptimeNanoseconds.addingReportingOverflow(nanoseconds)
        guard nanoseconds > 0, !overflow else { throw LocalDockerTransportError.invalidDeadline }
        end = value
    }

    func remainingMilliseconds() throws -> Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < end else { throw LocalDockerTransportError.deadline }
        // Short finite waits make cancellation prompt without cross-thread close.
        return Int32(min(20, max(1, (end - now + 999_999) / 1_000_000)))
    }
}

private final class LocalDockerSocketWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Tidy.local-docker-http", qos: .utility)
    private let cancellationLock = NSLock()
    private var cancelled = false
    private let approval: LocalSocketApproval
    private let expectedPeer: ProcessInstanceIdentity
    // Accessed only by queue-owned operations. Submitted operations retain self.
    private var descriptor: Int32 = -1

    init(approval: LocalSocketApproval, expectedPeer: ProcessInstanceIdentity) {
        self.approval = approval
        self.expectedPeer = expectedPeer
    }

    deinit {
        // Queued work retains self, so deinit cannot race a syscall. Keep the
        // final close on the same queue even when the actor was abandoned idle.
        let owned = descriptor
        queue.async { if owned >= 0 { Darwin.close(owned) } }
    }

    func requestCancellation() { cancellationLock.withLock { cancelled = true } }

    private func check(_ deadline: DockerTransportDeadline) throws {
        guard !cancellationLock.withLock({ cancelled }) else { throw LocalDockerTransportError.cancelled }
        _ = try deadline.remainingMilliseconds()
    }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func connect(timeout: Duration) async throws {
        let deadline = try DockerTransportDeadline(timeout)
        try await perform { [self] in
            do {
                try check(deadline)
                try validatePath()
                guard ProcessIdentity.matches(expectedPeer) else {
                    throw LocalDockerTransportError.peerIdentityChanged
                }
                guard descriptor == -1 else { throw LocalDockerTransportError.connectionFailed }
                descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
                guard descriptor >= 0 else { throw LocalDockerTransportError.connectionFailed }
                guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
                      fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                    throw LocalDockerTransportError.connectionFailed
                }
                var one: Int32 = 1
                guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one,
                    socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                    throw LocalDockerTransportError.connectionFailed
                }
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                let path = Array(approval.canonicalPath.utf8) + [0]
                guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                    throw LocalDockerTransportError.connectionFailed
                }
                withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
                address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                if result != 0 {
                    guard [EINPROGRESS, EAGAIN, EWOULDBLOCK, EINTR].contains(errno) else {
                        throw LocalDockerTransportError.connectionFailed
                    }
                    try wait(for: Int16(POLLOUT), deadline: deadline)
                    var failure: Int32 = 0
                    var size = socklen_t(MemoryLayout<Int32>.size)
                    guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &failure, &size) == 0,
                          size == MemoryLayout<Int32>.size, failure == 0 else {
                        throw LocalDockerTransportError.connectionFailed
                    }
                }
                try check(deadline)
                try validatePath()
                try validatePeer()
                try checkNoUnsolicitedBytes(deadline: deadline)
            } catch {
                closeOwned()
                throw error
            }
        }
    }

    func query(_ request: Data, deadline: DockerTransportDeadline) async throws -> DockerHTTPResponse {
        try await perform { [self] in
            try exchange(request, deadline: deadline)
        }
    }

    private func exchange(_ request: Data, deadline: DockerTransportDeadline) throws -> DockerHTTPResponse {
        do {
            try check(deadline)
            guard descriptor >= 0 else { throw LocalDockerTransportError.closed }
            try validatePath()
            try validatePeer()
            try checkNoUnsolicitedBytes(deadline: deadline)
            var written = 0
            while written < request.count {
                try check(deadline)
                let sent = request.withUnsafeBytes { raw in
                    send(descriptor, raw.baseAddress!.advanced(by: written), raw.count - written, 0)
                }
                if sent > 0 { written += sent }
                else if sent < 0, errno == EINTR { continue }
                else if sent < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    try wait(for: Int16(POLLOUT), deadline: deadline)
                } else { throw LocalDockerTransportError.disconnected }
            }
            var responseBytes = Data()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let maximum = DockerHTTPFraming.maximumHeaderBytes + DockerHTTPFraming.maximumBodyBytes
            while true {
                try check(deadline)
                let count = recv(descriptor, &buffer, min(buffer.count, maximum + 1 - responseBytes.count), 0)
                if count > 0 {
                    guard responseBytes.count + count <= maximum else {
                        throw DockerHTTPFramingError.tooLarge
                    }
                    responseBytes.append(contentsOf: buffer.prefix(count))
                    if let response = try DockerHTTPFraming.parse(responseBytes) {
                        guard !(300...399).contains(response.status) else {
                            throw LocalDockerTransportError.invalidResponse
                        }
                        try validatePath()
                        try validatePeer()
                        try check(deadline)
                        let disconnected = try peerHasClosedAfterResponse(deadline: deadline)
                        if response.connectionWillClose || disconnected { closeOwned() }
                        return DockerHTTPResponse(status: response.status, body: response.body,
                            connectionWillClose: response.connectionWillClose || disconnected)
                    }
                } else if count == 0 { throw LocalDockerTransportError.truncated }
                else if errno == EINTR { continue }
                else if errno == EAGAIN || errno == EWOULDBLOCK {
                    try wait(for: Int16(POLLIN), deadline: deadline)
                } else { throw LocalDockerTransportError.disconnected }
            }
        } catch {
            closeOwned()
            throw error
        }
    }

    func removeContainer(submission: ManualServiceSubmission, deadline: DockerTransportDeadline,
                         boundary: DockerRemovalCancellationBoundary) async throws -> BoundDockerServiceReceipt {
        try await perform { [self] in
            do {
                let binding = submission.effectBinding
                try binding.validate()
                guard binding.operation.adapter == .dockerStoppedContainerRemovalV1,
                      case .docker(let producer) = binding.operation.producer,
                      case .container(let container) = binding.operation.object,
                      expectedPeer.pid == getpid(), producer.socket == approval,
                      producer.peerPID == expectedPeer.pid, producer.peerUID == approval.ownerUID,
                      producer.peerBootID == expectedPeer.bootID,
                      producer.peerStartSeconds == expectedPeer.startSeconds,
                      producer.peerStartMicroseconds == expectedPeer.startMicroseconds,
                      producer.peerExecutable.canonicalPath == expectedPeer.executablePath,
                      producer.peerExecutable.device == expectedPeer.executableDevice,
                      producer.peerExecutable.inode == expectedPeer.executableInode else {
                    throw LocalDockerTransportError.peerIdentityChanged
                }
                try check(deadline)
                try validatePath(); try validatePeer()
                let version = try exchange(DockerHTTPRequest.version(), deadline: deadline)
                try requirePersistent(version, status: 200)
                let info = try exchange(DockerHTTPRequest.info(apiVersion: producer.version.apiVersion), deadline: deadline)
                try requirePersistent(info, status: 200)
                let observedProducer = try ManualProducerInventory.parseDockerProducer(
                    version: version.body, info: info.body, socket: approval,
                    peerPID: expectedPeer.pid, peerUID: approval.ownerUID, peerBootID: expectedPeer.bootID,
                    peerStartSeconds: expectedPeer.startSeconds, peerStartMicroseconds: expectedPeer.startMicroseconds,
                    peerExecutable: producer.peerExecutable, providerIdentifier: producer.providerIdentifier)
                guard observedProducer == producer else { throw ManualServiceInventoryError.identityMismatch }
                let inspectRequest = try DockerHTTPRequest.inspectContainer(apiVersion: producer.version.apiVersion, id: container.id)
                let inspection = try exchange(inspectRequest, deadline: deadline)
                try requirePersistent(inspection, status: 200)
                let observedContainer = try ManualProducerInventory.parseDockerContainer(inspect: inspection.body, expectedID: container.id)
                guard observedContainer == container else { throw ManualServiceInventoryError.identityMismatch }
                let request = try DockerHTTPRequest.removeContainer(apiVersion: producer.version.apiVersion, id: container.id)
                try check(deadline)
                try validatePath(); try validatePeer()
                // Durable submitted intent precedes the first possible DELETE
                // byte. Any later transport failure leaves that intent unresolved.
                let permit = try boundary.begin(submission)
                guard permit.binding == binding else { throw ManualServiceInventoryError.identityMismatch }
                let response = try exchange(request, deadline: deadline)
                guard !response.connectionWillClose else { throw LocalDockerTransportError.disconnected }
                switch response.status {
                case 204:
                    let postcondition = try exchange(inspectRequest, deadline: deadline)
                    try requirePersistent(postcondition, status: 404)
                    let message = try dockerError(postcondition.body, exactAbsentID: container.id)
                    return BoundDockerServiceReceipt(permit: permit, kind: .removed, request: request,
                        response: response, responseMessage: nil, postcondition: postcondition,
                        postconditionMessage: message, peer: expectedPeer, socket: approval)
                case 404:
                    let message = try dockerError(response.body, exactAbsentID: container.id)
                    return BoundDockerServiceReceipt(permit: permit, kind: .alreadyAbsent, request: request,
                        response: response, responseMessage: message, postcondition: nil,
                        postconditionMessage: nil, peer: expectedPeer, socket: approval)
                case 409:
                    let message = try dockerError(response.body, exactAbsentID: nil)
                    return BoundDockerServiceReceipt(permit: permit, kind: .refused, request: request,
                        response: response, responseMessage: message, postcondition: nil,
                        postconditionMessage: nil, peer: expectedPeer, socket: approval)
                default: throw LocalDockerTransportError.invalidResponse
                }
            } catch {
                closeOwned()
                throw error
            }
        }
    }

    private func requirePersistent(_ response: DockerHTTPResponse, status: Int) throws {
        guard response.status == status, !response.connectionWillClose else {
            throw LocalDockerTransportError.invalidResponse
        }
    }

    private func dockerError(_ data: Data, exactAbsentID: String?) throws -> String {
        guard data.count <= 8_192,
              case .object(let fields) = try StrictJSON.parse(data), Set(fields.keys) == ["message"],
              case .string(let message)? = fields["message"], !message.isEmpty,
              message.utf8.count <= 4_096, !message.utf8.contains(0) else {
            throw LocalDockerTransportError.invalidResponse
        }
        if let exactAbsentID, message != "No such container: \(exactAbsentID)" {
            throw LocalDockerTransportError.invalidResponse
        }
        return message
    }

    func close() async {
        requestCancellation()
        _ = try? await perform { [self] in closeOwned() }
    }

    func descriptorCount() async -> Int {
        (try? await perform { [self] in descriptor >= 0 ? 1 : 0 }) ?? 0
    }

    private func closeOwned() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }

    private func validatePath() throws {
        guard (try? LocalSocketApproval.verify(socket: URL(fileURLWithPath: approval.canonicalPath))) == approval else {
            throw LocalDockerTransportError.socketIdentityChanged
        }
    }

    private func validatePeer() throws {
        var uid: uid_t = 0, gid: gid_t = 0
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == approval.ownerUID,
              getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0,
              size == MemoryLayout<pid_t>.size, pid == getpid(), pid == expectedPeer.pid,
              (try? ProcessIdentity.capture(pid: pid)) == expectedPeer else {
            throw LocalDockerTransportError.peerIdentityChanged
        }
    }

    private func wait(for events: Int16, deadline: DockerTransportDeadline) throws {
        while true {
            try check(deadline)
            var value = pollfd(fd: descriptor, events: events, revents: 0)
            let result = poll(&value, 1, try deadline.remainingMilliseconds())
            if result < 0, errno == EINTR { continue }
            guard result >= 0, value.revents & Int16(POLLNVAL) == 0 else {
                throw LocalDockerTransportError.disconnected
            }
            if result > 0 { return }
        }
    }

    private func checkNoUnsolicitedBytes(deadline: DockerTransportDeadline) throws {
        if try peerHasClosedAfterResponse(deadline: deadline) { throw LocalDockerTransportError.disconnected }
    }

    private func peerHasClosedAfterResponse(deadline: DockerTransportDeadline) throws -> Bool {
        var byte: UInt8 = 0
        while true {
            try check(deadline)
            let result = recv(descriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            if result > 0 { throw LocalDockerTransportError.unsolicitedBytes }
            if result == 0 { return true }
            if errno == EINTR { continue }
            guard errno == EAGAIN || errno == EWOULDBLOCK else {
                throw LocalDockerTransportError.disconnected
            }
            return false
        }
    }
}
