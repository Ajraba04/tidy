import Foundation

public enum HeadroomPlanStatus: Equatable, Sendable {
    case targetMet, ready, insufficient, unavailable(String)
}

public struct HeadroomPlan: Sendable {
    public let id: UUID
    public let volumeID: UUID
    public let policyRevision: UInt64
    public let targetBytes: Int64
    public let availableBytes: Int64?
    public let deficitBytes: Int64?
    public let selected: [RankedCleanupCandidate]
    public let selectedBytes: Int64
    public let excluded: [RankedCleanupCandidate]
    public let status: HeadroomPlanStatus
    public let byteCap: Int64
    public let itemCap: Int
}

public enum HeadroomPlanner {
    public static func plan(ranking: CandidateRanking, volumeID: UUID,
                            strictAvailableBytes: Int64?, targetBytes: Int64,
                            byteCap: Int64, itemCap: Int, policyRevision: UInt64,
                            deselectedIDs: Set<String> = []) throws -> HeadroomPlan {
        guard targetBytes >= 0, byteCap >= 0, byteCap <= 100 * 1_073_741_824,
              itemCap >= 0, itemCap <= 100 else { throw PlanningError.invalidLimits }
        guard let available = strictAvailableBytes, available >= 0 else {
            return make(volumeID, policyRevision, targetBytes, nil, nil, [], 0,
                ranking.rows, .unavailable("Strict available capacity is unavailable."), byteCap, itemCap)
        }
        let deficit = targetBytes > available ? targetBytes - available : 0
        if deficit == 0 {
            return make(volumeID, policyRevision, targetBytes, available, 0, [], 0,
                ranking.rows, .targetMet, byteCap, itemCap)
        }
        var selected: [RankedCleanupCandidate] = [], excluded: [RankedCleanupCandidate] = []
        var bytes: Int64 = 0
        var overlap = OverlapLedger()
        for row in ranking.rows {
            guard row.sourceEligible, let marginal = row.candidate.record.allocatedBytes, marginal > 0,
                  !deselectedIDs.contains(row.candidate.record.id),
                  resourceVolume(row.candidate.record.resource) == volumeID,
                  selected.count < itemCap, bytes < deficit,
                  marginal <= byteCap - bytes else { excluded.append(row); continue }
            guard overlap.reserve(row.candidate) else { excluded.append(row); continue }
            selected.append(.init(candidate: row.candidate, marginalBytes: marginal,
                eligible: true, reason: "Within the reviewed volume, caps and non-overlapping selection."))
            bytes += marginal
        }
        return make(volumeID, policyRevision, targetBytes, available, deficit, selected,
                    bytes, excluded, bytes >= deficit ? .ready : .insufficient, byteCap, itemCap)
    }

    /// User deselection only removes work. Filling the deficit again requires a
    /// separate explicit preparation and review, not an implicit replacement.
    public static func removingSelection(_ ids: Set<String>, from plan: HeadroomPlan) -> HeadroomPlan {
        let removed = plan.selected.filter { ids.contains($0.candidate.record.id) }
        let kept = plan.selected.filter { !ids.contains($0.candidate.record.id) }
        let bytes = kept.reduce(Int64(0)) { $0 + ($1.marginalBytes ?? 0) }
        let status: HeadroomPlanStatus
        switch plan.status {
        case .targetMet, .unavailable: status = plan.status
        default: status = bytes >= (plan.deficitBytes ?? Int64.max) ? .ready : .insufficient
        }
        return make(plan.volumeID, plan.policyRevision, plan.targetBytes, plan.availableBytes,
            plan.deficitBytes, kept, bytes, plan.excluded + removed, status, plan.byteCap, plan.itemCap)
    }

    /// A run cursor never reranks or introduces candidates after confirmation.
    /// This is scheduling state, not coordinator execution authority.
    public struct RunCursor: Sendable {
        public let plan: HeadroomPlan
        public private(set) var dispatchedIDs: [String] = []
        public private(set) var chargedBytes: Int64 = 0
        public private(set) var stopReason: String?
        private var index = 0
        public init(plan: HeadroomPlan) { self.plan = plan }

        public mutating func next(strictAvailableBytes: Int64?, policyRevision: UInt64,
                                  cancelled: Bool, previousEffectCertain: Bool = true)
            -> RankedCleanupCandidate? {
            guard stopReason == nil else { return nil }
            if cancelled { stopReason = "Cancelled"; return nil }
            if !previousEffectCertain { stopReason = "Previous effect is uncertain"; return nil }
            if policyRevision != plan.policyRevision { stopReason = "Policy changed; fresh review required"; return nil }
            guard let available = strictAvailableBytes, available >= 0 else {
                stopReason = "Capacity unavailable"; return nil
            }
            if available >= plan.targetBytes { stopReason = "Target met"; return nil }
            guard index < plan.selected.count, dispatchedIDs.count < plan.itemCap else {
                stopReason = "Reviewed selection exhausted"; return nil
            }
            let row = plan.selected[index]
            guard let bytes = row.marginalBytes, bytes >= 0, bytes <= plan.byteCap - chargedBytes else {
                stopReason = "Reviewed cap reached"; return nil
            }
            index += 1; chargedBytes += bytes; dispatchedIDs.append(row.candidate.record.id)
            return row
        }
    }

    private static func resourceVolume(_ resource: ResourceIdentity) -> UUID? {
        switch resource {
        case .filesystem(let value): value.volumeID
        case .snapshot(let volumeID, _): volumeID
        case .simulator: nil
        case .localService: nil
        }
    }

    private static func make(_ volume: UUID, _ revision: UInt64, _ target: Int64,
                             _ available: Int64?, _ deficit: Int64?,
                             _ selected: [RankedCleanupCandidate], _ bytes: Int64,
                             _ excluded: [RankedCleanupCandidate], _ status: HeadroomPlanStatus,
                             _ cap: Int64, _ items: Int) -> HeadroomPlan {
        HeadroomPlan(id: UUID(), volumeID: volume, policyRevision: revision,
            targetBytes: target, availableBytes: available, deficitBytes: deficit,
            selected: selected, selectedBytes: bytes, excluded: excluded, status: status,
            byteCap: cap, itemCap: items)
    }
}
