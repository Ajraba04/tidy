import Foundation

/// Sole admission authority. No registered review or token can install an adapter.
public actor ExecutionCoordinator {
    private struct Registration {
        let review: RegisteredReview
        let identities: [String: [ResourceIdentity]]
        let reviewedFiles: [String: [ReviewedFileResource]]
        let inventory: [String: [InventoryRecord]]
        let associations: [String: [ResourceAssociationEvidence]]
        let unavailableIdentityIDs: Set<String>
    }
    private enum State { case idle, running(runID: UUID) }
    private struct Rejection { let planID: UUID; let disposition: RunDisposition }
    private struct CapturedReviewResources {
        let identities: [String: [ResourceIdentity]]
        let reviewedFiles: [String: [ReviewedFileResource]]
        let inventory: [String: [InventoryRecord]]
        let associations: [String: [ResourceAssociationEvidence]]
        let unavailable: Set<String>
    }
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
    private var progressPhase: ExecutionProgressPhase = .idle
    private var completedEffects = 0
    private var scheduledEffects = 0
    private var cancellation: EffectCancellationToken?
    private nonisolated let cancellationRelay = ExecutionCancellationRelay()
    private var cachedRecovery: MutationAdmission = .storageUnavailable
    private var progressSubscribers: [UUID:
        AsyncStream<ExecutionProgressSnapshot>.Continuation] = [:]
    private static let maximumProgressSubscribers = 8

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
        let captured = Self.captureReviewResources(plan: plan, environment: snapshot)
        try requireAdmission()
        return try barrier.withCurrentPolicy(revision: revision) {
            let selection = PlanSelection(plan: plan, selectDefaults: selectDefaults)
            guard captured.unavailable.isDisjoint(with: selection.selectedIDs) else { throw ConfirmationError.unavailableSelection }
            let binding = ReviewBinding(planID: UUID(), planRevision: 1, policyRevision: revision, selectedIDs: selection.selectedIDs)
            let review = RegisteredReview(binding: binding, plan: plan, selection: selection)
            reviews[binding.planID] = Registration(review: review, identities: captured.identities,
                reviewedFiles: captured.reviewedFiles, inventory: captured.inventory,
                associations: captured.associations,
                unavailableIdentityIDs: captured.unavailable)
            return review
        }
    }

    /// Explicit T08.5 review path. Discovery and measurement run through the caller's bridge
    /// façade on a session this call owns for exactly the duration of planning: a fresh
    /// `CoreOrchestrationContext` is built from it and released again before returning, whether
    /// planning succeeds or fails. No scheduler, session, or process authority is created here
    /// beyond that one bounded, finished-before-return session.
    ///
    /// A revision-zero/fresh-install envelope deliberately leaves the scheduler façade
    /// `.unavailable` until a real settings save completes (T08.1b). That is not treated as a
    /// review failure: every catalog row must still be visible with an honest status, so this
    /// falls back to the pre-orchestration planning shape in that case — the exact same
    /// "unavailable, here is why" rows the legacy path has always produced. This is a truthful
    /// degrade, not a silent one: no row is ever claimed discovered or measured that wasn't.
    public func prepareReview(engine: CleanEngine, tier: Tier, selectDefaults: Bool,
                              sessions: BridgeExplicitSessions) async throws -> RegisteredReview {
        try requireAdmission()
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
        let captured = Self.captureReviewResources(plan: plan, environment: snapshot)
        try requireAdmission()
        return try barrier.withCurrentPolicy(revision: revision) {
            let selection = PlanSelection(plan: plan, selectDefaults: selectDefaults)
            guard captured.unavailable.isDisjoint(with: selection.selectedIDs) else { throw ConfirmationError.unavailableSelection }
            let binding = ReviewBinding(planID: UUID(), planRevision: 1, policyRevision: revision, selectedIDs: selection.selectedIDs)
            let review = RegisteredReview(binding: binding, plan: plan, selection: selection)
            reviews[binding.planID] = Registration(review: review, identities: captured.identities,
                reviewedFiles: captured.reviewedFiles, inventory: captured.inventory,
                associations: captured.associations,
                unavailableIdentityIDs: captured.unavailable)
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
                                           reviewedFiles: registration.reviewedFiles,
                                           inventory: registration.inventory,
                                           associations: registration.associations,
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
        let executionRunID = UUID()
        state = .running(runID: executionRunID)
        progressPhase = .preparing
        completedEffects = 0
        scheduledEffects = 0
        cancellation = EffectCancellationToken()
        let runCancellation = cancellation!
        cancellationRelay.install(runCancellation)
        publishProgress()
        defer {
            admissionStore?.release()
            cancellationRelay.clear(runCancellation)
            state = .idle
            progressPhase = .idle
            completedEffects = 0
            scheduledEffects = 0
            cancellation = nil
            if let admissionStore {
                cachedRecovery = admissionStore.acquire()
                admissionStore.release()
            } else {
                cachedRecovery = .storageUnavailable
            }
            publishProgress()
        }
        let admission = admissionStore?.acquire() ?? .storageUnavailable
        cachedRecovery = admission
        publishProgress()
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
        scheduledEffects = selected.count
        progressPhase = .executing
        publishProgress()
        return await performAcceptedEffects(selected, registration: registered,
            binding: binding, runID: executionRunID, tier: tier)
    }

    /// The only call site that dispatches a real mutation. Every item here
    /// already passed `validateSelection`, i.e. `CapabilityRegistry`
    /// accepted it, while the synchronous policy barrier was held. Each
    /// item is independently re-checked against the one sealed adapter
    /// before it is touched: this function grants no authority of its own.
    private func performAcceptedEffects(_ items: [PlannedItem], registration: Registration,
                                        binding: ReviewBinding, runID: UUID,
                                        tier: Tier) async -> RunReport {
        let startedAt = Date()
        guard let admissionStore else { return report(.storageUnavailable, tier: tier) }
        let journal: RunJournal
        do {
            let storage = try DurableJournalStorage(directory: journalDirectory)
            journal = try RunJournal(store: admissionStore, storage: storage)
        } catch { return report(.storageUnavailable, tier: tier) }

        var sequence: UInt64 = 1
        func appendEvent(_ phase: JournalPhase) -> Bool {
            defer { sequence += 1 }
            return (try? journal.append(JournalEvent(runID: runID, sequence: sequence, phase: phase,
                operationID: nil, status: nil, reason: nil))) != nil
        }
        // Every accepted target below persists its immutable manifest and
        // versioned intent before `.started`; terminal proof is durable before
        // the intent can be retired. Journal failure stops further dispatch.
        guard appendEvent(.planned) else { return report(.storageUnavailable, tier: tier) }
        guard appendEvent(.confirmed) else { return report(.storageUnavailable, tier: tier) }

        let guardian = PathGuard(protectedRoots: environment.protectedRoots)
        var results: [ItemResult] = []
        var freeSpaceBeforeBytes: Int64 = 0
        var freeSpaceAfterBytes: Int64 = 0
        var capturedFirstMeasurement = false
        var measurementsAvailable = true

        for item in items {
            if cancellation?.isCancelled == true || Task.isCancelled {
                results.append(ItemResult(id: item.id, title: item.title, freedBytes: 0,
                    succeeded: false, message: "Cancelled before the next effect boundary.",
                    targetOutcomes: nil, effectStatus: .cancelled))
                completedEffects += 1
                publishProgress()
                continue
            }
            guard CapabilityRegistry.denialReason(for: item.action, itemID: item.id) == nil,
                  item.targets.count == 1, let target = item.targets.first,
                  guardian.isSafe(target.path, mustBeUnder: item.declaredRoot, home: environment.homeDirectory) else {
                results.append(ItemResult(id: item.id, title: item.title, freedBytes: 0, succeeded: false,
                    message: CapabilityRegistry.quarantineReason, targetOutcomes: nil, effectStatus: .skipped))
                completedEffects += 1
                publishProgress()
                continue
            }
            do {
                guard item.id == DerivedDataEffectAdapter.acceptedItemID,
                      let provider = AppleDerivedDataInventory.productionLeaseProvider,
                      let association = registration.associations[item.id]?.first else {
                    throw DerivedDataEffectAdapter.AdapterError.productionProofUnavailable
                }
                let completed = try executeRegisteredFilesystemTarget(
                    registration: registration, binding: binding, item: item,
                    targetOrdinal: 0, runID: runID, journal: journal,
                    association: association, leaseProvider: provider)
                if !capturedFirstMeasurement,
                   let before = completed.streamed.freeSpaceBeforeBytes {
                    freeSpaceBeforeBytes = before
                    capturedFirstMeasurement = true
                }
                if let after = completed.streamed.freeSpaceAfterBytes {
                    freeSpaceAfterBytes = after
                }
                else { measurementsAvailable = false }
                results.append(ItemResult(id: item.id, title: item.title, freedBytes: 0,
                    succeeded: completed.status == .succeeded,
                    message: completed.streamed.stop.map { "Stopped at safe boundary: \($0)" },
                    targetOutcomes: nil, effectStatus: completed.status))
            } catch {
                measurementsAvailable = false
                results.append(ItemResult(id: item.id, title: item.title, freedBytes: 0, succeeded: false,
                    message: "\(error)", targetOutcomes: nil, effectStatus: .failed))
            }
            completedEffects += 1
            publishProgress()
        }

        if results.allSatisfy({ $0.effectStatus != .uncertain }) {
            do { try journal.finish(runID: runID) }
            catch { return report(.storageUnavailable, tier: tier) }
        }

        return RunReport(tier: tier, results: results, startedAt: startedAt, finishedAt: Date(),
            freeSpaceBeforeBytes: freeSpaceBeforeBytes, freeSpaceAfterBytes: freeSpaceAfterBytes,
            disposition: .completed,
            coordinatorMeasurementsAvailable: measurementsAvailable && capturedFirstMeasurement)
    }

    private func executeRegisteredFilesystemTarget(
        registration: Registration, binding: ReviewBinding, item: PlannedItem,
        targetOrdinal: Int, runID: UUID, journal: RunJournal,
        association: ResourceAssociationEvidence,
        leaseProvider: any ProducerExclusionLeaseProviding
    ) throws -> CompletedFilesystemEffect {
        guard item.id == DerivedDataEffectAdapter.acceptedItemID,
              case .deleteContents = item.action,
              registration.review.binding == binding,
              registration.review.selection.selectedIDs.contains(item.id),
              let reviewed = registration.reviewedFiles[item.id],
              reviewed.indices.contains(targetOrdinal),
              let storedAssociation = registration.associations[item.id],
              storedAssociation.indices.contains(targetOrdinal),
              PersistedResourceAssociation(storedAssociation[targetOrdinal])
                == PersistedResourceAssociation(association) else {
            throw ConfirmationError.unavailableSelection
        }
        let operationID = UUID()
        let lifecycle = FilesystemEffectLifecycle(journal: journal)
        let prepared = try lifecycle.prepare(runID: runID, operationID: operationID,
            planID: binding.planID, planRevision: binding.planRevision,
            policyRevision: binding.policyRevision, selectedItemID: item.id,
            targetOrdinal: targetOrdinal, reviewed: reviewed[targetOrdinal],
            association: association)
        let cancellation = self.cancellation ?? EffectCancellationToken()
        let schedule = try FilesystemEffectSchedule(
            allocatedByteLimit: 256 * 1_024 * 1_024 * 1_024,
            leafLimit: ReviewedManifestArchive.maximumNodeCount,
            deadline: ContinuousClock.now.advanced(by: .seconds(300)),
            cancellation: cancellation, policyBarrier: barrier,
            policyRevision: binding.policyRevision)
        return try lifecycle.execute(prepared, reviewed: reviewed[targetOrdinal],
            association: association, currentProtectedRoots: environment.protectedRoots,
            leaseProvider: leaseProvider, schedule: schedule)
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

    /// Internal handoff for R03 persistence and focused authority tests. It
    /// returns immutable identities only; digests cannot authorize mutation
    /// without the coordinator-owned tree, association, and live lease.
    func reviewedFilesystemIdentities(planID: UUID, itemID: String) -> [FileResourceIdentity] {
        guard let files = reviews[planID]?.reviewedFiles[itemID] else { return [] }
        return files.map(\.identity)
    }

    public func mutationAdmission() -> MutationAdmission {
        if case .running = state { return .busy }
        guard let admissionStore else { return .storageUnavailable }
        defer { admissionStore.release() }
        let admission = admissionStore.acquire()
        cachedRecovery = admission
        publishProgress()
        return admission
    }

    public func executionProgress() -> ExecutionProgressSnapshot {
        progressSnapshot()
    }

    public func progressUpdates() -> AsyncStream<ExecutionProgressSnapshot> {
        let id = UUID()
        let pair = AsyncStream<ExecutionProgressSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        guard progressSubscribers.count < Self.maximumProgressSubscribers else {
            pair.continuation.finish()
            return pair.stream
        }
        progressSubscribers[id] = pair.continuation
        pair.continuation.yield(progressSnapshot())
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeProgressSubscriber(id) }
        }
        return pair.stream
    }

    private func progressSnapshot() -> ExecutionProgressSnapshot {
        let runID: UUID?
        switch state {
        case .idle: runID = nil
        case .running(let value): runID = value
        }
        return ExecutionProgressSnapshot(runID: runID, phase: progressPhase,
            completedEffects: completedEffects, scheduledEffects: scheduledEffects,
            cancellationRequested: cancellationRelay.isCancelled,
            recovery: caseRunningRecovery())
    }

    private func caseRunningRecovery() -> MutationAdmission {
        if case .running = state { return .busy }
        return cachedRecovery
    }

    public nonisolated func cancelCurrentRun() {
        cancellationRelay.cancel()
        Task { await self.cancellationDidChange() }
    }

    private func cancellationDidChange() { publishProgress() }

    private func publishProgress() {
        let snapshot = progressSnapshot()
        for continuation in progressSubscribers.values { continuation.yield(snapshot) }
    }

    private func removeProgressSubscriber(_ id: UUID) {
        progressSubscribers.removeValue(forKey: id)
    }

    public func reconcileUnfinishedEffects() async -> RecoveryReconciliationReport {
        guard case .idle = state, let admissionStore else {
            return RecoveryReconciliationReport(disposition: .storageUnavailable,
                inspectedEffects: 0, reconciledEffects: 0)
        }
        let admission = admissionStore.acquire()
        guard admission != .busy else {
            return RecoveryReconciliationReport(disposition: .blocked,
                inspectedEffects: 0, reconciledEffects: 0)
        }
        defer {
            admissionStore.release()
            progressPhase = .idle
            publishProgress()
        }
        guard admission != .storageUnavailable else {
            return RecoveryReconciliationReport(disposition: .storageUnavailable,
                inspectedEffects: 0, reconciledEffects: 0)
        }
        progressPhase = .reconciling
        publishProgress()
        let intents: [PendingEffectIntent]
        do { intents = try admissionStore.unfinishedIntentsWhileLocked() }
        catch {
            return RecoveryReconciliationReport(disposition: .storageUnavailable,
                inspectedEffects: 0, reconciledEffects: 0)
        }
        guard !intents.isEmpty else {
            cachedRecovery = .ready
            return RecoveryReconciliationReport(disposition: .noUnfinishedEffects,
                inspectedEffects: 0, reconciledEffects: 0)
        }
        let journal: RunJournal
        do {
            journal = try RunJournal(store: admissionStore,
                storage: DurableJournalStorage(directory: journalDirectory))
        } catch {
            return RecoveryReconciliationReport(disposition: .storageUnavailable,
                inspectedEffects: intents.count, reconciledEffects: 0)
        }
        var reconciled = 0
        var blocked = false
        for runID in Set(intents.map(\.runID)) {
            let runIntents = intents.filter { $0.runID == runID }
            guard runIntents.allSatisfy({ intent in
                guard intent.schemaVersion == 2,
                      case .filesystem(let binding)? = intent.binding else { return false }
                return binding.adapterID == AppleDerivedDataInventory.adapterID
                    && binding.adapterVersion == AppleDerivedDataInventory.contractVersion
            }) else {
                blocked = true
                continue
            }
            do {
                if try journal.reconcileTerminalRun(runID: runID) {
                    reconciled += runIntents.count
                } else {
                    // Missing paths, PIDs, locks, or a reboot are deliberately
                    // not substituted for an adapter terminal proof.
                    blocked = true
                }
            } catch {
                blocked = true
            }
        }
        if reconciled > 0 {
            reviews.removeAll()
            tokens.removeAll()
            rejections.removeAll()
            rejectionOrder.removeAll()
        }
        progressPhase = blocked ? .blocked : .idle
        cachedRecovery = blocked ? .uncertainAndPossiblyRunning : .ready
        publishProgress()
        return RecoveryReconciliationReport(
            disposition: blocked ? .blocked : .requireFreshReview,
            inspectedEffects: intents.count, reconciledEffects: reconciled)
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
            if row.id == DerivedDataEffectAdapter.acceptedItemID {
                let reviewed = registration.reviewedFiles[row.id] ?? []
                let records = registration.inventory[row.id] ?? []
                guard reviewed.count == row.targets.count,
                      records.count == row.targets.count,
                      records.allSatisfy({ $0.capability == .exactResourceMutation }) else {
                    throw ConfirmationError.unavailableSelection
                }
            }
        }
    }

    /// Captures authorization at review, never while executing. DerivedData
    /// gets the exact bounded descendant manifest and protection digest even
    /// though its production inventory remains read-only; R03 can persist the
    /// already-reviewed bytes without re-walking a fresher tree.
    private static func captureReviewResources(plan: CleanPlan,
                                               environment: CleanEnvironment) -> CapturedReviewResources {
        var identities: [String: [ResourceIdentity]] = [:]
        var reviewedFiles: [String: [ReviewedFileResource]] = [:]
        var inventory: [String: [InventoryRecord]] = [:]
        var associations: [String: [ResourceAssociationEvidence]] = [:]
        var unavailable: Set<String> = []
        for row in plan.reviewItems {
            var rowIdentities: [ResourceIdentity] = []
            var rowReviewed: [ReviewedFileResource] = []
            var rowInventory: [InventoryRecord] = []
            for target in row.targets {
                guard target.isFilesystemPath else {
                    unavailable.insert(row.id)
                    continue
                }
                do {
                    if row.id == DerivedDataEffectAdapter.acceptedItemID {
                        let reviewed = try ResourcePreflight.captureReviewedDirectory(
                            at: target.path, protectedRoots: environment.protectedRoots)
                        let resource = ResourceIdentity.filesystem(reviewed.identity)
                        rowIdentities.append(resource)
                        rowReviewed.append(reviewed)
                        rowInventory.append(AppleDerivedDataInventory.record(
                            resource: resource, observedAt: plan.generatedAt))
                    } else {
                        rowIdentities.append(.filesystem(
                            try ResourcePreflight.captureFile(at: target.path)))
                    }
                } catch {
                    unavailable.insert(row.id)
                }
            }
            identities[row.id] = rowIdentities
            reviewedFiles[row.id] = rowReviewed
            inventory[row.id] = rowInventory
            associations[row.id] = []
        }
        return CapturedReviewResources(identities: identities,
            reviewedFiles: reviewedFiles, inventory: inventory,
            associations: associations, unavailable: unavailable)
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
