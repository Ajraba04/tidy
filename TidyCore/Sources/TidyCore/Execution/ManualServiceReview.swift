import Foundation

public enum ManualServiceReviewError: Error, Equatable, Sendable {
    case policyDisabled, policyUnavailable, stalePolicy, authorityDenied, wrongInstallation
    case wrongOwner, wrongCoordinator, unknownReview, expiredReview, capacity, bindingMismatch
    case providerUnavailable, busy, recoveryBlocked, storageUnavailable
}

/// Opaque coordinator registration. The public summary is data only; no JSON
/// decoder or public initializer can manufacture this owner-bound review.
public struct ManualServiceReview: Sendable {
    public let summary: ManualServiceReviewSummary
    internal let coordinatorID: UUID
    internal let ownerID: UUID
    internal let bridgeID: UUID
    internal let policyRevision: UInt64

    /// Preparation registers caller-supplied candidate data only. A typed client
    /// must re-observe the actual producer/object before any future submission.
    public var requiresProducerReinspection: Bool { true }

    fileprivate init(summary: ManualServiceReviewSummary, coordinatorID: UUID,
                     ownerID: UUID, bridgeID: UUID, policyRevision: UInt64) {
        self.summary = summary; self.coordinatorID = coordinatorID
        self.ownerID = ownerID; self.bridgeID = bridgeID; self.policyRevision = policyRevision
    }
}

public struct ConfirmedManualServiceOperation: Sendable {
    internal let coordinatorID: UUID
    internal let nonce: UUID
    internal let bindingDigest: Data
    internal let ownerID: UUID
    internal let bridgeID: UUID
    internal let binding: ManualServiceOperationBinding
    internal let policyRevision: UInt64
    internal let reviewID: UUID
    internal let expiresAtMonotonicNanoseconds: UInt64

    fileprivate init(nonce: UUID, record: ManualServiceReviewLedger.Record) {
        coordinatorID = record.coordinatorID; self.nonce = nonce
        bindingDigest = record.summary.bindingDigest; binding = record.summary.binding
        ownerID = record.ownerID; bridgeID = record.bridgeID; policyRevision = record.policyRevision
        reviewID = record.summary.reviewID
        expiresAtMonotonicNanoseconds = record.summary.expiresAtMonotonicNanoseconds
    }
}

/// Service outcomes do not claim physical space or memory reclaim. Messages
/// are fixed coordinator copy, never interpolated producer or storage errors.
public struct ManualServiceExecutionReport: Sendable {
    public let runID: UUID?
    public let status: EffectStatus
    public let binding: ManualServiceOperationBinding
    public let message: String

    internal init(runID: UUID?, status: EffectStatus, binding: ManualServiceOperationBinding, message: String) {
        self.runID = runID; self.status = status; self.binding = binding; self.message = message
    }
}

/// Bounded ephemeral data storage. Its positive `take` result is not an accepted
/// effect token and cannot bypass the coordinator's compiled acceptance check.
struct ManualServiceReviewLedger {
    struct Record: Sendable {
        let summary: ManualServiceReviewSummary
        let ownerID: UUID
        let coordinatorID: UUID
        let bridgeID: UUID
        let policyRevision: UInt64
        let authority: LocalAuthoritySnapshot
    }
    private var records: [UUID: Record] = [:]
    var count: Int { records.count }

    mutating func insert(binding: ManualServiceOperationBinding, ownerID: UUID,
                         coordinatorID: UUID, bridgeID: UUID, policyRevision: UInt64,
                         authority: LocalAuthoritySnapshot, now: UInt64,
                         lifetime: UInt64 = ManualServiceReviewSummary.maximumLifetimeNanoseconds) throws -> Record {
        guard lifetime > 0, lifetime <= ManualServiceReviewSummary.maximumLifetimeNanoseconds else {
            throw ManualServiceReviewError.expiredReview
        }
        let (expiry, overflow) = now.addingReportingOverflow(lifetime)
        guard !overflow else { throw ManualServiceReviewError.expiredReview }
        let summary = try ManualServiceReviewSummary(reviewID: UUID(), binding: binding,
            issuedAtMonotonicNanoseconds: now, expiresAtMonotonicNanoseconds: expiry)
        records = records.filter { _, record in
            record.summary.expiresAtMonotonicNanoseconds > now
                && record.authority.isCurrent
                && !(record.ownerID == ownerID && record.bridgeID == bridgeID)
        }
        guard records.count < ManualServiceReviewSummary.maximumPendingReviewCount else {
            throw ManualServiceReviewError.capacity
        }
        let record = Record(summary: summary, ownerID: ownerID, coordinatorID: coordinatorID,
            bridgeID: bridgeID, policyRevision: policyRevision, authority: authority)
        records[summary.reviewID] = record
        return record
    }

    mutating func take(reviewID: UUID, ownerID: UUID, coordinatorID: UUID,
                       bridgeID: UUID, policyRevision: UInt64, now: UInt64) throws -> Record {
        let record = try owned(reviewID: reviewID, ownerID: ownerID, coordinatorID: coordinatorID, bridgeID: bridgeID)
        // Ownership failures cannot consume another window's registration.
        // Every owned attempt consumes before expiry, policy and provider checks.
        records.removeValue(forKey: reviewID)
        guard now >= record.summary.issuedAtMonotonicNanoseconds,
              now < record.summary.expiresAtMonotonicNanoseconds else {
            throw ManualServiceReviewError.expiredReview
        }
        guard record.policyRevision == policyRevision else { throw ManualServiceReviewError.stalePolicy }
        guard record.authority.isCurrent else { throw ManualServiceReviewError.authorityDenied }
        return record
    }

