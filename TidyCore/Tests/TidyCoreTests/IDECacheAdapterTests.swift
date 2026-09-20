import Foundation
import Testing
@testable import TidyCore

@Suite("IDE cache adapter", .serialized)
struct IDECacheAdapterTests {
    @Test("cache is visible while workspace and extensions are never targets")
    func excludesPersistentIDEState() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        _ = try fixture.directory("Library/Application Support/Code/Cache")
        _ = try fixture.directory("Library/Application Support/Code/workspaceStorage")
        _ = try fixture.directory("Library/Application Support/Code/extensions")
        let entries = try IDECacheAdapter().inventory(context: fixture.context())
        #expect(entries.count == 1)
        #expect(entries[0].record.kind == "ide-cache")
        #expect(entries[0].record.capability == .inventoryOnly)
    }
}
