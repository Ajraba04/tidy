import Foundation
import Testing
@testable import TidyCore

@Suite("DiskStats")
struct DiskStatsTests {
    @Test("missing production resource values are unavailable instead of fabricated zero")
    func missingResourceValuesAreUnavailable() {
        #expect(throws: DiskStats.Error.missingResourceValue(.volumeTotalCapacityKey)) {
            _ = try DiskStats.validating(totalCapacity: nil, availableCapacity: 20,
                importantUsageCapacity: 30, volumeIdentifier: "fixture")
        }
        #expect(throws: DiskStats.Error.missingResourceValue(.volumeAvailableCapacityKey)) {
            _ = try DiskStats.validating(totalCapacity: 100, availableCapacity: nil,
                importantUsageCapacity: 30, volumeIdentifier: "fixture")
        }
        #expect(throws: DiskStats.Error.missingResourceValue(.volumeAvailableCapacityForImportantUsageKey)) {
            _ = try DiskStats.validating(totalCapacity: 100, availableCapacity: 20,
                importantUsageCapacity: nil, volumeIdentifier: "fixture")
        }
    }

    @Test("reports sane figures for the root volume")
    func reportsSaneFiguresForRoot() throws {
        let stats = try DiskStats.current()
        #expect(stats.totalBytes > 0)
        #expect(stats.availableBytes >= 0)
        #expect(stats.availableBytes <= stats.totalBytes)
        // These live policy estimates are independent and are not guaranteed
        // to be ordered against each other.
        #expect(stats.availableForImportantUsageBytes >= 0)
        #expect(stats.availableForImportantUsageBytes <= stats.totalBytes)
    }
}

@Suite("MemoryStats")
struct MemoryStatsTests {
    @Test("reports sane figures for physical memory")
    func reportsSaneFiguresForMemory() throws {
        let stats = MemoryStats.current()
        #expect(stats.totalBytes > 0)
        let used = try #require(stats.usedBytes, "the real host_statistics64 call should not be denied here")
        #expect(used >= 0)
        #expect(used <= stats.totalBytes)
        #expect(stats.unavailableReason == nil)
    }

    @Test("denial is reported explicitly, never silently shown as zero bytes used")
    func deniedReadIsExplicitNotZero() {
        let stats = MemoryStats(totalBytes: 1_000, usedBytes: nil, unavailableReason: "denied")
        #expect(stats.usedBytes == nil)
        #expect(stats.unavailableReason == "denied")
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

@Suite("PathDisplay")
struct PathDisplayTests {
    @Test("shortens home directory to a tilde")
    func shortensHomeExactly() {
        #expect(PathDisplay.tilde("/Users/tester", homeDirectory: "/Users/tester") == "~")
    }

    @Test("shortens a path under home")
    func shortensPathUnderHome() {
        #expect(PathDisplay.tilde("/Users/tester/Library/Caches", homeDirectory: "/Users/tester") == "~/Library/Caches")
    }

    @Test("leaves a path outside home untouched")
    func leavesOutsideHomeUntouched() {
        #expect(PathDisplay.tilde("/Applications/Xcode.app", homeDirectory: "/Users/tester") == "/Applications/Xcode.app")
    }

    @Test("does not shorten a sibling that merely shares a prefix with home")
    func doesNotShortenSiblingWithSharedPrefix() {
        #expect(PathDisplay.tilde("/Users/tester2/file", homeDirectory: "/Users/tester") == "/Users/tester2/file")
    }
}

@Suite("ByteFormat")
struct ByteFormatTests {
    @Test("binary and decimal styles use their matching unit labels")
    func binaryAndDecimalStylesUseMatchingLabels() {
        let binary = ByteFormat.human(1_073_741_824, units: .binary,
                                      locale: Locale(identifier: "en_US_POSIX"))
        let decimal = ByteFormat.human(1_000_000_000, units: .decimal,
                                       locale: Locale(identifier: "en_US_POSIX"))
        #expect(binary.contains("GiB"))
        #expect(decimal.contains("GB"))
        #expect(!decimal.contains("GiB"))
    }

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
