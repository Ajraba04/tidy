import Foundation

public enum MaintenanceMode: String, Codable, Hashable, Sendable {
    case notifyOnly
    case authorizedCaches
}

public enum MaintenanceCapabilityID: String, Hashable, Codable, Sendable {
    /// Available for exact notify-only review. This does not place the
    /// capability in the unattended mutation allowlist below.
    case appleDerivedData = "safe.xcode.derived-data"
}

public enum MaintenanceRuleError: Error, Equatable, Sendable {
    case invalidCapability
    case invalidBounds
    case invalidVersion
    case invalidIdentity
}

/// Exact local authority for one rule. The grant captures effective caps rather
/// than settings which could later be imported or relaxed.
public struct MaintenanceGrant: Hashable, Codable, Sendable {
    public let ruleID: UUID
    public let mode: MaintenanceMode
    public let capabilityID: MaintenanceCapabilityID
    public let root: LocalRootApproval
    public let maxBytes: Int64
    public let maxItems: Int
    public let deadlineSeconds: Int
    public let minimumAgeDays: Int
    public let minimumIntervalHours: Int
    public let ruleVersion: UInt64
    public let policyRevision: UInt64

    public init(ruleID: UUID = UUID(), mode: MaintenanceMode,
                capabilityID: MaintenanceCapabilityID, root: LocalRootApproval,
                maxBytes: Int64, maxItems: Int, deadlineSeconds: Int,
                minimumAgeDays: Int, minimumIntervalHours: Int,
                ruleVersion: UInt64, policyRevision: UInt64) throws {
        self.ruleID = ruleID
        self.mode = mode
        self.capabilityID = capabilityID
        self.root = root
        self.maxBytes = maxBytes
        self.maxItems = maxItems
        self.deadlineSeconds = deadlineSeconds
        self.minimumAgeDays = minimumAgeDays
        self.minimumIntervalHours = minimumIntervalHours
        self.ruleVersion = ruleVersion
        self.policyRevision = policyRevision
        try validate()
    }

    internal func validate() throws {
        let maximumBytes = Int64(5) * 1_024 * 1_024 * 1_024
        guard maxBytes > 0, maxBytes <= maximumBytes,
              (1...20).contains(maxItems), (30...120).contains(deadlineSeconds),
              (30...365).contains(minimumAgeDays),
              (24...168).contains(minimumIntervalHours) else {
            throw MaintenanceRuleError.invalidBounds
        }
        guard ruleVersion > 0 else { throw MaintenanceRuleError.invalidVersion }
        guard root.canonicalPath.hasPrefix("/"), root.canonicalPath.utf8.count <= 4_096 else {
            throw MaintenanceRuleError.invalidIdentity
        }
    }

    public static func registryDefaultNotifyOnly(
        capabilityID: MaintenanceCapabilityID,
        root: LocalRootApproval,
        ruleID: UUID = UUID(),
        ruleVersion: UInt64 = 1,
        policyRevision: UInt64
    ) throws -> Self {
        try Self(ruleID: ruleID, mode: .notifyOnly,
                 capabilityID: capabilityID, root: root,
                 maxBytes: 1_024 * 1_024 * 1_024, maxItems: 5,
                 deadlineSeconds: 60, minimumAgeDays: 30,
                 minimumIntervalHours: 24, ruleVersion: ruleVersion,
                 policyRevision: policyRevision)
    }
}

public enum MaintenanceActivity: String, Codable, Hashable, Sendable {
    case knownIdle
    case active
    case unknown
}

public enum MaintenanceEvidenceOrigin: String, Codable, Hashable, Sendable {
    case supportedAdapter
    case imported
    case manual
}

public struct MaintenanceCandidate: Hashable, Codable, Sendable {
    public let capabilityID: MaintenanceCapabilityID
    public let root: LocalRootApproval
    public let allocatedBytes: Int64?
    public let itemCount: Int?
    public let ageDays: Int?
    public let activity: MaintenanceActivity
    public let ownerEvidenceKnown: Bool
    public let evidenceOrigin: MaintenanceEvidenceOrigin
    public let evidenceValidUntilMonotonicNanoseconds: UInt64
    public let immutableOrQuiescentScopeHeld: Bool
    public let ruleVersion: UInt64
    public let policyRevision: UInt64

