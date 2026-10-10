import Darwin
import Foundation
import Testing
@testable import TidyCore

private final class DockerTransportFixtureServer: @unchecked Sendable {
    let root: URL
    let socketURL: URL
    private let queue = DispatchQueue(label: "Tidy.test.local-docker-server")
    private let lock = NSLock()
    private var stopped = false
    private var capturedRequests: [Data] = []
    private let responses: [Data]
    private let stallAfterResponse: Bool
    private let heldResponseIndex: Int?
    private var responseReleased = false

    init(responses: [Data], stallAfterResponse: Bool = false, heldResponseIndex: Int? = nil) throws {
        root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("TidyDockerHTTP-\(UUID().uuidString)")
        socketURL = root.appendingPathComponent("server.sock")
        self.responses = responses
        self.stallAfterResponse = stallAfterResponse
        self.heldResponseIndex = heldResponseIndex
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        do {
            guard fcntl(listener, F_SETFL, O_NONBLOCK) == 0,
                  fcntl(listener, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(.EIO) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(socketURL.path.utf8) + [0]
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                throw POSIXError(.ENAMETOOLONG)
            }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(listener, 1) == 0 else { throw POSIXError(.EIO) }
        } catch {
            Darwin.close(listener)
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        queue.async { [self] in serve(listener) }
    }

    func requests() -> [Data] { lock.withLock { capturedRequests } }
    func releaseResponse() { lock.withLock { responseReleased = true } }

    func finish() async {
        lock.withLock { stopped = true }
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func ready(_ fd: Int32, events: Int16, until deadline: UInt64) -> Bool {
        while DispatchTime.now().uptimeNanoseconds < deadline, !lock.withLock({ stopped }) {
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            if poll(&descriptor, 1, 10) > 0 { return true }
        }
        return false
    }

    private func serve(_ listener: Int32) {
        defer { Darwin.close(listener) }
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        guard ready(listener, events: Int16(POLLIN), until: deadline) else { return }
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }
        _ = fcntl(client, F_SETFL, O_NONBLOCK)
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        for (responseIndex, response) in responses.enumerated() {
            var request = Data(), buffer = [UInt8](repeating: 0, count: 4_096)
            while request.range(of: Data("\r\n\r\n".utf8)) == nil {
                guard request.count <= 16_384,
                      ready(client, events: Int16(POLLIN), until: deadline) else { return }
                let count = recv(client, &buffer, buffer.count, 0)
                guard count > 0 else { return }
                request.append(contentsOf: buffer.prefix(count))
            }
            lock.withLock { capturedRequests.append(request) }
            while heldResponseIndex == responseIndex, !lock.withLock({ responseReleased }),
                  DispatchTime.now().uptimeNanoseconds < deadline, !lock.withLock({ stopped }) {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard !lock.withLock({ stopped }), DispatchTime.now().uptimeNanoseconds < deadline else { return }
            var offset = 0
            while offset < response.count {
                guard ready(client, events: Int16(POLLOUT), until: deadline) else { return }
                let sent = response.withUnsafeBytes { raw in
                    send(client, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                }
                guard sent > 0 else { return }
                offset += sent
            }
        }
        if stallAfterResponse {
            while DispatchTime.now().uptimeNanoseconds < deadline, !lock.withLock({ stopped }) {
                var descriptor = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
                if poll(&descriptor, 1, 10) > 0 {
                    var byte: UInt8 = 0
                    if recv(client, &byte, 1, MSG_PEEK) == 0 { return }
                }
            }
        }
    }
}

private struct DockerRemovalFixture {
    static let id = String(repeating: "a", count: 64)
    static let version = Data(#"{"Version":"27.3.1","ApiVersion":"1.47","MinAPIVersion":"1.24","Os":"linux","Arch":"arm64"}"#.utf8)
    static let info = Data(#"{"ServerVersion":"27.3.1","OSType":"linux","Architecture":"aarch64","ID":"owned-fixture-daemon"}"#.utf8)
    static var inspect: Data {
        Data(("{\"Id\":\"\(id)\",\"Name\":\"/owned-fixture\",\"Created\":\"2026-10-10T00:00:00Z\","
            + "\"Image\":\"sha256:\(String(repeating: "b", count: 64))\",\"State\":{\"Status\":\"exited\",\"Running\":false,\"Paused\":false,\"Restarting\":false},"
            + "\"Mounts\":[],\"Config\":{\"Labels\":{},\"Volumes\":null},\"HostConfig\":{\"VolumeDriver\":\"\",\"Binds\":null,\"VolumesFrom\":null}}").utf8)
    }
    static func response(_ status: Int, _ body: Data = Data()) -> Data {
        Data("HTTP/1.1 \(status) Fixture\r\nContent-Length: \(body.count)\r\nConnection: keep-alive\r\n\r\n".utf8) + body
    }
    static var absent: Data { Data("{\"message\":\"No such container: \(id)\"}".utf8) }

    let admission: MutationAdmissionStore
    let journal: RunJournal
    let submission: ManualServiceSubmission
    let binding: ManualServiceEffectBinding
    let operationID: UUID

    init(server: DockerTransportFixtureServer, wrongPeerBinding: Bool = false) throws {
        let peer = try ProcessIdentity.capture(pid: getpid())
        let producer = try ManualProducerInventory.parseDockerProducer(version: Self.version, info: Self.info,
            socket: LocalSocketApproval.verify(socket: server.socketURL), peerPID: peer.pid,
            peerUID: geteuid(), peerBootID: peer.bootID,
            peerStartSeconds: peer.startSeconds + (wrongPeerBinding ? 1 : 0),
            peerStartMicroseconds: peer.startMicroseconds,
            peerExecutable: LocalExecutableApproval.verify(executable: URL(fileURLWithPath: peer.executablePath)),
            providerIdentifier: "owned-fake-provider")
        let container = try ManualProducerInventory.parseDockerContainer(inspect: Self.inspect, expectedID: Self.id)
        binding = try ManualServiceEffectBinding(reviewID: UUID(), coordinatorID: UUID(),
            policyRevision: 1, authorityRevision: 1,
            installation: LocalInstallationIdentity.verify(directory: server.root),
            operation: ManualServiceOperationBinding(adapter: .dockerStoppedContainerRemovalV1,
                object: .container(container), producer: .docker(producer)))
        let directory = server.root.appendingPathComponent("execution")
        admission = try MutationAdmissionStore(directory: directory)
        guard admission.acquire() == .ready else { throw JournalError.unavailable }
        journal = try RunJournal(store: admission, storage: DurableJournalStorage(directory: directory))
        let runID = UUID(); operationID = UUID()
        try journal.append(.init(runID: runID, sequence: 1, phase: .planned, operationID: nil, status: nil, reason: nil))
        try journal.append(.init(runID: runID, sequence: 2, phase: .confirmed, operationID: nil, status: nil, reason: nil))
        submission = try ManualServiceSubmission.prepare(runID: runID, operationID: operationID,
            binding: binding, journal: journal)
    }
}

@Suite("Owned fake Docker removal protocol", .serialized)
struct LocalDockerRemovalProtocolTests {
    private func connect(_ server: DockerTransportFixtureServer) async throws -> LocalDockerHTTPConnection {
        try await LocalDockerHTTPConnection.connectForTesting(
            approval: LocalSocketApproval.verify(socket: server.socketURL),
            expectedPeer: ProcessIdentity.capture(pid: getpid()))
    }

    @Test("successful fixed DELETE requires a same-connection exact absent postcondition")
    func successSequence() async throws {
        let responses = [DockerRemovalFixture.response(200, DockerRemovalFixture.version),
            DockerRemovalFixture.response(200, DockerRemovalFixture.info),
            DockerRemovalFixture.response(200, DockerRemovalFixture.inspect),
            DockerRemovalFixture.response(204), DockerRemovalFixture.response(404, DockerRemovalFixture.absent)]
        let server = try DockerTransportFixtureServer(responses: responses, stallAfterResponse: true)
        let fixture = try DockerRemovalFixture(server: server)
        let connection = try await connect(server)
        let receipt = try await connection.removeContainerForTesting(submission: fixture.submission)
        #expect(receipt.kind == .removed)
        #expect(receipt.binding == fixture.binding)
        #expect(receipt.operationID == fixture.operationID)
        #expect(receipt.responseStatus == 204 && receipt.postconditionStatus == 404)
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
        let requests = server.requests().compactMap { String(data: $0, encoding: .utf8)?.components(separatedBy: "\r\n").first }
        #expect(requests == ["GET /version HTTP/1.1", "GET /v1.47/info HTTP/1.1",
            "GET /v1.47/containers/\(DockerRemovalFixture.id)/json HTTP/1.1",
            "DELETE /v1.47/containers/\(DockerRemovalFixture.id)?force=false&v=false&link=false HTTP/1.1",
            "GET /v1.47/containers/\(DockerRemovalFixture.id)/json HTTP/1.1"])
        await #expect(throws: Error.self) { try await connection.removeContainerForTesting(submission: fixture.submission) }
        #expect(server.requests().count == 5)
        await connection.close(); fixture.admission.release(); await server.finish()
    }

    @Test("compiled Docker receipts recover publication before terminal events", arguments: [204, 404, 409])
    func durableTerminalProof(status: Int) async throws {
        let body = status == 204 ? Data() : status == 404 ? DockerRemovalFixture.absent
            : Data(#"{"message":"private daemon detail must not enter journal"}"#.utf8)
        var replies = [DockerRemovalFixture.response(200, DockerRemovalFixture.version),
            DockerRemovalFixture.response(200, DockerRemovalFixture.info),
            DockerRemovalFixture.response(200, DockerRemovalFixture.inspect),
            DockerRemovalFixture.response(status, body)]
        if status == 204 { replies.append(DockerRemovalFixture.response(404, DockerRemovalFixture.absent)) }
        let server = try DockerTransportFixtureServer(responses: replies, stallAfterResponse: true)
        let fixture = try DockerRemovalFixture(server: server)
        let connection = try await connect(server)
        let receipt = try await connection.removeContainerForTesting(submission: fixture.submission)
        let proof = try CompiledEffectTerminalVerifier.manualDockerReceipt(receipt)
        let intent = try #require(fixture.admission.unfinishedIntentsWhileLocked().first)
        #expect(CompiledEffectTerminalVerifier.validate(proof.archive, intent: intent))
        #expect(proof.archive.terminalStatus == (status == 204 ? .succeeded : status == 404 ? .skipped : .failed))
        #expect(proof.archive.outcomeCount == (status == 204 ? 1 : 0))
        let bytes = try JSONEncoder().encode(proof.archive)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("private daemon detail"))
        var tampered = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        tampered["outcomeCount"] = 99
        #expect(!CompiledEffectTerminalVerifier.validate(
            try JSONDecoder().decode(EffectTerminalProofArchive.self,
                from: JSONSerialization.data(withJSONObject: tampered)), intent: intent))
        let reference = try fixture.journal.persistTerminalProof(proof)
        #expect(reference.id == fixture.operationID)
        fixture.admission.release()
        let directory = server.root.appendingPathComponent("execution")
        let reopened = try MutationAdmissionStore(directory: directory)
        #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
        let journal = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: directory))
        #expect(try journal.reconcileTerminalRun(runID: receipt.runID))
        #expect(reopened.acquire() == .ready)
        #expect(try journal.events(runID: receipt.runID).filter { $0.phase == .itemTerminal }.count == 1)
        #expect(try journal.reconcileTerminalRun(runID: receipt.runID))
        reopened.release()
        await connection.close(); await server.finish()
    }

    @Test("failed producer/object preflight never sends DELETE", arguments: ["running", "foreignID", "provider", "bindingPeer"])
    func failedPreflight(kind: String) async throws {
        let inspect = kind == "running"
            ? Data(String(decoding: DockerRemovalFixture.inspect, as: UTF8.self).replacingOccurrences(of: "\"Running\":false", with: "\"Running\":true").utf8)
            : kind == "foreignID"
                ? Data(String(decoding: DockerRemovalFixture.inspect, as: UTF8.self).replacingOccurrences(of: DockerRemovalFixture.id, with: String(repeating: "c", count: 64)).utf8)
                : DockerRemovalFixture.inspect
        let info = kind == "provider" ? Data(String(decoding: DockerRemovalFixture.info, as: UTF8.self).replacingOccurrences(of: "owned-fixture-daemon", with: "different-daemon").utf8) : DockerRemovalFixture.info
        let server = try DockerTransportFixtureServer(responses: [.init(DockerRemovalFixture.response(200, DockerRemovalFixture.version)),
            DockerRemovalFixture.response(200, info), DockerRemovalFixture.response(200, inspect)], stallAfterResponse: true)
        let fixture = try DockerRemovalFixture(server: server, wrongPeerBinding: kind == "bindingPeer")
        let connection = try await connect(server)
        await #expect(throws: Error.self) { try await connection.removeContainerForTesting(submission: fixture.submission) }
        #expect(!server.requests().contains { $0.starts(with: Data("DELETE ".utf8)) })
        if kind == "bindingPeer" { #expect(server.requests().isEmpty) }
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .prepared)
        await connection.close(); fixture.admission.release(); await server.finish()
    }

    @Test("DELETE404 and409 receipts require bounded valid error semantics", arguments: [404, 409])
    func terminalErrors(status: Int) async throws {
        let body = status == 404 ? DockerRemovalFixture.absent : Data(#"{"message":"conflict: container is running"}"#.utf8)
        let server = try DockerTransportFixtureServer(responses: [DockerRemovalFixture.response(200, DockerRemovalFixture.version),
            DockerRemovalFixture.response(200, DockerRemovalFixture.info), DockerRemovalFixture.response(200, DockerRemovalFixture.inspect),
            DockerRemovalFixture.response(status, body)], stallAfterResponse: true)
        let fixture = try DockerRemovalFixture(server: server)
        let connection = try await connect(server)
        let receipt = try await connection.removeContainerForTesting(submission: fixture.submission)
        #expect(receipt.kind == (status == 404 ? .alreadyAbsent : .refused))
        #expect(server.requests().count == 4)
        await connection.close(); fixture.admission.release(); await server.finish()
    }

    @Test("lost or malformed terminal replies leave submitted intent unresolved", arguments: ["lost", "foreign404", "malformed409", "postconditionWrongID"])
    func uncertainReplies(kind: String) async throws {
        let foreign = DockerRemovalFixture.response(404, Data(#"{"message":"No such container: wrong"}"#.utf8))
        let tail: [Data]
        switch kind {
        case "lost": tail = [Data()]
        case "malformed409": tail = [DockerRemovalFixture.response(409, Data(#"{"message":false}"#.utf8))]
        case "postconditionWrongID": tail = [DockerRemovalFixture.response(204), foreign]
        default: tail = [foreign]
        }
        let server = try DockerTransportFixtureServer(responses: [DockerRemovalFixture.response(200, DockerRemovalFixture.version),
            DockerRemovalFixture.response(200, DockerRemovalFixture.info), DockerRemovalFixture.response(200, DockerRemovalFixture.inspect)] + tail, stallAfterResponse: true)
        let fixture = try DockerRemovalFixture(server: server)
        let connection = try await connect(server)
        await #expect(throws: Error.self) { try await connection.removeContainerForTesting(submission: fixture.submission, timeout: .milliseconds(250)) }
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .submitted)
        #expect(throws: Error.self) { try fixture.submission.cancelBeforeSubmission() }
        #expect(server.requests().filter { $0.starts(with: Data("DELETE ".utf8)) }.count == 1)
        await connection.close(); fixture.admission.release(); await server.finish()
    }

    @Test("cancellation during preflight never arms submission or sends DELETE")
    func cancellationBeforeSubmission() async throws {
        let server = try DockerTransportFixtureServer(responses: [DockerRemovalFixture.response(200, DockerRemovalFixture.version),
            DockerRemovalFixture.response(200, DockerRemovalFixture.info), DockerRemovalFixture.response(200, DockerRemovalFixture.inspect)],
            stallAfterResponse: true, heldResponseIndex: 2)
        let fixture = try DockerRemovalFixture(server: server)
        let connection = try await connect(server)
        let submission = fixture.submission
        let operation = Task { try await connection.removeContainerForTesting(submission: submission) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while server.requests().count < 3, ContinuousClock.now < deadline { await Task.yield() }
        #expect(server.requests().count == 3)
        operation.cancel()
        server.releaseResponse()
        await #expect(throws: Error.self) { try await operation.value }
        #expect(try fixture.admission.unfinishedIntentsWhileLocked().first?.phase == .prepared)
        #expect(!server.requests().contains { $0.starts(with: Data("DELETE ".utf8)) })
        await connection.close(); fixture.admission.release(); await server.finish()
    }

    @Test("initiator cancellation after DELETE does not discard terminal collection")
    func cancellationAfterSubmission() async throws {
        let server = try DockerTransportFixtureServer(responses: [DockerRemovalFixture.response(200, DockerRemovalFixture.version),
            DockerRemovalFixture.response(200, DockerRemovalFixture.info), DockerRemovalFixture.response(200, DockerRemovalFixture.inspect),
            DockerRemovalFixture.response(204), DockerRemovalFixture.response(404, DockerRemovalFixture.absent)],
            stallAfterResponse: true, heldResponseIndex: 3)
        let fixture = try DockerRemovalFixture(server: server)
        let connection = try await connect(server)
        let submission = fixture.submission
        let operation = Task { try await connection.removeContainerForTesting(submission: submission) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while server.requests().count < 4, ContinuousClock.now < deadline { await Task.yield() }
        #expect(server.requests().count == 4)
        operation.cancel()
        server.releaseResponse()
        #expect(try await operation.value.kind == .removed)
        #expect(server.requests().filter { $0.starts(with: Data("DELETE ".utf8)) }.count == 1)
        await connection.close(); fixture.admission.release(); await server.finish()
    }

    @Test("fixture connection factory rejects every foreign process before socket writes")
    func foreignProcessFactoryDenied() async throws {
        let server = try DockerTransportFixtureServer(responses: [])
        let peer = try ProcessIdentity.capture(pid: getpid())
        let foreign = ProcessInstanceIdentity(bootID: peer.bootID, pid: peer.pid + 1,
            startSeconds: peer.startSeconds, startMicroseconds: peer.startMicroseconds,
            executablePath: peer.executablePath, executableDevice: peer.executableDevice, executableInode: peer.executableInode)
        await #expect(throws: Error.self) {
            try await LocalDockerHTTPConnection.connectForTesting(
                approval: LocalSocketApproval.verify(socket: server.socketURL), expectedPeer: foreign)
        }
        #expect(server.requests().isEmpty)
        await server.finish()
    }
}

@Suite("Bounded local Docker read transport", .serialized)
struct LocalDockerHTTPTransportTests {
    private func response(_ body: String = "{}") -> Data {
        Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: keep-alive\r\n\r\n\(body)".utf8)
    }

    @Test("one bound local connection sends only exact typed GET routes")
    func exactGETRoutes() async throws {
        // A keep-alive success fixture must retain its peer through the final
        // identity check. Closing immediately after write races that check;
        // explicit finish/client close and the existing five-second watchdog
        // still bound the server lifetime.
        let server = try DockerTransportFixtureServer(responses: [response(), response(), response()],
            stallAfterResponse: true)
        let approval = try LocalSocketApproval.verify(socket: server.socketURL)
        let peer = try ProcessIdentity.capture(pid: getpid())
        let connection = try await LocalDockerHTTPConnection.connectForTesting(
            approval: approval, expectedPeer: peer)
        let id = String(repeating: "a", count: 64)
        let queries: [LocalDockerReadQuery] = [.version, .info(apiVersion: "1.47"),
            .inspectContainer(apiVersion: "1.47", id: id)]
        for (index, query) in queries.enumerated() {
            do {
                let value = try await connection.query(query, timeout: .seconds(1))
                #expect(value.body == Data("{}".utf8))
            } catch {
                Issue.record("Exact GET fixture request \(index + 1) failed: \(error)")
                await connection.close()
                await server.finish()
                throw error
            }
        }
        await connection.close()
        #expect(await connection.ownedDescriptorCountForTesting() == 0)
        let lines = server.requests().compactMap { String(data: $0, encoding: .utf8)?.components(separatedBy: "\r\n").first }
        #expect(lines == ["GET /version HTTP/1.1", "GET /v1.47/info HTTP/1.1",
            "GET /v1.47/containers/\(id)/json HTTP/1.1"])
        await #expect(throws: (any Error).self) { try await connection.query(.version) }
        #expect(server.requests().count == 3)
        await server.finish()
    }

    @Test("peer mismatch and replaced socket identity cannot produce an accepted connection")
    func wrongPeerAndSocketReplacement() async throws {
        let server = try DockerTransportFixtureServer(responses: [response()])
        let approval = try LocalSocketApproval.verify(socket: server.socketURL)
        let peer = try ProcessIdentity.capture(pid: getpid())
        let wrong = ProcessInstanceIdentity(bootID: peer.bootID, pid: peer.pid,
            startSeconds: peer.startSeconds + 1, startMicroseconds: peer.startMicroseconds,
            executablePath: peer.executablePath, executableDevice: peer.executableDevice,
            executableInode: peer.executableInode)
        await #expect(throws: (any Error).self) {
            try await LocalDockerHTTPConnection.connectForTesting(approval: approval, expectedPeer: wrong)
        }
        try FileManager.default.moveItem(at: server.socketURL,
            to: server.root.appendingPathComponent("original.sock"))
        try Data().write(to: server.socketURL)
        await #expect(throws: (any Error).self) {
            try await LocalDockerHTTPConnection.connectForTesting(approval: approval, expectedPeer: peer)
        }
        #expect(server.requests().isEmpty)
        await server.finish()
    }

    @Test("partial, oversized and pipelined responses close the owned connection",
          arguments: ["partial", "oversized", "pipelined"])
    func hostileResponses(kind: String) async throws {
        let bytes: Data
        switch kind {
        case "partial": bytes = Data("HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\n{}".utf8)
        case "oversized": bytes = Data("HTTP/1.1 200 OK\r\nContent-Length: 999999999\r\n\r\n".utf8)
        default: bytes = response() + response()
        }
        let server = try DockerTransportFixtureServer(responses: [bytes], stallAfterResponse: kind == "partial")
        let connection = try await LocalDockerHTTPConnection.connectForTesting(
            approval: LocalSocketApproval.verify(socket: server.socketURL),
            expectedPeer: ProcessIdentity.capture(pid: getpid()))
        await #expect(throws: (any Error).self) {
            try await connection.query(.version, timeout: .milliseconds(100))
        }
        #expect(await connection.ownedDescriptorCountForTesting() == 0)
        await #expect(throws: (any Error).self) { try await connection.query(.version) }
        await server.finish()
    }

    @Test("close while a request is pending prevents reuse without closing a worker's live descriptor")
    func closeDuringRead() async throws {
        let server = try DockerTransportFixtureServer(responses: [Data()], stallAfterResponse: true)
        let connection = try await LocalDockerHTTPConnection.connectForTesting(
            approval: LocalSocketApproval.verify(socket: server.socketURL),
            expectedPeer: ProcessIdentity.capture(pid: getpid()))
        let request = Task { try await connection.query(.version, timeout: .seconds(1)) }
        let requestDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while server.requests().isEmpty, ContinuousClock.now < requestDeadline { await Task.yield() }
        #expect(!server.requests().isEmpty)
        await #expect(throws: (any Error).self) { try await connection.query(.version) }
        await connection.close()
        await #expect(throws: (any Error).self) { try await request.value }
        #expect(await connection.ownedDescriptorCountForTesting() == 0)
        await server.finish()
    }

    @Test("task cancellation closes the retained connection and cannot permit a later query")
    func cancellationDuringRead() async throws {
        let server = try DockerTransportFixtureServer(responses: [Data()], stallAfterResponse: true)
        let connection = try await LocalDockerHTTPConnection.connectForTesting(
            approval: LocalSocketApproval.verify(socket: server.socketURL),
            expectedPeer: ProcessIdentity.capture(pid: getpid()))
        let request = Task { try await connection.query(.version, timeout: .seconds(1)) }
        let requestDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while server.requests().isEmpty, ContinuousClock.now < requestDeadline { await Task.yield() }
        #expect(!server.requests().isEmpty)
        request.cancel()
        await #expect(throws: (any Error).self) { try await request.value }
        #expect(await connection.ownedDescriptorCountForTesting() == 0)
        await #expect(throws: (any Error).self) { try await connection.query(.version) }
        await server.finish()
    }

    @Test("invalid versions and short or injected IDs cannot write a request")
    func invalidQueriesDoNotReachSocket() async throws {
        let server = try DockerTransportFixtureServer(responses: [response()])
        let connection = try await LocalDockerHTTPConnection.connectForTesting(
            approval: LocalSocketApproval.verify(socket: server.socketURL),
            expectedPeer: ProcessIdentity.capture(pid: getpid()))
        for query in [LocalDockerReadQuery.info(apiVersion: "1.47\r\nInjected: yes"),
                      .inspectContainer(apiVersion: "1.47", id: "abc"),
                      .inspectContainer(apiVersion: "1.47", id: String(repeating: "A", count: 64))] {
            await #expect(throws: (any Error).self) { try await connection.query(query) }
        }
        #expect(server.requests().isEmpty)
        await connection.close()
        #expect(await connection.ownedDescriptorCountForTesting() == 0)
        await server.finish()
    }
}
