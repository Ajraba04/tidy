import Foundation

/// Owns settings revisions and bytes at an explicit URL. No execution-policy authority.
public actor SettingsStore {
    private let url: URL
    private let io: any JournalPOSIXIO
    private var loadedEnvelope: SettingsEnvelope?
    private var loadedImage: SettingsDiskImage?
    private var recoveryReason: SettingsRecoveryReason?
    private var publicationFailure: SettingsPublicationFailure?
    private var issuedPreview: RollbackBinding?

    private struct RollbackBinding {
        let token: UUID
        let revision: UInt64
        let backup: SettingsFileImage
        let config: TidyConfig
        let preferences: PolicyPreferences?
    }

    public init(url: URL) { self.url = url; self.io = DarwinJournalIO() }
    internal init(url: URL, io: any JournalPOSIXIO) { self.url = url; self.io = io }
    internal func lastPublicationFailure() -> SettingsPublicationFailure? { publicationFailure }

    public func load() -> SettingsLoadResult {
        if let recoveryReason { return recovery(recoveryReason) }
        do {
            let image = try SettingsFiles.load(url)
            let result = try image.loaded()
            if loadedImage != image { issuedPreview = nil }
            loadedImage = image; loadedEnvelope = result.envelope
            return result
        } catch {
            let reason: SettingsRecoveryReason
            switch error {
            case SettingsDecoding.Failure.unsupportedSchema(let version): reason = .unsupportedSchema(version)
            case SettingsDecoding.Failure.oversized: reason = .oversized
            case SettingsFiles.Failure.unsafeLocation: reason = .unsafeLocation
            case SettingsFiles.Failure.unavailable, SettingsFiles.Failure.busy: reason = .unavailable
            default: reason = .malformed
            }
            // Transient lock contention cannot permanently poison a valid actor.
            if case SettingsFiles.Failure.busy = error { return recovery(reason) }
            latch(reason)
            return recovery(reason)
        }
    }

    public func update(expectedRevision: UInt64, change: SettingsChange) throws -> SettingsEnvelope {
        let current = try writable(expectedRevision: expectedRevision)
        var config = current.config
        var preferences = current.preferences
        switch change {
        case .transcriptAgeDays(let days):
            config.transcriptAgeThresholdDays = days
            preferences = updating(PolicyPreferences.project(legacy: current.config,
                                                             saved: preferences),
                                   id: "cleanup.transcriptDays",
                                   value: .integer(Int64(days)))
        case .legacyPreferences(let value):
            preferences = applyingLegacyDelta(from: current.config, to: value,
                                              preferences: preferences)
            config = value
        case .preferences(let value):
            preferences = value
            reverseProject(replacing: current.preferences?.global,
                           with: value.global,
                           into: &config)
        case .legacyPreferenceDelta(let delta):
            guard delta.baseRevision <= current.revision else {
                throw SettingsStoreError.staleRevision
            }
            for touched in delta.touchedCompatibilityBase {
                guard preferences?.global.fields[touched.id] == touched.baseValue else {
                    throw SettingsStoreError.staleRevision
                }
            }
            config = try applying(delta, to: current.config)
            preferences = applyingLegacyDelta(from: current.config, to: config,
                                              preferences: preferences)
        case .globalPreferenceDelta(let delta):
            guard delta.baseRevision <= current.revision else {
                throw SettingsStoreError.staleRevision
            }
            var replacement = preferences ?? PolicyPreferences()
            guard replacement.global.fields[delta.id] == delta.baseValue else {
                throw SettingsStoreError.staleRevision
            }
            let prior = replacement.global
            replacement.global.fields[delta.id] = delta.editedValue
            preferences = replacement
            reverseProject(replacing: prior, with: replacement.global, into: &config)
        }
        return try save(current: current, config: config, preferences: preferences)
    }

    public func previewRollback() throws -> SettingsRollbackPreview {
        guard recoveryReason == nil else { throw SettingsStoreError.readOnlyRecovery }
        guard let current = loadedEnvelope, let original = loadedImage else { throw SettingsStoreError.unavailable }
        let disk: SettingsDiskImage
        do { disk = try SettingsFiles.load(url); _ = try disk.loaded() }
        catch {
            if case SettingsFiles.Failure.busy = error { throw SettingsStoreError.unavailable }
            latch(.unavailable); throw SettingsStoreError.readOnlyRecovery
        }
        guard disk == original else { throw SettingsStoreError.changedExternally }
        guard let backup = disk.backup else { throw SettingsStoreError.unavailable }
        let frozen: SettingsEnvelope
        do {
            guard let decoded = try SettingsDecoding.load(backup.bytes).envelope else {
                throw SettingsStoreError.unavailable
            }
            frozen = decoded
        } catch { throw SettingsStoreError.unavailable }
        let token = UUID()
        issuedPreview = RollbackBinding(token: token, revision: current.revision, backup: backup,
                                        config: frozen.config, preferences: frozen.preferences)
        return SettingsRollbackPreview(config: frozen.config, preferences: frozen.preferences,
                                       identity: token)
    }

    public func rollback(expectedRevision: UInt64, preview: SettingsRollbackPreview) throws -> SettingsEnvelope {
        let current = try writable(expectedRevision: expectedRevision)
        guard let issued = issuedPreview, issued.token == preview.identity,
              issued.revision == current.revision, issued.config == preview.config,
              issued.preferences == preview.preferences else {
            throw SettingsStoreError.invalidChange
        }
        guard loadedImage?.backup == issued.backup else { throw SettingsStoreError.changedExternally }
        // save rechecks this captured backup identity and exact bytes under the stable lock.
        return try save(current: current, config: issued.config, preferences: issued.preferences)
    }

    private func writable(expectedRevision: UInt64) throws -> SettingsEnvelope {
        guard recoveryReason == nil else { throw SettingsStoreError.readOnlyRecovery }
        guard let current = loadedEnvelope, loadedImage != nil else { throw SettingsStoreError.unavailable }
        guard expectedRevision == current.revision else { throw SettingsStoreError.staleRevision }
        return current
    }

    private func save(current: SettingsEnvelope, config: TidyConfig,
                      preferences: PolicyPreferences?) throws -> SettingsEnvelope {
        let (revision, overflow) = current.revision.addingReportingOverflow(1)
        guard !overflow else { throw SettingsStoreError.revisionOverflow }
        let candidate = SettingsEnvelope(schemaVersion: 2, revision: revision, config: config,
                                         preferences: preferences)
        // Complete value/bounds/encoding checks precede even directory or lock creation.
        let bytes = try SettingsDecoding.encode(candidate)
        guard let expected = loadedImage else { throw SettingsStoreError.unavailable }
        let publication = SettingsPublication(url: url, io: io)
        do {
            let image = try publication.publish(expected: expected, envelope: candidate, bytes: bytes)
            loadedImage = image; loadedEnvelope = candidate; issuedPreview = nil
            publicationFailure = nil
            return candidate
        } catch {
            if let failure = publication.failure { publicationFailure = failure }
            if publication.recoveryRequired || (error as? SettingsStoreError) == .readOnlyRecovery {
                latch(.unavailable)
            }
            throw error
        }
    }

    private func latch(_ reason: SettingsRecoveryReason) {
        recoveryReason = reason; loadedEnvelope = nil; loadedImage = nil; issuedPreview = nil
    }

    private func recovery(_ reason: SettingsRecoveryReason) -> SettingsLoadResult {
        SettingsLoadResult(disposition: .recoveryReadOnly, envelope: nil, recoveryReason: reason)
    }

    private func updating(_ saved: PolicyPreferences?, id: String,
                          value: SettingValue) -> PolicyPreferences {
        var preferences = saved ?? PolicyPreferences()
        preferences.global.fields[SettingID(rawValue: id)] = value
        return preferences
    }

    private func applyingLegacyDelta(from base: TidyConfig, to edited: TidyConfig,
                                     preferences saved: PolicyPreferences?) -> PolicyPreferences? {
        var preferences: PolicyPreferences? = PolicyPreferences.project(legacy: base, saved: saved)
        func update(_ id: String, _ value: SettingValue) {
            preferences = updating(preferences, id: id, value: value)
        }
        if base.transcriptAgeThresholdDays != edited.transcriptAgeThresholdDays {
            update("cleanup.transcriptDays", .integer(Int64(edited.transcriptAgeThresholdDays)))
        }
        if base.staleNodeModulesThresholdDays != edited.staleNodeModulesThresholdDays {
            update("item.normal.extras.stale-node-modules.inactiveDays",
                   .integer(Int64(edited.staleNodeModulesThresholdDays)))
        }
        if base.keepCookieDomains != edited.keepCookieDomains {
            update("browsers.keepCookieDomains", .strings(edited.keepCookieDomains))
        }
        if base.allowRestartToReclaimSwap != edited.allowRestartToReclaimSwap {
            update("rescue.showAdvancedMemoryActions", .bool(edited.allowRestartToReclaimSwap))
        }
        return preferences
    }

    private func applying(_ delta: LegacyPreferenceDelta,
                          to current: TidyConfig) throws -> TidyConfig {
        var result = current
        func replace<T: Equatable>(_ base: T, _ edited: T, _ current: T,
                                    _ assign: (T) -> Void) throws {
            guard base != edited else { return }
            guard current == base else { throw SettingsStoreError.staleRevision }
            assign(edited)
        }
        try replace(delta.base.schemaVersion, delta.edited.schemaVersion, current.schemaVersion) {
            result.schemaVersion = $0
        }
        try replace(delta.base.hasCompletedOnboarding, delta.edited.hasCompletedOnboarding,
                    current.hasCompletedOnboarding) { result.hasCompletedOnboarding = $0 }
        try replace(delta.base.keepCookieDomains, delta.edited.keepCookieDomains,
                    current.keepCookieDomains) { result.keepCookieDomains = $0 }
        try replace(delta.base.simulatorsApprovedForDeletion,
                    delta.edited.simulatorsApprovedForDeletion,
                    current.simulatorsApprovedForDeletion) {
            result.simulatorsApprovedForDeletion = $0
        }
        try replace(delta.base.gitRoots, delta.edited.gitRoots, current.gitRoots) {
            result.gitRoots = $0
        }
        try replace(delta.base.staleNodeModulesThresholdDays,
                    delta.edited.staleNodeModulesThresholdDays,
                    current.staleNodeModulesThresholdDays) {
            result.staleNodeModulesThresholdDays = $0
        }
        try replace(delta.base.transcriptAgeThresholdDays,
                    delta.edited.transcriptAgeThresholdDays,
                    current.transcriptAgeThresholdDays) {
            result.transcriptAgeThresholdDays = $0
        }
        try replace(delta.base.appsApprovedForQuit, delta.edited.appsApprovedForQuit,
                    current.appsApprovedForQuit) { result.appsApprovedForQuit = $0 }
        try replace(delta.base.allowRestartToReclaimSwap,
                    delta.edited.allowRestartToReclaimSwap,
                    current.allowRestartToReclaimSwap) {
            result.allowRestartToReclaimSwap = $0
        }
        try replace(delta.base.presets, delta.edited.presets, current.presets) {
            result.presets = $0
        }
        return result
    }

    internal func isRecoveryRequired() -> Bool { recoveryReason != nil }

    private func reverseProject(replacing prior: PolicyValues?, with global: PolicyValues,
                                into config: inout TidyConfig) {
        let transcript = SettingID(rawValue: "cleanup.transcriptDays")
        if case .integer(let value)? = global.fields[transcript], let exact = Int(exactly: value) {
            config.transcriptAgeThresholdDays = exact
        } else if prior?.fields[transcript] != nil {
            config.transcriptAgeThresholdDays = 45
        }

        let stale = SettingID(rawValue: "item.normal.extras.stale-node-modules.inactiveDays")
        if case .integer(let value)? = global.fields[stale], let exact = Int(exactly: value) {
            config.staleNodeModulesThresholdDays = exact
        } else if prior?.fields[stale] != nil {
            config.staleNodeModulesThresholdDays = 60
        }

        let domains = SettingID(rawValue: "browsers.keepCookieDomains")
        if case .strings(let values)? = global.fields[domains] {
            config.keepCookieDomains = values
        } else if prior?.fields[domains] != nil {
            config.keepCookieDomains = []
        }

        let advanced = SettingID(rawValue: "rescue.showAdvancedMemoryActions")
        if case .bool(let visible)? = global.fields[advanced] {
            config.allowRestartToReclaimSwap = visible
        } else if prior?.fields[advanced] != nil {
            config.allowRestartToReclaimSwap = false
        }
    }
}
