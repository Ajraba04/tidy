import Foundation

public enum CleanupCost: Int, Comparable, Sendable {
    case negligible, low, moderate, high
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum AllocationKnowledge: Equatable, Sendable {
    case exclusiveEstimate
    case shared(String)
    case unknown
}

/// Adapter classification used only to withhold recommendations. It conveys no
/// ownership or execution authority. Archives, models and data are not artifacts.
public enum ArtifactRetention: Sendable {
    case notArtifact
    case projectArtifact(createdAt: Date?)
}

/// Display/planning information is not an execution grant. Only an internal
/// adapter can attach producer evidence; the coordinator still seals execution.
public struct CleanupCandidate: Sendable {
    public let record: InventoryRecord
    public let catalogID: String
    public let cost: CleanupCost
    public let lastActivityAt: Date?
    public let manualRisk: Bool
    public let allocation: AllocationKnowledge
    public let artifactRetention: ArtifactRetention
    let ownership: CandidateOwnership?

    public init(record: InventoryRecord, catalogID: String, cost: CleanupCost,
                lastActivityAt: Date?, manualRisk: Bool = false,
                allocation: AllocationKnowledge = .unknown,
                artifactRetention: ArtifactRetention = .notArtifact) {
        self.record = record; self.catalogID = catalogID; self.cost = cost
        self.lastActivityAt = lastActivityAt; self.manualRisk = manualRisk
        self.allocation = allocation; self.ownership = nil
        self.artifactRetention = artifactRetention
    }

    init(record: InventoryRecord, catalogID: String, cost: CleanupCost,
         lastActivityAt: Date?, manualRisk: Bool = false,
         allocation: AllocationKnowledge = .exclusiveEstimate,
         association: ResourceAssociationEvidence, lease: any ProducerExclusionLease,
         artifactRetention: ArtifactRetention = .notArtifact) {
        self.record = record; self.catalogID = catalogID; self.cost = cost
        self.lastActivityAt = lastActivityAt; self.manualRisk = manualRisk
        self.allocation = allocation
        self.artifactRetention = artifactRetention
        self.ownership = CandidateOwnership(association: association, lease: lease)
    }
}

struct CandidateOwnership: Sendable {
    let association: ResourceAssociationEvidence
    let lease: any ProducerExclusionLease

    func validate(_ record: InventoryRecord, now: Date,
                  monotonicNow: ContinuousClock.Instant) throws {
        guard record.ownerIDs == association.ownerIDs else {
            throw ResourceAuthorityError.incompleteOwners
        }
        try ResourceAuthorityValidator.validateAssociation(association,
            resource: record.resource, adapterID: record.adapterID,
            adapterVersion: record.adapterVersion, now: now)
        try ResourceAuthorityValidator.validateRuntime(lease.proof, association: association,
            resource: record.resource, adapterID: record.adapterID,
            adapterVersion: record.adapterVersion, now: now,
            monotonicAcquiredAt: lease.acquiredAt, monotonicDeadline: lease.deadline,
            monotonicNow: monotonicNow)
    }
}

public struct RankedCleanupCandidate: Sendable {
    public let candidate: CleanupCandidate
    public let marginalBytes: Int64?
    public let eligible: Bool
    public let reason: String
    let sourceEligible: Bool

    init(candidate: CleanupCandidate, marginalBytes: Int64?, eligible: Bool,
         reason: String, sourceEligible: Bool? = nil) {
        self.candidate = candidate; self.marginalBytes = marginalBytes
        self.eligible = eligible; self.reason = reason
        self.sourceEligible = sourceEligible ?? eligible
    }
}

public struct CandidateRanking: Sendable {
    public let rows: [RankedCleanupCandidate]
    public var eligible: [RankedCleanupCandidate] { rows.filter(\.eligible) }
    public var blocked: [RankedCleanupCandidate] { rows.filter { !$0.eligible } }
}

public enum PlanningError: Error, Equatable, Sendable {
    case tooManyCandidates, invalidLimits, stalePlan, unavailableMeasurement
}
