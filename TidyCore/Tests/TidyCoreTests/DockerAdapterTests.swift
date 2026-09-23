import Darwin
import Foundation
import Testing
@testable import TidyCore

@Suite("Docker adapter")
struct DockerAdapterTests {
    @Test("only exact unreferenced images and acknowledged stopped containers form denied specs")
    func exactObjectContracts() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let (_, descriptor, endpointIdentity) = try fixture.socket("docker/docker.sock")
        defer { close(descriptor) }
        let endpoint = "unix://" + endpointIdentity.canonicalPath
        let imageID = String(repeating: "a", count: 64)
        let data = try JSONSerialization.data(withJSONObject: [[
            "id": imageID, "kind": "image", "referenceCount": 0
        ], [
            "id": String(repeating: "b", count: 64), "kind": "container",
            "state": "stopped", "hasWritableData": true
        ]])
        let rows = try #require(DockerAdapter.parseObjectList(data))
        let image = try #require(rows.first)
        let spec = try #require(DockerAdapter.effectSpec(object: image,
            endpoint: endpoint,
            endpointIdentity: endpointIdentity))
        #expect(spec.exactArgv == ["--host", endpoint,
                                  "image", "rm", imageID])
        if case .unavailable = spec.availability {} else { Issue.record("enabled") }
        #expect(DockerAdapter.effectSpec(object: rows[1],
            endpoint: "unix:///private/fixture/docker.sock") == nil)
        #expect(DockerAdapter.effectSpec(object: image, endpoint: "ssh://fixture") == nil)
    }
}
