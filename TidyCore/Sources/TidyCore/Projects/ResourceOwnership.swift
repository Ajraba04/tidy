import Foundation

public enum AdapterCapability: String, Codable, Sendable {
    case inventoryOnly
    case exactResourceMutation
}

public enum ResourceActivity: String, Codable, Sendable {
    case running
    case pinned
    case recent
    case inactiveConfirmed
    case unknown

    public var blocksMutation: Bool { self != .inactiveConfirmed }
}

public enum InventoryConfidence: String, Codable, Sendable {
    case exact
    case partial
    case unknown
}

public struct InventoryRecord: Sendable {
    public let id: String
    public let adapterID: String
    public let adapterVersion: String
    public let resource: ResourceIdentity
    public let ownerIDs: Set<String>
    public let scopeID: String
    public let kind: String
    public let capability: AdapterCapability
    public let allocatedBytes: Int64?
    public let confidence: InventoryConfidence
    public let activity: ResourceActivity
    public let observedAt: Date
    public let reason: String

    init(id: String, adapterID: String, adapterVersion: String,
         resource: ResourceIdentity, ownerIDs: Set<String>, scopeID: String,
         kind: String, capability: AdapterCapability, allocatedBytes: Int64?,
         confidence: InventoryConfidence, activity: ResourceActivity,
         observedAt: Date, reason: String) {
        self.id = id
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.resource = resource
        self.ownerIDs = ownerIDs
        self.scopeID = scopeID
        self.kind = kind
        self.capability = capability
        self.allocatedBytes = allocatedBytes
        self.confidence = confidence
        self.activity = activity
        self.observedAt = observedAt
        self.reason = reason
    }
}

enum OwnershipCompleteness: String, Sendable {
    case complete
    case incomplete
    case unknown
}

enum AssociationEvidenceMethod: String, Sendable {
    case producerManifest
    case manualAcknowledgement
    case unsupported
}

enum RuntimeEvidenceMethod: String, Sendable {
    case producerExclusionLease
    case processAbsence
    case tidyAdvisoryLock
    case manualInactivity
    case unsupported
}

/// A bounded association record produced during review. Its initializer is
/// internal deliberately: app callers, settings and imported data cannot mint
/// execution authority. R03 persists this value together with the exact
/// manifest identity; it is never reconstructed from display text.
struct ResourceAssociationEvidence: Sendable {
    let adapterID: String
    let adapterVersion: String
    let resource: ResourceIdentity
    let producerIDs: Set<String>
    let ownerIDs: Set<String>
    let sharedOwnerIDs: Set<String>
    let completeness: OwnershipCompleteness
    let observedAt: Date
    let validUntil: Date
    let method: AssociationEvidenceMethod

    init(adapterID: String, adapterVersion: String, resource: ResourceIdentity,
         producerIDs: Set<String>, ownerIDs: Set<String>, sharedOwnerIDs: Set<String>,
         completeness: OwnershipCompleteness, observedAt: Date, validUntil: Date,
         method: AssociationEvidenceMethod) {
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.resource = resource
        self.producerIDs = producerIDs
        self.ownerIDs = ownerIDs
        self.sharedOwnerIDs = sharedOwnerIDs
        self.completeness = completeness
        self.observedAt = observedAt
        self.validUntil = validUntil
        self.method = method
    }
}

/// Proof attached to a held producer exclusion primitive. A time stamp by
/// itself is insufficient: mutation code receives this value only through a
/// live `ProducerExclusionLease` whose lifetime encloses every filesystem
/// effect.
struct RuntimeProducerProof: Sendable {
    let adapterID: String
    let adapterVersion: String
    let resource: ResourceIdentity
    let producerIDs: Set<String>
    let ownerIDs: Set<String>
    let sharedOwnerIDs: Set<String>
    let completeness: OwnershipCompleteness
    let observedAt: Date
    let validUntil: Date
    let method: RuntimeEvidenceMethod

    init(adapterID: String, adapterVersion: String, resource: ResourceIdentity,
         producerIDs: Set<String>, ownerIDs: Set<String>, sharedOwnerIDs: Set<String>,
         completeness: OwnershipCompleteness, observedAt: Date, validUntil: Date,
         method: RuntimeEvidenceMethod) {
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.resource = resource
        self.producerIDs = producerIDs
        self.ownerIDs = ownerIDs
        self.sharedOwnerIDs = sharedOwnerIDs
        self.completeness = completeness
        self.observedAt = observedAt
        self.validUntil = validUntil
        self.method = method
    }
}

protocol ProducerExclusionLease: AnyObject, Sendable {
    var proof: RuntimeProducerProof { get }
    /// Process-local monotonic evidence. These instants are deliberately not
    /// Codable and cannot be reconstructed after relaunch or wall-clock edit.
    var acquiredAt: ContinuousClock.Instant { get }
    var deadline: ContinuousClock.Instant { get }
}

