import Foundation
import Observation
import TidyCore

@Observable @MainActor
final class AppConfigStore {
    var config: TidyConfig {
        get { displayed.config }
        set {
            let delta = LegacyPreferenceDelta(baseRevision: acknowledged.revision,
                                              base: displayed.config, edited: newValue,
                                              compatibilityBase: displayed.preferences?.global)
            switch bridge.submit(legacy: delta) {
            case .accepted(let id, _):
                pendingOrder.append(id)
                pending[id] = .legacy(delta)
                replayVisibleState()
            case .rejected: break
            }
        }
    }
    var preferences: PolicyPreferences {
        PolicyPreferences.project(legacy: displayed.config, saved: displayed.preferences)
    }
    var activeProfileID: UUID? { displayed.activeProfileID }
    var inertImports: [InertPortableSetting] { displayed.inertImports }
    var settingsRevision: UInt64 { displayed.revision }
    var profiles: [SavedProfile] { preferences.profiles }
    var hasPendingSettingsWrites: Bool { !pendingOrder.isEmpty }
    var effectivePolicy: EffectivePolicy? { resolvePolicy(displayed) }
    var acknowledgedEffectivePolicy: EffectivePolicy? { resolvePolicy(acknowledged) }

    private let bridge: ExecutionPolicyBridge
    private var acknowledged: SettingsEnvelope
    private var displayed: SettingsEnvelope
    private var pendingOrder: [SettingsIntentID] = []
    private var pending: [SettingsIntentID: PendingTransform] = [:]
    private var observerToken: UUID?
    private var acknowledgedPolicyObservers:
        [UUID: @MainActor (UInt64, EffectivePolicy?) -> Void] = [:]
    private var selectedVolumeID: UUID?
    private var selectedVolumeCapacityBytes: Int64?
    private var selectedVolumeObservedAt: Date?

    private enum PendingTransform {
        case legacy(LegacyPreferenceDelta)
        case global(GlobalPreferenceDelta)
        case document(PreferencesDocumentDelta)
        case importPreview(SettingsImportPreview)
    }

    init(loaded: SettingsEnvelope, bridge: ExecutionPolicyBridge) {
        self.acknowledged = loaded
        self.displayed = loaded
        self.bridge = bridge
        self.observerToken = bridge.observeOutcomes { [weak self] outcome in
            self?.receive(outcome)
        }
    }

    convenience init(config: TidyConfig, bridge: ExecutionPolicyBridge) {
        self.init(loaded: SettingsEnvelope(schemaVersion: 2, revision: 0, config: config),
                  bridge: bridge)
    }

    @discardableResult
    func setGlobalPreference(_ id: SettingID,
                             to value: SettingValue?) -> SettingsSubmissionAdmission {
        let delta = GlobalPreferenceDelta(baseRevision: acknowledged.revision, id: id,
            baseValue: displayed.preferences?.global.fields[id], editedValue: value)
        let admission = bridge.submit(global: delta)
        if case .accepted(let intentID, _) = admission {
            pendingOrder.append(intentID)
            pending[intentID] = .global(delta)
            replayVisibleState()
        }
        return admission
    }

    @discardableResult
    func submit(document delta: PreferencesDocumentDelta) -> SettingsSubmissionAdmission {
        let admission = bridge.submit(document: delta)
        if case .accepted(let intentID, _) = admission {
            pendingOrder.append(intentID); pending[intentID] = .document(delta)
            replayVisibleState()
        }
        return admission
    }

    func previewProfileWorkflow(_ request: SettingsProfileWorkflowRequest) throws
        -> SettingsProfileWorkflowPreview {
        try SettingsWorkflow.previewProfile(request, current: displayed)
    }

    @discardableResult
    func commitProfileWorkflow(_ preview: SettingsProfileWorkflowPreview)
        -> SettingsSubmissionAdmission {
        submit(document: preview.delta)
    }

    func previewSelectiveReset(_ request: SettingsSelectiveResetRequest) throws
        -> SettingsSelectiveResetPreview {
        try SettingsWorkflow.previewSelectiveReset(request, current: displayed)
    }

    @discardableResult
    func commitSelectiveReset(_ preview: SettingsSelectiveResetPreview)
        -> SettingsSubmissionAdmission {
        submit(document: preview.delta)
    }

    func exportPortableSettings() throws -> Data {
        try SettingsWorkflow.exportPortable(current: displayed)
    }

    func analyzeImportSummary(bytes: Data) async throws -> SettingsImportUISummary {
        try SettingsImportUISummary(try await analyzeImport(bytes: bytes))
    }

    func analyzeImport(bytes: Data) async throws -> SettingsImportAnalysis {
        try await bridge.analyzeImport(bytes: bytes)
    }

    func issueImportPreview(analysisID: SettingsImportAnalysisID,
                            choices: [UUID: ProfileCollisionChoice]) async throws
        -> SettingsImportPreview {
        try await bridge.issueImportPreview(analysisID: analysisID, choices: choices)
    }

    @discardableResult
    func commitImport(_ preview: SettingsImportPreview) -> SettingsSubmissionAdmission {
        let admission = bridge.submit(importPreview: preview)
        if case .accepted(let intentID, _) = admission {
            pendingOrder.append(intentID); pending[intentID] = .importPreview(preview)
            replayVisibleState()
        }
        return admission
    }

