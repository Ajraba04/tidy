import Foundation

public struct MaintenanceReviewToken: Hashable, Sendable {
    fileprivate let value: UUID
    fileprivate init(value: UUID) { self.value = value }
}

public struct ReviewedMaintenanceRequest: Equatable, Sendable {
    public let requestID: UUID
    public let grant: MaintenanceGrant
    public let candidate: MaintenanceCandidate
    public let authorizedAtMonotonicNanoseconds: UInt64
    public let schedulingDeadlineMonotonicNanoseconds: UInt64

    internal init(requestID: UUID, grant: MaintenanceGrant,
                  candidate: MaintenanceCandidate,
                  authorizedAtMonotonicNanoseconds: UInt64,
                  schedulingDeadlineMonotonicNanoseconds: UInt64) {
        self.requestID = requestID
        self.grant = grant
        self.candidate = candidate
        self.authorizedAtMonotonicNanoseconds = authorizedAtMonotonicNanoseconds
        self.schedulingDeadlineMonotonicNanoseconds = schedulingDeadlineMonotonicNanoseconds
    }
}

public struct MaintenanceScheduleRecord: Codable, Equatable, Sendable {
    public let ruleID: UUID
    public let bootID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallDate: Date

    public init(ruleID: UUID, bootID: UUID, monotonicNanoseconds: UInt64,
                wallDate: Date) {
        self.ruleID = ruleID
        self.bootID = bootID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallDate = wallDate
    }
}

