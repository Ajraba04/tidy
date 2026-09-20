import Foundation
import Observation

public typealias SettingsIntentID = UUID

private final class SettingsSchedulerBootstrapUse: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func consume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { return false }
        consumed = true
        return true
    }
}

/// Store-bound bootstrap evidence. Its initializer is file-private, so an app
/// caller cannot manufacture absent-file provenance from a default envelope or
/// replay provenance from another `SettingsStore` actor.
public struct SettingsSchedulerBootstrap: @unchecked Sendable {
    public let result: SettingsLoadResult
    fileprivate let store: SettingsStore
    fileprivate let generation: UInt64?
    fileprivate let image: SettingsDiskImage?
    fileprivate let use: SettingsSchedulerBootstrapUse

    fileprivate init(result: SettingsLoadResult, store: SettingsStore,
                     generation: UInt64?, image: SettingsDiskImage?) {
        self.result = result
        self.store = store
        self.generation = generation
        self.image = image
        self.use = SettingsSchedulerBootstrapUse()
    }

    fileprivate func belongs(to store: SettingsStore, result: SettingsLoadResult) -> Bool {
        self.store === store && self.result == result && generation != nil && image != nil
    }
}

private struct SettingsSchedulerBootstrapLease: Sendable {
    let id: UUID
}

public extension SettingsStore {
    /// Loads settings and binds the exact result to this actor for app bootstrap.
    /// Ordinary `load()` remains data only and cannot opt revision zero into the scheduler.
    func loadForSchedulerBootstrap() -> SettingsSchedulerBootstrap {
        let result = load()
        let generation = schedulerBootstrapGenerationExhausted
            ? nil : schedulerBootstrapGeneration
        let image = schedulerBootstrapImageForIssue()
        return SettingsSchedulerBootstrap(result: result, store: self,
            generation: generation, image: image)
    }

    fileprivate func acquireSchedulerBootstrap(
        _ bootstrap: SettingsSchedulerBootstrap
    ) -> SettingsSchedulerBootstrapLease? {
        guard bootstrap.store === self, bootstrap.result.disposition == .newDefaults,
              let generation = bootstrap.generation,
              generation == schedulerBootstrapGeneration,
              !schedulerBootstrapGenerationExhausted,
              schedulerBootstrapReservation == nil,
              let image = bootstrap.image,
              bootstrap.use.consume(),
              revalidateSchedulerBootstrapImage(image) else { return nil }
        let lease = SettingsSchedulerBootstrapLease(id: UUID())
        schedulerBootstrapReservation = lease.id
        return lease
    }

    fileprivate func releaseSchedulerBootstrap(_ lease: SettingsSchedulerBootstrapLease) {
        guard schedulerBootstrapReservation == lease.id else { return }
        schedulerBootstrapReservation = nil
    }
}

public enum SettingsSubmissionRejection: Equatable, Sendable {
    case invalid, unsupportedAuthority, queueFull, unavailable
}

public enum SettingsIntentOutcome: Equatable, Sendable {
    case saved(SettingsIntentID, SettingsEnvelope)
    case conflict(SettingsIntentID)
    case invalid(SettingsIntentID)
    case failed(SettingsIntentID, recoveryRequired: Bool)
}

public enum SettingsSubmissionAdmission: Sendable {
    case rejected(SettingsIntentID, SettingsSubmissionRejection)
    case accepted(SettingsIntentID, Task<SettingsIntentOutcome, Never>)
}

internal enum ExecutionPolicyBridgeTestPoint: Hashable, Sendable {
    case acceptedAfterBarrierBeforePrepareAndSave(SettingsIntentID)
    case acceptedAfterPresentationPrepareBeforeSave(SettingsIntentID)
    case durablySavedBeforeCommit(SettingsIntentID)
    case terminalBeforeAdmissionHoldRelease(SettingsIntentID)
}

internal protocol ExecutionPolicyBridgeTestHook: Sendable {
    func receive(_ event: ExecutionPolicyBridgeTestPoint) async
}

/// Bounded explicit-work access vended only by an execution-policy bridge.
public struct BridgeExplicitSessions: Sendable {
    fileprivate let bridge: ExecutionPolicyBridge

    fileprivate init(bridge: ExecutionPolicyBridge) { self.bridge = bridge }

    public func beginSession(requirements: SchedulerRequirements) async throws -> WorkSession {
        try await bridge.beginExplicitSession(requirements: requirements)
    }

    public func withPermit<T: Sendable>(session: WorkSession,
        operation: @Sendable (SchedulerCancellationProbe) async throws -> T) async throws -> T {
        try await bridge.withExplicitPermit(session: session, operation: operation)
    }

    public func cancel(session: WorkSession) async { await bridge.cancelExplicitSession(session) }

    public func finish(session: WorkSession) async { await bridge.finishExplicitSession(session) }

    public func state(of session: WorkSession) async -> WorkSessionState? {
        await bridge.explicitSessionState(session)
    }

    public func snapshot() async -> WorkSchedulerSnapshot {
        await bridge.explicitSessionSnapshot()
    }

    /// Awaits the bridge's own pending initial-install/settle work (see `ExecutionPolicyBridge
    /// .drain()`) without granting any additional authority. A caller that needs to know whether
    /// the scheduler is genuinely installed should call this first, then read `snapshot()
    /// .availability`. Exact in-memory defaults from an absent settings file may install
    /// read-only explicit-scan policy; arbitrary revision-zero documents remain unavailable.
    public func awaitInitialInstall() async { await bridge.drain() }

    public func updateLiveObservation(epoch: UInt64, monotonicNanoseconds: UInt64,
                                      observation: SchedulerLiveObservation) async
      -> SchedulerLiveObservationResult {
        await bridge.updateLiveObservation(epoch: epoch,
            monotonicNanoseconds: monotonicNanoseconds, observation: observation)
    }
}

