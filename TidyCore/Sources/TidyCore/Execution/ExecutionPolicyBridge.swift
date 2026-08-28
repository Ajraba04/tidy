import Foundation
import Observation

public typealias SettingsIntentID = UUID

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

@Observable @MainActor
public final class ExecutionPolicyBridge {
    public private(set) var updateGeneration = UUID()
    public private(set) var isExecutionEnabled: Bool
    public private(set) var storageUpdatePending = false
    public private(set) var policyUpdatePending = false
    public private(set) var persistenceError: String?
    public private(set) var durableSettingsRevision: UInt64?
    public private(set) var acknowledgedEnvelope: SettingsEnvelope?
    internal private(set) var pendingSnapshotCount = 0
    internal private(set) var pendingSnapshotBytes = 0

    private let coordinator: ExecutionCoordinator
    private let settings: SettingsStore
    private let homeDirectory: String
    private let detectedTools: Set<ToolchainID>
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
                  homeDirectory: homeDirectory, detectedTools: detectedTools,
                  pendingByteLimit: Self.maximumPendingBytes)
    }

    internal init(coordinator: ExecutionCoordinator, settings: SettingsStore,
                  loaded: SettingsLoadResult, homeDirectory: String,
                  detectedTools: Set<ToolchainID>, pendingByteLimit: Int) {
        self.coordinator = coordinator
        self.settings = settings
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
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
    }

    @discardableResult
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
                     effect: definition.effect)
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
        return admit(id: id, sequence: sequence, payload: .document(delta), effect: applied.effect)
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
            payload: .importPreview(expectedRevision: binding.revision, preview: preview), effect: effect)
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
        return admit(id: id, sequence: sequence, payload: .legacy(delta), effect: .invalidate)
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
                       effect: AuthorityEffect) -> SettingsSubmissionAdmission {
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

        pendingSnapshotCount += 1
        pendingSnapshotBytes = retainedTotal
        pendingPayloadOrder.append(id)
        pendingPayloads[id] = payload
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
            pendingPayloadOrder.removeAll { $0 == id }
            pendingPayloads[id] = nil
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
            let change: SettingsChange
            switch payload {
            case .legacy(let delta):
                // A stored whole-value delta remains bound to the exact config
                // prediction it was accepted against. If an earlier dependency
                // failed, do not replay only its changed fields over another base.
                guard delta.base == acknowledgedEnvelope?.config else {
                    throw SettingsStoreError.staleRevision
                }
                change = .legacyPreferenceDelta(delta)
            case .global(let delta): change = .globalPreferenceDelta(delta)
            case .document(let delta): change = .preferencesDocument(delta)
            case .importPreview(let expectedRevision, let preview):
                guard expectedRevision == lastSuccessfullyPersistedRevision else {
                    throw SettingsStoreError.staleRevision
                }
                let saved = try await settings.commitImport(expectedRevision: expectedRevision,
                                                            previewID: preview.id)
                return try await acceptSaved(saved, id: id, ticket: ticket,
                                             intentGeneration: intentGeneration,
                                             sequence: sequence)
            }
            let saved = try await settings.update(expectedRevision: expectedRevision, change: change)
            return try await acceptSaved(saved, id: id, ticket: ticket,
                                         intentGeneration: intentGeneration, sequence: sequence)
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
                             sequence: UInt64) async throws -> SettingsIntentOutcome {
        lastSuccessfullyPersistedRevision = saved.revision
        durableSettingsRevision = saved.revision
        acknowledgedEnvelope = saved
        issuedImportBinding = nil
        _ = advanceImportLifecycle()
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
            revision: envelope.revision, config: config, preferences: preferences)
    }

    private func applyingGlobalPrediction(_ delta: GlobalPreferenceDelta,
                                          to envelope: SettingsEnvelope) -> SettingsEnvelope {
        var preferences = envelope.preferences ?? PolicyPreferences()
        let prior = preferences.global
        preferences.global.fields[delta.id] = delta.editedValue
        let config = LegacyCompatibilityProjection.reverseProject(envelope.config,
            replacing: prior, with: preferences.global)
        return SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences)
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

    public func drain() async {
        while let tail = pendingTail { _ = await tail.value }
    }
}
