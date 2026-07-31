import Foundation
import Testing
@testable import TidyCore

@Suite("SizeCache")
struct SizeCacheTests {

    @Test("returns nil for a path that was never stored")
    func returnsNilForUnknownPath() {
        let cache = SizeCache(fileURL: nil)
        #expect(cache.cachedBytes(forPath: "/nowhere", modifiedAt: 0) == nil)
    }

    @Test("round-trips a stored size for the same modification time")
    func roundTripsStoredSize() {
        var cache = SizeCache(fileURL: nil)
        cache.store(bytes: 12_345, forPath: "/some/path", modifiedAt: 1000)
        #expect(cache.cachedBytes(forPath: "/some/path", modifiedAt: 1000) == 12_345)
    }

    @Test("invalidates a cached size when the modification time no longer matches")
    func invalidatesOnModificationTimeMismatch() {
        var cache = SizeCache(fileURL: nil)
        cache.store(bytes: 12_345, forPath: "/some/path", modifiedAt: 1000)
        #expect(cache.cachedBytes(forPath: "/some/path", modifiedAt: 2000) == nil)
    }

    @Test("persists across instances backed by the same file")
    func persistsAcrossInstances() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SizeCacheTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var first = SizeCache(fileURL: fileURL)
        first.store(bytes: 777, forPath: "/persisted", modifiedAt: 42)
        first.save()

        let second = SizeCache(fileURL: fileURL)
        #expect(second.cachedBytes(forPath: "/persisted", modifiedAt: 42) == 777)
    }
}