@Observable @MainActor
public final class ExecutionPolicyBridge {
    public private(set) var updateGeneration = UUID()
    public private(set) var isExecutionEnabled: Bool
    public private(set) var storageUpdatePending = false
    public private(set) var policyUpdatePending = false
    public private(set) var persistenceError: String?
    public private(set) var durableSettingsRevision: UInt64?
    public private(set) var acknowledgedEnvelope: SettingsEnvelope?
    /// The exact envelope accepted by the read-only scheduler. This may be
    /// revision zero only for canonical in-memory `.newDefaults`; mutation
    /// authority continues to use the separately quarantined coordinator.
    internal private(set) var acknowledgedScanEnvelope: SettingsEnvelope?
    internal private(set) var pendingSnapshotCount = 0
    internal private(set) var pendingSnapshotBytes = 0

    private let coordinator: ExecutionCoordinator
    private let settings: SettingsStore
    private let homeDirectory: String
    private let detectedTools: Set<ToolchainID>
    private let schedulerController: SchedulerPolicyController
    private let scheduler: WorkScheduler
    private let schedulerCapability: SchedulerPolicyControllerCapability
    private let testHook: (any ExecutionPolicyBridgeTestHook)?
    private var generation = UUID()
    private var lastSuccessfullyPersistedRevision: UInt64?
    private var pendingTail: Task<SettingsIntentOutcome, Never>?
    private var pendingTailID: UUID?
    private var pendingPolicyCount = 0
    private var recoveryTicket: PolicyUpdateTicket?
    private var predictedSubmittedEnvelope: SettingsEnvelope
    private var pendingPayloadOrder: [SettingsIntentID] = []
    private var pendingPayloads: [SettingsIntentID: Payload] = [:]
    private var observers: [UUID: @MainActor (SettingsIntentOutcome) -> Void] = [:]
    private var submissionSequence: UInt64 = 0
    private var errorSequence: UInt64 = 0
    private var policyFailureActive = false
    private let pendingByteLimit: Int
    private var issuedImportBinding: IssuedImportBinding?
    private var importLifecycleGeneration: UInt64 = 0
    private var initialSchedulerInstall: Task<Void, Never>?
    private var schedulerAdmissionPendingCount = 0
    private var pendingSchedulerInvalidations: Set<SettingsIntentID> = []
    private var pendingSchedulerTickets: [SettingsIntentID: SchedulerAdmissionTicket] = [:]
    private var pendingSchedulerHolds: [SettingsIntentID: SchedulerAdmissionHold] = [:]
    private var liveObservationEpoch: UInt64 = 0
    private var criticalResumeNotBefore: UInt64?

    private enum SchedulerPreparation {
        case invalidating(PreparedSchedulerPolicy)
        case presentation(PreparedSchedulerPresentation)
    }

    private enum SchedulerHandoffError: Error { case invalid }

    private struct IssuedImportBinding: Sendable {
        let preview: SettingsImportPreview
        let revision: UInt64
    }

    private struct RetainedDocumentMirror: Codable {
        let intentID: UUID
        let delta: PreferencesDocumentDelta
    }
    private struct RetainedImportMirror: Codable {
        struct Row: Codable {
            let scope: String; let profileID: UUID?; let id: String?; let idDigest: String?
            let outcome: String; let value: SettingValue?; let valueKind: String?
            let valueDigest: String?
        }
        struct Collision: Codable {
            let profileID: UUID; let localName: String; let importedName: String
        }
        struct Choice: Codable {
            let profileID: UUID; let kind: String; let cloneID: UUID?
        }
        let intentID: UUID
        let expectedRevision: UInt64
        let previewID: UUID
        let analysisID: UUID
        let rows: [Row]
        let collisions: [Collision]
        let choices: [Choice]
        let preferences: PolicyPreferences
        let inertImports: [InertPortableSetting]
        let sourceDigest: String
        let candidateDigest: String
    }

    private enum Payload: Sendable {
        case legacy(LegacyPreferenceDelta)
        case global(GlobalPreferenceDelta)
        case document(PreferencesDocumentDelta)
        case importPreview(expectedRevision: UInt64, preview: SettingsImportPreview)
    }

    private static let maximumPendingSnapshots = 32
    private static let maximumPendingBytes = 32 * 1_048_576
    private static let saveFailure = "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again."
    private static let overflowFailure = "Settings changes are pending; wait and save again."

    public convenience init(coordinator: ExecutionCoordinator, settings: SettingsStore,
                            loaded: SettingsLoadResult, homeDirectory: String,
                            detectedTools: Set<ToolchainID>) {
        self.init(coordinator: coordinator, settings: settings, loaded: loaded,
                  bootstrap: nil, homeDirectory: homeDirectory, detectedTools: detectedTools,
                  pendingByteLimit: Self.maximumPendingBytes, schedulerTestHook: nil,
                  testHook: nil)
    }

    public convenience init(coordinator: ExecutionCoordinator, settings: SettingsStore,
                            bootstrap: SettingsSchedulerBootstrap, homeDirectory: String,
                            detectedTools: Set<ToolchainID>) {
        self.init(coordinator: coordinator, settings: settings, loaded: bootstrap.result,
                  bootstrap: bootstrap, homeDirectory: homeDirectory,
                  detectedTools: detectedTools, pendingByteLimit: Self.maximumPendingBytes,
                  schedulerTestHook: nil, testHook: nil)
    }

