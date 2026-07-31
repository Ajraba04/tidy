import Foundation

/// Live disk space for one volume, read via `URLResourceValues` — no
/// spawned `df`.
public struct DiskStats: Sendable, Equatable {
    /// Total volume capacity.
    public let totalBytes: Int64
    /// Strictly available space (`.volumeAvailableCapacityKey`).
    public let availableBytes: Int64
    /// Finder-style available space including purgeable
    /// (`.volumeAvailableCapacityForImportantUsageKey`) — the headline
    /// number, since it matches what Finder and About This Mac show.
    public let availableForImportantUsageBytes: Int64

    public static func current(volumeURL: URL = URL(fileURLWithPath: "/")) throws -> DiskStats {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        let values = try volumeURL.resourceValues(forKeys: keys)
        return DiskStats(
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: Int64(values.volumeAvailableCapacity ?? 0),
            availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }
}
