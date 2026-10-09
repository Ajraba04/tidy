import Foundation

/// Sole admission authority. No registered review or token can install an adapter.
public actor ExecutionCoordinator {
    private struct Registration {
        let review: RegisteredReview
        let identities: [String: [ResourceIdentity]]
        let trees: [String: ReviewedTree]
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
    private var reconciledAtLaunch = false

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
        guard reviews.count < 8 else { throw ConfirmationError.busy }
        guard case .ready(let revision) = barrier.snapshot() else { throw ConfirmationError.stalePolicy }
        let snapshot = try barrier.withCurrentPolicy(revision: revision) { environment }
        let plan = await engine.makePlan(items: CleanCatalog.allItems, tier: tier, environment: snapshot)
        guard Set(plan.reviewItems.map(\.id)).count == plan.reviewItems.count else {
            throw ConfirmationError.unavailableSelection
        }
        let (identities, trees, unavailable) = captureReviewEvidence(plan)
        try requireAdmission()
        return try barrier.withCurrentPolicy(revision: revision) {
            guard reviews.count < 8 else { throw ConfirmationError.busy }
            let selection = PlanSelection(plan: plan, selectDefaults: selectDefaults)
            guard unavailable.isDisjoint(with: selection.selectedIDs) else { throw ConfirmationError.unavailableSelection }
            let binding = ReviewBinding(planID: UUID(), planRevision: 1, policyRevision: revision, selectedIDs: selection.selectedIDs)
            let review = RegisteredReview(binding: binding, plan: plan, selection: selection)
            reviews[binding.planID] = Registration(review: review, identities: identities, trees: trees, unavailableIdentityIDs: unavailable)
            return review
        }
    }

    /// Explicit T08.5 review path. Discovery and measurement run through the caller's bridge
    /// façade on a session this call owns for exactly the duration of planning: a fresh
    /// `CoreOrchestrationContext` is built from it and released again before returning, whether
    /// planning succeeds or fails. No scheduler, session, or process authority is created here
    /// beyond that one bounded, finished-before-return session.
    ///
    /// Valid defaults support read-only discovery from first launch. Recovery-mode
    /// policy remains unavailable and yields only explicitly unavailable catalog rows.
    public func prepareReview(engine: CleanEngine, tier: Tier, selectDefaults: Bool,
                              sessions: BridgeExplicitSessions) async throws -> RegisteredReview {
        try requireAdmission()
        guard reviews.count < 8 else { throw ConfirmationError.busy }
        guard case .ready(let revision) = barrier.snapshot() else { throw ConfirmationError.stalePolicy }
        let snapshot = try barrier.withCurrentPolicy(revision: revision) { environment }
        await sessions.awaitInitialInstall()
        var orchestrated: CleanPlan?
        if await sessions.snapshot().availability == .available {
            orchestrated = await Self.planWithOrchestration(engine: engine, tier: tier,
                environment: snapshot, sessions: sessions)
        }
        let plan: CleanPlan
        if let orchestrated {
            plan = orchestrated
        } else {
            plan = await engine.makePlan(items: CleanCatalog.allItems, tier: tier, environment: snapshot)
        }
        guard Set(plan.reviewItems.map(\.id)).count == plan.reviewItems.count else {
            throw ConfirmationError.unavailableSelection
        }
        let (identities, trees, unavailable) = captureReviewEvidence(plan)
        try requireAdmission()
        return try barrier.withCurrentPolicy(revision: revision) {
            guard reviews.count < 8 else { throw ConfirmationError.busy }
            let selection = PlanSelection(plan: plan, selectDefaults: selectDefaults)
            guard unavailable.isDisjoint(with: selection.selectedIDs) else { throw ConfirmationError.unavailableSelection }
            let binding = ReviewBinding(planID: UUID(), planRevision: 1, policyRevision: revision, selectedIDs: selection.selectedIDs)
            let review = RegisteredReview(binding: binding, plan: plan, selection: selection)
            reviews[binding.planID] = Registration(review: review, identities: identities, trees: trees, unavailableIdentityIDs: unavailable)
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
            reviews[planID] = Registration(review: next, identities: registration.identities, trees: registration.trees,
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
        reviews.removeValue(forKey: binding.planID)
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
        return await performAcceptedEffects(selected, trees: registered.trees, tier: tier, policyRevision: binding.policyRevision)
    }

    /// The only call site that dispatches a real mutation. Every item here
    /// already passed `validateSelection`, i.e. `CapabilityRegistry`
    /// accepted it, while the synchronous policy barrier was held. Each
    /// item is independently re-checked against the one sealed adapter
    /// before it is touched: this function grants no authority of its own.
    private func performAcceptedEffects(_ items: [PlannedItem], trees: [String: ReviewedTree], tier: Tier, policyRevision: UInt64) async -> RunReport {
        let startedAt = Date()
        guard let admissionStore else { return report(.storageUnavailable, tier: tier) }
        let journal: RunJournal
        do {
            let storage = try DurableJournalStorage(directory: journalDirectory)
            journal = try RunJournal(store: admissionStore, storage: storage)
            let history = RunHistoryPolicy.resolve(environment.effectivePolicy)
            try journal.applyHistoryLimits(enabled: history.enabled, days: history.days,
                bytes: history.maximumBytes, now: Date())
        } catch { return report(.storageUnavailable, tier: tier) }

        let runID = UUID()
        var sequence: UInt64 = 1
        func appendEvent(_ phase: JournalPhase) -> Bool {
            defer { sequence += 1 }
            return (try? journal.append(JournalEvent(runID: runID, sequence: sequence, phase: phase,
                operationID: nil, status: nil, reason: nil))) != nil
        }
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
                guard let tree = trees[item.id] else { throw ConfirmationError.unavailableSelection }
                let operationID = UUID()
                let effect = try DerivedDataEffectAdapter.execute(itemID: item.id, action: item.action,
                    target: target, reviewedTree: tree, operationID: operationID,
                    shouldContinue: { self.barrier.snapshot() == .ready(revision: policyRevision) }) {
                    try journal.persistIntent(PendingEffectIntent(runID: runID, operationID: operationID,
                        adapterID: DerivedDataEffectAdapter.acceptedItemID, bootID: UUID(),
                        executablePath: "", executableDevice: 0, executableInode: 0,
                        childPID: nil, childStartSeconds: nil, childStartMicroseconds: nil, phase: .prepared))
                    try journal.append(JournalEvent(runID: runID, sequence: sequence, phase: .started,
                        operationID: operationID, status: nil, reason: nil))
                    sequence += 1
                }
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
                try journal.completeFilesystemEffect(effect, runID: runID, sequence: sequence)
                sequence += 1
            } catch {
                measurementsAvailable = false
                if results.last?.id != item.id {
                    results.append(ItemResult(id: item.id, title: item.title, freedBytes: 0, succeeded: false,
                        message: "\(error)", targetOutcomes: nil, effectStatus: .failed))
                }
                if admissionStore.readAdmissionWhileLocked() != .ready { break }
            }
        }

        do { try journal.finish(runID: runID) }
        catch {
            return RunReport(tier: tier, results: results, startedAt: startedAt, finishedAt: Date(),
                freeSpaceBeforeBytes: freeSpaceBeforeBytes, freeSpaceAfterBytes: freeSpaceAfterBytes,
                disposition: .recoveryBlocked, coordinatorMeasurementsAvailable: false)
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
        let admission = admissionStore.acquire()
        if !reconciledAtLaunch, admission == .ready || admission == .uncertainAndPossiblyRunning {
            reconciledAtLaunch = true
            do {
                let journal = try RunJournal(store: admissionStore,
                    storage: DurableJournalStorage(directory: journalDirectory))
                try journal.reconcileSynchronousFilesystemEffects()
                return admissionStore.readAdmissionWhileLocked()
            } catch { return .storageUnavailable }
        }
        return admission
    }

    public func retryRecovery() -> MutationAdmission {
        guard case .idle = state else { return .busy }
        reconciledAtLaunch = false
        return mutationAdmission()
    }

    private func requireAdmission() throws {
        switch mutationAdmission() {
        case .ready: return
        case .busy: throw ConfirmationError.busy
        case .uncertainAndPossiblyRunning: throw ConfirmationError.recoveryBlocked
        case .storageUnavailable: throw ConfirmationError.storageUnavailable
        }
    }

    private func captureReviewEvidence(_ plan: CleanPlan) ->
        ([String: [ResourceIdentity]], [String: ReviewedTree], Set<String>) {
        var identities: [String: [ResourceIdentity]] = [:]
        var trees: [String: ReviewedTree] = [:]
        var unavailable = Set<String>()
        for row in plan.reviewItems where row.review.isSelectable {
            do {
                guard row.targets.count == 1, let target = row.targets.first, target.isFilesystemPath,
                      PathGuard(protectedRoots: environment.protectedRoots).isSafe(target.path,
                        mustBeUnder: row.declaredRoot, home: environment.homeDirectory) else {
                    throw ConfirmationError.unavailableSelection
                }
                let identity = try ResourcePreflight.captureFile(at: target.path)
                let tree = try ReviewedTree.capture(anchor: DirectoryAnchor.open(path: target.path), excluding: [])
                guard ResourcePreflight.unchanged(identity) else { throw ConfirmationError.unavailableSelection }
                identities[row.id] = [.filesystem(identity)]
                trees[row.id] = tree
            } catch { unavailable.insert(row.id) }
        }
        return (identities, trees, unavailable)
    }

    private func validateSelection(_ registration: Registration) throws {
        let selected = registration.review.selection.selectedItems
        guard selected.count <= (environment.effectivePolicy?.manualBatchItems ?? 100) else {
            throw ConfirmationError.unavailableSelection
        }
        var bytes: Int64 = 0
        for tree in selected.compactMap({ registration.trees[$0.id] }) {
            for leaf in tree.batches.lazy.flatMap(\.entries) {
                guard let allocated = leaf.snapshot.allocatedBytes, allocated >= 0 else {
                    throw ConfirmationError.unavailableSelection
                }
                let (sum, overflow) = bytes.addingReportingOverflow(allocated)
                guard !overflow, sum <= (environment.effectivePolicy?.manualBatchBytes ?? 107_374_182_400) else {
                    throw ConfirmationError.unavailableSelection
                }
                bytes = sum
            }
        }
        for row in registration.review.selection.selectedItems {
            guard row.review.isSelectable,
                  CapabilityRegistry.denialReason(for: row.action, itemID: row.id) == nil,
                  !registration.unavailableIdentityIDs.contains(row.id),
                  let identities = registration.identities[row.id], identities.count == row.targets.count,
                  identities.allSatisfy({ identity in
                      if case .filesystem(let file) = identity { return ResourcePreflight.unchanged(file) }
                      return false
                  }), registration.trees[row.id] != nil else {
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

    /// Owns one bounded session for exactly the duration of orchestration-based planning and
    /// always releases it before returning. `nil` means the caller must fall back to the
    /// legacy shape — never a thrown error that would otherwise abort a review that could still
    /// be shown truthfully.
    private static func planWithOrchestration(engine: CleanEngine, tier: Tier,
                                              environment: CleanEnvironment,
                                              sessions: BridgeExplicitSessions) async -> CleanPlan? {
        let session: WorkSession
        do {
            session = try await sessions.beginSession(
                requirements: SchedulerRequirements(features: [.headroom]))
        } catch { return nil }
        do {
            let orchestration = try await CoreOrchestrationContext.make(sessions: sessions,
                session: session, sessionID: UUID())
            let plan = await engine.makePlan(items: CleanCatalog.allItems, tier: tier,
                environment: environment, orchestration: orchestration)
            await sessions.finish(session: session)
            return plan
        } catch {
            await sessions.finish(session: session)
            return nil
        }
    }

    private func report(_ disposition: RunDisposition, tier: Tier = .safe) -> RunReport {
        RunReport(tier: tier, results: [], startedAt: Date(), finishedAt: Date(),
                  freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0,
                  disposition: disposition, coordinatorMeasurementsAvailable: false)
    }
}
