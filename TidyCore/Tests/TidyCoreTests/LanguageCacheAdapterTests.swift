import Foundation
import Testing
@testable import TidyCore

@Suite("Language cache adapter", .serialized)
struct LanguageCacheAdapterTests {
    @Test("virtual environments and Conda data are permanently report only")
    func environmentsRemainInventoryOnly() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let project = try fixture.project("Python", toolchains: [.python])
        for name in [".venv", ".conda", "target"] {
            let directory = URL(fileURLWithPath: project.canonicalRoot)
                .appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("user-data".utf8).write(to: directory.appendingPathComponent("keep"))
        }
        let entries = try LanguageCacheAdapter().inventory(
            context: fixture.context(projects: [project]))
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.record.capability == .inventoryOnly })
        #expect(entries.allSatisfy { $0.effectSpec == nil })
    }
}