protocol ProducerExclusionLeaseProviding: Sendable {
    /// Must acquire the producer-owned exclusion primitive and then observe
    /// fresh state. Merely checking for a process or taking a Tidy-owned lock
    /// does not conform to this contract.
    func acquireLease(for resource: ResourceIdentity) throws -> any ProducerExclusionLease
    /// Reacquires producer-owned exclusion and fresh observations at a safe
    /// leaf boundary. Providers may use the same primitive internally, but
    /// must return a newly observed proof with a new monotonic lifetime.
    func renewLease(for resource: ResourceIdentity,
                    after previous: any ProducerExclusionLease) throws
        -> any ProducerExclusionLease
}

extension ProducerExclusionLeaseProviding {
    func renewLease(for resource: ResourceIdentity,
                    after previous: any ProducerExclusionLease) throws
        -> any ProducerExclusionLease {
        _ = previous
        return try acquireLease(for: resource)
    }
}

enum ResourceAuthorityError: Error, Equatable {
    case wrongAdapter
    case unsupportedAdapterVersion
    case resourceChanged
    case missingProducerIdentity
    case incompleteOwners
    case unknownSharedOwner
    case staleAssociation
    case unsupportedAssociationMethod
    case staleRuntimeProof
    case unsupportedRuntimeMethod
    case protectionScopeChanged
    case productionProofUnavailable
}

enum ResourceAuthorityValidator {
    static let maximumAssociationAge: TimeInterval = 24 * 60 * 60
    static let maximumRuntimeAge: TimeInterval = 5

    static func validateAssociation(_ evidence: ResourceAssociationEvidence,
                                    resource: ResourceIdentity,
                                    adapterID: String, adapterVersion: String,
                                    now: Date) throws {
        guard evidence.adapterID == adapterID else { throw ResourceAuthorityError.wrongAdapter }
        guard evidence.adapterVersion == adapterVersion else {
            throw ResourceAuthorityError.unsupportedAdapterVersion
        }
        guard evidence.resource == resource else { throw ResourceAuthorityError.resourceChanged }
        guard evidence.method == .producerManifest else {
            throw ResourceAuthorityError.unsupportedAssociationMethod
        }
        guard evidence.completeness == .complete, !evidence.ownerIDs.isEmpty else {
            throw ResourceAuthorityError.incompleteOwners
        }
        guard !evidence.producerIDs.isEmpty else { throw ResourceAuthorityError.missingProducerIdentity }
        guard evidence.sharedOwnerIDs.isSubset(of: evidence.ownerIDs) else {
            throw ResourceAuthorityError.unknownSharedOwner
        }
        let age = now.timeIntervalSince(evidence.observedAt)
        let declaredLifetime = evidence.validUntil.timeIntervalSince(evidence.observedAt)
        guard age >= 0, age <= Self.maximumAssociationAge,
              declaredLifetime >= 0, declaredLifetime <= Self.maximumAssociationAge,
              now <= evidence.validUntil else {
            throw ResourceAuthorityError.staleAssociation
        }
    }

    static func validateRuntime(_ proof: RuntimeProducerProof,
                                association: ResourceAssociationEvidence,
                                resource: ResourceIdentity,
                                adapterID: String, adapterVersion: String,
                                now: Date,
                                monotonicAcquiredAt: ContinuousClock.Instant,
                                monotonicDeadline: ContinuousClock.Instant,
                                monotonicNow: ContinuousClock.Instant) throws {
        guard proof.adapterID == adapterID else { throw ResourceAuthorityError.wrongAdapter }
        guard proof.adapterVersion == adapterVersion else {
            throw ResourceAuthorityError.unsupportedAdapterVersion
        }
        guard proof.resource == resource else { throw ResourceAuthorityError.resourceChanged }
        guard proof.method == .producerExclusionLease else {
            throw ResourceAuthorityError.unsupportedRuntimeMethod
        }
        guard proof.completeness == .complete, proof.ownerIDs == association.ownerIDs else {
            throw ResourceAuthorityError.incompleteOwners
        }
        guard proof.producerIDs == association.producerIDs, !proof.producerIDs.isEmpty else {
            throw ResourceAuthorityError.missingProducerIdentity
        }
        guard proof.sharedOwnerIDs.isSubset(of: proof.ownerIDs),
              proof.sharedOwnerIDs == association.sharedOwnerIDs else {
            throw ResourceAuthorityError.unknownSharedOwner
        }
        let monotonicLifetime = monotonicAcquiredAt.duration(to: monotonicDeadline)
        guard monotonicNow >= monotonicAcquiredAt,
              monotonicNow <= monotonicDeadline,
              monotonicLifetime >= .zero,
              monotonicLifetime <= .seconds(Self.maximumRuntimeAge) else {
            throw ResourceAuthorityError.staleRuntimeProof
        }
        let age = now.timeIntervalSince(proof.observedAt)
        let declaredLifetime = proof.validUntil.timeIntervalSince(proof.observedAt)
        guard age >= 0, age <= Self.maximumRuntimeAge,
              declaredLifetime >= 0, declaredLifetime <= Self.maximumRuntimeAge,
              now <= proof.validUntil else {
            throw ResourceAuthorityError.staleRuntimeProof
        }
    }
}
