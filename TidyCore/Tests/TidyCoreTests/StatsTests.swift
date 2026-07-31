import Testing
@testable import TidyCore

@Suite("DiskStats")
struct DiskStatsTests {
    @Test("reports sane figures for the root volume")
    func reportsSaneFiguresForRoot() throws {
        let stats = try DiskStats.current()
        #expect(stats.totalBytes > 0)
        #expect(stats.availableBytes >= 0)
        #expect(stats.availableBytes <= stats.totalBytes)
        // Finder-style "important usage" free space includes purgeable
        // space, so it is never smaller than the strict figure.
        #expect(stats.availableForImportantUsageBytes >= stats.availableBytes)
    }
}

@Suite("MemoryStats")
struct MemoryStatsTests {
    @Test("reports sane figures for physical memory")
    func reportsSaneFiguresForMemory() {
        let stats = MemoryStats.current()
        #expect(stats.totalBytes > 0)
        #expect(stats.usedBytes >= 0)
        #expect(stats.usedBytes <= stats.totalBytes)
    }
}

@Suite("SwapStats")
struct SwapStatsTests {
    @Test("reports sane figures when swap is enabled")
    func reportsSaneFiguresWhenEnabled() {
        guard let stats = SwapStats.current() else { return }
        #expect(stats.totalBytes >= 0)
        #expect(stats.usedBytes >= 0)
        #expect(stats.usedBytes <= stats.totalBytes)
    }
}
