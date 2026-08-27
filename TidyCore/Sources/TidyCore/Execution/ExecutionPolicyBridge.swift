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

    private enum Payload: Sendable {
        case legacy(LegacyPreferenceDelta)
        case global(GlobalPreferenceDelta)
    }

    private static let maximumPendingSnapshots = 32
    private static let maximumPendingBytes = 32 * 1_048_576
    private static let saveFailure = "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again."
    private static let overflowFailure = "Settings changes are pending; wait and save again."

    public init(coordinator: ExecutionCoordinator, settings: SettingsStore,
                loaded: SettingsLoadResult, homeDirectory: String,
                detectedTools: Set<ToolchainID>) {
        self.coordinator = coordinator
        self.settings = settings
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
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
        guard pendingSnapshotCount < Self.maximumPendingSnapshots,
              pendingSnapshotBytes <= Self.maximumPendingBytes - bytes else {
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
        pendingSnapshotBytes += bytes
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
            }
            let saved = try await settings.update(expectedRevision: expectedRevision, change: change)
            lastSuccessfullyPersistedRevision = saved.revision
            durableSettingsRevision = saved.revision
            acknowledgedEnvelope = saved

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

    private func reserveSequence() -> UInt64? {
        let (next, overflow) = submissionSequence.addingReportingOverflow(1)
        guard !overflow else { return nil }
        submissionSequence = next
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
        }
        return total
    }

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
            }
        }
        predictedSubmittedEnvelope = envelope
    }

    private func applyingPrediction(_ delta: LegacyPreferenceDelta,
                                    to envelope: SettingsEnvelope) -> SettingsEnvelope {
        var config = envelope.config
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
        var preferences = envelope.preferences ?? PolicyPreferences()
        for touched in delta.touchedCompatibilityBase {
            preferences.global.fields[touched.id] = touched.editedValue
        }
        return SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences)
    }

    private func applyingGlobalPrediction(_ delta: GlobalPreferenceDelta,
                                          to envelope: SettingsEnvelope) -> SettingsEnvelope {
        var config = envelope.config
        var preferences = envelope.preferences ?? PolicyPreferences()
        preferences.global.fields[delta.id] = delta.editedValue
        switch delta.id.rawValue {
        case "cleanup.transcriptDays":
            if case .integer(let value)? = delta.editedValue { config.transcriptAgeThresholdDays = Int(value) }
            else if delta.baseValue != nil { config.transcriptAgeThresholdDays = 45 }
        case "item.normal.extras.stale-node-modules.inactiveDays":
            if case .integer(let value)? = delta.editedValue { config.staleNodeModulesThresholdDays = Int(value) }
            else if delta.baseValue != nil { config.staleNodeModulesThresholdDays = 60 }
        case "browsers.keepCookieDomains":
            if case .strings(let values)? = delta.editedValue { config.keepCookieDomains = values }
            else if delta.baseValue != nil { config.keepCookieDomains = [] }
        case "rescue.showAdvancedMemoryActions":
            if case .bool(let value)? = delta.editedValue { config.allowRestartToReclaimSwap = value }
            else if delta.baseValue != nil { config.allowRestartToReclaimSwap = false }
        default: break
        }
        return SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences)
    }

    public func drain() async {
        while let tail = pendingTail { _ = await tail.value }
    }
}
