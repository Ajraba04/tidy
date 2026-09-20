import Foundation

public enum GracefulTerminationObservation: Equatable, Sendable {
    case exited
    case alreadyExited
    case refused
    case timedOut
    case unavailable
}

/// The app layer may implement this with NSRunningApplication. The Core
/// contract exposes no signal, force-quit, AppleScript, or restart operation.
public protocol GracefulApplicationTerminating: Sendable {
    func requestGracefulTermination(of workload: WorkloadIdentity,
                                    timeoutSeconds: Int,
                                    authorization: GracefulTerminationAuthorization) async
        -> GracefulTerminationObservation
}

public struct RescueLivePolicy: Sendable {
    public let revision: UInt64
    public let policy: EffectivePolicy?

    public init(revision: UInt64, policy: EffectivePolicy?) {
        self.revision = revision
        self.policy = policy
    }

    fileprivate var rescueEnabled: Bool {
        policy?.allowedFeatures.contains("rescue") == true
    }
}

public struct GracefulTerminationAuthorization: Sendable {
    private let workload: WorkloadIdentity
    private let approval: RescueApplicationApproval
    private let authority: LocalAuthoritySnapshot
    private let policyRevision: UInt64
    private let livePolicy: @MainActor @Sendable () -> RescueLivePolicy

    fileprivate init(workload: WorkloadIdentity,
                     approval: RescueApplicationApproval,
                     authority: LocalAuthoritySnapshot,
                     policyRevision: UInt64,
                     livePolicy: @escaping @MainActor @Sendable () -> RescueLivePolicy) {
        self.workload = workload
        self.approval = approval
        self.authority = authority
        self.policyRevision = policyRevision
        self.livePolicy = livePolicy
    }

    /// Production calls this synchronously inside the same MainActor block as
    /// the exact graceful request. There is no public initializer or Boolean
    /// authority shortcut.
    @MainActor public func permitsTermination(of current: WorkloadIdentity) -> Bool {
        let currentPolicy = livePolicy()
        return current == workload && approval.contains(current)
            && authority.permits(.rescueApplication(approval))
            && currentPolicy.revision == policyRevision
            && currentPolicy.rescueEnabled
    }
}

public struct RescueReviewToken: Hashable, Sendable {
    fileprivate let value: UUID
    fileprivate let generation: UInt64
    fileprivate init(value: UUID, generation: UInt64) {
        self.value = value
        self.generation = generation
    }
}

public struct RescueReview: Sendable {
    public let token: RescueReviewToken
    public let workload: WorkloadIdentity
    public let isSelected: Bool

    fileprivate init(token: RescueReviewToken, workload: WorkloadIdentity,
                     isSelected: Bool) {
        self.token = token
        self.workload = workload
        self.isSelected = isSelected
    }
}

public enum RescueDenial: Error, Equatable, Sendable {
    case notApproved
    case unknownReview
    case expiredReview
    case wrongOwner
    case notSelected
    case identityChanged
    case invalidTimeout
    case capacityExceeded
    case policyChanged
    case featureDisabled
}

public struct RescueMemoryObservation: Equatable, Sendable {
    public let beforeAvailableBytes: Int64?
    public let afterAvailableBytes: Int64?
    /// A signed system-wide observation. It is intentionally not attributed to
    /// the application and may be negative because unrelated work is noisy.
    public let noisyAvailableByteDelta: Int64?

    public init(beforeAvailableBytes: Int64?, afterAvailableBytes: Int64?) {
        self.beforeAvailableBytes = Self.valid(beforeAvailableBytes)
        self.afterAvailableBytes = Self.valid(afterAvailableBytes)
        if let before = self.beforeAvailableBytes, let after = self.afterAvailableBytes {
            let (delta, overflow) = after.subtractingReportingOverflow(before)
            noisyAvailableByteDelta = overflow ? nil : delta
        } else {
            noisyAvailableByteDelta = nil
        }
    }

    private static func valid(_ value: Int64?) -> Int64? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}

public struct RescueOutcome: Equatable, Sendable {
    public let workload: WorkloadIdentity
    public let termination: GracefulTerminationObservation
    public let memory: RescueMemoryObservation

    public init(workload: WorkloadIdentity, termination: GracefulTerminationObservation,
                memory: RescueMemoryObservation = .init(beforeAvailableBytes: nil,
                                                        afterAvailableBytes: nil)) {
        self.workload = workload
        self.termination = termination
        self.memory = memory
    }

    public func recordingSystemObservation(beforeAvailableBytes: Int64?,
                                           afterAvailableBytes: Int64?) -> Self {
        Self(workload: workload, termination: termination,
             memory: .init(beforeAvailableBytes: beforeAvailableBytes,
                           afterAvailableBytes: afterAvailableBytes))
    }
}

