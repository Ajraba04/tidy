import Darwin
import Foundation
import Testing
@testable import TidyCore

@Suite("Local model adapter", .serialized)
struct LocalModelAdapterTests {
    @Test("hard-linked model aliases are measured non-additively and remain report only")
    func sharedBlobIsNotDoubleCounted() throws {
        let fixture = try AdapterTestFixture(); defer { fixture.remove() }
        let store = try fixture.directory(".ollama/models")
        let blob = store.appendingPathComponent("blob")
        try Data(repeating: 7, count: 4_096).write(to: blob)
        let beforeEntries = try LocalModelAdapter().inventory(context: fixture.context())
        let before = try #require(beforeEntries.first?.record.allocatedBytes)
        #expect(link(blob.path, store.appendingPathComponent("alias").path) == 0)
        let afterEntries = try LocalModelAdapter().inventory(context: fixture.context())
        let afterEntry = try #require(afterEntries.first)
        #expect(before > 0)
        #expect(afterEntry.record.allocatedBytes == nil)
        #expect(afterEntry.record.reason.contains("shared"))
        #expect(afterEntry.record.capability == .inventoryOnly)
        #expect(afterEntry.effectSpec == nil)
    }
}