    internal init(coordinator: ExecutionCoordinator, settings: SettingsStore,
                  loaded: SettingsLoadResult,
                  bootstrap: SettingsSchedulerBootstrap? = nil,
                  homeDirectory: String,
                  detectedTools: Set<ToolchainID>, pendingByteLimit: Int,
                  schedulerTestHook: (any SchedulerTestHook)? = nil,
                  testHook: (any ExecutionPolicyBridgeTestHook)? = nil) {
        self.coordinator = coordinator
        self.settings = settings
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
        self.testHook = testHook
        let logicalCPUCount = min(max(1, ProcessInfo.processInfo.activeProcessorCount), 1_024)
        let inputs = try! SchedulerResolutionInputs(logicalCPUCount: logicalCPUCount)
        if let schedulerTestHook {
            let made = try! SchedulerPolicyController.makeForTesting(inputs: inputs,
                limits: try! .init(), initialGeneration: 0, initialObservationEpoch: 0,
                initialWaiterID: 0, hook: schedulerTestHook)
            self.schedulerController = made.controller
            self.scheduler = made.scheduler
            self.schedulerCapability = made.capability
        } else {
            let made = try! SchedulerPolicyController.make(inputs: inputs)
            self.schedulerController = made.controller
            self.scheduler = made.scheduler
            self.schedulerCapability = made.capability
        }
        self.pendingByteLimit = min(max(0, pendingByteLimit), Self.maximumPendingBytes)
        let envelope = loaded.envelope
        let revision = envelope?.revision
        self.acknowledgedEnvelope = envelope
        self.predictedSubmittedEnvelope = envelope ?? SettingsEnvelope(schemaVersion: 2,
            revision: 0, config: TidyConfig(schemaVersion: 2))
        self.lastSuccessfullyPersistedRevision = revision
        self.durableSettingsRevision = revision
        self.isExecutionEnabled = revision != nil && loaded.disposition != .recoveryReadOnly

        if !isExecutionEnabled {
            self.persistenceError = "Settings are read-only. Cleanup remains disabled."
            do { recoveryTicket = try coordinator.beginPolicyUpdate() }
            catch { self.persistenceError = "Settings could not be applied. Cleanup remains disabled." }
        }

        let initialSchedulerOrigin: SchedulerPolicyOrigin?
        if let envelope, envelope.revision > 0, loaded.disposition != .recoveryReadOnly {
            initialSchedulerOrigin = .durable
        } else if let envelope, bootstrap?.belongs(to: settings, result: loaded) == true,
                  loaded.disposition == .newDefaults,
                  envelope == Self.canonicalFreshDefaults {
            initialSchedulerOrigin = .freshDefaults
        } else {
            initialSchedulerOrigin = nil
        }
        if let envelope, let initialSchedulerOrigin {
            initialSchedulerInstall = Task { @MainActor [weak self] in
                await self?.installInitialScheduler(envelope, origin: initialSchedulerOrigin,
                    bootstrap: bootstrap)
            }
        }
    }

    @discardableResult
    internal func scanScopeValidity() -> @Sendable () -> Bool {
        schedulerController.readValidity()
    }

    public func observeOutcomes(
        _ observer: @escaping @MainActor (SettingsIntentOutcome) -> Void
    ) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    public func removeOutcomeObserver(_ token: UUID) { observers[token] = nil }

    public func submit(global delta: GlobalPreferenceDelta) -> SettingsSubmissionAdmission {
        let id = UUID()
        guard let sequence = reserveSequence() else {
            return rejectSequenceOverflow(id: id)
        }
        guard let currentRevision = acknowledgedEnvelope?.revision,
              delta.baseRevision <= currentRevision else {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings change is invalid.")
        }
        let matches = PolicyDefaults.rows.filter { $0.id == delta.id }
        guard matches.count == 1, let definition = matches.first,
              definition.layers.contains(.global),
              definition.resolution != .authority else {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings change is invalid.")
        }
        guard definition.effect != .consent else {
            return rejectBeforeRetention(id: id, sequence: sequence,
                reason: .unsupportedAuthority,
                message: "This setting requires a separate authorization flow.")
        }
        let predictedRaw = predictedSubmittedEnvelope.preferences?.global.fields[delta.id]
        guard delta.baseValue == predictedRaw else {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings change is based on stale settings.")
        }
        do {
            if let base = delta.baseValue {
                try PolicyValidator.validateStructure(
                    PolicyValues(fields: [delta.id: base]), at: .global)
            }
            var complete = predictedSubmittedEnvelope.preferences?.global ?? PolicyValues()
            complete.fields[delta.id] = delta.editedValue
            try PolicyValidator.validateStructure(complete, at: .global)
        } catch {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings change is invalid.")
        }
        return admit(id: id, sequence: sequence, payload: .global(delta),
                     effect: definition.effect, presentation: isPresentationDelta(delta))
    }

