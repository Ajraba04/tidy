import Foundation

/// Sole admission authority. No registered review or token can install an adapter.
public actor ExecutionCoordinator {
    private struct Registration {
        let review: RegisteredReview
        let identities: [String: [ResourceIdentity]]
        let unavailableIdentityIDs: Set<String>
    }
    private enum State { case idle, running(runID: UUID) }
    private struct Rejection { let planID: UUID; let disposition: RunDisposition }
    private let id: UUID
    private nonisolated let barrier: PolicyInvalidationBarrier
    private var environment: CleanEnvironment
    private let admissionStore: MutationAdmissionStore?
    private var state: State = .idle
    private var reviews: [UUID: Registration] = [:]
    private var tokens: [UUID: ReviewBinding] = [:]
    private var rejections: [UUID: Rejection] = [:]
    private var rejectionOrder: [UUID] = []

    public init(environment: CleanEnvironment, journalDirectory: URL) {
        let id = UUID()
        self.id = id
        self.barrier = PolicyInvalidationBarrier(coordinatorID: id)
        self.environment = environment
        self.admissionStore = try? MutationAdmissionStore(directory: journalDirectory)
    }

    public func prepareReview(engine: CleanEngine, tier: Tier, selectDefaults: Bool) async throws -> RegisteredReview {
        try requireAdmission()
        guard case .ready(let revision) = barrier.snapshot() else { throw ConfirmationError.stalePolicy }
        let snapshot = try barrier.withCurrentPolicy(revision: revision) { environment }
        let plan = await engine.makePlan(items: CleanCatalog.allItems, tier: tier, environment: snapshot)
        guard Set(plan.reviewItems.map(\.id)).count == plan.reviewItems.count else {
            throw ConfirmationError.unavailableSelection
        }
        var identities: [String: [ResourceIdentity]] = [:]
        var unavailable: Set<String> = []
        for row in plan.reviewItems {
            var captured: [ResourceIdentity] = []
            for target in row.targets {
                if target.isFilesystemPath, let identity = try? ResourcePreflight.captureFile(at: target.path) {
                    captured.append(.filesystem(identity))
                } else { unavailable.insert(row.id) }
            }
            identities[row.id] = captured
        }
        try requireAdmission()
        return try barrier.withCurrentPolicy(revision: revision) {
            let selection = PlanSelection(plan: plan, selectDefaults: selectDefaults)
            guard unavailable.isDisjoint(with: selection.selectedIDs) else { throw ConfirmationError.unavailableSelection }
            let binding = ReviewBinding(planID: UUID(), planRevision: 1, policyRevision: revision, selectedIDs: selection.selectedIDs)
            let review = RegisteredReview(binding: binding, plan: plan, selection: selection)
            reviews[binding.planID] = Registration(review: review, identities: identities, unavailableIdentityIDs: unavailable)
            return review
        }
    }

    public func setSelection(planID: UUID, selectedIDs: Set<String>) throws -> RegisteredReview {
        guard let registration = reviews[planID] else { throw ConfirmationError.unknownPlan }
        let old = registration.review
        let ids = Set(old.plan.reviewItems.map(\.id))
        guard selectedIDs.isSubset(of: ids) else { throw ConfirmationError.unknownSelectedID }
        var selection = PlanSelection(plan: old.plan, selectDefaults: false)
        for id in selectedIDs { selection.setSelected(true, id: id) }
        guard selection.selectedIDs == selectedIDs,
              registration.unavailableIdentityIDs.isDisjoint(with: selectedIDs) else {
            throw ConfirmationError.unavailableSelection
        }
        return try barrier.withCurrentPolicy(revision: old.binding.policyRevision) {
            guard old.binding.planRevision < UInt64.max else { throw ConfirmationError.staleReview }
            let binding = ReviewBinding(planID: planID, planRevision: old.binding.planRevision + 1,
                                        policyRevision: old.binding.policyRevision, selectedIDs: selectedIDs)
            let next = RegisteredReview(binding: binding, plan: old.plan, selection: selection)
            invalidateTokens(planID: planID, reason: .staleReview)
            reviews[planID] = Registration(review: next, identities: registration.identities,
                                           unavailableIdentityIDs: registration.unavailableIdentityIDs)
            return next
        }
    }

    public func confirm(binding: ReviewBinding) throws -> ConfirmedPlan { try mintConfirmedPlan(binding: binding) }

    internal func reserveConfirmation(binding: ReviewBinding) throws -> (coordinatorID: UUID, nonce: UUID) {
        guard let registered = reviews[binding.planID] else { throw ConfirmationError.unknownPlan }
        try requireAdmission()
        return try barrier.withCurrentPolicy(revision: binding.policyRevision) {
            guard registered.review.binding.matches(binding) else { throw ConfirmationError.staleReview }
            try validateSelection(registered)
            invalidateTokens(planID: binding.planID, reason: .staleReview)
            let nonce = UUID()
            tokens[nonce] = binding
            return (id, nonce)
        }
    }

    public func execute(_ token: ConfirmedPlan, currentPolicyRevision: UInt64) async -> RunReport {
        if case .running = state { return report(.busy) }
        guard token.coordinatorID == id else { return report(.invalidToken) }
        let binding = tokens[token.nonce]
        let rejection = rejections[token.nonce]
        guard binding != nil || rejection != nil else { return report(.invalidToken) }
        state = .running(runID: UUID())
        defer { admissionStore?.release(); state = .idle }
        let admission = admissionStore?.acquire() ?? .storageUnavailable
        if admission == .busy { return report(.busy) } // reservation released; genuine token retained
        tokens.removeValue(forKey: token.nonce)
        rejections.removeValue(forKey: token.nonce)
        rejectionOrder.removeAll { $0 == token.nonce }
        switch admission {
        case .ready: break
        case .busy: return report(.busy)
        case .storageUnavailable: return report(.storageUnavailable)
        case .uncertainAndPossiblyRunning: return report(.recoveryBlocked)
        }
        if let rejection { return report(rejection.disposition) }
        guard let binding, let registered = reviews[binding.planID] else { return report(.invalidToken) }
        let tier = registered.review.plan.tier
        do {
            // This is the final synchronous no-op commit, not a permit for a later effect.
            return try barrier.withCurrentPolicy(revision: binding.policyRevision) {
                guard currentPolicyRevision == binding.policyRevision else { throw ConfirmationError.stalePolicy }
                guard registered.review.binding == binding else { throw ConfirmationError.staleReview }
                try validateSelection(registered)
                guard registered.review.selection.selectedItems.isEmpty else {
                    // T03/T04 must supply sealed, bounded adapters; raw engine execution is never called.
                    throw ConfirmationError.unavailableSelection
                }
                return report(.noWork, tier: tier)
            }
        } catch let error as ConfirmationError {
            switch error {
            case .stalePolicy: return report(.stalePolicy, tier: tier)
            case .staleReview: return report(.staleReview, tier: tier)
            default: return report(.unavailableSelection, tier: tier)
            }
        } catch { return report(.unavailableSelection, tier: tier) }
    }

    public nonisolated func beginPolicyUpdate() throws -> PolicyUpdateTicket { try barrier.beginUpdate() }
    public nonisolated func policyAdmission() -> PolicyAdmission { barrier.snapshot() }
    internal func commitPolicyUpdate(_ ticket: PolicyUpdateTicket, environment: CleanEnvironment) throws -> PolicyCommit {
        try barrier.commit(ticket) {
            self.environment = environment
            return PolicyCommit.applied(revision: ticket.revision)
        } ?? .superseded
    }
    public func currentPolicyRevision() -> UInt64 {
        switch barrier.snapshot() {
        case .ready(let revision), .updating(let revision): return revision
        case .unavailable: return UInt64.max
        }
    }

    public func discardReview(planID: UUID) {
        reviews.removeValue(forKey: planID)
        tokens = tokens.filter { $0.value.planID != planID }
        rejections = rejections.filter { $0.value.planID != planID }
        rejectionOrder.removeAll { rejections[$0] == nil }
    }

    public func mutationAdmission() -> MutationAdmission {
        if case .running = state { return .busy }
        guard let admissionStore else { return .storageUnavailable }
        defer { admissionStore.release() }
        return admissionStore.acquire()
    }

    private func requireAdmission() throws {
        switch mutationAdmission() {
        case .ready: return
        case .busy: throw ConfirmationError.busy
        case .uncertainAndPossiblyRunning: throw ConfirmationError.recoveryBlocked
        case .storageUnavailable: throw ConfirmationError.storageUnavailable
        }
    }

    private func validateSelection(_ registration: Registration) throws {
        for row in registration.review.selection.selectedItems {
            guard row.review.isSelectable,
                  CapabilityRegistry.denialReason(for: row.action, itemID: row.id) == nil,
                  !registration.unavailableIdentityIDs.contains(row.id) else {
                throw ConfirmationError.unavailableSelection
            }
        }
    }

    private func invalidateTokens(planID: UUID, reason: RunDisposition) {
        let invalidated = tokens.filter { $0.value.planID == planID }.map(\.key)
        for nonce in invalidated {
            tokens.removeValue(forKey: nonce)
            rejections[nonce] = Rejection(planID: planID, disposition: reason)
            rejectionOrder.append(nonce)
        }
        // Diagnostic reasons are bounded and never survive review disposal or process exit.
        while rejectionOrder.count > 256 {
            rejections.removeValue(forKey: rejectionOrder.removeFirst())
        }
    }

    private func report(_ disposition: RunDisposition, tier: Tier = .safe) -> RunReport {
        RunReport(tier: tier, results: [], startedAt: Date(), finishedAt: Date(),
                  freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0,
                  disposition: disposition, coordinatorMeasurementsAvailable: false)
    }
}
