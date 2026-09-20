import Foundation
import Testing
@testable import TidyCore

@Suite("Node developer adapter", .serialized)
struct NodeDeveloperAdapterTests {
    @Test("edited dependency trees stay manual risk and outputs stay unavailable")
    func dependencyAndOutputBoundaries() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let project = try fixture.project("Web", toolchains: [.node])
        let modules = URL(fileURLWithPath: project.canonicalRoot)
            .appendingPathComponent("node_modules", isDirectory: true)
        let output = URL(fileURLWithPath: project.canonicalRoot)
            .appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("edited".utf8).write(to: modules.appendingPathComponent("local.js"))
        let entries = try NodeDeveloperAdapter().inventory(
            context: fixture.context(projects: [project]))
        let dependency = try #require(entries.first { $0.record.kind == "node-modules" })
        #expect(dependency.disposition == .manualRisk)
        #expect(dependency.effectSpec == nil)
        let dist = try #require(entries.first { $0.record.kind == "node-output:dist" })
        #expect(dist.record.capability == .inventoryOnly)
        if case .unavailable? = dist.effectSpec?.availability {} else {
            Issue.record("output mutation enabled")
        }
        #expect(try String(contentsOf: modules.appendingPathComponent("local.js"),
                           encoding: .utf8) == "edited")
    }
}
