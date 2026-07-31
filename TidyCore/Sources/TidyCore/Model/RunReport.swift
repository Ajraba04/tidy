import Foundation

/// The outcome of executing one `PlannedItem`.
public struct ItemResult: Identifiable, Sendable, Codable {
    public let id: String
    public let title: String
    public let freedBytes: Int64
    public let succeeded: Bool
    public let message: String?

    public init(id: String, title: String, freedBytes: Int64, succeeded: Bool, message: String? = nil) {
        self.id = id
        self.title = title
        self.freedBytes = freedBytes
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
}
