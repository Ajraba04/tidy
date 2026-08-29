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
    private let journalDirectory: URL
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
        self.journalDirectory = journalDirectory
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
        let selected: [PlannedItem]
        do {
            // Everything above and inside this closure is the final
            // synchronous commit: revision/binding/capability checks only.
            // Real effects never run while the synchronous policy barrier is
            // held, so a slow or uninterruptible syscall below cannot block
            // policy invalidation.
            selected = try barrier.withCurrentPolicy(revision: binding.policyRevision) { () -> [PlannedItem] in
                guard currentPolicyRevision == binding.policyRevision else { throw ConfirmationError.stalePolicy }
                guard registered.review.binding == binding else { throw ConfirmationError.staleReview }
                try validateSelection(registered)
                return registered.review.selection.selectedItems
            }
        } catch let error as ConfirmationError {
            switch error {
            case .stalePolicy: return report(.stalePolicy, tier: tier)
            case .staleReview: return report(.staleReview, tier: tier)
            default: return report(.unavailableSelection, tier: tier)
            }
        } catch { return report(.unavailableSelection, tier: tier) }

        guard !selected.isEmpty else { return report(.noWork, tier: tier) }
        return await performAcceptedEffects(selected, tier: tier)
    }

    /// The only call site that dispatches a real mutation. Every item here
    /// already passed `validateSelection`, i.e. `CapabilityRegistry`
    /// accepted it, while the synchronous policy barrier was held. Each
    /// item is independently re-checked against the one sealed adapter
    /// before it is touched: this function grants no authority of its own.
    private func performAcceptedEffects(_ items: [PlannedItem], tier: Tier) async -> RunReport {
        let startedAt = Date()
        guard let admissionStore else { return report(.storageUnavailable, tier: tier) }
        let journal: RunJournal
        do {
            let storage = try DurableJournalStorage(directory: journalDirectory)
            journal = try RunJournal(store: admissionStore, storage: storage)
        } catch { return report(.storageUnavailable, tier: tier) }

        let runID = UUID()
        var sequence: UInt64 = 1
        func appendEvent(_ phase: JournalPhase) -> Bool {
            defer { sequence += 1 }
            return (try? journal.append(JournalEvent(runID: runID, sequence: sequence, phase: phase,
                operationID: nil, status: nil, reason: nil))) != nil
        }
        // `RunJournal.append(.started)` requires a matching `PendingEffectIntent`
        // already durably persisted in the single mandatory admission ledger,
        // and there is no accepted API anywhere in this package that later
        // removes a persisted intent (RunRecoveryTests.diagnosticSucceededNeverSuppliesTerminalProof
        // proves `.itemTerminal(.succeeded)` does not reconcile one either).
        // Persisting one here would make every future mutation across the
        // whole app permanently `.uncertainAndPossiblyRunning` after the
        // very first real cleanup, which is a strictly worse outcome than a
        // narrower journal record. Until a reviewed reconciliation primitive
        // lands in `MutationAdmissionStore`, this coordinator only records
        // the confirmed intent to run (`.planned`/`.confirmed`), never a
        // per-operation `.started`/`.itemTerminal`/`.finished` sequence for a
        // real effect. Journal failures below latch the mandatory admission
        // store unavailable on their own (`RunJournal.observed`); this run
        // simply stops making progress rather than report a success it
        // cannot durably record.
        guard appendEvent(.planned) else { return report(.storageUnavailable, tier: tier) }
        guard appendEvent(.confirmed) else { return report(.storageUnavailable, tier: tier) }

        let guardian = PathGuard(protectedRoots: environment.protectedRoots)
        var results: [ItemResult] = []
        var freeSpaceBeforeBytes: Int64 = 0
        var freeSpaceAfterBytes: Int64 = 0
        var capturedFirstMeasurement = false
        var measurementsAvailable = true

        for item in items {
            guard CapabilityRegistry.denialReason(for: item.action, itemID: item.id) == nil,
                  item.targets.count == 1, let target = item.targets.first,
                  guardian.isSafe(target.path, mustBeUnder: item.declaredRoot, home: environment.homeDirectory) else {
                results.append(ItemResult(id: item.id, title: item.title, freedBytes: 0, succeeded: false,
                    message: CapabilityRegistry.quarantineReason, targetOutcomes: nil, effectStatus: .skipped))
                continue
            }
            do {
                let effect = try DerivedDataEffectAdapter.execute(itemID: item.id, action: item.action, target: target)
                if !capturedFirstMeasurement, let before = effect.freeSpaceBeforeBytes {
                    freeSpaceBeforeBytes = before
                    capturedFirstMeasurement = true
                }
                if let after = effect.freeSpaceAfterBytes { freeSpaceAfterBytes = after }
                else { measurementsAvailable = false }
                let status = EffectAccounting.aggregateStatus(effect.outcomes)
                let freed = EffectAccounting.checkedSum(effect.outcomes.map(\.removedAllocatedBytes))
                results.append(ItemResult(id: item.id, title: item.title, freedBytes: freed.bytes ?? 0,
                    succeeded: status == .succeeded, message: nil,
                    targetOutcomes: effect.outcomes, effectStatus: status))
            } catch {
                measurementsAvailable = false
                results.append(ItemResult(id: item.id, title: item.title, freedBytes: 0, succeeded: false,
                    message: "\(error)", targetOutcomes: nil, effectStatus: .failed))
            }
        }

        return RunReport(tier: tier, results: results, startedAt: startedAt, finishedAt: Date(),
            freeSpaceBeforeBytes: freeSpaceBeforeBytes, freeSpaceAfterBytes: freeSpaceAfterBytes,
            disposition: .completed,
            coordinatorMeasurementsAvailable: measurementsAvailable && capturedFirstMeasurement)
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
