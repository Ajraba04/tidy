import Foundation
public struct ReviewBinding: Equatable, Sendable {
    public let planID: UUID
    public let planRevision: UInt64
    public let policyRevision: UInt64
    public let selectedIDs: Set<String>
    public init(planID: UUID, planRevision: UInt64, policyRevision: UInt64, selectedIDs: Set<String>) {
        self.planID = planID; self.planRevision = planRevision
        self.policyRevision = policyRevision; self.selectedIDs = selectedIDs
    }
    public func matches(_ other: Self) -> Bool { self == other }
}
public struct RegisteredReview: Sendable {
    public let binding: ReviewBinding
    public let plan: CleanPlan
    public let selection: PlanSelection
}
public enum ConfirmationError: Error, Equatable, Sendable {
    case unknownPlan, staleReview, stalePolicy, unknownSelectedID
    case unavailableSelection, busy, recoveryBlocked, storageUnavailable
}
public struct ConfirmedPlan: Sendable {
    internal let coordinatorID: UUID
    internal let nonce: UUID
    fileprivate init(coordinatorID: UUID, nonce: UUID) {
        self.coordinatorID = coordinatorID; self.nonce = nonce
    }
}
extension ExecutionCoordinator {
    internal func mintConfirmedPlan(binding: ReviewBinding) throws -> ConfirmedPlan {
        let reservation = try reserveConfirmation(binding: binding)
        return ConfirmedPlan(coordinatorID: reservation.coordinatorID, nonce: reservation.nonce)
    }
}
public enum RunDisposition: String, Codable, Sendable {
    case completed, noWork, invalidToken, staleReview, stalePolicy
    case busy, recoveryBlocked, storageUnavailable, unavailableSelection
}
public enum MutationAdmission: Equatable, Sendable {
    case ready, busy, uncertainAndPossiblyRunning, storageUnavailable
}
