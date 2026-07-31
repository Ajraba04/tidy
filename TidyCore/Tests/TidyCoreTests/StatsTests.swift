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

@Suite("ByteFormat")
struct ByteFormatTests {
    @Test("never returns an empty string")
    func neverReturnsEmptyString() {
        #expect(!ByteFormat.human(0).isEmpty)
        #expect(!ByteFormat.human(5_000_000_000).isEmpty)
    }

    @Test("formats gigabyte-scale and megabyte-scale values distinctly")
    func formatsDistinctScales() {
        #expect(ByteFormat.human(5_000_000) != ByteFormat.human(5_000_000_000))
    }

    @Test("clamps negative input to zero rather than crashing")
    func clampsNegativeInput() {
        #expect(ByteFormat.human(-100) == ByteFormat.human(0))
    }
}
