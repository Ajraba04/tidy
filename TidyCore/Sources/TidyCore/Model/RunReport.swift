import Foundation

/// The outcome of executing one `PlannedItem`.
public struct ItemResult: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let freedBytes: Int64
    /// RAM returned by this item, if any. Separate from `freedBytes`
    /// because disk and memory are different resources: summing them would
    /// produce a headline number that is wrong about both.
    public let reclaimedMemoryBytes: Int64
    public let succeeded: Bool
    public let message: String?

    public init(
        id: String,
        title: String,
        freedBytes: Int64,
        reclaimedMemoryBytes: Int64 = 0,
        succeeded: Bool,
        message: String? = nil
    ) {
        self.id = id
        self.title = title
        self.freedBytes = freedBytes
        self.reclaimedMemoryBytes = reclaimedMemoryBytes
        self.succeeded = succeeded
        self.message = message
    }
}

/// The record of one `CleanEngine.execute` run, matching what the shell
/// script appended to its log file, but structured and written to
/// `runs.jsonl` as one JSON object per line.
public struct RunReport: Sendable, Codable {
    public let tier: Tier
    public let results: [ItemResult]
    public let startedAt: Date
    public let finishedAt: Date
    public let freeSpaceBeforeBytes: Int64
    public let freeSpaceAfterBytes: Int64

    public init(
        tier: Tier,
        results: [ItemResult],
        startedAt: Date,
        finishedAt: Date,
        freeSpaceBeforeBytes: Int64,
        freeSpaceAfterBytes: Int64
    ) {
        self.tier = tier
        self.results = results
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.freeSpaceBeforeBytes = freeSpaceBeforeBytes
        self.freeSpaceAfterBytes = freeSpaceAfterBytes
    }

    public var totalFreedBytes: Int64 {
        results.reduce(0) { $0 + $1.freedBytes }
    }

    public var measuredDeltaBytes: Int64 {
        max(0, freeSpaceAfterBytes - freeSpaceBeforeBytes)
    }

    public var totalReclaimedMemoryBytes: Int64 {
        results.reduce(0) { $0 + $1.reclaimedMemoryBytes }
    }

    /// True when the estimate and the observed free-space change disagree
    /// by more than a rounding-level margin, which is the moment the app
    /// owes the user an explanation rather than a number.
    public var freedFigureNeedsReconciling: Bool {
        guard totalFreedBytes > 0 else { return false }
        let difference = abs(totalFreedBytes - measuredDeltaBytes)
        return difference > max(64 * 1024 * 1024, totalFreedBytes / 10)
    }
}
