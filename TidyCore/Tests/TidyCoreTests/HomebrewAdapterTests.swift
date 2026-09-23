import Foundation
import Testing
@testable import TidyCore

@Suite("Homebrew adapter", .serialized)
struct HomebrewAdapterTests {
    @Test("cache inventory never supplies broad cleanup")
    func cacheIsReportOnly() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        _ = try fixture.directory("Library/Caches/Homebrew")
        let entries = try HomebrewAdapter().inventory(context: fixture.context())
        #expect(entries.count == 1)
        #expect(entries[0].record.kind == "homebrew-download-cache")
        #expect(entries[0].record.capability == .inventoryOnly)
        #expect(entries[0].effectSpec == nil)
    }
}