    mutating func cancel(reviewID: UUID, ownerID: UUID, coordinatorID: UUID, bridgeID: UUID) throws {
        _ = try owned(reviewID: reviewID, ownerID: ownerID, coordinatorID: coordinatorID, bridgeID: bridgeID)
        records.removeValue(forKey: reviewID)
    }

    private func owned(reviewID: UUID, ownerID: UUID, coordinatorID: UUID, bridgeID: UUID) throws -> Record {
        guard let record = records[reviewID] else { throw ManualServiceReviewError.unknownReview }
        guard record.coordinatorID == coordinatorID else { throw ManualServiceReviewError.wrongCoordinator }
        guard record.ownerID == ownerID, record.bridgeID == bridgeID else { throw ManualServiceReviewError.wrongOwner }
        return record
    }
}

/// Data-only bounded storage; neither inserting nor taking a record can mint
/// the fileprivate confirmed token or any accepted producer/effect authority.
struct ManualServiceConfirmedLedger {
    struct Entry: Sendable {
        let nonce: UUID
        let record: ManualServiceReviewLedger.Record
    }
    private var records: [UUID: ManualServiceReviewLedger.Record] = [:]
    var count: Int { records.count }

    mutating func insert(_ record: ManualServiceReviewLedger.Record, now: UInt64) throws -> Entry {
        records = records.filter { $0.value.summary.expiresAtMonotonicNanoseconds > now && $0.value.authority.isCurrent }
        try requireLifetime(record, now: now)
        guard record.authority.isCurrent else { throw ManualServiceReviewError.authorityDenied }
        guard records.count < ManualServiceReviewSummary.maximumPendingReviewCount else { throw ManualServiceReviewError.capacity }
        let nonce = UUID()
        records[nonce] = record
        return Entry(nonce: nonce, record: record)
    }

    func owned(nonce: UUID, ownerID: UUID, coordinatorID: UUID,
               bridgeID: UUID) throws -> ManualServiceReviewLedger.Record {
        guard let record = records[nonce] else { throw ManualServiceReviewError.unknownReview }
        guard record.coordinatorID == coordinatorID else { throw ManualServiceReviewError.wrongCoordinator }
        guard record.ownerID == ownerID, record.bridgeID == bridgeID else { throw ManualServiceReviewError.wrongOwner }
        return record
    }

    mutating func discardOwned(nonce: UUID, ownerID: UUID, coordinatorID: UUID, bridgeID: UUID) throws {
        _ = try owned(nonce: nonce, ownerID: ownerID, coordinatorID: coordinatorID, bridgeID: bridgeID)
        records.removeValue(forKey: nonce)
    }

    mutating func take(nonce: UUID, ownerID: UUID, coordinatorID: UUID, bridgeID: UUID,
                       bindingDigest: Data, policyRevision: UInt64,
                       authority: LocalAuthoritySnapshot, now: UInt64) throws -> ManualServiceReviewLedger.Record {
        let record = try owned(nonce: nonce, ownerID: ownerID, coordinatorID: coordinatorID, bridgeID: bridgeID)
        records.removeValue(forKey: nonce)
        try requireLifetime(record, now: now)
        guard record.policyRevision == policyRevision else { throw ManualServiceReviewError.stalePolicy }
        guard record.summary.bindingDigest == bindingDigest,
              try record.summary.binding.canonicalDigest() == bindingDigest else { throw ManualServiceReviewError.bindingMismatch }
        guard record.authority.isCurrent, authority.isCurrent,
              record.authority.installation == authority.installation,
              record.authority.revision == authority.revision else { throw ManualServiceReviewError.authorityDenied }
        return record
    }

    private func requireLifetime(_ record: ManualServiceReviewLedger.Record, now: UInt64) throws {
        guard now >= record.summary.issuedAtMonotonicNanoseconds,
              now < record.summary.expiresAtMonotonicNanoseconds else { throw ManualServiceReviewError.expiredReview }
    }
}

extension ExecutionCoordinator {
    internal func issueManualServiceReview(grant: ManualServicePolicyGrant,
                                          binding: ManualServiceOperationBinding,
                                          ownerID: UUID) throws -> ManualServiceReview {
        let record = try registerManualServiceReview(grant: grant, binding: binding, ownerID: ownerID)
        return ManualServiceReview(summary: record.summary, coordinatorID: record.coordinatorID,
            ownerID: record.ownerID, bridgeID: record.bridgeID, policyRevision: record.policyRevision)
    }

    internal func mintConfirmedManualServiceOperation(grant: ManualServicePolicyGrant,
                                                     review: ManualServiceReview,
                                                     ownerID: UUID) throws -> ConfirmedManualServiceOperation {
        let reservation = try reserveManualServiceConfirmation(grant: grant, review: review, ownerID: ownerID)
        return ConfirmedManualServiceOperation(nonce: reservation.nonce, record: reservation.record)
    }
}
