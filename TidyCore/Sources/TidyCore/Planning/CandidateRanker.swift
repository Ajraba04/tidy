import Foundation

public enum CandidateRanker {
    public static let maximumCandidates = 10_000

    public static func rank(_ candidates: [CleanupCandidate], policy: EffectivePolicy,
                            pinnedOwnerIDs: Set<String> = [], currentOwnerID: String? = nil,
                            now: Date = Date()) throws -> CandidateRanking {
        guard candidates.count <= maximumCandidates else { throw PlanningError.tooManyCandidates }
        var ownerReferences = 0
        for candidate in candidates {
            if case .filesystem(let file) = candidate.record.resource,
               file.canonicalPath.utf8.count > 4_096 { throw PlanningError.invalidLimits }
            guard candidate.record.ownerIDs.count <= 256 else { throw PlanningError.tooManyCandidates }
            ownerReferences += candidate.record.ownerIDs.count
            guard ownerReferences <= 100_000 else { throw PlanningError.tooManyCandidates }
        }
        let duplicateIDs = Set(Dictionary(grouping: candidates, by: { $0.record.id })
            .filter { $0.value.count > 1 }.keys)
        let ordered = candidates.sorted { left, right in
            if left.cost != right.cost { return left.cost < right.cost }
            let lc = confidence(left.record.confidence), rc = confidence(right.record.confidence)
            if lc != rc { return lc > rc }
            let lb = left.record.allocatedBytes ?? -1, rb = right.record.allocatedBytes ?? -1
            if lb != rb { return lb > rb }
            return left.record.id < right.record.id
        }
        let workingSet = CandidateWorkingSet.protectedReasons(candidates, policy: policy, now: now)
        let monotonicNow = ContinuousClock().now
        var overlap = OverlapLedger()
        let rows = ordered.map { candidate -> RankedCleanupCandidate in
            if let reason = workingSet[candidate.record.id] {
                return .init(candidate: candidate, marginalBytes: nil, eligible: false, reason: reason)
            }
            if let reason = rejection(candidate, policy: policy, duplicateIDs: duplicateIDs,
                                      pinned: pinnedOwnerIDs, current: currentOwnerID,
                                      now: now, monotonicNow: monotonicNow) {
                return .init(candidate: candidate, marginalBytes: nil,
                             eligible: false, reason: reason)
            }
            guard overlap.reserve(candidate) else {
                return .init(candidate: candidate, marginalBytes: nil, eligible: false,
                    reason: candidate.allocation == .exclusiveEstimate
                        ? "Overlaps an earlier selected resource; estimates are not added twice."
                        : "Shared or unknown allocation is not an additive reclaim estimate.",
                    sourceEligible: candidate.allocation == .exclusiveEstimate)
            }
            return .init(candidate: candidate, marginalBytes: candidate.record.allocatedBytes,
                eligible: true, reason: "Fresh complete ownership and held producer exclusion; ordered by cost, confidence, size and stable ID.")
        }
        return CandidateRanking(rows: rows)
    }

    private static func rejection(_ candidate: CleanupCandidate, policy: EffectivePolicy,
                                  duplicateIDs: Set<String>, pinned: Set<String>, current: String?,
                                  now: Date, monotonicNow: ContinuousClock.Instant) -> String? {
        let record = candidate.record
        if duplicateIDs.contains(record.id) { return "Ambiguous duplicate candidate identity." }
        if !policy.allowedFeatures.contains("buildPrep") { return "Build Prep is disabled." }
        if candidate.manualRisk { return "Dependency or other manual-risk resource requires a separate explicit review." }
        if record.capability != .exactResourceMutation {
            return record.reason.isEmpty ? "This resource does not support an accepted cleanup effect." : record.reason
        }
        if policy.fields[SettingID(rawValue: "item.\(candidate.catalogID).enabled")]?.value
            != .stored(.bool(true)) { return "This item is disabled or unsupported by the acknowledged policy." }
        let ceiling: CleanupCost
        switch policy.fields[SettingID(rawValue: "cleanup.costCeiling")]?.value {
        case .stored(.choice("high")): ceiling = .high
        case .stored(.choice("medium")): ceiling = .moderate
        default: ceiling = .low
        }
        if candidate.cost > ceiling { return "Rebuild cost exceeds the selected ceiling." }
        if !record.ownerIDs.isDisjoint(with: pinned) || current.map(record.ownerIDs.contains) == true {
            return "Pinned or current project resources are protected."
        }
        if record.activity.blocksMutation { return "Activity is active, recent, pinned or unknown." }
        if case .filesystem(let file) = record.resource,
           policy.exclusions.contains(where: { PathGuard.isEqualOrDescendant(file.canonicalPath, of: $0) }) {
            return "Resource is inside an excluded root."
        }
        guard let bytes = record.allocatedBytes, bytes >= 0 else { return "Allocated size is unknown or invalid." }
        let minimum = max(integer(policy, "item.\(candidate.catalogID).minimumItemMiB")
            ?? integer(policy, "cleanup.minimumItemMiB") ?? 1,
            integer(policy, "cleanup.minimumCandidateMiB") ?? 100)
        let (minimumBytes, overflow) = minimum.multipliedReportingOverflow(by: 1_048_576)
        if overflow || minimum < 0 || bytes < minimumBytes || bytes == 0 { return "Resource is below the minimum size." }
        let days = max(integer(policy, "item.\(candidate.catalogID).inactiveDays")
            ?? integer(policy, "cleanup.inactiveDays") ?? 60,
            integer(policy, "cleanup.recentProtectionDays") ?? 7)
        guard days >= 0, let last = candidate.lastActivityAt,
              now.timeIntervalSince(last).isFinite,
              now.timeIntervalSince(last) >= Double(days) * 86_400 else {
            return "Inactivity history is missing, recent or invalid."
        }
        guard let proof = candidate.ownership else { return "No supported producer ownership proof is attached." }
        do { try proof.validate(record, now: now, monotonicNow: monotonicNow) }
        catch { return "Producer ownership or exclusion evidence is stale, incomplete or unavailable." }
        return nil
    }

    private static func integer(_ policy: EffectivePolicy, _ id: String) -> Int64? {
        guard case .stored(.integer(let value))? = policy.fields[.init(rawValue: id)]?.value else { return nil }
        return value
    }

    private static func confidence(_ value: InventoryConfidence) -> Int {
        switch value { case .exact: 2; case .partial: 1; case .unknown: 0 }
    }
}
