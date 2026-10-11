import CryptoKit
import Foundation

/// Owns settings revisions and bytes at an explicit URL. No execution-policy authority.
public actor SettingsStore {
    private let url: URL
    private let io: any JournalPOSIXIO
    private var loadedEnvelope: SettingsEnvelope?
    private var loadedImage: SettingsDiskImage?
    private var recoveryReason: SettingsRecoveryReason?
    private var publicationFailure: SettingsPublicationFailure?
    private var issuedRollbackPreview: RollbackBinding?
    private var issuedImportAnalysis: ImportAnalysisBinding?
    private var issuedImportPreview: ImportPreviewBinding?
    /// Provenance generation for the one app-bootstrap settings snapshot.
    /// Every later load or state-changing request advances it; exhaustion denies.
    internal var schedulerBootstrapGeneration: UInt64 = 0
    internal var schedulerBootstrapGenerationExhausted = false
    internal var schedulerBootstrapReservation: UUID?

    private struct RollbackBinding {
        let token: UUID
        let revision: UInt64
        let backup: SettingsFileImage
        let config: TidyConfig
        let preferences: PolicyPreferences?
        let activeProfileID: UUID?
        let inertImports: [InertPortableSetting]
    }

    private struct ImportAnalysisBinding {
        let analysis: SettingsImportAnalysis
        let revision: UInt64
        let image: SettingsDiskImage
        let sourceDigest: String
    }

    private struct ImportPreviewBinding {
        let preview: SettingsImportPreview
        let revision: UInt64
        let image: SettingsDiskImage
    }

    public init(url: URL) { self.url = url; self.io = DarwinJournalIO() }
    internal init(url: URL, io: any JournalPOSIXIO) { self.url = url; self.io = io }
    internal func lastPublicationFailure() -> SettingsPublicationFailure? { publicationFailure }
    internal func schedulerBootstrapImageForIssue() -> SettingsDiskImage? { loadedImage }

    public func load() -> SettingsLoadResult {
        guard invalidateSchedulerBootstrapBeforeAccess() else {
            return recovery(.unavailable)
        }
        issuedImportAnalysis = nil; issuedImportPreview = nil
        if let recoveryReason { return recovery(recoveryReason) }
        do {
            let image = try SettingsFiles.load(url)
            let result = try image.loaded()
            if loadedImage != image { issuedRollbackPreview = nil }
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

    /// Revalidates an acknowledgement without adopting newer settings or
    /// invalidating any preview/bootstrap evidence. A caller retaining an old
    /// envelope must not authorize destructive optional-data retention from it.
    public func acknowledgesPersistedEnvelope(_ expected: SettingsEnvelope) -> Bool {
        guard expected.revision > 0, recoveryReason == nil,
              loadedEnvelope == expected, let image = loadedImage else { return false }
        do {
            // Compare the complete image, including identities, backup, lock
            // and store metadata. Equal decoded values alone are insufficient.
            return try SettingsFiles.load(url) == image
        } catch {
            // Observation failure is not a settings operation: preserve actor
            // state and let the caller retain optional data until refreshed.
            return false
        }
    }

    public func update(expectedRevision: UInt64, change: SettingsChange) throws -> SettingsEnvelope {
        guard invalidateSchedulerBootstrapBeforeAccess() else {
            throw SettingsStoreError.unavailable
        }
        let current = try writable(expectedRevision: expectedRevision)
        var config = current.config
        var preferences = current.preferences
        switch change {
        case .transcriptAgeDays(let days):
            var edited = config
            edited.transcriptAgeThresholdDays = days
            preferences = LegacyCompatibilityProjection.applyingLegacyEdit(
                from: config, to: edited, saved: preferences)
            config = edited
        case .legacyPreferences(let value):
            preferences = LegacyCompatibilityProjection.applyingLegacyEdit(
                from: current.config, to: value, saved: preferences)
            config = value
        case .preferences(let value):
            preferences = value
            config = LegacyCompatibilityProjection.reverseProject(config,
                replacing: current.preferences?.global, with: value.global)
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
            preferences = LegacyCompatibilityProjection.applyingLegacyEdit(
                from: current.config, to: config, saved: preferences)
        case .globalPreferenceDelta(let delta):
            guard delta.baseRevision <= current.revision else {
                throw SettingsStoreError.staleRevision
            }
            guard preferences?.global.fields[delta.id] == delta.baseValue else {
                throw SettingsStoreError.staleRevision
            }
            // Compare against the stored raw value before materializing the
            // first typed document. Preserve every existing legacy preference
            // when an unrelated global field causes that first materialization.
            var replacement = preferences ?? PolicyPreferences.project(legacy: current.config, saved: nil)
            let prior = replacement.global
            replacement.global.fields[delta.id] = delta.editedValue
            preferences = replacement
            config = LegacyCompatibilityProjection.reverseProject(config,
                replacing: prior, with: replacement.global)
        case .preferencesDocument(let delta):
            let applied: AppliedPreferencesDocument
            do { applied = try PreferencesDocumentProjection.apply(delta, to: current) }
            catch PreferencesDocumentProjectionError.stale {
                throw SettingsStoreError.staleRevision
            } catch { throw SettingsStoreError.invalidChange }
            return try save(current: current, config: applied.envelope.config,
                            preferences: applied.envelope.preferences,
                            activeProfileID: applied.envelope.activeProfileID,
                            replaceActiveProfile: true,
                            inertImports: applied.envelope.inertImports)
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
        issuedRollbackPreview = RollbackBinding(token: token, revision: current.revision,
            backup: backup, config: frozen.config, preferences: frozen.preferences,
            activeProfileID: frozen.activeProfileID, inertImports: frozen.inertImports)
        return SettingsRollbackPreview(config: frozen.config, preferences: frozen.preferences,
            activeProfileID: frozen.activeProfileID, inertImports: frozen.inertImports,
            identity: token)
    }

    public func rollback(expectedRevision: UInt64, preview: SettingsRollbackPreview) throws -> SettingsEnvelope {
        guard invalidateSchedulerBootstrapBeforeAccess() else {
            throw SettingsStoreError.unavailable
        }
        let current = try writable(expectedRevision: expectedRevision)
        guard let issued = issuedRollbackPreview, issued.token == preview.identity,
              issued.revision == current.revision, issued.config == preview.config,
              issued.preferences == preview.preferences,
              issued.activeProfileID == preview.activeProfileID,
              issued.inertImports == preview.inertImports else {
            throw SettingsStoreError.invalidChange
        }
        guard loadedImage?.backup == issued.backup else { throw SettingsStoreError.changedExternally }
        // save rechecks this captured backup identity and exact bytes under the stable lock.
        return try save(current: current, config: issued.config, preferences: issued.preferences,
                        activeProfileID: issued.activeProfileID, replaceActiveProfile: true,
                        inertImports: issued.inertImports)
    }

    private func writable(expectedRevision: UInt64) throws -> SettingsEnvelope {
        guard recoveryReason == nil else { throw SettingsStoreError.readOnlyRecovery }
        guard let current = loadedEnvelope, loadedImage != nil else { throw SettingsStoreError.unavailable }
        guard expectedRevision == current.revision else { throw SettingsStoreError.staleRevision }
        return current
    }

    private func save(current: SettingsEnvelope, config: TidyConfig,
                      preferences: PolicyPreferences?, activeProfileID: UUID? = nil,
                      replaceActiveProfile: Bool = false,
                      inertImports: [InertPortableSetting]? = nil) throws -> SettingsEnvelope {
        let (revision, overflow) = current.revision.addingReportingOverflow(1)
        guard !overflow else { throw SettingsStoreError.revisionOverflow }
        let candidate = SettingsEnvelope(schemaVersion: 2, revision: revision, config: config,
                                         preferences: preferences,
                                         activeProfileID: replaceActiveProfile ? activeProfileID : current.activeProfileID,
                                         inertImports: inertImports ?? current.inertImports)
        // Complete value/bounds/encoding checks precede even directory or lock creation.
        let bytes = try SettingsDecoding.encode(candidate)
        guard let expected = loadedImage else { throw SettingsStoreError.unavailable }
        let publication = SettingsPublication(url: url, io: io)
        do {
            let image = try publication.publish(expected: expected, envelope: candidate, bytes: bytes)
            loadedImage = image; loadedEnvelope = candidate; issuedRollbackPreview = nil
            issuedImportAnalysis = nil; issuedImportPreview = nil
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
        recoveryReason = reason; loadedEnvelope = nil; loadedImage = nil; issuedRollbackPreview = nil
        issuedImportAnalysis = nil; issuedImportPreview = nil
    }

    private func recovery(_ reason: SettingsRecoveryReason) -> SettingsLoadResult {
        SettingsLoadResult(disposition: .recoveryReadOnly, envelope: nil, recoveryReason: reason)
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

    public func analyzeImport(bytes: Data) throws -> SettingsImportAnalysis {
        issuedImportAnalysis = nil; issuedImportPreview = nil
        guard recoveryReason == nil else { throw SettingsStoreError.readOnlyRecovery }
        try refreshEmptyParentIdentityIfNeeded()
        guard let current = loadedEnvelope, let image = loadedImage else {
            throw SettingsStoreError.unavailable
        }
        try requireCurrentDisk(image)
        let parsed = try SettingsTransfer.analyze(bytes: bytes,
            current: .init(preferences: current.preferences ?? .init(),
                           inertImports: current.inertImports))
        let identity = UUID()
        let issued = SettingsTransfer.issuedAnalysis(parsed, identity: identity)
        issuedImportAnalysis = .init(analysis: issued, revision: current.revision,
                                     image: image, sourceDigest: SettingsFiles.digest(bytes))
        return issued
    }

    /// App bootstrap loads new defaults before the execution journal creates its
    /// sibling support directory. Accept only that content-free parent creation;
    /// every file/content/identity change remains subject to the exact image check.
    private func refreshEmptyParentIdentityIfNeeded() throws {
        guard let prior = loadedImage, prior.directory == nil,
              prior.config == nil, prior.backup == nil,
              prior.lock == nil, prior.metadata == nil else { return }
        let disk: SettingsDiskImage
        do {
            disk = try SettingsFiles.load(url)
            _ = try disk.loaded()
        } catch {
            if case SettingsFiles.Failure.busy = error { throw SettingsStoreError.unavailable }
            throw SettingsStoreError.changedExternally
        }
        guard disk.config == nil, disk.backup == nil,
              disk.lock == nil, disk.metadata == nil else {
            throw SettingsStoreError.changedExternally
        }
        loadedImage = disk
    }

    public func issueImportPreview(analysisID: SettingsImportAnalysisID,
                                   choices: [UUID: ProfileCollisionChoice]) throws
        -> SettingsImportPreview {
        guard let binding = issuedImportAnalysis,
              binding.analysis.analysisID == analysisID else {
            throw SettingsStoreError.invalidChange
        }
        issuedImportAnalysis = nil; issuedImportPreview = nil
        guard recoveryReason == nil, let current = loadedEnvelope,
              current.revision == binding.revision, loadedImage == binding.image else {
            throw SettingsStoreError.invalidChange
        }
        try requireCurrentDisk(binding.image)
        let frozenChoices = choices
        let resolved: ResolvedSettingsImport
        do { resolved = try SettingsTransfer.resolve(binding.analysis, choices: frozenChoices) }
        catch { throw SettingsStoreError.invalidChange }
        do { try SettingsTransfer.validatePersistedState(resolved.candidate) }
        catch { throw SettingsStoreError.invalidChange }
        let envelope = try importEnvelope(current: current, candidate: resolved.candidate)
        let candidateDigest = SettingsFiles.digest(try SettingsDecoding.encode(envelope))
        let preview = SettingsImportPreview(id: UUID(), analysisID: analysisID,
            rows: resolved.rows, collisions: binding.analysis.collisions,
            choices: frozenChoices, candidate: resolved.candidate,
            sourceDigest: binding.sourceDigest, candidateDigest: candidateDigest)
        issuedImportPreview = .init(preview: preview, revision: current.revision,
                                    image: binding.image)
        return preview
    }

    public func commitImport(expectedRevision: UInt64,
                             previewID: SettingsImportPreviewID) throws -> SettingsEnvelope {
        guard invalidateSchedulerBootstrapBeforeAccess() else {
            throw SettingsStoreError.unavailable
        }
        let binding = issuedImportPreview
        issuedImportPreview = nil; issuedImportAnalysis = nil
        guard let binding, binding.preview.id == previewID else {
            throw SettingsStoreError.invalidChange
        }
        let current = try writable(expectedRevision: expectedRevision)
        guard binding.revision == current.revision, loadedImage == binding.image else {
            throw SettingsStoreError.changedExternally
        }
        try requireCurrentDisk(binding.image)
        let expected = try importEnvelope(current: current, candidate: binding.preview.candidate)
        guard SettingsFiles.digest(try SettingsDecoding.encode(expected)) ==
              binding.preview.candidateDigest else { throw SettingsStoreError.invalidChange }
        return try save(current: current, config: expected.config,
                        preferences: binding.preview.candidate.preferences,
                        activeProfileID: current.activeProfileID, replaceActiveProfile: true,
                        inertImports: binding.preview.candidate.inertImports)
    }

    public func cancelImport(analysisID: SettingsImportAnalysisID) {
        if issuedImportAnalysis?.analysis.analysisID == analysisID { issuedImportAnalysis = nil }
    }

    public func cancelImport(previewID: SettingsImportPreviewID) {
        if issuedImportPreview?.preview.id == previewID { issuedImportPreview = nil }
    }

    private func importEnvelope(current: SettingsEnvelope,
                                candidate: PortableSettingsState) throws -> SettingsEnvelope {
        let (revision, overflow) = current.revision.addingReportingOverflow(1)
        guard !overflow else { throw SettingsStoreError.revisionOverflow }
        let config = LegacyCompatibilityProjection.reverseProject(current.config,
            replacing: current.preferences?.global, with: candidate.preferences.global)
        return SettingsEnvelope(schemaVersion: 2, revision: revision, config: config,
            preferences: candidate.preferences, activeProfileID: current.activeProfileID,
            inertImports: candidate.inertImports)
    }

    private func requireCurrentDisk(_ expected: SettingsDiskImage) throws {
        let disk: SettingsDiskImage
        do { disk = try SettingsFiles.load(url); _ = try disk.loaded() }
        catch {
            if case SettingsFiles.Failure.busy = error { throw SettingsStoreError.unavailable }
            latch(.unavailable); throw SettingsStoreError.readOnlyRecovery
        }
        guard disk == expected else { throw SettingsStoreError.changedExternally }
    }

    internal func isRecoveryRequired() -> Bool { recoveryReason != nil }

    /// Invalidates unconsumed bootstrap evidence. While initial scheduler
    /// installation owns its short reservation, competing access fails without
    /// stealing the reservation or wrapping the generation.
    internal func invalidateSchedulerBootstrapBeforeAccess() -> Bool {
        guard schedulerBootstrapReservation == nil,
              !schedulerBootstrapGenerationExhausted else { return false }
        let (next, overflow) = schedulerBootstrapGeneration.addingReportingOverflow(1)
        guard !overflow else {
            schedulerBootstrapGenerationExhausted = true
            return false
        }
        schedulerBootstrapGeneration = next
        return true
    }

    internal func forceSchedulerBootstrapGenerationForTesting(_ value: UInt64) {
        schedulerBootstrapGeneration = value
        schedulerBootstrapGenerationExhausted = false
        schedulerBootstrapReservation = nil
    }

    /// Reopens the settings path immediately before scheduler admission. The
    /// exact captured disk image must still exist. The sole exception mirrors
    /// `refreshEmptyParentIdentityIfNeeded`: journal bootstrap may create the
    /// previously absent parent while every settings artifact remains absent.
    internal func revalidateSchedulerBootstrapImage(_ expected: SettingsDiskImage) -> Bool {
        guard loadedImage == expected else { return false }
        let disk: SettingsDiskImage
        do {
            disk = try SettingsFiles.load(url)
            guard try disk.loaded().disposition == .newDefaults else { return false }
        } catch {
            return false
        }
        if disk == expected { return true }
        guard expected.directory == nil,
              expected.config == nil, expected.backup == nil,
              expected.lock == nil, expected.metadata == nil,
              disk.config == nil, disk.backup == nil,
              disk.lock == nil, disk.metadata == nil else { return false }
        loadedImage = disk
        return true
    }

}
