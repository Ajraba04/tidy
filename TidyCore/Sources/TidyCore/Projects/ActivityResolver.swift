import Foundation

public enum ActivityEvidence: String, Codable, Sendable, Equatable {
    case running, pinned, recent, inactiveConfirmed, unknown
    public var blocksRecommendation: Bool { self != .inactiveConfirmed }
}

/// Descriptive evidence supplied by a versioned adapter, never a mutation token.
/// Execution must reacquire its real producer lease and filesystem identity.
public struct OwnershipEvidence: Sendable {
    public let resourceIdentity: String
    public let adapterVersion: String
    public let policyRevision: UInt64
    public let owners: Set<String>
    public let observedOwners: Set<String>
    public let quiescentOwners: Set<String>
    public let observedAt: Date
    public let associationObservedAt: Date
    public let leaseValidUntil: Date?
    public let enumerationComplete: Bool
    public let immutableCompletedObject: Bool

    public init(resourceIdentity: String, adapterVersion: String, policyRevision: UInt64,
        owners: Set<String>, observedOwners: Set<String>, quiescentOwners: Set<String>,
        observedAt: Date, associationObservedAt: Date, leaseValidUntil: Date?,
        enumerationComplete: Bool, immutableCompletedObject: Bool) {
        self.resourceIdentity = resourceIdentity; self.adapterVersion = adapterVersion
        self.policyRevision = policyRevision; self.owners = owners; self.observedOwners = observedOwners
        self.quiescentOwners = quiescentOwners; self.observedAt = observedAt
        self.associationObservedAt = associationObservedAt; self.leaseValidUntil = leaseValidUntil
        self.enumerationComplete = enumerationComplete; self.immutableCompletedObject = immutableCompletedObject
    }
}

public enum ActivityResolver {
    /// Absence of a process, age alone, and manual acknowledgement are deliberately
    /// insufficient inputs. Running/pinned/recent protections cannot be overridden.
    public static func resolve(evidence: OwnershipEvidence?, resourceIdentity: String,
        policyRevision: UInt64, pinned: Bool, running: Bool, recent: Bool, now: Date) -> ActivityEvidence {
        if pinned { return .pinned }
        if running { return .running }
        if recent { return .recent }
        guard let evidence, !resourceIdentity.isEmpty, resourceIdentity.utf8.count <= 4_096,
              evidence.resourceIdentity == resourceIdentity, !evidence.adapterVersion.isEmpty,
              evidence.adapterVersion.utf8.count <= 256, evidence.policyRevision == policyRevision,
              evidence.enumerationComplete, evidence.immutableCompletedObject,
              !evidence.owners.isEmpty, evidence.owners.count <= 64,
              evidence.owners.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }),
              evidence.observedOwners == evidence.owners, evidence.quiescentOwners == evidence.owners,
              let lease = evidence.leaseValidUntil, lease > now else { return .unknown }
        let runtimeAge = now.timeIntervalSince(evidence.observedAt)
        let associationAge = now.timeIntervalSince(evidence.associationObservedAt)
        guard runtimeAge.isFinite, associationAge.isFinite,
              (0..<5).contains(runtimeAge), (0..<86_400).contains(associationAge) else { return .unknown }
        return .inactiveConfirmed
    }
}
