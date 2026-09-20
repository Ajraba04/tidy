import Darwin
import Foundation
import Testing
@testable import TidyCore

@Suite("Local endpoint guard", .serialized)
struct LocalEndpointGuardTests {
    @Test("approved exact Unix socket identity is accepted and revalidated")
    func approvedSocketIdentity() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-Endpoint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let socketURL = root.appendingPathComponent("docker.sock")
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(descriptor >= 0)
        defer { if descriptor >= 0 { close(descriptor) } }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        #expect(pathBytes.count < MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
        let identity = try LocalSocketApproval.verify(socket: socketURL)
        let result = LocalEndpointGuard.captureApproved(
            endpoint: "unix://" + socketURL.path, approved: [identity])
        switch result {
        case .success(let captured): #expect(captured == identity)
        case .failure(let denial): Issue.record("Unexpected denial: \(denial)")
        }
    }

    @Test("remote and symlink endpoints are denied before any client call")
    func remoteAndSymlinkDenied() throws {
        #expect(!LocalEndpointGuard.permitsLocalEndpointSyntax("ssh://fixture"))
        #expect(!LocalEndpointGuard.permitsLocalEndpointSyntax("tcp://127.0.0.1:2375"))
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("Tidy-Endpoint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("regular")
        try Data().write(to: target)
        let alias = root.appendingPathComponent("docker.sock")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let result = LocalEndpointGuard.captureApproved(
            endpoint: "unix://" + alias.path, approved: [])
        switch result {
        case .failure(.symbolicLink): break
        default: Issue.record("Symbolic-link endpoint was not rejected")
        }
    }
}
