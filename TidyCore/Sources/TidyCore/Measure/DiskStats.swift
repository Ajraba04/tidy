import Foundation

/// Live disk space for one volume, read via `URLResourceValues` instead
/// of a spawned `df`.
public struct DiskStats: Sendable, Equatable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case missingResourceValue(URLResourceKey)
        case invalidResourceValue(URLResourceKey)
    }
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
        return try validating(totalCapacity: values.volumeTotalCapacity,
            availableCapacity: values.volumeAvailableCapacity,
            importantUsageCapacity: values.volumeAvailableCapacityForImportantUsage,
            volumeIdentifier: values.volumeUUIDString)
    }

    public static func validating(totalCapacity: Int?, availableCapacity: Int?,
                                  importantUsageCapacity: Int64?,
                                  volumeIdentifier: String?) throws -> DiskStats {
        guard let totalCapacity else { throw Error.missingResourceValue(.volumeTotalCapacityKey) }
        guard let availableCapacity else { throw Error.missingResourceValue(.volumeAvailableCapacityKey) }
        guard let importantUsageCapacity else {
            throw Error.missingResourceValue(.volumeAvailableCapacityForImportantUsageKey)
        }
        let total = Int64(totalCapacity)
        let available = Int64(availableCapacity)
        guard total > 0 else { throw Error.invalidResourceValue(.volumeTotalCapacityKey) }
        guard available >= 0, available <= total else {
            throw Error.invalidResourceValue(.volumeAvailableCapacityKey)
        }
        guard importantUsageCapacity >= 0, importantUsageCapacity <= total else {
            throw Error.invalidResourceValue(.volumeAvailableCapacityForImportantUsageKey)
        }
        return DiskStats(totalBytes: total, availableBytes: available,
            availableForImportantUsageBytes: importantUsageCapacity,
            volumeIdentifier: volumeIdentifier)
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