    func cancelImport(analysisID: SettingsImportAnalysisID) async {
        await bridge.cancelImport(analysisID: analysisID)
    }

    func cancelImport(previewID: SettingsImportPreviewID) async {
        await bridge.cancelImport(previewID: previewID)
    }

    @discardableResult
    func observeAcknowledgedPolicy(
        _ observer: @escaping @MainActor (UInt64, EffectivePolicy?) -> Void
    ) -> UUID {
        let token = UUID()
        acknowledgedPolicyObservers[token] = observer
        observer(acknowledged.revision, acknowledgedEffectivePolicy)
        return token
    }

    func removeAcknowledgedPolicyObserver(_ token: UUID) {
        acknowledgedPolicyObservers.removeValue(forKey: token)
    }

    /// Accept only a measured UUID plus a positive capacity. A mount path is
    /// display data and never becomes volume authority through this seam.
    func updateSelectedVolume(identity: String?, capacityBytes: Int64?, observedAt: Date) {
        guard selectedVolumeObservedAt.map({ observedAt >= $0 }) ?? true else { return }
        selectedVolumeObservedAt = observedAt
        guard let identity, let id = UUID(uuidString: identity),
              let capacityBytes, capacityBytes > 0 else {
            selectedVolumeID = nil
            selectedVolumeCapacityBytes = nil
            return
        }
        selectedVolumeID = id
        selectedVolumeCapacityBytes = capacityBytes
    }

    private func receive(_ outcome: SettingsIntentOutcome) {
        let id: SettingsIntentID
        switch outcome {
        case .saved(let value, _), .conflict(let value), .invalid(let value),
             .failed(let value, _): id = value
        }
        var didSave = false
        if case .saved(_, let exact) = outcome {
            acknowledged = exact
            didSave = true
        }
        if pending[id] != nil {
            pending[id] = nil
            pendingOrder.removeAll { $0 == id }
        }
        replayVisibleState()
        if didSave {
            let revision = acknowledged.revision
            let policy = acknowledgedEffectivePolicy
            for observer in acknowledgedPolicyObservers.values { observer(revision, policy) }
        }
    }

    private func resolvePolicy(_ envelope: SettingsEnvelope) -> EffectivePolicy? {
        let projected = PolicyPreferences.project(legacy: envelope.config,
            saved: envelope.preferences)
        var layers: [PolicyLayer: PolicyValues] = [.global: projected.global]
        if let activeProfileID = envelope.activeProfileID {
            guard projected.profiles.filter({ $0.id == activeProfileID }).count == 1,
                  let profile = projected.profiles.first(where: { $0.id == activeProfileID })
            else { return nil }
            layers[.profile] = profile.values
        }
        let approved: Set<UUID> = selectedVolumeID.map { Set([$0]) } ?? []
        let inputs = PolicyInputs(layers: layers, selectedVolumeID: selectedVolumeID,
            approvedVolumeIDs: approved, capacityBytes: selectedVolumeCapacityBytes,
            logicalCPUCount: max(1, ProcessInfo.processInfo.activeProcessorCount),
            lowPower: false, seriousThermal: false, critical: false,
            mandatoryExclusions: [])
        return try? PolicyResolver.resolve(inputs)
    }

    private func replayVisibleState() {
        var envelope = SettingsEnvelope(schemaVersion: acknowledged.schemaVersion,
            revision: acknowledged.revision, config: acknowledged.config,
            preferences: acknowledged.preferences, activeProfileID: acknowledged.activeProfileID,
            inertImports: acknowledged.inertImports)
        for id in pendingOrder {
            guard let transform = pending[id] else { continue }
            switch transform {
            case .legacy(let delta):
                envelope = applying(delta, to: envelope)
            case .global(let delta):
                var values = envelope.preferences ?? PolicyPreferences()
                let prior = values.global
                values.global.fields[delta.id] = delta.editedValue
                let config = LegacyCompatibilityProjection.reverseProject(envelope.config,
                    replacing: prior, with: values.global)
                envelope = SettingsEnvelope(schemaVersion: envelope.schemaVersion,
                    revision: envelope.revision, config: config, preferences: values,
                    activeProfileID: envelope.activeProfileID,
                    inertImports: envelope.inertImports)
            case .document(let delta):
                if let applied = try? PreferencesDocumentProjection.apply(delta, to: envelope) {
                    envelope = applied.envelope
                }
            case .importPreview(let preview):
                envelope = applying(preview, to: envelope)
            }
        }
        displayed = envelope
    }

    private func applying(_ delta: LegacyPreferenceDelta,
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

    private func applying(_ preview: SettingsImportPreview,
                          to envelope: SettingsEnvelope) -> SettingsEnvelope {
        var preferences = preview.candidate.preferences
        preferences.projects = envelope.preferences?.projects ?? [:]
        let config = LegacyCompatibilityProjection.reverseProject(envelope.config,
            replacing: envelope.preferences?.global, with: preferences.global)
        return SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences,
            activeProfileID: envelope.activeProfileID,
            inertImports: preview.candidate.inertImports)
    }
}
