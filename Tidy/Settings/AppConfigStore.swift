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

    private let bridge: ExecutionPolicyBridge
    private var acknowledged: SettingsEnvelope
    private var displayed: SettingsEnvelope
    private var pendingOrder: [SettingsIntentID] = []
    private var pending: [SettingsIntentID: PendingTransform] = [:]
    private var bufferedOutcomes: [SettingsIntentID: SettingsIntentOutcome] = [:]
    private var observerToken: UUID?

    private enum PendingTransform {
        case legacy(LegacyPreferenceDelta)
        case global(GlobalPreferenceDelta)
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

    private func receive(_ outcome: SettingsIntentOutcome) {
        let id: SettingsIntentID
        switch outcome {
        case .saved(let value, _), .conflict(let value), .invalid(let value),
             .failed(let value, _): id = value
        }
        // The bridge keeps a source-compatible direct submission API for core
        // callers. Only outcomes for intents accepted through this store own a
        // displayed transform; unrelated outcomes must not accumulate here.
        guard pending[id] != nil else { return }
        bufferedOutcomes[id] = outcome
        drainBufferedHead()
    }

    private func drainBufferedHead() {
        while let id = pendingOrder.first, let outcome = bufferedOutcomes.removeValue(forKey: id) {
            pendingOrder.removeFirst()
            pending[id] = nil
            if case .saved(_, let exact) = outcome { acknowledged = exact }
        }
        replayVisibleState()
    }

    private func replayVisibleState() {
        var envelope = SettingsEnvelope(schemaVersion: acknowledged.schemaVersion,
            revision: acknowledged.revision, config: acknowledged.config,
            preferences: acknowledged.preferences)
        for id in pendingOrder {
            guard let transform = pending[id] else { continue }
            switch transform {
            case .legacy(let delta):
                envelope = applying(delta, to: envelope)
            case .global(let delta):
                var values = envelope.preferences ?? PolicyPreferences()
                values.global.fields[delta.id] = delta.editedValue
                envelope = SettingsEnvelope(schemaVersion: envelope.schemaVersion,
                    revision: envelope.revision, config: envelope.config, preferences: values)
            }
        }
        displayed = envelope
    }

    private func applying(_ delta: LegacyPreferenceDelta,
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
        for item in delta.touchedCompatibilityBase {
            preferences.global.fields[item.id] = item.editedValue
        }
        return SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences)
    }
}
