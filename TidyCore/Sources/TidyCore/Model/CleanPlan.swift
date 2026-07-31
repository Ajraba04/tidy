import Foundation

/// One catalog item as it resolved on this machine right now: its targets
/// and their measured size. Producing a `PlannedItem` never deletes
/// anything.
public struct PlannedItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let tier: Tier
    public let dangerNote: String?
    public let costNote: String?
    public let targets: [TargetPath]
    public let estimatedBytes: Int64
    public let action: CleanAction

    public init(
        id: String,
        title: String,
        tier: Tier,
        dangerNote: String?,
        costNote: String?,
        targets: [TargetPath],
        estimatedBytes: Int64,
        action: CleanAction
    ) {
        self.id = id
        self.title = title
        self.tier = tier
        self.dangerNote = dangerNote
        self.costNote = costNote
        self.targets = targets
        self.estimatedBytes = estimatedBytes
        self.action = action
    }

    public var isEmpty: Bool { targets.isEmpty }
}

/// The mandatory middle screen between "what could be cleaned" and
/// "delete it": every mode, including the shell script's `--dry-run`,
/// produces one of these before `CleanEngine.execute` runs.
public struct CleanPlan: Sendable {
    public let tier: Tier
    public let plannedItems: [PlannedItem]
    public let generatedAt: Date

    public init(tier: Tier, plannedItems: [PlannedItem], generatedAt: Date = Date()) {
        self.tier = tier
        self.plannedItems = plannedItems
        self.generatedAt = generatedAt
    }

    public var totalEstimatedBytes: Int64 {
        plannedItems.reduce(0) { $0 + $1.estimatedBytes }
    }

    public var nonEmptyItems: [PlannedItem] {
        plannedItems.filter { !$0.isEmpty }
    }
}