public actor RescuePlanner {
    private struct Pending: Sendable {
        let workload: WorkloadIdentity
        let approval: RescueApplicationApproval
        let authority: LocalAuthoritySnapshot
        let policyRevision: UInt64
        let owner: UUID
        let deadlineNanoseconds: UInt64
        let generation: UInt64
        var selected: Bool
    }

    private let terminator: any GracefulApplicationTerminating
    private let livePolicy: @MainActor @Sendable () -> RescueLivePolicy
    private static let maximumPendingReviews = 64
    private var pending: [UUID: Pending] = [:]
    private var generation: UInt64 = 0

    public init(terminator: any GracefulApplicationTerminating,
                livePolicy: @escaping @MainActor @Sendable () -> RescueLivePolicy) {
        self.terminator = terminator
        self.livePolicy = livePolicy
    }

    public func beginReview(workload: WorkloadIdentity,
                            approval: RescueApplicationApproval,
                            authority: LocalAuthoritySnapshot,
                            owner: UUID,
                            nowMonotonicNanoseconds: UInt64,
                            validityNanoseconds: UInt64 = 300_000_000_000) async throws -> RescueReview {
        let capturedPolicy = await livePolicy()
        guard capturedPolicy.rescueEnabled else { throw RescueDenial.featureDisabled }
        guard authority.permits(.rescueApplication(approval)),
              approval.isCurrent(), approval.contains(workload) else {
            throw RescueDenial.notApproved
        }
        guard validityNanoseconds > 0, validityNanoseconds <= 600_000_000_000 else {
            throw RescueDenial.expiredReview
        }
        pending = pending.filter { $0.value.deadlineNanoseconds >= nowMonotonicNanoseconds }
        guard pending.count < Self.maximumPendingReviews else {
            throw RescueDenial.capacityExceeded
        }
        let (deadline, overflow) = nowMonotonicNanoseconds.addingReportingOverflow(validityNanoseconds)
        guard !overflow else { throw RescueDenial.expiredReview }
        generation &+= 1
        let token = RescueReviewToken(value: UUID(), generation: generation)
        guard authority.permits(.rescueApplication(approval)) else {
            throw RescueDenial.notApproved
        }
        pending[token.value] = Pending(workload: workload, approval: approval,
            authority: authority, policyRevision: capturedPolicy.revision,
            owner: owner, deadlineNanoseconds: deadline,
            generation: token.generation, selected: false)
        return RescueReview(token: token, workload: workload, isSelected: false)
    }

    @discardableResult
    public func select(_ token: RescueReviewToken, owner: UUID,
                       nowMonotonicNanoseconds: UInt64) async throws -> RescueReview {
        var review = try require(token, owner: owner, now: nowMonotonicNanoseconds)
        let policy = await livePolicy()
        review = try require(token, owner: owner, now: nowMonotonicNanoseconds)
        try requirePolicy(policy, revision: review.policyRevision)
        review.selected = true
        pending[token.value] = review
        return RescueReview(token: token, workload: review.workload, isSelected: true)
    }

    public func cancel(_ token: RescueReviewToken, owner: UUID) throws {
        guard let review = pending[token.value] else { throw RescueDenial.unknownReview }
        guard review.owner == owner else { throw RescueDenial.wrongOwner }
        pending[token.value] = nil
    }

    public func requestGracefulTermination(_ token: RescueReviewToken,
                                           owner: UUID,
                                           currentIdentity: WorkloadIdentity?,
                                           nowMonotonicNanoseconds: UInt64,
                                           timeoutSeconds: Int) async throws -> RescueOutcome {
        var review = try require(token, owner: owner, now: nowMonotonicNanoseconds)
        let policy = await livePolicy()
        review = try require(token, owner: owner, now: nowMonotonicNanoseconds)
        try requirePolicy(policy, revision: review.policyRevision)
        guard review.selected else { throw RescueDenial.notSelected }
        guard (5...60).contains(timeoutSeconds) else { throw RescueDenial.invalidTimeout }
        guard let currentIdentity else {
            pending[token.value] = nil
            return RescueOutcome(workload: review.workload, termination: .alreadyExited)
        }
        guard currentIdentity == review.workload else { throw RescueDenial.identityChanged }
        guard review.authority.permits(.rescueApplication(review.approval)) else {
            throw RescueDenial.notApproved
        }
        let authorization = GracefulTerminationAuthorization(
            workload: review.workload, approval: review.approval,
            authority: review.authority, policyRevision: review.policyRevision,
            livePolicy: livePolicy)
        guard await authorization.permitsTermination(of: currentIdentity) else {
            throw RescueDenial.policyChanged
        }
        review = try require(token, owner: owner, now: nowMonotonicNanoseconds)
        guard review.selected, currentIdentity == review.workload else {
            throw RescueDenial.identityChanged
        }
        pending[token.value] = nil // consume before crossing the termination boundary
        let observation = await terminator.requestGracefulTermination(
            of: currentIdentity, timeoutSeconds: timeoutSeconds,
            authorization: authorization)
        return RescueOutcome(workload: review.workload, termination: observation)
    }

    private func require(_ token: RescueReviewToken, owner: UUID,
                         now: UInt64) throws -> Pending {
        guard let review = pending[token.value], review.generation == token.generation else {
            throw RescueDenial.unknownReview
        }
        guard review.owner == owner else { throw RescueDenial.wrongOwner }
        guard review.authority.permits(.rescueApplication(review.approval)) else {
            pending[token.value] = nil
            throw RescueDenial.notApproved
        }
        guard now <= review.deadlineNanoseconds else {
            pending[token.value] = nil
            throw RescueDenial.expiredReview
        }
        return review
    }

    private func requirePolicy(_ policy: RescueLivePolicy,
                               revision: UInt64) throws {
        guard policy.revision == revision else { throw RescueDenial.policyChanged }
        guard policy.rescueEnabled else { throw RescueDenial.featureDisabled }
    }
}
