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
    private var legacySubmittedConfig: TidyConfig
    private var legacySubmittedPreferences: PolicyPreferences?
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
        self.legacySubmittedConfig = envelope?.config ?? TidyConfig(schemaVersion: 2)
        self.legacySubmittedPreferences = envelope?.preferences
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
        if let value = delta.editedValue {
            do {
                try PolicyValidator.validateStructure(
                    PolicyValues(fields: [delta.id: value]), at: .global)
            } catch {
                return rejectBeforeRetention(id: id, sequence: sequence, reason: .invalid,
                                             message: "The settings change is invalid.")
            }
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
        let admission = admit(id: id, sequence: sequence, payload: .legacy(delta),
                              effect: .invalidate)
        if case .accepted = admission {
            legacySubmittedConfig = delta.edited
            var projected = legacySubmittedPreferences ?? PolicyPreferences()
            for touched in delta.touchedCompatibilityBase {
                projected.global.fields[touched.id] = touched.editedValue
            }
            legacySubmittedPreferences = projected
        }
        return admission
    }

    /// Source-compatible whole-value entry point. New app code uses the
    /// base-bound typed/delta APIs above.
    @discardableResult
    public func submit(config: TidyConfig) -> Task<Void, Never> {
        let delta = LegacyPreferenceDelta(baseRevision: acknowledgedEnvelope?.revision ?? 0,
            base: legacySubmittedConfig, edited: config,
            compatibilityBase: legacySubmittedPreferences?.global)
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
            let outcome = await perform(id: id, payload: payload, ticket: ticket,
                                        intentGeneration: intentGeneration,
                                        sequence: sequence)
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

    private func perform(id: SettingsIntentID, payload: Payload,
                         ticket: PolicyUpdateTicket?,
                         intentGeneration: UUID?, sequence: UInt64) async -> SettingsIntentOutcome {
        do {
            guard let expectedRevision = lastSuccessfullyPersistedRevision else {
                throw SettingsStoreError.readOnlyRecovery
            }
            let change: SettingsChange
            switch payload {
            case .legacy(let delta): change = .legacyPreferenceDelta(delta)
            case .global(let delta): change = .globalPreferenceDelta(delta)
            }
            let saved = try await settings.update(expectedRevision: expectedRevision, change: change)
            lastSuccessfullyPersistedRevision = saved.revision
            durableSettingsRevision = saved.revision
            acknowledgedEnvelope = saved
            if pendingSnapshotCount == 1 {
                legacySubmittedConfig = saved.config
                legacySubmittedPreferences = saved.preferences
            }

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

    public func drain() async {
        while let tail = pendingTail { _ = await tail.value }
    }
}