    public init(capabilityID: MaintenanceCapabilityID, root: LocalRootApproval,
                allocatedBytes: Int64?, itemCount: Int?, ageDays: Int?,
                activity: MaintenanceActivity, evidenceOrigin: MaintenanceEvidenceOrigin,
                ownerEvidenceKnown: Bool = true,
                evidenceValidUntilMonotonicNanoseconds: UInt64,
                immutableOrQuiescentScopeHeld: Bool, ruleVersion: UInt64,
                policyRevision: UInt64) {
        self.capabilityID = capabilityID
        self.root = root
        self.allocatedBytes = allocatedBytes
        self.itemCount = itemCount
        self.ageDays = ageDays
        self.activity = activity
        self.ownerEvidenceKnown = ownerEvidenceKnown
        self.evidenceOrigin = evidenceOrigin
        self.evidenceValidUntilMonotonicNanoseconds = evidenceValidUntilMonotonicNanoseconds
        self.immutableOrQuiescentScopeHeld = immutableOrQuiescentScopeHeld
        self.ruleVersion = ruleVersion
        self.policyRevision = policyRevision
    }
}

public enum MaintenanceDenial: String, Error, Codable, Equatable, Sendable {
    case featureDisabled
    case authorityMissing
    case ruleRevoked
    case identityMismatch
    case policyChanged
    case ruleChanged
    case measurementUnknown
    case ownerUnknown
    case staleEvidence
    case activeOrUnknown
    case importedOrManualEvidence
    case ageTooYoung
    case capExceeded
    case capabilityNotAllowlisted
    case immutableScopeMissing
    case frequencyLimited
    case clockDiscontinuity
    case unknownReview
    case notSelected
    case expiredReview
}

public enum MaintenanceNavigation: String, Codable, Hashable, Sendable {
    case reviewCache
}

public struct MaintenanceNotification: Equatable, Sendable {
    public let ruleID: UUID
    public let capabilityID: MaintenanceCapabilityID
    public let navigation: MaintenanceNavigation
    public let observedBytes: Int64
}

enum MaintenanceRules {
    /// Deliberately empty for the first release. Adapter acceptance must add an
    /// exact ID here in a source-reviewed change; Safe tier membership is not
    /// sufficient.
    static let unattendedCapabilityIDs: Set<MaintenanceCapabilityID> = []

    static func validate(grant: MaintenanceGrant, candidate: MaintenanceCandidate,
                         featureEnabled: Bool, currentPolicyRevision: UInt64,
                         nowMonotonicNanoseconds: UInt64,
                         requireImmutableScope: Bool) throws {
        guard featureEnabled else { throw MaintenanceDenial.featureDisabled }
        try grant.validate()
        guard grant.capabilityID == candidate.capabilityID,
              grant.root == candidate.root else { throw MaintenanceDenial.identityMismatch }
        guard grant.policyRevision == currentPolicyRevision,
              candidate.policyRevision == currentPolicyRevision else {
            throw MaintenanceDenial.policyChanged
        }
        guard grant.ruleVersion == candidate.ruleVersion else {
            throw MaintenanceDenial.ruleChanged
        }
        guard candidate.evidenceOrigin == .supportedAdapter else {
            throw MaintenanceDenial.importedOrManualEvidence
        }
        guard nowMonotonicNanoseconds <= candidate.evidenceValidUntilMonotonicNanoseconds else {
            throw MaintenanceDenial.staleEvidence
        }
        guard candidate.ownerEvidenceKnown else { throw MaintenanceDenial.ownerUnknown }
        guard candidate.activity == .knownIdle else { throw MaintenanceDenial.activeOrUnknown }
        guard let bytes = candidate.allocatedBytes, bytes >= 0,
              let items = candidate.itemCount, items > 0,
              let age = candidate.ageDays, age >= 0 else {
            throw MaintenanceDenial.measurementUnknown
        }
        guard age >= grant.minimumAgeDays else { throw MaintenanceDenial.ageTooYoung }
        guard bytes <= grant.maxBytes, items <= grant.maxItems else {
            throw MaintenanceDenial.capExceeded
        }
        if requireImmutableScope {
            guard unattendedCapabilityIDs.contains(candidate.capabilityID) else {
                throw MaintenanceDenial.capabilityNotAllowlisted
            }
            guard candidate.immutableOrQuiescentScopeHeld else {
                throw MaintenanceDenial.immutableScopeMissing
            }
        }
    }
}
