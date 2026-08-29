import Foundation

/// Live disk space for one volume, read via `URLResourceValues` instead
/// of a spawned `df`.
public struct DiskStats: Sendable, Equatable {
    public let totalBytes: Int64
    /// Strictly available space (`.volumeAvailableCapacityKey`).
    public let availableBytes: Int64
    /// Finder-style available space including purgeable
    /// (`.volumeAvailableCapacityForImportantUsageKey`): the headline
    /// number, since it matches what Finder and About This Mac show. This is
    /// a live policy estimate and is not guaranteed to equal or exceed the
    /// strict available-space value from the same snapshot.
    public let availableForImportantUsageBytes: Int64
    /// The volume's own identity (`.volumeUUIDStringKey`), not this app's
    /// invention: lets a per-volume headroom observation be labelled and
    /// matched against a saved override even if the mount path changes.
    /// `nil` when the filesystem does not report one (e.g. some network
    /// volumes); callers fall back to the mount path for display only, never
    /// for matching a saved override.
    public let volumeIdentifier: String?

    public static func current(volumeURL: URL = URL(fileURLWithPath: "/")) throws -> DiskStats {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeUUIDStringKey
        ]
        let values = try volumeURL.resourceValues(forKeys: keys)
        return DiskStats(
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: Int64(values.volumeAvailableCapacity ?? 0),
            availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage ?? 0,
            volumeIdentifier: values.volumeUUIDString
        )
    }

    public init(totalBytes: Int64, availableBytes: Int64,
                availableForImportantUsageBytes: Int64, volumeIdentifier: String? = nil) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.availableForImportantUsageBytes = availableForImportantUsageBytes
        self.volumeIdentifier = volumeIdentifier
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }
}
