import Foundation
import Testing
@testable import TidyCore

@Suite("Data directory adapter", .serialized)
struct DataDirectoryAdapterTests {
    @Test("database and VM directories have no effect specification")
    func dataStaysInventoryOnly() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let project = try fixture.project("Data")
        for name in ["postgres", "vm"] {
            let directory = URL(fileURLWithPath: project.canonicalRoot)
                .appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: directory.appendingPathComponent("user-data"))
        }
        let entries = try DataDirectoryAdapter().inventory(
            context: fixture.context(projects: [project]))
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.record.capability == .inventoryOnly })
        #expect(entries.allSatisfy { $0.effectSpec == nil })
    }
}