    public func submit(document delta: PreferencesDocumentDelta) -> SettingsSubmissionAdmission {
        let id = UUID()
        guard let sequence = reserveSequence() else { return rejectSequenceOverflow(id: id) }
        let applied: AppliedPreferencesDocument
        do {
            applied = try PreferencesDocumentProjection.apply(delta, to: predictedSubmittedEnvelope)
            // Bound aggregate strings and exact persisted bytes before the
            // retained Codable mirror is allowed to allocate.
            _ = try SettingsDecoding.encode(predictedSubmittedEnvelope)
            _ = try SettingsDecoding.encode(applied.envelope)
        }
        catch PreferencesDocumentProjectionError.unsupportedAuthority {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .unsupportedAuthority,
                message: "This setting requires a separate authorization flow.")
        } catch {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings change is invalid.")
        }
        return admit(id: id, sequence: sequence, payload: .document(delta), effect: applied.effect,
                     presentation: false)
    }

    public func submit(importPreview preview: SettingsImportPreview) -> SettingsSubmissionAdmission {
        let id = UUID()
        guard let sequence = reserveSequence() else { return rejectSequenceOverflow(id: id) }
        guard pendingSnapshotCount == 0, pendingPayloadOrder.isEmpty,
              let binding = issuedImportBinding, binding.preview == preview,
              binding.revision == acknowledgedEnvelope?.revision,
              binding.revision == predictedSubmittedEnvelope.revision else {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings import is no longer current.")
        }
        let candidate: SettingsEnvelope
        do {
            candidate = try importPrediction(preview.candidate, from: predictedSubmittedEnvelope)
            _ = try PreferencesDocumentEffect.classify(before: predictedSubmittedEnvelope,
                                                        after: candidate)
        } catch PreferencesDocumentProjectionError.unsupportedAuthority {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .unsupportedAuthority,
                message: "This import requires a separate authorization flow.")
        } catch {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings import is invalid.")
        }
        let effect: AuthorityEffect
        do { effect = try PreferencesDocumentEffect.classify(before: predictedSubmittedEnvelope,
                                                              after: candidate) }
        catch {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings import is invalid.")
        }
        let admission = admit(id: id, sequence: sequence,
            payload: .importPreview(expectedRevision: binding.revision, preview: preview), effect: effect,
            presentation: false)
        if case .accepted = admission {
            issuedImportBinding = nil
            _ = advanceImportLifecycle()
        }
        return admission
    }

    public func analyzeImport(bytes: Data) async throws -> SettingsImportAnalysis {
        issuedImportBinding = nil
        guard let lifecycle = advanceImportLifecycle() else {
            throw SettingsStoreError.invalidChange
        }
        let analysis = try await settings.analyzeImport(bytes: bytes)
        guard lifecycle == importLifecycleGeneration else {
            if let id = analysis.analysisID { await settings.cancelImport(analysisID: id) }
            throw SettingsStoreError.invalidChange
        }
        return analysis
    }

    public func issueImportPreview(analysisID: SettingsImportAnalysisID,
                                   choices: [UUID: ProfileCollisionChoice]) async throws
        -> SettingsImportPreview {
        issuedImportBinding = nil
        guard let lifecycle = advanceImportLifecycle() else {
            throw SettingsStoreError.invalidChange
        }
        guard pendingSnapshotCount == 0, pendingPayloadOrder.isEmpty,
              let revision = acknowledgedEnvelope?.revision,
              revision == predictedSubmittedEnvelope.revision else {
            throw SettingsStoreError.invalidChange
        }
        let preview = try await settings.issueImportPreview(analysisID: analysisID, choices: choices)
        guard lifecycle == importLifecycleGeneration else {
            await settings.cancelImport(previewID: preview.id)
            throw SettingsStoreError.invalidChange
        }
        issuedImportBinding = .init(preview: preview, revision: revision)
        return preview
    }

    public func cancelImport(analysisID: SettingsImportAnalysisID) async {
        issuedImportBinding = nil
        _ = advanceImportLifecycle()
        await settings.cancelImport(analysisID: analysisID)
    }

    public func cancelImport(previewID: SettingsImportPreviewID) async {
        if issuedImportBinding?.preview.id == previewID { issuedImportBinding = nil }
        _ = advanceImportLifecycle()
        await settings.cancelImport(previewID: previewID)
    }

    public func submit(legacy delta: LegacyPreferenceDelta) -> SettingsSubmissionAdmission {
        let id = UUID()
        guard let sequence = reserveSequence() else {
            return rejectSequenceOverflow(id: id)
        }
        guard let currentRevision = acknowledgedEnvelope?.revision else {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .unavailable,
                                         message: Self.saveFailure)
        }
        guard delta.baseRevision <= currentRevision else {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: "The settings change is invalid.")
        }
        return admit(id: id, sequence: sequence, payload: .legacy(delta), effect: .invalidate,
                     presentation: false)
    }

    /// Source-compatible whole-value entry point. New app code uses the
    /// base-bound typed/delta APIs above.
    @discardableResult
    public func submit(config: TidyConfig) -> Task<Void, Never> {
        let delta = LegacyPreferenceDelta(baseRevision: acknowledgedEnvelope?.revision ?? 0,
            base: predictedSubmittedEnvelope.config, edited: config,
            compatibilityBase: predictedSubmittedEnvelope.preferences?.global)
        switch submit(legacy: delta) {
        case .accepted(_, let completion):
            return Task { _ = await completion.value }
        case .rejected:
            return Task {}
        }
    }

    private func admit(id: SettingsIntentID, sequence: UInt64, payload: Payload,
                       effect: AuthorityEffect, presentation: Bool) -> SettingsSubmissionAdmission {
        let bytes: Int
        do { bytes = try retainedBytes(id: id, payload: payload) }
        catch {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                         message: Self.saveFailure)
        }
        let retainedTotal: Int
        do { retainedTotal = try Self.checkedRetainedTotalForTesting(pendingSnapshotBytes,
                                                                      adding: bytes) }
        catch {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .queueFull,
                                         message: Self.overflowFailure)
        }
        guard pendingSnapshotCount < Self.maximumPendingSnapshots,
              bytes <= pendingByteLimit, retainedTotal <= pendingByteLimit else {
            return rejectBeforeRetention(id: id, sequence: sequence, reason: .queueFull,
                                         message: Self.overflowFailure)
        }

        let schedulerTicket: SchedulerAdmissionTicket?
        if presentation {
            schedulerTicket = nil
        } else if schedulerAdmissionPendingCount == 0 {
            do {
                schedulerTicket = try schedulerController.beginAdmissionTransition(
                    using: schedulerCapability)
            } catch {
                persistenceError = "Settings could not be applied. Cleanup remains disabled."
                errorSequence = sequence
                return .rejected(id, .unavailable)
            }
        } else {
            // An earlier accepted handoff has already synchronously closed the core
            // barrier. The façade remains closed until this queued handoff completes.
            schedulerTicket = nil
        }

        let ticket: PolicyUpdateTicket?
        if effect == .invalidate {
            do { ticket = try coordinator.beginPolicyUpdate() }
            catch {
                persistenceError = "Settings could not be applied. Cleanup remains disabled."
                errorSequence = sequence
                return .rejected(id, .unavailable)
            }
        } else {
            ticket = nil
        }

        let schedulerHold: SchedulerAdmissionHold?
        if presentation {
            schedulerHold = nil
        } else {
            do {
                schedulerHold = try schedulerController.acquireAdmissionHold(
                    using: schedulerCapability)
            } catch {
                persistenceError = "Settings could not be applied. Cleanup remains disabled."
                errorSequence = sequence
                return .rejected(id, .unavailable)
            }
        }

        pendingSnapshotCount += 1
        pendingSnapshotBytes = retainedTotal
        pendingPayloadOrder.append(id)
        pendingPayloads[id] = payload
        if !presentation {
            schedulerAdmissionPendingCount += 1
            pendingSchedulerInvalidations.insert(id)
            if let schedulerTicket { pendingSchedulerTickets[id] = schedulerTicket }
            if let schedulerHold { pendingSchedulerHolds[id] = schedulerHold }
        }
        rebuildPredictedSubmission()
        storageUpdatePending = true
        let intentGeneration: UUID?
        if ticket != nil {
            pendingPolicyCount += 1
            policyUpdatePending = true
            isExecutionEnabled = false
            persistenceError = nil
            errorSequence = sequence
            policyFailureActive = false
            let next = UUID()
            generation = next
            updateGeneration = next
            intentGeneration = next
        } else {
            intentGeneration = nil
        }

        let previous = pendingTail
        let task = Task { @MainActor [self] in
            if let previous { _ = await previous.value }
            let outcome = await perform(id: id, ticket: ticket,
                                        intentGeneration: intentGeneration,
                                        sequence: sequence)
            await testHook?.receive(.terminalBeforeAdmissionHoldRelease(id))
            let schedulerHold = pendingSchedulerHolds.removeValue(forKey: id)
            if let schedulerHold {
                await schedulerController.releaseAdmissionHold(schedulerHold,
                                                               using: schedulerCapability)
            }
            pendingPayloadOrder.removeAll { $0 == id }
            pendingPayloads[id] = nil
            if pendingSchedulerInvalidations.remove(id) != nil {
                schedulerAdmissionPendingCount -= 1
            }
            pendingSchedulerTickets[id] = nil
            rebuildPredictedSubmission()
            pendingSnapshotCount -= 1
            pendingSnapshotBytes -= bytes
            if ticket != nil { pendingPolicyCount -= 1 }
            storageUpdatePending = pendingSnapshotCount > 0
            policyUpdatePending = pendingPolicyCount > 0
            if pendingTailID == id {
                pendingTail = nil
                pendingTailID = nil
            }
            for observer in observers.values { observer(outcome) }
            return outcome
        }
        pendingTail = task
        pendingTailID = id
        return .accepted(id, task)
    }

    private func perform(id: SettingsIntentID, ticket: PolicyUpdateTicket?,
                         intentGeneration: UUID?, sequence: UInt64) async -> SettingsIntentOutcome {
        do {
            guard let expectedRevision = lastSuccessfullyPersistedRevision else {
                throw SettingsStoreError.readOnlyRecovery
            }
            guard let payload = pendingPayloads[id] else {
                throw SettingsStoreError.invalidChange
            }
            let candidate = try schedulerCandidate(for: payload, expectedRevision: expectedRevision)
            let preparation = try await prepareScheduler(id: id, candidate: candidate)
            do {
                try Task.checkCancellation()
                let saved: SettingsEnvelope
                switch payload {
                case .legacy(let delta):
                    saved = try await settings.update(expectedRevision: expectedRevision,
                                                      change: .legacyPreferenceDelta(delta))
                case .global(let delta):
                    saved = try await settings.update(expectedRevision: expectedRevision,
                                                      change: .globalPreferenceDelta(delta))
                case .document(let delta):
                    saved = try await settings.update(expectedRevision: expectedRevision,
                                                      change: .preferencesDocument(delta))
                case .importPreview(let expectedRevision, let preview):
                    guard expectedRevision == lastSuccessfullyPersistedRevision else {
                        throw SettingsStoreError.staleRevision
                    }
                    saved = try await settings.commitImport(expectedRevision: expectedRevision,
                                                            previewID: preview.id)
                }
                await testHook?.receive(.durablySavedBeforeCommit(id))
                return try await acceptSaved(saved, id: id, ticket: ticket,
                                             intentGeneration: intentGeneration, sequence: sequence,
                                             preparation: preparation)
            } catch {
                await discardSchedulerPreparation(preparation)
                throw error
            }
        } catch is SchedulerHandoffError {
            if ticket != nil {
                isExecutionEnabled = false
                policyFailureActive = true
            }
            if !policyFailureActive || ticket != nil {
                persistenceError = "The settings change is invalid."
                errorSequence = sequence
            }
            return .invalid(id)
        } catch let error as SettingsStoreError
            where error == .staleRevision || error == .changedExternally {
            if ticket != nil {
                isExecutionEnabled = false
                policyFailureActive = true
            }
            if !policyFailureActive || ticket != nil {
                persistenceError = "Settings changed elsewhere. Review this edit and try again."
                errorSequence = sequence
            }
            return .conflict(id)
        } catch let error as SettingsStoreError
            where error == .invalidChange || error == .oversized {
            if ticket != nil {
                isExecutionEnabled = false
                policyFailureActive = true
            }
            if !policyFailureActive || ticket != nil {
                persistenceError = "The settings change is invalid."
                errorSequence = sequence
            }
            return .invalid(id)
        } catch {
            let recoveryRequired = await settings.isRecoveryRequired()
            if recoveryRequired, ticket == nil, recoveryTicket == nil {
                recoveryTicket = try? coordinator.beginPolicyUpdate()
            } else if recoveryRequired, let ticket {
                recoveryTicket = ticket
            }
            if ticket != nil || recoveryRequired {
                isExecutionEnabled = false
                policyFailureActive = true
            }
            if !policyFailureActive || ticket != nil || recoveryRequired {
                persistenceError = Self.saveFailure
                errorSequence = sequence
            }
            return .failed(id, recoveryRequired: recoveryRequired)
        }
    }

    private func acceptSaved(_ saved: SettingsEnvelope, id: SettingsIntentID,
                             ticket: PolicyUpdateTicket?, intentGeneration: UUID?,
                             sequence: UInt64,
                             preparation: SchedulerPreparation) async throws -> SettingsIntentOutcome {
        let schedulerCommitted: Bool
        switch preparation {
        case .invalidating(let prepared):
            if case .committed = await schedulerController.commit(prepared,
                acknowledgedEnvelope: saved, using: schedulerCapability) {
                schedulerCommitted = true
            } else {
                schedulerCommitted = false
            }
        case .presentation(let prepared):
            if case .committed = await schedulerController.commitPresentation(prepared,
                acknowledgedEnvelope: saved, using: schedulerCapability) {
                schedulerCommitted = true
            } else {
                schedulerCommitted = false
            }
        }
        lastSuccessfullyPersistedRevision = saved.revision
        durableSettingsRevision = saved.revision
        acknowledgedEnvelope = saved
        acknowledgedScanEnvelope = nil
        issuedImportBinding = nil
        _ = advanceImportLifecycle()
        guard schedulerCommitted else {
            if ticket != nil {
                isExecutionEnabled = false
                policyFailureActive = true
            }
            if !policyFailureActive || ticket != nil {
                persistenceError = "Settings were saved but could not be applied. Cleanup remains disabled."
                errorSequence = sequence
            }
            return .saved(id, saved)
        }
        acknowledgedScanEnvelope = saved
        if let ticket {
            let environment = saved.config.makePolicyEnvironment(
                homeDirectory: homeDirectory, detectedTools: detectedTools)
            let commit = try await coordinator.commitPolicyUpdate(ticket, environment: environment)
            if case .applied = commit, pendingPolicyCount == 1,
               generation == intentGeneration {
                isExecutionEnabled = true
                policyFailureActive = false
                if sequence >= errorSequence { persistenceError = nil }
            } else if pendingPolicyCount == 1, generation == intentGeneration {
                persistenceError = "A newer settings update is pending. Cleanup remains disabled."
                errorSequence = sequence
                policyFailureActive = true
                isExecutionEnabled = false
            }
        } else if !policyFailureActive, sequence >= errorSequence {
            persistenceError = nil
        }
        return .saved(id, saved)
    }

    private func schedulerCandidate(for payload: Payload,
                                    expectedRevision: UInt64) throws -> SettingsEnvelope {
        guard let acknowledgedEnvelope, acknowledgedEnvelope.revision == expectedRevision else {
            throw SettingsStoreError.staleRevision
        }
        let candidate: SettingsEnvelope
        switch payload {
        case .legacy(let delta):
            // A stored whole-value delta remains bound to the exact config
            // acknowledgement it was accepted against; it is never rebased.
            guard delta.base == acknowledgedEnvelope.config else {
                throw SettingsStoreError.staleRevision
            }
            candidate = applyingPrediction(delta, to: acknowledgedEnvelope)
        case .global(let delta):
            candidate = applyingGlobalPrediction(delta, to: acknowledgedEnvelope)
        case .document(let delta):
            candidate = try PreferencesDocumentProjection.apply(delta, to: acknowledgedEnvelope).envelope
        case .importPreview(let expectedRevision, let preview):
            guard expectedRevision == lastSuccessfullyPersistedRevision else {
                throw SettingsStoreError.staleRevision
            }
            candidate = try importPrediction(preview.candidate, from: acknowledgedEnvelope)
        }
        let (revision, overflow) = expectedRevision.addingReportingOverflow(1)
        guard !overflow else { throw SettingsStoreError.invalidChange }
        return SettingsEnvelope(schemaVersion: candidate.schemaVersion, revision: revision,
            config: candidate.config, preferences: candidate.preferences,
            activeProfileID: candidate.activeProfileID, inertImports: candidate.inertImports)
    }

    private func prepareScheduler(id: SettingsIntentID,
                                  candidate: SettingsEnvelope) async throws -> SchedulerPreparation {
        if pendingSchedulerInvalidations.contains(id) {
            let admission: SchedulerAdmissionTicket
            if let ticket = pendingSchedulerTickets[id] {
                admission = ticket
            } else {
                do {
                    admission = try schedulerController.beginAdmissionTransition(using: schedulerCapability)
                } catch {
                    throw SchedulerHandoffError.invalid
                }
                pendingSchedulerTickets[id] = admission
            }
            await testHook?.receive(.acceptedAfterBarrierBeforePrepareAndSave(id))
            try Task.checkCancellation()
            let result = await schedulerController.prepare(admission, candidate: candidate,
                observation: .unknown, using: schedulerCapability)
            guard case .prepared(let prepared, _) = result else { throw SchedulerHandoffError.invalid }
            return .invalidating(prepared)
        }

        let result = await schedulerController.preparePresentation(candidate: candidate,
            observation: .unknown, using: schedulerCapability)
        guard case .prepared(let prepared, _) = result else { throw SchedulerHandoffError.invalid }
        await testHook?.receive(.acceptedAfterPresentationPrepareBeforeSave(id))
        return .presentation(prepared)
    }

    private func discardSchedulerPreparation(_ preparation: SchedulerPreparation) async {
        switch preparation {
        case .invalidating(let prepared):
            _ = await schedulerController.fail(prepared, using: schedulerCapability)
        case .presentation(let prepared):
            _ = await schedulerController.discardPresentation(prepared, using: schedulerCapability)
        }
    }

    private func reserveSequence() -> UInt64? {
        let (next, overflow) = submissionSequence.addingReportingOverflow(1)
        guard !overflow else { return nil }
        submissionSequence = next
        return next
    }

    private func advanceImportLifecycle() -> UInt64? {
        let (next, overflow) = importLifecycleGeneration.addingReportingOverflow(1)
        guard !overflow else { return nil }
        importLifecycleGeneration = next
        return next
    }

    private func rejectSequenceOverflow(id: SettingsIntentID) -> SettingsSubmissionAdmission {
        if !policyFailureActive {
            persistenceError = "Settings changes cannot be sequenced; restart Tidy before saving again."
        }
        return .rejected(id, .queueFull)
    }

    private func rejectBeforeRetention(id: SettingsIntentID, sequence: UInt64,
                                       reason: SettingsSubmissionRejection,
                                       message: String) -> SettingsSubmissionAdmission {
        if !policyFailureActive {
            persistenceError = message
            errorSequence = sequence
        }
        return .rejected(id, reason)
    }

    private func retainedBytes(id: SettingsIntentID, payload: Payload) throws -> Int {
        var total = id.uuidString.utf8.count + 64
        func add(_ value: Int) throws {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow, next <= Self.maximumPendingBytes else {
                throw SettingsStoreError.oversized
            }
            total = next
        }
        switch payload {
        case .legacy(let delta):
            try add(SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2,
                revision: delta.baseRevision, config: delta.base)).count)
            try add(SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2,
                revision: delta.baseRevision, config: delta.edited)).count)
            for item in delta.touchedCompatibilityBase {
                try add(item.id.rawValue.utf8.count)
                if let value = item.baseValue { try add(JSONEncoder().encode(value).count) }
                if let value = item.editedValue { try add(JSONEncoder().encode(value).count) }
            }
        case .global(let delta):
            try add(delta.id.rawValue.utf8.count)
            if let value = delta.baseValue { try add(JSONEncoder().encode(value).count) }
            if let value = delta.editedValue { try add(JSONEncoder().encode(value).count) }
        case .document(let delta):
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            total = try encoder.encode(RetainedDocumentMirror(intentID: id, delta: delta)).count
        case .importPreview(let expectedRevision, let preview):
            total = try Self.retainedImportAccountingData(intentID: id,
                expectedRevision: expectedRevision, preview: preview).count
        }
        return total
    }

    internal static func retainedImportAccountingData(intentID: SettingsIntentID,
                                                       expectedRevision: UInt64,
                                                       preview: SettingsImportPreview) throws -> Data {
        let rows = preview.rows.map {
            RetainedImportMirror.Row(scope: $0.scope.rawValue, profileID: $0.profileID,
                id: $0.id, idDigest: $0.idDigest, outcome: $0.outcome.rawValue,
                value: $0.value, valueKind: $0.valueKind?.rawValue,
                valueDigest: $0.valueDigest)
        }
        let collisions = preview.collisions.map {
            RetainedImportMirror.Collision(profileID: $0.profileID, localName: $0.localName,
                                            importedName: $0.importedName)
        }
        let choices = preview.choices.map { profileID, value -> RetainedImportMirror.Choice in
            switch value {
            case .keepLocal: return .init(profileID: profileID, kind: "keepLocal", cloneID: nil)
            case .replace: return .init(profileID: profileID, kind: "replace", cloneID: nil)
            case .clone(let id): return .init(profileID: profileID, kind: "clone", cloneID: id)
            }
        }.sorted { $0.profileID.uuidString < $1.profileID.uuidString }
        let mirror = RetainedImportMirror(intentID: intentID,
            expectedRevision: expectedRevision, previewID: preview.id,
            analysisID: preview.analysisID, rows: rows, collisions: collisions,
            choices: choices, preferences: preview.candidate.preferences,
            inertImports: preview.candidate.inertImports,
            sourceDigest: preview.sourceDigest, candidateDigest: preview.candidateDigest)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(mirror)
    }

    internal static func checkedRetainedTotalForTesting(_ current: Int,
                                                        adding: Int) throws -> Int {
        let (total, overflow) = current.addingReportingOverflow(adding)
        guard current >= 0, adding >= 0, !overflow else { throw SettingsStoreError.oversized }
        return total
    }

    internal var pendingByteLimitForTesting: Int { pendingByteLimit }

    /// Replays accepted intent payloads in admission order over the exact last
    /// durable acknowledgement. Stored deltas are never rebased: this is only
    /// the prediction used to bind later source-compatible submissions.
    private func rebuildPredictedSubmission() {
        var envelope = acknowledgedEnvelope ?? SettingsEnvelope(schemaVersion: 2,
            revision: 0, config: TidyConfig(schemaVersion: 2))
        for id in pendingPayloadOrder {
            guard let payload = pendingPayloads[id] else { continue }
            switch payload {
            case .legacy(let delta):
                envelope = applyingPrediction(delta, to: envelope)
            case .global(let delta):
                envelope = applyingGlobalPrediction(delta, to: envelope)
            case .document(let delta):
                if let applied = try? PreferencesDocumentProjection.apply(delta, to: envelope) {
                    envelope = applied.envelope
                }
            case .importPreview(_, let preview):
                if let prediction = try? importPrediction(preview.candidate, from: envelope) {
                    envelope = prediction
                }
            }
        }
        predictedSubmittedEnvelope = envelope
    }

    private func applyingPrediction(_ delta: LegacyPreferenceDelta,
                                    to envelope: SettingsEnvelope) -> SettingsEnvelope {
        let base = envelope.config
        var config = base
        if delta.base.schemaVersion != delta.edited.schemaVersion { config.schemaVersion = delta.edited.schemaVersion }
        if delta.base.hasCompletedOnboarding != delta.edited.hasCompletedOnboarding { config.hasCompletedOnboarding = delta.edited.hasCompletedOnboarding }
        if delta.base.keepCookieDomains != delta.edited.keepCookieDomains { config.keepCookieDomains = delta.edited.keepCookieDomains }
        if delta.base.simulatorsApprovedForDeletion != delta.edited.simulatorsApprovedForDeletion { config.simulatorsApprovedForDeletion = delta.edited.simulatorsApprovedForDeletion }
        if delta.base.gitRoots != delta.edited.gitRoots { config.gitRoots = delta.edited.gitRoots }
        if delta.base.staleNodeModulesThresholdDays != delta.edited.staleNodeModulesThresholdDays { config.staleNodeModulesThresholdDays = delta.edited.staleNodeModulesThresholdDays }
        if delta.base.transcriptAgeThresholdDays != delta.edited.transcriptAgeThresholdDays { config.transcriptAgeThresholdDays = delta.edited.transcriptAgeThresholdDays }
        if delta.base.appsApprovedForQuit != delta.edited.appsApprovedForQuit { config.appsApprovedForQuit = delta.edited.appsApprovedForQuit }
        if delta.base.allowRestartToReclaimSwap != delta.edited.allowRestartToReclaimSwap { config.allowRestartToReclaimSwap = delta.edited.allowRestartToReclaimSwap }
        if delta.base.presets != delta.edited.presets { config.presets = delta.edited.presets }
        let preferences = LegacyCompatibilityProjection.applyingLegacyEdit(
            from: base, to: config, saved: envelope.preferences)
        return SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences,
            activeProfileID: envelope.activeProfileID, inertImports: envelope.inertImports)
    }

    private func applyingGlobalPrediction(_ delta: GlobalPreferenceDelta,
                                          to envelope: SettingsEnvelope) -> SettingsEnvelope {
        var preferences = envelope.preferences ?? PolicyPreferences()
        let prior = preferences.global
        preferences.global.fields[delta.id] = delta.editedValue
        let config = LegacyCompatibilityProjection.reverseProject(envelope.config,
            replacing: prior, with: preferences.global)
        return SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences,
            activeProfileID: envelope.activeProfileID, inertImports: envelope.inertImports)
    }

    private func importPrediction(_ candidate: PortableSettingsState,
                                  from envelope: SettingsEnvelope) throws -> SettingsEnvelope {
        var preferences = candidate.preferences
        preferences.projects = envelope.preferences?.projects ?? [:]
        let config = LegacyCompatibilityProjection.reverseProject(envelope.config,
            replacing: envelope.preferences?.global, with: preferences.global)
        let predicted = SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences,
            activeProfileID: envelope.activeProfileID, inertImports: candidate.inertImports)
        _ = try PreferencesDocumentEffect.classify(before: envelope, after: predicted)
        return predicted
    }

    private func isPresentationDelta(_ delta: GlobalPreferenceDelta) -> Bool {
        guard delta.id == SettingID(rawValue: "scan.uiBatchesPerSecond"),
              case .integer = delta.baseValue,
              case .integer = delta.editedValue else { return false }
        return true
    }

    private static var canonicalFreshDefaults: SettingsEnvelope {
        SettingsEnvelope(schemaVersion: TidyConfig.currentSchemaVersion, revision: 0,
            config: TidyConfig(schemaVersion: TidyConfig.currentSchemaVersion))
    }

    private func installInitialScheduler(_ envelope: SettingsEnvelope,
                                         origin: SchedulerPolicyOrigin,
                                         bootstrap: SettingsSchedulerBootstrap?) async {
        // Durable policy and exact absent-file defaults both enter through the
        // first-install invalidating path. A competing accepted bridge handoff
        // wins; its barrier remains closed.
        if origin == .freshDefaults {
            guard let bootstrap,
                  let lease = await settings.acquireSchedulerBootstrap(bootstrap) else { return }
            await installInitialSchedulerUnderLease(envelope, origin: origin)
            await settings.releaseSchedulerBootstrap(lease)
            return
        }
        await installInitialSchedulerUnderLease(envelope, origin: origin)
    }

    private func installInitialSchedulerUnderLease(_ envelope: SettingsEnvelope,
                                                   origin: SchedulerPolicyOrigin) async {
        guard schedulerAdmissionPendingCount == 0 else { return }
        let admission: SchedulerAdmissionTicket
        do { admission = try schedulerController.beginAdmissionTransition(using: schedulerCapability) }
        catch { return }
        let preparation = await schedulerController.prepare(admission, candidate: envelope,
            observation: .unknown, origin: origin, using: schedulerCapability)
        guard case .prepared(let prepared, _) = preparation else { return }
        if case .committed = await schedulerController.commit(prepared,
            acknowledgedEnvelope: envelope, using: schedulerCapability) {
            acknowledgedScanEnvelope = envelope
        }
    }

    fileprivate func beginExplicitSession(requirements: SchedulerRequirements) async throws -> WorkSession {
        guard schedulerAdmissionPendingCount == 0 else { throw WorkSchedulerError.admissionUpdating }
        let capability = try await schedulerController.issueExplicitCapability(requirements: requirements,
            using: schedulerCapability)
        guard schedulerAdmissionPendingCount == 0 else { throw WorkSchedulerError.admissionUpdating }
        return try await scheduler.beginSession(requirements: requirements, capability: capability)
    }

    fileprivate func withExplicitPermit<T: Sendable>(session: WorkSession,
        operation: @Sendable (SchedulerCancellationProbe) async throws -> T) async throws -> T {
        guard schedulerAdmissionPendingCount == 0 else { throw WorkSchedulerError.admissionUpdating }
        return try await scheduler.withPermit(session: session, operation: operation)
    }

    fileprivate func cancelExplicitSession(_ session: WorkSession) async {
        await scheduler.cancel(session: session)
    }

    fileprivate func finishExplicitSession(_ session: WorkSession) async {
        await scheduler.finish(session: session)
    }

    fileprivate func explicitSessionState(_ session: WorkSession) async -> WorkSessionState? {
        await scheduler.state(of: session)
    }

    fileprivate func explicitSessionSnapshot() async -> WorkSchedulerSnapshot {
        await scheduler.snapshot()
    }

    fileprivate func updateLiveObservation(epoch: UInt64, monotonicNanoseconds: UInt64,
                                           observation: SchedulerLiveObservation) async
      -> SchedulerLiveObservationResult {
        guard epoch > liveObservationEpoch else {
            return .rejectedStale(current: liveObservationEpoch)
        }
        guard let envelope = acknowledgedScanEnvelope,
              schedulerAdmissionPendingCount == 0 else {
            return .unavailable
        }
        let raw: SchedulerObservation
        switch observation {
        case .unknown: raw = .unknown
        case .nominal: raw = .nominal
        case .constrained: raw = .constrained
        case .critical: raw = .critical
        }
        let effective: SchedulerObservation
        if raw == .critical {
            let policy = await schedulerController.resolvedPolicy(
                using: schedulerCapability)
            let seconds: UInt64
            if case .stored(.integer(let configured))? = policy?.fields[
                SettingID(rawValue: "scan.resumeAfterCriticalSeconds")]?.value,
               configured >= 0, let exact = UInt64(exactly: configured) {
                seconds = exact
            } else {
                seconds = 120
            }
            let (delay, delayOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
            let (deadline, deadlineOverflow) = monotonicNanoseconds.addingReportingOverflow(delay)
            guard !delayOverflow, !deadlineOverflow else { return .unavailable }
            criticalResumeNotBefore = deadline
            effective = .critical
        } else if let deadline = criticalResumeNotBefore,
                  monotonicNanoseconds < deadline {
            effective = .critical
        } else {
            criticalResumeNotBefore = nil
            effective = raw
        }
        let result = await schedulerController.updateObservation(epoch: epoch,
            observation: effective, acknowledgedEnvelope: envelope,
            using: schedulerCapability)
        switch result {
        case .applied:
            liveObservationEpoch = epoch
            return .applied
        case .rejectedStale(let current):
            liveObservationEpoch = max(liveObservationEpoch, current)
            return .rejectedStale(current: current)
        case .failedClosed:
            return .unavailable
        }
    }

    public func drain() async {
        if let initialSchedulerInstall { await initialSchedulerInstall.value }
        while let tail = pendingTail { _ = await tail.value }
    }
}

public extension ExecutionPolicyBridge {
    var explicitSessions: BridgeExplicitSessions { BridgeExplicitSessions(bridge: self) }
}
