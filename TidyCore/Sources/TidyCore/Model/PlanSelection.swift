public struct PlanSelection: Sendable {
    public let plan: CleanPlan
    public private(set) var selectedIDs: Set<String>

    public init(plan: CleanPlan, selectDefaults: Bool) {
        self.plan = plan
        let eligible = Self.eligibleIDs(in: plan)
        self.selectedIDs = selectDefaults ? Set(plan.reviewItems.filter { eligible.contains($0.id) && !$0.review.requiresPerRunOptIn }.map(\.id)) : []
    }
    public var reviewItems: [PlannedItem] { plan.reviewItems }
    public var selectedItems: [PlannedItem] { reviewItems.filter { selectedIDs.contains($0.id) } }
    public var selectedCount: Int { selectedItems.count }
    public var selectedEstimatedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.estimatedBytes } }
    public var selectedPlan: CleanPlan { CleanPlan(tier: plan.tier, plannedItems: selectedItems, generatedAt: plan.generatedAt) }
    public mutating func setSelected(_ selected: Bool, id: String) {
        guard Self.eligibleIDs(in: plan).contains(id) else { return }
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
    }
    public mutating func applyPresetIDs(_ ids: Set<String>) {
        let eligible = Self.eligibleIDs(in: plan)
        selectedIDs = Set(ids.filter { id in eligible.contains(id) && !(reviewItems.first { $0.id == id }?.review.requiresPerRunOptIn ?? true) })
    }
    private static func eligibleIDs(in plan: CleanPlan) -> Set<String> {
        let counts = Dictionary(grouping: plan.reviewItems, by: \.id).mapValues(\.count)
        return Set(plan.reviewItems.compactMap { item in
            guard counts[item.id] == 1, item.review.id == item.id, item.review.isSelectable,
                  CapabilityRegistry.denialReason(for: item.action, itemID: item.id) == nil else { return nil }
            return item.id
        })
    }
}