public actor MaintenanceAuthorization {
    private struct Pending: Sendable {
        let grant: MaintenanceGrant
        let candidate: MaintenanceCandidate
        let expiresAt: UInt64
        var selected: Bool
    }

    private var pending: [UUID: Pending] = [:]
    private var schedule: [UUID: MaintenanceScheduleRecord]
    private let scheduleValid: Bool
    private var revokedRules: Set<UUID> = []

    public init(scheduleRecords: [MaintenanceScheduleRecord] = []) {
        var loaded: [UUID: MaintenanceScheduleRecord] = [:]
        var valid = scheduleRecords.count <= 256
        for record in scheduleRecords.prefix(256) {
            if loaded.updateValue(record, forKey: record.ruleID) != nil { valid = false }
        }
        schedule = loaded
        scheduleValid = valid
    }

    public func notification(for grant: MaintenanceGrant,
                             candidate: MaintenanceCandidate,
                             authority: LocalAuthoritySnapshot,
                             featureEnabled: Bool,
                             currentPolicyRevision: UInt64,
                             bootID: UUID,
                             nowMonotonicNanoseconds: UInt64,
                             nowWallDate: Date) throws -> MaintenanceNotification {
        guard grant.mode == .notifyOnly,
              authority.permits(.maintenanceNotifyOnly(grant)) else {
            throw MaintenanceDenial.authorityMissing
        }
        guard !revokedRules.contains(grant.ruleID) else { throw MaintenanceDenial.ruleRevoked }
        try MaintenanceRules.validate(grant: grant, candidate: candidate,
            featureEnabled: featureEnabled, currentPolicyRevision: currentPolicyRevision,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds,
            requireImmutableScope: false)
        try requireInterval(grant: grant, bootID: bootID,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds, nowWallDate: nowWallDate)
        return MaintenanceNotification(ruleID: grant.ruleID,
            capabilityID: grant.capabilityID, navigation: .reviewCache,
            observedBytes: candidate.allocatedBytes!)
    }

    public func beginReview(grant: MaintenanceGrant,
                            candidate: MaintenanceCandidate,
                            authority: LocalAuthoritySnapshot,
                            featureEnabled: Bool,
                            currentPolicyRevision: UInt64,
                            bootID: UUID,
                            nowMonotonicNanoseconds: UInt64,
                            nowWallDate: Date,
                            validityNanoseconds: UInt64 = 300_000_000_000) throws
        -> MaintenanceReviewToken {
        guard grant.mode == .authorizedCaches,
              authority.permits(.maintenanceCaches(grant)) else {
            throw MaintenanceDenial.authorityMissing
        }
        guard !revokedRules.contains(grant.ruleID) else { throw MaintenanceDenial.ruleRevoked }
        try MaintenanceRules.validate(grant: grant, candidate: candidate,
            featureEnabled: featureEnabled, currentPolicyRevision: currentPolicyRevision,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds,
            requireImmutableScope: true)
        try requireInterval(grant: grant, bootID: bootID,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds, nowWallDate: nowWallDate)
        guard pending.count < 64, validityNanoseconds > 0,
              validityNanoseconds <= 600_000_000_000 else {
            throw MaintenanceDenial.expiredReview
        }
        let (expiry, overflow) = nowMonotonicNanoseconds.addingReportingOverflow(validityNanoseconds)
        guard !overflow else { throw MaintenanceDenial.expiredReview }
        let token = MaintenanceReviewToken(value: UUID())
        pending[token.value] = Pending(grant: grant, candidate: candidate,
            expiresAt: expiry, selected: false)
        return token
    }

    public func select(_ token: MaintenanceReviewToken,
                       nowMonotonicNanoseconds: UInt64) throws {
        var review = try require(token, now: nowMonotonicNanoseconds)
        review.selected = true
        pending[token.value] = review
    }

    public func confirm(_ token: MaintenanceReviewToken,
                        authority: LocalAuthoritySnapshot,
                        featureEnabled: Bool,
                        currentPolicyRevision: UInt64,
                        bootID: UUID,
                        nowMonotonicNanoseconds: UInt64,
                        nowWallDate: Date) throws -> ReviewedMaintenanceRequest {
        let review = try require(token, now: nowMonotonicNanoseconds)
        guard review.selected else { throw MaintenanceDenial.notSelected }
        pending[token.value] = nil // one-shot before returning execution-shaped data
        guard !revokedRules.contains(review.grant.ruleID),
              authority.permits(.maintenanceCaches(review.grant)) else {
            throw MaintenanceDenial.authorityMissing
        }
        try MaintenanceRules.validate(grant: review.grant, candidate: review.candidate,
            featureEnabled: featureEnabled, currentPolicyRevision: currentPolicyRevision,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds,
            requireImmutableScope: true)
        try requireInterval(grant: review.grant, bootID: bootID,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds, nowWallDate: nowWallDate)
        let nanoseconds = UInt64(review.grant.deadlineSeconds) * 1_000_000_000
        let (deadline, overflow) = nowMonotonicNanoseconds.addingReportingOverflow(nanoseconds)
        guard !overflow else { throw MaintenanceDenial.expiredReview }
        schedule[review.grant.ruleID] = MaintenanceScheduleRecord(
            ruleID: review.grant.ruleID, bootID: bootID,
            monotonicNanoseconds: nowMonotonicNanoseconds, wallDate: nowWallDate)
        return ReviewedMaintenanceRequest(requestID: UUID(), grant: review.grant,
            candidate: review.candidate,
            authorizedAtMonotonicNanoseconds: nowMonotonicNanoseconds,
            schedulingDeadlineMonotonicNanoseconds: deadline)
    }

    public func revoke(ruleID: UUID) {
        revokedRules.insert(ruleID)
        pending = pending.filter { $0.value.grant.ruleID != ruleID }
    }

    public func scheduleRecords() -> [MaintenanceScheduleRecord] {
        schedule.values.sorted { $0.ruleID.uuidString < $1.ruleID.uuidString }
    }

    private func require(_ token: MaintenanceReviewToken, now: UInt64) throws -> Pending {
        guard let review = pending[token.value] else { throw MaintenanceDenial.unknownReview }
        guard now <= review.expiresAt else {
            pending[token.value] = nil
            throw MaintenanceDenial.expiredReview
        }
        return review
    }

    private func requireInterval(grant: MaintenanceGrant, bootID: UUID,
                                 nowMonotonicNanoseconds: UInt64,
                                 nowWallDate: Date) throws {
        guard scheduleValid else { throw MaintenanceDenial.clockDiscontinuity }
        try MaintenanceScheduleInterval.require(grant: grant,
            previous: schedule[grant.ruleID], bootID: bootID,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds, nowWallDate: nowWallDate)
    }
}

enum MaintenanceScheduleInterval {
    static func require(grant: MaintenanceGrant,
                        previous: MaintenanceScheduleRecord?,
                        bootID: UUID,
                        nowMonotonicNanoseconds: UInt64,
                        nowWallDate: Date) throws {
        guard let previous else { return }
        let intervalSeconds = TimeInterval(grant.minimumIntervalHours * 3_600)
        if previous.bootID == bootID {
            guard nowMonotonicNanoseconds >= previous.monotonicNanoseconds else {
                throw MaintenanceDenial.clockDiscontinuity
            }
            let required = UInt64(grant.minimumIntervalHours) * 3_600 * 1_000_000_000
            guard nowMonotonicNanoseconds - previous.monotonicNanoseconds >= required else {
                throw MaintenanceDenial.frequencyLimited
            }
        } else {
            // Across boots, monotonic values cannot be compared. Wall rollback
            // and insufficient elapsed wall time both remain fail-closed.
            guard nowWallDate >= previous.wallDate,
                  nowWallDate.timeIntervalSince(previous.wallDate) >= intervalSeconds else {
                throw MaintenanceDenial.clockDiscontinuity
            }
        }
    }
}
