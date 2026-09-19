import Foundation
import Observation
import SwiftUI
import TidyCore
import UniformTypeIdentifiers

@MainActor func resolvedUIAdvancedSettings(_ policy: EffectivePolicy?) -> Bool {
    guard let policy, case .stored(.bool(let value))? =
        policy.fields[SettingID(rawValue: "ui.advancedSettings")]?.value else { return false }
    return value
}

enum SettingsRowAvailability: Equatable {
    case editable, notApplicable(String), unavailable(String), deferred(String)
}
enum SettingsSemanticTextRole: Equatable { case primary, secondary, warning }
enum SettingsLayoutMode: Equatable { case columns, stacked }
enum SettingsControlKind: Equatable { case toggle, integer, optionalInteger, choice, readOnly }

enum SettingsRegistryState: Equatable {
    case valid
    case invalid(String)
}

enum SettingsSurfaceEmptyState: Equatable {
    case content
    case noMatches
    case registryFailure(String)

    static func resolve(rows: [SettingsSurfaceRow],
                        registryState: SettingsRegistryState) -> Self {
        if case .invalid(let message) = registryState { return .registryFailure(message) }
        return rows.isEmpty ? .noMatches : .content
    }
}

enum SettingsVisualContract {
    static let titleRole: SettingsSemanticTextRole = .primary
    static let metadataRole: SettingsSemanticTextRole = .secondary
    static let unavailableRole: SettingsSemanticTextRole = .warning
    static func layoutMode(for size: DynamicTypeSize) -> SettingsLayoutMode {
        size.isAccessibilitySize ? .stacked : .columns
    }
}

enum SettingsSearch {
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }


    static func haystack(for row: SettingsSurfaceRow) -> [String] {
        [row.id.rawValue, row.title, row.help, row.consequence, row.defaultText,
         row.effectiveText, row.sourceText, row.ruleText, row.availabilityText]
    }
}

enum SettingsCopy {
    static func resolve(_ key: String, arguments: [CVarArg] = [],
                        bundle: Bundle = .main) -> String {
        let fallbackKey = "settings.copy.missing"
        let locale = Locale(identifier: "en_US_POSIX")
        let fallback = String(localized: String.LocalizationValue(fallbackKey),
                              bundle: bundle, locale: locale)
        let safeFallback = fallback == fallbackKey ? "Description unavailable." : fallback
        let resolved = String(localized: String.LocalizationValue(key),
                              bundle: bundle, locale: locale)
        guard resolved != key else { return safeFallback }
        guard !arguments.isEmpty else { return resolved }
        return String(format: resolved, locale: locale, arguments: arguments)
    }
}

struct SettingsSurfaceRow: Identifiable, Equatable {
    let setting: PresentedSetting
    let storedValue: SettingValue?
    let effectiveField: EffectiveField?
    let controlKind: SettingsControlKind
    let availability: SettingsRowAvailability
    let focusIndex: Int
    let title: String
    let help: String
    let consequence: String
    let defaultText: String
    let effectiveText: String
    let sourceText: String
    let ruleText: String
    let availabilityText: String
    let accessibilityLabel: String
    var id: SettingID { setting.definition.id }
    var accessibilityIdentifier: String {
        SettingsPresentationRegistry.accessibilityIdentifier(for: id)
    }
}

@MainActor
struct SettingsSurfaceModel {
    let store: AppConfigStore
    let bundle: Bundle
    init(store: AppConfigStore, bundle: Bundle = .main) {
        self.store = store; self.bundle = bundle
    }

    private(set) static var registryValidationCount = 0
    private(set) static var localizationResolutionCount = 0
    private static let presentedResult: Result<[PresentedSetting], Error> = {
        registryValidationCount += 1
        return Result { try SettingsPresentationRegistry.all(volumeIDs: []) }
    }()
    private static var presentedSettings: [PresentedSetting] {
        (try? presentedResult.get()) ?? []
    }

    private struct ResolvedCopy {
        let title: String
        let help: String
        let consequence: String
        let applicability: String
    }

    private struct CopyCacheKey: Hashable {
        let bundlePath: String
        let bundleIdentifier: String?
        let id: SettingID
    }

    private static var copyCache: [CopyCacheKey: ResolvedCopy] = [:]

    static var registryState: SettingsRegistryState {
        switch presentedResult {
        case .success: return .valid
        case .failure: return .invalid("The presentation registry did not validate.")
        }
    }

    static func fixtureRows(bundle: Bundle = .main) -> [SettingsSurfaceRow] {
        let settings = presentedSettings
        let stored = PolicyValues()
        var fields: [SettingID: EffectiveField] = [:]
        for setting in settings {
            fields[setting.definition.id] = EffectiveField(
                value: .stored(setting.definition.defaultValue), sources: [.builtIn],
                reason: .defaultValue)
        }
        let effectivePolicy = EffectivePolicy(fields: fields, allowedFeatures: [],
            walkWorkers: 1, readOnlyProcesses: 1, scanAdmission: .paused,
            manualBatchBytes: 0, manualBatchItems: 0, exclusions: [])
        return settings.enumerated().map { index, setting in
            let definition = setting.definition
            let kind = control(for: definition)
            let availability = availability(for: definition, control: kind)
            let copy = resolvedCopy(for: setting, bundle: bundle)
            let effective = effectivePolicy.fields[definition.id]
            let consequence = copy.consequence
            let applicability = copy.applicability + " Resolution: " +
                describe(definition.resolution) + ". Layers: " +
                describe(definition.layers) + "."
            return SettingsSurfaceRow(setting: setting,
                storedValue: stored.fields[definition.id], effectiveField: effective,
                controlKind: kind, availability: availability, focusIndex: index,
                title: copy.title, help: copy.help, consequence: consequence,
                defaultText: describe(definition.defaultValue),
                effectiveText: describe(effective?.value),
                sourceText: describe(effective?.sources), ruleText: describe(definition.rule),
                availabilityText: availabilityDescription(availability,
                    localized: applicability, effective: effective),
                accessibilityLabel: copy.title + ", " + definition.id.rawValue)
        }
    }

    func rows(query: String, showsAdvanced: Bool) -> [SettingsSurfaceRow] {
        rows(query: query, showsAdvanced: showsAdvanced, section: nil)
    }

    func rows(query: String, showsAdvanced: Bool,
              section: SettingsPresentationSection?) -> [SettingsSurfaceRow] {
        let needle = SettingsSearch.normalize(query)
        let preferences = store.preferences
        let effectivePolicy = store.effectivePolicy
        let visible = Self.presentedSettings.lazy.filter { setting in
            section == nil || setting.presentation.section == section
        }.map {
            project($0, preferences: preferences, effectivePolicy: effectivePolicy)
        }.filter { row in
            if !needle.isEmpty {
                return SettingsSearch.normalize(
                    SettingsSearch.haystack(for: row).joined(separator: " "))
                    .contains(needle)
            }
            return showsAdvanced || row.setting.presentation.tier == .basic
        }
        return visible.enumerated().map { index, row in
            SettingsSurfaceRow(setting: row.setting, storedValue: row.storedValue,
                effectiveField: row.effectiveField, controlKind: row.controlKind,
                availability: row.availability, focusIndex: index, title: row.title,
                help: row.help, consequence: row.consequence, defaultText: row.defaultText,
                effectiveText: row.effectiveText, sourceText: row.sourceText,
                ruleText: row.ruleText, availabilityText: row.availabilityText,
                accessibilityLabel: row.accessibilityLabel)
        }
    }

    func submit(id: SettingID, value: SettingValue?) -> SettingsSubmissionAdmission? {
        guard let definition = SettingsPresentationRegistry.renderedUniverse(volumeIDs: [])
            .first(where: { $0.id == id }),
              definition.resolution != .authority,
              definition.layers.contains(.global), control(for: definition) != .readOnly,
              SettingsPresentationRegistry.consumerSupport(for: definition).isConnected
        else { return nil }
        var candidate = store.preferences.global
        candidate.fields[id] = value
        guard (try? PolicyValidator.validateStructure(candidate, at: .global)) != nil else {
            return nil
        }
        return store.setGlobalPreference(id, to: value)
    }

    private func project(_ setting: PresentedSetting, preferences: PolicyPreferences,
                         effectivePolicy: EffectivePolicy?) -> SettingsSurfaceRow {
        let definition = setting.definition
        let kind = control(for: definition)
        let availability = Self.availability(for: definition, control: kind)
        let copy = Self.resolvedCopy(for: setting, bundle: bundle)
        let consequence = copy.consequence
        let applicability = copy.applicability
        let effective = effectivePolicy?.fields[definition.id]
        let availabilityText = availabilityDescription(availability,
            localized: applicability + " Resolution: " + describe(definition.resolution) +
                ". Layers: " + describe(definition.layers) + ".",
            effective: effective)
        return SettingsSurfaceRow(setting: setting,
            storedValue: preferences.global.fields[definition.id],
            effectiveField: effective, controlKind: kind, availability: availability,
            focusIndex: 0, title: copy.title, help: copy.help, consequence: consequence,
            defaultText: describe(definition.defaultValue),
            effectiveText: describe(effective?.value), sourceText: describe(effective?.sources),
            ruleText: describe(definition.rule), availabilityText: availabilityText,
            accessibilityLabel: copy.title + ", " + definition.id.rawValue)
    }

    private static func resolvedCopy(for setting: PresentedSetting,
                                     bundle: Bundle) -> ResolvedCopy {
        let key = CopyCacheKey(
            bundlePath: bundle.bundleURL.standardizedFileURL.path,
            bundleIdentifier: bundle.bundleIdentifier,
            id: setting.definition.id)
        if let cached = copyCache[key] { return cached }
        localizationResolutionCount += 4
        let arguments: [CVarArg] = dynamicIdentity(for: setting).map { [$0] } ?? []
        let consequenceArguments = arguments + [describe(setting.definition.effect)]
        let resolved = ResolvedCopy(
            title: SettingsCopy.resolve(setting.presentation.keys.title,
                                        arguments: arguments, bundle: bundle),
            help: SettingsCopy.resolve(setting.presentation.keys.help,
                                       arguments: arguments, bundle: bundle),
            consequence: SettingsCopy.resolve(setting.presentation.keys.consequence,
                                              arguments: consequenceArguments, bundle: bundle),
            applicability: SettingsCopy.resolve(setting.presentation.keys.applicability,
                                                arguments: arguments, bundle: bundle))
        copyCache[key] = resolved
        return resolved
    }

    private static func dynamicIdentity(for setting: PresentedSetting) -> String? {
        switch setting.presentation.pattern {
        case .exact: return nil
        case .catalogItem(let suffix):
            return String(setting.definition.id.rawValue.dropFirst("item.".count)
                .dropLast(("." + suffix).count))
        case .volumeOverride:
            return String(setting.definition.id.rawValue.dropFirst("headroom.volumeOverrides.".count))
        }
    }

    private static func availability(for definition: SettingDefinition,
                                     control: SettingsControlKind) -> SettingsRowAvailability {
        switch SettingsPresentationRegistry.consumerSupport(for: definition) {
        case .unavailable(let reason):
            return definition.resolution == .authority ? .deferred(reason) : .unavailable(reason)
        case .connected:
            if !definition.layers.contains(.global) {
                return .unavailable("This setting is not editable at the global layer.")
            }
            if control == .readOnly {
                return .unavailable("This setting needs a bounded editor that is not implemented.")
            }
            return .editable
        }
    }
}

private func control(for definition: SettingDefinition) -> SettingsControlKind {
    switch (definition.kind, definition.rule) {
    case (.bool, .boolean): return .toggle
    case (.integer, .integer): return .integer
    case (.optionalInteger, .optionalInteger), (.optionalInteger, .headroomTarget),
         (.optionalInteger, .headroomWarning), (.optionalInteger, .headroomClear),
         (.optionalInteger, .budgetHigh), (.optionalInteger, .budgetLow): return .optionalInteger
    case (.choice, .choices): return .choice
    default: return .readOnly
    }
}

private func describe(_ value: SettingValue?) -> String {
    guard let value else { return "Uses the inherited value" }
    switch value {
    case .bool(let value): return value ? "On" : "Off"
    case .integer(let value): return String(value)
    case .choice(let value): return value
    case .strings(let values): return values.isEmpty ? "None" : values.joined(separator: ", ")
    case .null: return "Automatic"
    case .volume(let value): return String(describing: value)
    }
}

private func describe(_ value: EffectiveValue?) -> String {
    guard let value else { return "Not currently projected" }
    switch value {
    case .stored(let stored): return describe(stored)
    case .bytes(let bytes): return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    case .unavailable(let reason): return "Not applicable: " + describe(reason)
    }
}

private func describe(_ sources: [FieldSource]?) -> String {
    guard let sources, !sources.isEmpty else { return "Built-in policy" }
    return sources.map {
        switch $0 {
        case .builtIn: return "Built-in"
        case .layer(let layer): return "Layer: " + layer.rawValue
        case .volume(let layer, let id): return "Volume: " + layer.rawValue + " " + id.uuidString
        case .immutable: return "Immutable protection"
        case .localAuthority: return "Local authority"
        }
    }.joined(separator: ", ")
}

private func describe(_ reason: FieldReason) -> String {
    switch reason {
    case .defaultValue: "default value"
    case .replaced: "replaced"
    case .denied: "denied"
    case .union: "union"
    case .strictestCap: "strictest cap"
    case .automatic: "automatic"
    case .inherited: "inherited"
    case .preset: "preset"
    case .cpuCeiling: "CPU ceiling"
    case .pressureCeiling: "pressure ceiling"
    case .capacityUnavailable: "capacity unavailable"
    case .invalidForVolume: "invalid for volume"
    case .unmatchedVolume: "unmatched volume"
    case .authorityUnavailable: "authority unavailable"
    case .protected: "protected"
    case .quarantine: "quarantine"
    case .notConfigured: "not configured"
    }
}

func describe(_ effect: AuthorityEffect) -> String {
    switch effect {
    case .none: "This change causes no plan invalidation."
    case .invalidate: "This change invalidates the current cleanup plan."
    case .consent: "This change requires separate consent; consent is not granted here."
    }
}

private func describe(_ resolution: ResolutionClass) -> String {
    switch resolution {
    case .preference: "preference"
    case .restriction: "restriction"
    case .authority: "authority"
    }
}

private func describe(_ layers: Set<PolicyLayer>) -> String {
    guard !layers.isEmpty else { return "none; local authority only" }
    return PolicyLayer.allCases.compactMap { layer in
        guard layers.contains(layer) else { return nil }
        switch layer {
        case .global: return "global"
        case .profile: return "profile"
        case .project: return "project"
        case .run: return "run"
        }
    }.joined(separator: ", ")
}

private func describe(_ rule: Rule) -> String {
    switch rule {
    case .boolean: return "On or off"
    case .integer(let low, let high): return "Whole number from \(low) through \(high)"
    case .optionalInteger(let low, let high): return "Automatic, or \(low) through \(high)"
    case .choices(let values): return "One of: " + values.joined(separator: ", ")
    case .identityList: return "Approved local identities"
    case .domains: return "Canonical domain names"
    case .projectID: return "Project identity or none"
    case .exclusions: return "Canonical absolute paths"
    case .pins: return "Unique project identities"
    case .headroomTarget, .headroomWarning, .headroomClear:
        return "Automatic, or 1 through 1024 GiB"
    case .volumeOverride: return "Per-volume headroom thresholds"
    case .budgetHigh: return "Automatic, or 1 through 1024 GiB"
    case .budgetLow: return "Automatic, or 0 through 1023 GiB"
    case .cards: return "Ordered dashboard card identities"
    case .ecosystemOrder: return "Ordered ecosystem identities"
    case .clock: return "24-hour time"
    case .quietEnd: return "24-hour time distinct from quiet start"
    }
}

private func availabilityDescription(_ availability: SettingsRowAvailability,
                                     localized: String, effective: EffectiveField?) -> String {
    let base: String
    switch availability {
    case .editable: base = localized
    case .notApplicable(let reason), .unavailable(let reason), .deferred(let reason):
        base = reason + " " + localized
    }
    if case .unavailable(let reason)? = effective?.value {
        return base + " Not applicable: " + describe(reason)
    }
    return base
}

enum SettingsWorkflowTab: String, CaseIterable, Equatable, Hashable {
    case profiles, transfer, reset
}

enum SettingsImportPresentationState: Equatable {
    case idle, analyzing, analysis(SettingsImportUISummary)
    case issuingPreview(SettingsImportUISummary), confirmation(SettingsImportPreview)
    case submitting(SettingsImportPreviewID), failed(String)
}

struct SettingsImportReviewDigests: Equatable {
    let source: String
    let candidate: String
}

enum SettingsImportFileReaderError: Error, Equatable {
    case unavailable
    case tooLarge
}

enum SettingsImportFileReader {
    static let maximumByteCount = 1_048_576

    static func read(_ url: URL) throws -> Data {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { throw SettingsImportFileReaderError.unavailable }
        defer { try? handle.close() }
        do {
            guard try handle.seekToEnd() <= UInt64(maximumByteCount) else {
                throw SettingsImportFileReaderError.tooLarge
            }
            try handle.seek(toOffset: 0)
            guard let data = try handle.read(upToCount: 1_048_577),
                  data.count <= maximumByteCount else {
                throw SettingsImportFileReaderError.tooLarge
            }
            return data
        } catch let error as SettingsImportFileReaderError {
            throw error
        } catch {
            throw SettingsImportFileReaderError.unavailable
        }
    }
}

enum SettingsWorkflowConfirmation: Equatable {
    case profile(SettingsProfileWorkflowPreview), reset(SettingsSelectiveResetPreview)
}

enum SettingsDeferredWorkflow: String, CaseIterable, Equatable, Hashable {
    case localReassociation, historyAndIndexClearing
}

enum SettingsWorkflowControlRole: String, CaseIterable, Equatable, Hashable {
    case profilesTab, transferTab, resetTab, createProfile, createFactory
    case cloneProfile, renameProfile, deleteProfile, activateProfile, deactivateProfile
    case profileNameEditor, profileValueEditor, confirmProfile, cancelProfile
    case chooseImport, issueImport, confirmImport, cancelImport, exportPortable
    case collisionKeepLocal, collisionReplace, collisionClone
    case resetGlobalField, resetProfileField, resetRestrictionOptIn
    case previewReset, confirmReset, cancelReset, localReassociation, historyAndIndexClearing
}

enum SettingsWorkflowControlAvailability: Equatable {
    case enabled
    case unavailable(reasonKey: String, label: String)
}

enum SettingsWorkflowImportPhase: CaseIterable, Equatable, Hashable {
    case idle, analyzing, analysis, issuing, confirmation, submitting, failed
}

enum SettingsWorkflowEditorTarget: Equatable, Hashable { case newProfile, profile(UUID) }

struct SettingsWorkflowProfileEditorContext: Equatable {
    let target: SettingsWorkflowEditorTarget
    let valueFieldIDs: [SettingID]
}

enum ProfileCollisionControlChoice: String, CaseIterable, Equatable, Hashable {
    case keepLocal, replace, clone
}

enum SettingsWorkflowControlIdentity: Equatable, Hashable {
    case profile(UUID), factory(String)
    case collision(UUID, ProfileCollisionControlChoice)
    case globalResetField(SettingID)
    case profileResetField(UUID, SettingID)
    case restrictionOptIn(UUID, SettingID)
    case profileName(SettingsWorkflowEditorTarget)
    case profileValue(SettingsWorkflowEditorTarget, SettingID)
}

struct SettingsWorkflowControlContext: Equatable {
    let profileIDs: [UUID]
    let activeProfileID: UUID?
    let profileEditor: SettingsWorkflowProfileEditorContext?
    let importPhase: SettingsWorkflowImportPhase
    let collisions: [ProfileImportCollision]
    let hasCompleteCollisionChoices: Bool
    let hasPreparedProfile: Bool
    let resetGlobalFieldIDs: [SettingID]
    let resetProfileID: UUID?
    let resetProfileFieldIDs: [SettingID]
    let ownedRestrictionFieldIDs: Set<SettingID>
    let hasResetSelection: Bool
    let hasPreparedReset: Bool
}

struct SettingsWorkflowControlDescriptor: Identifiable, Equatable {
    let id: String
    let role: SettingsWorkflowControlRole
    let titleKey: String
    let label: String
    let availability: SettingsWorkflowControlAvailability
    let focusOrder: Int
    let identity: SettingsWorkflowControlIdentity?

    var accessibilityHint: String {
        if case .unavailable(_, let label) = availability { return label }
        return ""
    }
}

enum SettingsWorkflowPresentationError: Error, Equatable {
    case tooManyProfiles, duplicateCollision(UUID), tooManyCollisions
    case tooManyEditorFields, tooManyResetFields, tooManyControls
    case invalidActiveProfile(UUID), invalidEditorTarget(UUID)
    case invalidEditorField(SettingID), profileRequired, missingResetProfile(UUID)
    case invalidResetField(SettingID), invalidRestrictionOptIn(SettingID)
}

struct SettingsImportOutcomePresentation: Identifiable, Equatable {
    let outcome: SettingsImportOutcome
    let titleKey: String
    let explanationKey: String
    let count: Int
    var id: String { outcome.rawValue }
}

enum SettingsWorkflowPresentation {
    static let importOutcomeOrder: [SettingsImportOutcome] = [
        .committable, .collision, .inert, .redacted, .requiresLocalReassociation,
        .rejectedAuthority, .rejectedProtectionWeakening, .rejectedInvalid,
        .rejectedNonPortable, .rejectedUnsupportedLayer
    ]
    static let maximumControlDescriptors = 3_423

    static var profileEditorFieldIDs: [SettingID] {
        unique(SettingsPresentationRegistry.renderedUniverse(volumeIDs: [])
            .filter(isEditableProfileField)
            .map(\.id)).sorted { $0.rawValue < $1.rawValue }
    }

    static func isEditableProfileField(_ definition: SettingDefinition) -> Bool {
        definition.layers.contains(.profile) &&
            (definition.resolution == .preference || definition.resolution == .restriction) &&
            definition.kind != .optionalProjectID && definition.kind != .volumeOverride
    }

    static func canPreviewReset(selectedProfileFieldIDs: Set<SettingID>,
                                ownedRestrictionFieldIDs: Set<SettingID>,
                                optedInRestrictionIDs: Set<SettingID>,
                                hasOtherSelection: Bool) -> Bool {
        let selectedRestrictions = selectedProfileFieldIDs.intersection(
            ownedRestrictionFieldIDs)
        return (hasOtherSelection || !selectedProfileFieldIDs.isEmpty) &&
            selectedRestrictions.isSubset(of: optedInRestrictionIDs)
    }

    static func importOutcomes(_ summary: SettingsImportUISummary)
        -> [SettingsImportOutcomePresentation] {
        importOutcomeOrder.map { outcome in
            .init(outcome: outcome,
                  titleKey: "settings.import.outcome.\(outcome.rawValue).title",
                  explanationKey: "settings.import.outcome.\(outcome.rawValue).explanation",
                  count: summary.rows.lazy.filter { $0.outcome == outcome }.count)
        }
    }

    static func canIssuePreview(summary: SettingsImportUISummary,
                                choices: [UUID: ProfileCollisionChoice]) -> Bool {
        Set(summary.collisions.map(\.profileID)) == Set(choices.keys)
    }

    static func accessibilityID(for outcome: SettingsImportOutcome) -> String {
        "settings.import.outcome." + outcome.rawValue
    }

    static func deferredExplanationKey(_ workflow: SettingsDeferredWorkflow) -> String {
        "settings.deferred.\(workflow.rawValue).explanation"
    }

    static func deferredExplanation(_ workflow: SettingsDeferredWorkflow,
                                    bundle: Bundle) -> String {
        SettingsCopy.resolve(deferredExplanationKey(workflow), bundle: bundle)
    }

    static func controls(context: SettingsWorkflowControlContext,
                         localize: (String) -> String) throws
        -> [SettingsWorkflowControlDescriptor] {
        let profiles = unique(context.profileIDs).sorted { $0.uuidString < $1.uuidString }
        guard profiles.count <= SessionProfiles.maximumCount else { throw SettingsWorkflowPresentationError.tooManyProfiles }
        if let active = context.activeProfileID, !profiles.contains(active) {
            throw SettingsWorkflowPresentationError.invalidActiveProfile(active)
        }
        guard context.collisions.count <= SessionProfiles.maximumCount else {
            throw SettingsWorkflowPresentationError.tooManyCollisions
        }
        var collisionIDs = Set<UUID>()
        for collision in context.collisions {
            guard collisionIDs.insert(collision.profileID).inserted else {
                throw SettingsWorkflowPresentationError.duplicateCollision(collision.profileID)
            }
            guard profiles.contains(collision.profileID) else {
                throw SettingsWorkflowPresentationError.missingResetProfile(collision.profileID)
            }
        }
        let collisions = context.collisions.sorted { $0.profileID.uuidString < $1.profileID.uuidString }
        let editorIDs = unique(context.profileEditor?.valueFieldIDs ?? [])
            .sorted { $0.rawValue < $1.rawValue }
        guard editorIDs.count <= 1_000 else { throw SettingsWorkflowPresentationError.tooManyEditorFields }
        if let editor = context.profileEditor {
            if case .profile(let id) = editor.target, !profiles.contains(id) {
                throw SettingsWorkflowPresentationError.invalidEditorTarget(id)
            }
            for id in editorIDs {
                guard validProfileField(id) else {
                    throw SettingsWorkflowPresentationError.invalidEditorField(id)
                }
            }
        }
        let globalReset = unique(context.resetGlobalFieldIDs).sorted { $0.rawValue < $1.rawValue }
        let profileReset = unique(context.resetProfileFieldIDs).sorted { $0.rawValue < $1.rawValue }
        guard Set(globalReset).union(profileReset).count <= 1_000 else {
            throw SettingsWorkflowPresentationError.tooManyResetFields
        }
        if !profileReset.isEmpty && context.resetProfileID == nil {
            throw SettingsWorkflowPresentationError.profileRequired
        }
        if let resetProfileID = context.resetProfileID, !profiles.contains(resetProfileID) {
            throw SettingsWorkflowPresentationError.missingResetProfile(resetProfileID)
        }
        for id in globalReset {
            guard validGlobalReset(id) else { throw SettingsWorkflowPresentationError.invalidResetField(id) }
        }
        for id in profileReset {
            guard validProfileField(id) else { throw SettingsWorkflowPresentationError.invalidResetField(id) }
        }
        for id in context.ownedRestrictionFieldIDs {
            guard profileReset.contains(id),
                  definition(for: id)?.resolution == .restriction else {
                throw SettingsWorkflowPresentationError.invalidRestrictionOptIn(id)
            }
        }

        var result: [SettingsWorkflowControlDescriptor] = []
        func unavailable(_ key: String) -> SettingsWorkflowControlAvailability {
            .unavailable(reasonKey: key, label: localize(key))
        }
        func availability(_ enabled: Bool, _ key: String) -> SettingsWorkflowControlAvailability {
            enabled ? .enabled : unavailable(key)
        }
        func append(_ id: String, _ role: SettingsWorkflowControlRole, _ key: String,
                    _ availability: SettingsWorkflowControlAvailability,
                    _ identity: SettingsWorkflowControlIdentity? = nil,
                    identities: [String] = []) throws {
            let label = ([localize(key)] + identities).joined(separator: " — ")
            result.append(.init(id: id, role: role, titleKey: key, label: label,
                availability: availability, focusOrder: result.count, identity: identity))
            guard result.count <= maximumControlDescriptors else {
                throw SettingsWorkflowPresentationError.tooManyControls
            }
        }
        let profileReady = !context.hasPreparedProfile
        let profileAvailability = availability(profileReady,
            "settings.control.unavailable.issuedPreview")
        try append("settings.workflow.tab.profiles", .profilesTab,
                   "settings.workflow.tab.profiles", .enabled)
        try append("settings.workflow.tab.transfer", .transferTab,
                   "settings.workflow.tab.transfer", .enabled)
        try append("settings.workflow.tab.reset", .resetTab,
                   "settings.workflow.tab.reset", .enabled)
        try append("settings.profile.action.create", .createProfile,
                   "settings.profile.create", .enabled)
        for key in SessionProfiles.factoryKeys {
            try append("settings.profile.factory." + key, .createFactory,
                       "settings.profile.factory." + key, profileAvailability,
                       .factory(key), identities: [key])
        }
        for id in profiles {
            for role in [SettingsWorkflowControlRole.cloneProfile, .renameProfile,
                         .deleteProfile, .activateProfile, .deactivateProfile] {
                var value = profileAvailability
                if profileReady && role == .activateProfile && context.activeProfileID == id {
                    value = unavailable("settings.control.unavailable.activeProfile")
                } else if profileReady && role == .deactivateProfile && context.activeProfileID != id {
                    value = unavailable("settings.control.unavailable.noProfile")
                }
                let key = "settings.profile." + role.rawValue.replacingOccurrences(of: "Profile", with: "")
                try append("settings.profile.action.\(role.rawValue).\(id.uuidString)", role,
                           key, value, .profile(id), identities: [id.uuidString])
            }
        }
        if let editor = context.profileEditor {
            let target = targetText(editor.target)
            try append("settings.profile.editor.name." + target, .profileNameEditor,
                       "settings.profile.editor.name", profileAvailability,
                       .profileName(editor.target), identities: [target])
            for id in editorIDs {
                try append("settings.profile.editor.value.\(target).\(id.rawValue)",
                           .profileValueEditor, "settings.profile.editor.value", profileAvailability,
                           .profileValue(editor.target, id), identities: [target, id.rawValue])
            }
        }
        try append("settings.profile.confirm", .confirmProfile, "settings.profile.confirm",
                   availability(context.hasPreparedProfile,
                                "settings.control.unavailable.issuedPreview"))
        try append("settings.profile.cancel", .cancelProfile, "settings.profile.cancel",
                   availability(context.hasPreparedProfile,
                                "settings.control.unavailable.issuedPreview"))
        try append("settings.import.choose", .chooseImport, "settings.import.choose", .enabled)
        try append("settings.import.issue", .issueImport, "settings.import.issue",
                   availability(context.importPhase == .analysis &&
                                context.hasCompleteCollisionChoices,
                                "settings.control.unavailable.importAnalysis"))
        try append("settings.import.confirm", .confirmImport, "settings.import.confirm",
                   availability(context.importPhase == .confirmation,
                                "settings.control.unavailable.issuedPreview"))
        try append("settings.import.cancel", .cancelImport, "settings.import.cancel",
                   availability([.analyzing, .analysis, .issuing, .confirmation]
                    .contains(context.importPhase), "settings.control.unavailable.importAnalysis"))
        try append("settings.export.choose", .exportPortable, "settings.export.choose", .enabled)
        for collision in collisions {
            for choice in ProfileCollisionControlChoice.allCases {
                let role: SettingsWorkflowControlRole = choice == .keepLocal ? .collisionKeepLocal :
                    (choice == .replace ? .collisionReplace : .collisionClone)
                try append("settings.import.collision.\(collision.profileID.uuidString).\(choice.rawValue)",
                    role, "settings.import.collision." + choice.rawValue,
                    availability(context.importPhase == .analysis,
                                 "settings.control.unavailable.importAnalysis"),
                    .collision(collision.profileID, choice), identities: [choice.rawValue,
                        collision.profileID.uuidString, collision.localName, collision.importedName])
            }
        }
        let resetAvailability = availability(!context.hasPreparedReset,
            "settings.control.unavailable.resetPreview")
        for id in globalReset {
            try append("settings.reset.global." + id.rawValue, .resetGlobalField,
                       "settings.reset.field.global", resetAvailability,
                       .globalResetField(id), identities: [id.rawValue])
        }
        if let resetProfileID = context.resetProfileID {
            for id in profileReset {
                try append("settings.reset.profile.\(resetProfileID.uuidString).\(id.rawValue)",
                           .resetProfileField, "settings.reset.field.profile", resetAvailability,
                           .profileResetField(resetProfileID, id),
                           identities: [resetProfileID.uuidString, id.rawValue])
            }
            for id in context.ownedRestrictionFieldIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
                try append("settings.reset.restrictionOptIn.\(resetProfileID.uuidString).\(id.rawValue)",
                           .resetRestrictionOptIn, "settings.reset.ownedRestrictionOptIn",
                           resetAvailability, .restrictionOptIn(resetProfileID, id),
                           identities: [resetProfileID.uuidString, id.rawValue])
            }
        }
        try append("settings.reset.preview", .previewReset, "settings.reset.preview",
                   availability(context.hasResetSelection,
                                "settings.control.unavailable.resetSelection"))
        try append("settings.reset.confirm", .confirmReset, "settings.reset.confirm",
                   availability(context.hasPreparedReset,
                                "settings.control.unavailable.resetPreview"))
        try append("settings.reset.cancel", .cancelReset, "settings.reset.cancel",
                   availability(context.hasPreparedReset,
                                "settings.control.unavailable.resetPreview"))
        try append("settings.deferred.localReassociation", .localReassociation,
                   "settings.deferred.localReassociation.title",
                   unavailable("settings.control.unavailable.deferred"))
        try append("settings.deferred.historyAndIndexClearing", .historyAndIndexClearing,
                   "settings.deferred.historyAndIndexClearing.title",
                   unavailable("settings.control.unavailable.deferred"))

        if context.importPhase == .submitting {
            result = result.enumerated().map { index, descriptor in
                let deferred = descriptor.role == .localReassociation ||
                    descriptor.role == .historyAndIndexClearing
                return .init(id: descriptor.id, role: descriptor.role,
                    titleKey: descriptor.titleKey, label: descriptor.label,
                    availability: deferred ? descriptor.availability :
                        unavailable("settings.control.unavailable.submitting"),
                    focusOrder: index, identity: descriptor.identity)
            }
        }
        return result
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
    private static func validProfileField(_ id: SettingID) -> Bool {
        guard let definition = definition(for: id) else { return false }
        return isEditableProfileField(definition)
    }
    private static func validGlobalReset(_ id: SettingID) -> Bool {
        guard let definition = definition(for: id) else { return false }
        return definition.layers.contains(.global) && definition.resolution == .preference
    }
    private static func definition(for id: SettingID) -> SettingDefinition? {
        SettingsPresentationRegistry.renderedUniverse(volumeIDs: [])
            .first(where: { $0.id == id })
    }
    private static func targetText(_ target: SettingsWorkflowEditorTarget) -> String {
        switch target { case .newProfile: return "new"; case .profile(let id): return id.uuidString }
    }
}

struct SettingsWorkflowImportOperations {
    let analyze: @MainActor (Data) async throws -> SettingsImportUISummary
    let issue: @MainActor (SettingsImportAnalysisID,
                           [UUID: ProfileCollisionChoice]) async throws -> SettingsImportPreview
    let cancelAnalysis: @MainActor (SettingsImportAnalysisID) async -> Void
    let cancelPreview: @MainActor (SettingsImportPreviewID) async -> Void
    let submit: @MainActor (SettingsImportPreview) -> SettingsSubmissionAdmission

    @MainActor static func live(store: AppConfigStore) -> Self {
        .init(analyze: { try await store.analyzeImportSummary(bytes: $0) },
              issue: { try await store.issueImportPreview(analysisID: $0, choices: $1) },
              cancelAnalysis: { await store.cancelImport(analysisID: $0) },
              cancelPreview: { await store.cancelImport(previewID: $0) },
              submit: { store.commitImport($0) })
    }
}

@Observable @MainActor final class SettingsWorkflowController {
    let store: AppConfigStore
    let bundle: Bundle
    private(set) var importState: SettingsImportPresentationState = .idle
    private(set) var collisionChoices: [UUID: ProfileCollisionChoice] = [:]
    private(set) var importReviewSummary: SettingsImportUISummary?
    private(set) var importReviewDigests: SettingsImportReviewDigests?
    private(set) var confirmation: SettingsWorkflowConfirmation?
    private(set) var lastExportByteCount: Int?
    private var operationGeneration: UInt64 = 0
    private let importOperations: SettingsWorkflowImportOperations

    init(store: AppConfigStore, bundle: Bundle = .main) {
        self.store = store; self.bundle = bundle
        self.importOperations = .live(store: store)
    }
    internal init(testing store: AppConfigStore,
                  importOperations: SettingsWorkflowImportOperations,
                  bundle: Bundle) {
        self.store = store; self.importOperations = importOperations; self.bundle = bundle
    }

    func prepareProfile(_ request: SettingsProfileWorkflowRequest) throws {
        confirmation = .profile(try store.previewProfileWorkflow(request))
    }
    func prepareReset(_ request: SettingsSelectiveResetRequest) throws {
        confirmation = .reset(try store.previewSelectiveReset(request))
    }
    func cancelConfirmation() { confirmation = nil }
    func confirmPreparedChange() -> SettingsSubmissionAdmission? {
        guard let prepared = confirmation else { return nil }
        let admission: SettingsSubmissionAdmission
        switch prepared {
        case .profile(let preview): admission = store.commitProfileWorkflow(preview)
        case .reset(let preview): admission = store.commitSelectiveReset(preview)
        }
        confirmation = nil
        return admission
    }
    func chooseCollision(profileID: UUID, choice: ProfileCollisionChoice) {
        guard case .analysis(let summary) = importState,
              summary.collisions.contains(where: { $0.profileID == profileID }) else { return }
        collisionChoices[profileID] = choice
    }
    func makeExportDocument() throws -> PortableSettingsDocument {
        let data = try store.exportPortableSettings(); lastExportByteCount = data.count
        return .init(data: data)
    }
    private var failureCopy: String { SettingsCopy.resolve("settings.import.failure", bundle: bundle) }
    private var importPhase: SettingsWorkflowImportPhase {
        switch importState {
        case .idle: .idle; case .analyzing: .analyzing; case .analysis: .analysis
        case .issuingPreview: .issuing; case .confirmation: .confirmation
        case .submitting: .submitting; case .failed: .failed
        }
    }

// SETTINGS_WORKFLOW_TASK_BOUNDARIES_BEGIN
// SETTINGS_WORKFLOW_TASK_BEGIN_beginImportSelection
    @discardableResult func beginImportSelection(bytes: Data) -> Task<Void, Never> {
        let submitting: Bool
        switch importState { case .submitting: submitting = true; default: submitting = false }
        var priorAnalysis: SettingsImportAnalysisID?
        var priorPreview: SettingsImportPreviewID?
        if !submitting {
            switch importState {
            case .analysis(let value), .issuingPreview(let value): priorAnalysis = value.analysisID
            case .confirmation(let value): priorPreview = value.id
            default: break
            }
            operationGeneration &+= 1
            importState = .analyzing; collisionChoices = [:]
            importReviewSummary = nil; importReviewDigests = nil
        }
        let generation = operationGeneration
        return Task { @MainActor [self] in
            guard !submitting else { return }
            if let priorAnalysis { await importOperations.cancelAnalysis(priorAnalysis) }
            if let priorPreview { await importOperations.cancelPreview(priorPreview) }
            guard generation == operationGeneration else { return }
            do {
                let summary = try await importOperations.analyze(bytes)
                guard generation == operationGeneration else {
                    await importOperations.cancelAnalysis(summary.analysisID); return
                }
                importReviewSummary = summary; importState = .analysis(summary)
            } catch {
                guard generation == operationGeneration else { return }
                importState = .failed(failureCopy)
            }
        }
    }
// SETTINGS_WORKFLOW_TASK_END_beginImportSelection
// SETTINGS_WORKFLOW_TASK_BEGIN_beginImportPreviewIssuance
    @discardableResult func beginImportPreviewIssuance() -> Task<Void, Never> {
        let submitting: Bool
        switch importState { case .submitting: submitting = true; default: submitting = false }
        let summary: SettingsImportUISummary?
        if !submitting, case .analysis(let value) = importState,
           SettingsWorkflowPresentation.canIssuePreview(summary: value, choices: collisionChoices) {
            summary = value; operationGeneration &+= 1; importState = .issuingPreview(value)
        } else { summary = nil }
        let generation = operationGeneration
        let choices = collisionChoices
        return Task { @MainActor [self] in
            guard !submitting, let summary, generation == operationGeneration else { return }
            do {
                let preview = try await importOperations.issue(summary.analysisID, choices)
                guard generation == operationGeneration else {
                    await importOperations.cancelPreview(preview.id); return
                }
                importReviewDigests = .init(source: preview.sourceDigest,
                                            candidate: preview.candidateDigest)
                importState = .confirmation(preview)
            } catch {
                await importOperations.cancelAnalysis(summary.analysisID)
                guard generation == operationGeneration else { return }
                collisionChoices = [:]; importState = .failed(failureCopy)
                importReviewSummary = nil; importReviewDigests = nil
            }
        }
    }
// SETTINGS_WORKFLOW_TASK_END_beginImportPreviewIssuance
// SETTINGS_WORKFLOW_TASK_BEGIN_beginImportConfirmation
    @discardableResult func beginImportConfirmation() -> Task<Void, Never> {
        let submitting: Bool
        switch importState { case .submitting: submitting = true; default: submitting = false }
        let preview: SettingsImportPreview?
        if !submitting, case .confirmation(let value) = importState {
            preview = value; operationGeneration &+= 1; importState = .submitting(value.id)
        } else { preview = nil }
        let generation = operationGeneration
        return Task { @MainActor [self] in
            guard !submitting, let preview, generation == operationGeneration else { return }
            switch importOperations.submit(preview) {
            case .rejected:
                await importOperations.cancelPreview(preview.id)
                guard generation == operationGeneration else { return }
                collisionChoices = [:]; importState = .failed(failureCopy)
                importReviewSummary = nil; importReviewDigests = nil
            case .accepted(_, let completion):
                let outcome = await completion.value
                guard generation == operationGeneration else { return }
                collisionChoices = [:]
                if case .saved = outcome { importState = .idle }
                else { importState = .failed(failureCopy) }
                importReviewSummary = nil; importReviewDigests = nil
            }
        }
    }
// SETTINGS_WORKFLOW_TASK_END_beginImportConfirmation
// SETTINGS_WORKFLOW_TASK_BEGIN_beginImportCancellation
    @discardableResult func beginImportCancellation() -> Task<Void, Never> {
        let submitting: Bool
        switch importState { case .submitting: submitting = true; default: submitting = false }
        var analysisID: SettingsImportAnalysisID?
        var previewID: SettingsImportPreviewID?
        if !submitting {
            switch importState {
            case .analysis(let value), .issuingPreview(let value): analysisID = value.analysisID
            case .confirmation(let value): previewID = value.id
            default: break
            }
            operationGeneration &+= 1; importState = .idle; collisionChoices = [:]
            importReviewSummary = nil; importReviewDigests = nil
        }
        let generation = operationGeneration
        return Task { @MainActor [self] in
            guard !submitting else { return }
            _ = generation
            if let analysisID { await importOperations.cancelAnalysis(analysisID) }
            if let previewID { await importOperations.cancelPreview(previewID) }
        }
    }
// SETTINGS_WORKFLOW_TASK_END_beginImportCancellation
// SETTINGS_WORKFLOW_TASK_BOUNDARIES_END
}

struct PortableSettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsWorkflowSurface: View {
    let store: AppConfigStore
    let bundle: Bundle
    @State private var controller: SettingsWorkflowController
    @State private var selectedTab: SettingsWorkflowTab
    @State private var showsImporter = false
    @State private var showsExporter = false
    @State private var exportDocument: PortableSettingsDocument?
    @State private var resetGlobalIDs = Set<SettingID>()
    @State private var resetProfileID: UUID?
    @State private var resetProfileIDs = Set<SettingID>()
    @State private var resetOwnedRestrictionIDs = Set<SettingID>()
    @State private var profileEditorTarget: SettingsWorkflowEditorTarget?
    @State private var profileEditorFieldIDs = [SettingID]()
    @State private var profileNameDraft = ""
    @State private var profileValuesDraft = PolicyValues()
    @State private var workflowMessage = ""

    init(store: AppConfigStore, bundle: Bundle = .main,
         initialTab: SettingsWorkflowTab = .profiles) {
        self.store = store; self.bundle = bundle
        _controller = State(initialValue: SettingsWorkflowController(store: store, bundle: bundle))
        _selectedTab = State(initialValue: initialTab)
        _resetProfileID = State(initialValue: store.profiles.first?.id)
    }

    var body: some View {
        let projection: Result<[SettingsWorkflowControlDescriptor], Error> = Result {
            try SettingsWorkflowPresentation.controls(context: controlContext,
                localize: { SettingsCopy.resolve($0, bundle: bundle) })
        }
        return Group {
            switch projection {
            case .success(let descriptorControls):
                workflowContent(descriptorControls)
            case .failure:
                Text(SettingsCopy.resolve("settings.copy.missing", bundle: bundle))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.workflow.projectionFailure")
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? SettingsImportFileReader.read(url) else {
                workflowMessage = SettingsCopy.resolve("settings.import.failure", bundle: bundle)
                return
            }
            controller.beginImportSelection(bytes: data)
        }
        .fileExporter(isPresented: $showsExporter, document: exportDocument,
                      contentType: .json, defaultFilename: "tidy-settings") { result in
            if case .failure = result {
                workflowMessage = SettingsCopy.resolve("settings.export.failure", bundle: bundle)
            }
            exportDocument = nil
        }
    }

    private func workflowContent(
        _ descriptorControls: [SettingsWorkflowControlDescriptor]
    ) -> some View {
        let tabHint = descriptorControls.lazy.filter {
            [.profilesTab, .transferTab, .resetTab].contains($0.role)
        }.map(\.accessibilityHint).first(where: { !$0.isEmpty }) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(SettingsCopy.resolve("settings.workflow.tab.profiles", bundle: bundle) + ", " +
                 SettingsCopy.resolve("settings.workflow.tab.transfer", bundle: bundle) + ", " +
                 SettingsCopy.resolve("settings.workflow.tab.reset", bundle: bundle)).font(.title2)
            Text(SettingsCopy.resolve("settings.workflow.revision", bundle: bundle) +
                 " \(store.settingsRevision)").foregroundStyle(.secondary)
            Picker("Workflow", selection: $selectedTab) {
                ForEach(SettingsWorkflowTab.allCases, id: \.self) { tab in
                    let role: SettingsWorkflowControlRole = tab == .profiles ? .profilesTab :
                        (tab == .transfer ? .transferTab : .resetTab)
                    let descriptor = descriptorControls.first { $0.role == role }
                    Text(descriptor?.label ?? SettingsCopy.resolve(
                        "settings.workflow.tab." + tab.rawValue, bundle: bundle)).tag(tab)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("settings.workflow.tabs")
                .accessibilityHint(tabHint)
                .disabled(descriptorControls.filter {
                    [.profilesTab, .transferTab, .resetTab].contains($0.role)
                }.contains { $0.availability != .enabled })
            if !workflowMessage.isEmpty { Text(workflowMessage).foregroundStyle(.secondary) }
            if case .failed(let message) = controller.importState {
                Text(message).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.import.failure")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    switch selectedTab {
                    case .profiles: profileContent(descriptorControls)
                    case .transfer: transferContent(descriptorControls)
                    case .reset: resetContent(descriptorControls)
                    }
                }
            }.frame(minHeight: 220, maxHeight: 420)
        }
    }

    private var controlContext: SettingsWorkflowControlContext {
        let collisions = controller.importReviewSummary?.collisions ?? []
        let phase: SettingsWorkflowImportPhase
        switch controller.importState {
        case .idle: phase = .idle; case .analyzing: phase = .analyzing
        case .analysis: phase = .analysis; case .issuingPreview: phase = .issuing
        case .confirmation: phase = .confirmation; case .submitting: phase = .submitting
        case .failed: phase = .failed
        }
        let hasProfile: Bool
        let hasReset: Bool
        switch controller.confirmation {
        case .profile?: hasProfile = true; hasReset = false
        case .reset?: hasProfile = false; hasReset = true
        case nil: hasProfile = false; hasReset = false
        }
        let resetIDs = store.preferences.global.fields.keys.filter { id in
            guard let definition = SettingsPresentationRegistry.renderedUniverse(volumeIDs: [])
                .first(where: { $0.id == id }) else { return false }
            return definition.layers.contains(.global) && definition.resolution == .preference
        }
        let editor = profileEditorTarget.map {
            SettingsWorkflowProfileEditorContext(target: $0,
                valueFieldIDs: profileEditorFieldIDs)
        }
        let profileFields = resetProfileID.flatMap { id in
            store.profiles.first(where: { $0.id == id }).map { Array($0.values.fields.keys) }
        } ?? []
        let ownedRestrictions = Set(profileFields.filter { id in
            SettingsPresentationRegistry.renderedUniverse(volumeIDs: []).first {
                $0.id == id
            }?.resolution == .restriction
        })
        return .init(profileIDs: store.profiles.map(\.id), activeProfileID: store.activeProfileID,
            profileEditor: editor, importPhase: phase, collisions: collisions,
            hasCompleteCollisionChoices: collisions.allSatisfy {
                controller.collisionChoices[$0.profileID] != nil
            }, hasPreparedProfile: hasProfile, resetGlobalFieldIDs: Array(resetIDs),
            resetProfileID: resetProfileID, resetProfileFieldIDs: profileFields,
            ownedRestrictionFieldIDs: ownedRestrictions,
            hasResetSelection: SettingsWorkflowPresentation.canPreviewReset(
                selectedProfileFieldIDs: resetProfileIDs,
                ownedRestrictionFieldIDs: ownedRestrictions,
                optedInRestrictionIDs: resetOwnedRestrictionIDs,
                hasOtherSelection: !resetGlobalIDs.isEmpty),
            hasPreparedReset: hasReset)
    }

    @ViewBuilder private func profileContent(_ controls: [SettingsWorkflowControlDescriptor]) -> some View {
        Text(SettingsCopy.resolve("settings.workflow.tab.profiles", bundle: bundle)).font(.headline)
        workflowButton(controls, role: .createProfile) {
            beginProfileEditor(target: .newProfile, name: "", values: .init())
        }
        ForEach(SessionProfiles.factoryKeys, id: \.self) { key in
            workflowButton(controls, id: "settings.profile.factory." + key) {
                prepareProfile(.createFactory(key: key, id: UUID(), name: key.capitalized))
            }
        }
        ForEach(store.profiles, id: \.id) { profile in
            Text(profile.name + " — " + profile.id.uuidString).font(.subheadline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
                workflowButton(controls,
                    id: "settings.profile.action.cloneProfile.\(profile.id.uuidString)") {
                    prepareProfile(.clone(sourceID: profile.id, newID: UUID(),
                                          name: profile.name + " Copy"))
                }
                workflowButton(controls,
                    id: "settings.profile.action.renameProfile.\(profile.id.uuidString)") {
                    beginProfileEditor(target: .profile(profile.id), name: profile.name,
                                       values: profile.values)
                }
                workflowButton(controls,
                    id: "settings.profile.action.deleteProfile.\(profile.id.uuidString)") {
                    prepareProfile(.delete(id: profile.id))
                }
                workflowButton(controls,
                    id: "settings.profile.action.activateProfile.\(profile.id.uuidString)") {
                    prepareProfile(.activate(profile.id))
                }
                workflowButton(controls,
                    id: "settings.profile.action.deactivateProfile.\(profile.id.uuidString)") {
                    prepareProfile(.activate(nil))
                }
            }
        }
        ForEach(controls.filter { $0.role == .profileNameEditor }) { descriptor in
            TextField(descriptor.label, text: $profileNameDraft)
                .disabled(descriptor.availability != .enabled)
                .accessibilityIdentifier(descriptor.id)
                .accessibilityLabel(descriptor.label)
                .accessibilityHint(descriptor.accessibilityHint)
                .onSubmit { submitProfileNameEditor() }
        }
        ForEach(controls.filter { $0.role == .profileValueEditor }) { descriptor in
            profileValueEditor(descriptor)
        }
        if case .profile(let preview)? = controller.confirmation {
            profilePreviewDetails(preview)
            workflowButton(controls, role: .confirmProfile) { _ = controller.confirmPreparedChange() }
            workflowButton(controls, role: .cancelProfile) { controller.cancelConfirmation() }
        }
    }

    @ViewBuilder private func transferContent(_ controls: [SettingsWorkflowControlDescriptor]) -> some View {
        workflowButton(controls, role: .chooseImport) { showsImporter = true }
        if let summary = controller.importReviewSummary {
            ForEach(SettingsWorkflowPresentation.importOutcomes(summary)) { outcome in
                VStack(alignment: .leading) {
                    Text("\(SettingsCopy.resolve(outcome.titleKey, bundle: bundle)): \(outcome.count)")
                    Text(SettingsCopy.resolve(outcome.explanationKey, bundle: bundle))
                        .font(.caption).foregroundStyle(.secondary)
                }
                    .accessibilityIdentifier(SettingsWorkflowPresentation.accessibilityID(
                        for: outcome.outcome))
            }
            ForEach(summary.collisions, id: \.profileID) { collision in
                Text(collision.localName + " / " + collision.importedName)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
                    ForEach(controls.filter { descriptor in
                        if case .collision(let id, _) = descriptor.identity {
                            return id == collision.profileID
                        }
                        return false
                    }) { descriptor in
                        workflowButton(descriptor) {
                            applyCollisionDescriptor(descriptor)
                        }
                    }
                }
                if let choice = controller.collisionChoices[collision.profileID] {
                    Text(collisionChoiceText(choice)).font(.caption).textSelection(.enabled)
                }
            }
        }
        if let digests = controller.importReviewDigests {
            Text(SettingsCopy.resolve("settings.import.sourceDigest", bundle: bundle) +
                 ": " + digests.source).textSelection(.enabled)
            Text(SettingsCopy.resolve("settings.import.candidateDigest", bundle: bundle) +
                 ": " + digests.candidate).textSelection(.enabled)
        }
        workflowButton(controls, role: .issueImport) { controller.beginImportPreviewIssuance() }
        workflowButton(controls, role: .confirmImport) { controller.beginImportConfirmation() }
        workflowButton(controls, role: .cancelImport) { controller.beginImportCancellation() }
        workflowButton(controls, role: .exportPortable) {
            do { exportDocument = try controller.makeExportDocument(); showsExporter = true }
            catch { workflowMessage = SettingsCopy.resolve("settings.export.failure", bundle: bundle) }
        }
        ForEach(SettingsDeferredWorkflow.allCases, id: \.self) { deferred in
            Text(SettingsWorkflowPresentation.deferredExplanation(deferred, bundle: bundle))
                .accessibilityIdentifier("settings.deferred." + deferred.rawValue)
        }
    }

    @ViewBuilder private func resetContent(_ controls: [SettingsWorkflowControlDescriptor]) -> some View {
        Text(SettingsCopy.resolve("settings.reset.select", bundle: bundle))
            .foregroundStyle(.secondary)
        ForEach(controls.filter { $0.role == .resetGlobalField }) { descriptor in
            if case .globalResetField(let id) = descriptor.identity {
                selectionToggle(descriptor, selection: $resetGlobalIDs, id: id)
            }
        }
        if let resetProfileID {
            Text(resetProfileID.uuidString).font(.caption).textSelection(.enabled)
            ForEach(controls.filter { $0.role == .resetProfileField }) { descriptor in
                if case .profileResetField(_, let id) = descriptor.identity {
                    selectionToggle(descriptor, selection: $resetProfileIDs, id: id)
                }
            }
            ForEach(controls.filter { $0.role == .resetRestrictionOptIn }) { descriptor in
                if case .restrictionOptIn(_, let id) = descriptor.identity {
                    selectionToggle(descriptor, selection: $resetOwnedRestrictionIDs, id: id)
                }
            }
        }
        workflowButton(controls, role: .previewReset) {
            let ownedRestrictions = Set(controls.compactMap { descriptor -> SettingID? in
                guard case .restrictionOptIn(_, let id) = descriptor.identity else { return nil }
                return id
            })
            guard SettingsWorkflowPresentation.canPreviewReset(
                selectedProfileFieldIDs: resetProfileIDs,
                ownedRestrictionFieldIDs: ownedRestrictions,
                optedInRestrictionIDs: resetOwnedRestrictionIDs,
                hasOtherSelection: !resetGlobalIDs.isEmpty) else {
                workflowMessage = SettingsCopy.resolve(
                    "settings.reset.ownedRestrictionOptIn", bundle: bundle); return
            }
            do { try controller.prepareReset(.init(globalPreferenceIDs: resetGlobalIDs,
                profileID: resetProfileID, profileFieldIDs: resetProfileIDs,
                includeOwnedProfileRestrictions: !resetProfileIDs.intersection(
                    ownedRestrictions).isEmpty)) }
            catch { workflowMessage = SettingsCopy.resolve("settings.reset.immutable", bundle: bundle) }
        }
        if case .reset(let preview)? = controller.confirmation {
            resetPreviewDetails(preview)
            workflowButton(controls, role: .confirmReset) { _ = controller.confirmPreparedChange() }
            workflowButton(controls, role: .cancelReset) { controller.cancelConfirmation() }
        }
    }

    @ViewBuilder private func profileValueEditor(
        _ descriptor: SettingsWorkflowControlDescriptor
    ) -> some View {
        if case .profileValue(_, let id) = descriptor.identity,
           let value = profileValuesDraft.fields[id] ?? SettingsPresentationRegistry
            .renderedUniverse(volumeIDs: []).first(where: { $0.id == id })?.defaultValue {
            switch value {
            case .bool(let current):
                Toggle(descriptor.label, isOn: Binding(get: { current }, set: { newValue in
                    profileValuesDraft.fields[id] = .bool(newValue)
                    submitProfileValueEditor()
                }))
                .disabled(descriptor.availability != .enabled)
                .accessibilityIdentifier(descriptor.id)
                .accessibilityHint(descriptor.accessibilityHint)
            case .integer, .choice, .strings, .null:
                TextField(descriptor.label, text: Binding(get: {
                    describe(profileValuesDraft.fields[id])
                }, set: { text in
                    profileValuesDraft.fields[id] = parsedProfileValue(
                        text, replacing: profileValuesDraft.fields[id] ?? value)
                }))
                .disabled(descriptor.availability != .enabled)
                .accessibilityIdentifier(descriptor.id)
                .accessibilityLabel(descriptor.label)
                .accessibilityHint(descriptor.accessibilityHint)
                .onSubmit { submitProfileValueEditor() }
            case .volume:
                Text(descriptor.label + ": " + describe(value)).foregroundStyle(.secondary)
                    .accessibilityIdentifier(descriptor.id)
            }
        }
    }

    private func selectionToggle(_ descriptor: SettingsWorkflowControlDescriptor,
                                 selection: Binding<Set<SettingID>>, id: SettingID) -> some View {
        Toggle(descriptor.label, isOn: Binding(get: {
            selection.wrappedValue.contains(id)
        }, set: { enabled in
            if enabled { selection.wrappedValue.insert(id) }
            else { selection.wrappedValue.remove(id) }
        }))
        .disabled(descriptor.availability != .enabled)
        .accessibilityIdentifier(descriptor.id)
        .accessibilityLabel(descriptor.label)
        .accessibilityHint(descriptor.accessibilityHint)
    }

    @ViewBuilder private func profilePreviewDetails(
        _ preview: SettingsProfileWorkflowPreview
    ) -> some View {
        Text(SettingsCopy.resolve("settings.profile.preview", bundle: bundle)).font(.headline)
        Text("\(SettingsCopy.resolve("settings.workflow.revision", bundle: bundle)): \(preview.baseRevision)")
        if let id = preview.profileID { Text(id.uuidString).textSelection(.enabled) }
        Text("\(SettingsCopy.resolve("settings.profile.activeBefore", bundle: bundle)): " +
             (preview.activeProfileBefore?.uuidString ?? "—"))
        Text("\(SettingsCopy.resolve("settings.profile.activeAfter", bundle: bundle)): " +
             (preview.activeProfileAfter?.uuidString ?? "—"))
        if let before = preview.before { Text("\(before.name) — \(before.id.uuidString)") }
        if let after = preview.after { Text("\(after.name) — \(after.id.uuidString)") }
        ForEach(preview.fieldChanges, id: \.id) { change in
            VStack(alignment: .leading) {
                Text(change.id.rawValue + ": " + describe(change.oldValue) + " → " +
                     describe(change.newValue))
                Text("Default: \(describe(change.defaultValue)); \(describe(change.rule)); " +
                     "\(describe(change.effect)); \(String(describing: change.oldSource)) → " +
                     String(describing: change.newSource))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Text(describe(preview.effect)).font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func resetPreviewDetails(
        _ preview: SettingsSelectiveResetPreview
    ) -> some View {
        Text(SettingsCopy.resolve("settings.reset.preview", bundle: bundle)).font(.headline)
        Text("\(SettingsCopy.resolve("settings.workflow.revision", bundle: bundle)): \(preview.baseRevision)")
        ForEach(preview.globalChanges, id: \.id) { change in
            Text(change.id.rawValue + ": " + describe(change.oldValue) + " → " +
                 describe(change.newValue) + " · Default: " + describe(change.defaultValue))
        }
        if let profile = preview.profileReset {
            Text(profile.profileID.uuidString).textSelection(.enabled)
            ForEach(profile.changes, id: \.id) { change in
                Text(change.id.rawValue + ": " + describe(change.oldValue) + " → " +
                     describe(change.newValue) + " · " + describe(change.defaultValue))
                Text(describe(change.rule) + " · " + describe(change.effect) + " · " +
                     String(describing: change.oldSource) + " → " +
                     String(describing: change.newSource))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        ForEach(preview.immutableBoundaries.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) {
            Text(SettingsCopy.resolve("settings.reset.boundary." + $0.rawValue, bundle: bundle))
        }
        Text(describe(preview.effect)).font(.caption).foregroundStyle(.secondary)
    }

    private func beginProfileEditor(target: SettingsWorkflowEditorTarget,
                                    name: String, values: PolicyValues) {
        profileEditorTarget = target; profileNameDraft = name; profileValuesDraft = values
        profileEditorFieldIDs = SettingsWorkflowPresentation.profileEditorFieldIDs
    }

    private func submitProfileNameEditor() {
        guard let target = profileEditorTarget else { return }
        switch target {
        case .newProfile:
            prepareProfile(.create(id: UUID(), name: profileNameDraft, values: profileValuesDraft))
        case .profile(let id):
            prepareProfile(.rename(id: id, name: profileNameDraft))
        }
    }

    private func submitProfileValueEditor() {
        guard let target = profileEditorTarget else { return }
        switch target {
        case .newProfile:
            prepareProfile(.create(id: UUID(), name: profileNameDraft, values: profileValuesDraft))
        case .profile(let id):
            prepareProfile(.update(id: id, values: profileValuesDraft))
        }
    }

    private func parsedProfileValue(_ text: String, replacing value: SettingValue) -> SettingValue {
        switch value {
        case .integer: return Int64(text).map(SettingValue.integer) ?? value
        case .choice: return .choice(text)
        case .strings: return .strings(text.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        })
        case .null: return text.isEmpty || text == "Automatic" ? .null : value
        case .bool, .volume: return value
        }
    }

    private func applyCollisionDescriptor(_ descriptor: SettingsWorkflowControlDescriptor) {
        guard case .collision(let id, let choice) = descriptor.identity else { return }
        switch choice {
        case .keepLocal: controller.chooseCollision(profileID: id, choice: .keepLocal)
        case .replace: controller.chooseCollision(profileID: id, choice: .replace)
        case .clone: controller.chooseCollision(profileID: id, choice: .clone(UUID()))
        }
    }

    private func collisionChoiceText(_ choice: ProfileCollisionChoice) -> String {
        switch choice {
        case .keepLocal: SettingsCopy.resolve("settings.import.collision.keepLocal", bundle: bundle)
        case .replace: SettingsCopy.resolve("settings.import.collision.replace", bundle: bundle)
        case .clone(let id): SettingsCopy.resolve("settings.import.collision.clone", bundle: bundle) +
            " — " + id.uuidString
        }
    }

    @ViewBuilder private func workflowButton(_ controls: [SettingsWorkflowControlDescriptor],
                                             role: SettingsWorkflowControlRole,
                                             action: @escaping () -> Void) -> some View {
        if let descriptor = controls.first(where: { $0.role == role }) {
            workflowButton(descriptor, action: action)
        }
    }
    @ViewBuilder private func workflowButton(_ controls: [SettingsWorkflowControlDescriptor],
                                             id: String,
                                             action: @escaping () -> Void) -> some View {
        if let descriptor = controls.first(where: { $0.id == id }) {
            workflowButton(descriptor, action: action)
        }
    }
    private func workflowButton(_ descriptor: SettingsWorkflowControlDescriptor,
                                action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(descriptor.label, action: action)
                .disabled(descriptor.availability != .enabled)
                .accessibilityIdentifier(descriptor.id)
                .accessibilityLabel(descriptor.label)
                .accessibilityHint(descriptor.accessibilityHint)
            if case .unavailable(_, let label) = descriptor.availability {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func prepareProfile(_ request: SettingsProfileWorkflowRequest) {
        do { try controller.prepareProfile(request) }
        catch { workflowMessage = String(describing: error) }
    }
}

struct SettingsView: View {
    @Environment(AppConfigStore.self) private var store
    @State private var selectedSection = SettingsPresentationSection.features
    @State private var query = ""
    @State private var showsAdvanced = false
    var body: some View {
        let model = SettingsSurfaceModel(store: store)
        let persistedAdvanced = resolvedUIAdvancedSettings(store.acknowledgedEffectivePolicy)
        let revealsAdvanced = showsAdvanced || persistedAdvanced
        let rows = model.rows(query: query, showsAdvanced: revealsAdvanced,
                              section: selectedSection)
        VStack(alignment: .leading, spacing: 12) {
            Picker("Settings section", selection: $selectedSection) {
                ForEach(SettingsPresentationSection.allCases, id: \.self) { section in
                    Text(section.rawValue.capitalized).tag(section)
                        .accessibilityIdentifier("settings.section." + section.rawValue)
                }
            }.pickerStyle(.segmented)
            TextField("Search settings", text: $query)
                .accessibilityLabel("Search settings")
                .accessibilityIdentifier("settings.search")
            Toggle("Show Advanced", isOn: Binding(get: { revealsAdvanced }, set: { value in
                showsAdvanced = value
                _ = model.submit(id: SettingID(rawValue: "ui.advancedSettings"),
                    value: .bool(value))
            }))
                .accessibilityIdentifier("settings.showAdvanced")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    RegistrySettingsContent(rows: rows) { id, value in
                        _ = model.submit(id: id, value: value)
                    }
                    SettingsWorkflowSurface(store: store)
                }
            }
            .accessibilityIdentifier("settings.content")
        }.padding().frame(minWidth: 480, minHeight: 520).navigationTitle("Settings")
    }
}

struct RegistrySettingsSurface: View {
    let rows: [SettingsSurfaceRow]
    var registryState: SettingsRegistryState = SettingsSurfaceModel.registryState
    let submit: (SettingID, SettingValue?) -> Void
    var body: some View {
        ScrollView {
            RegistrySettingsContent(rows: rows, registryState: registryState, submit: submit)
        }
    }
}

/// The production window owns scrolling so workflow controls cannot compress
/// the registry into a viewport shorter than a single settings row.
private struct RegistrySettingsContent: View {
    let rows: [SettingsSurfaceRow]
    var registryState: SettingsRegistryState = SettingsSurfaceModel.registryState
    let submit: (SettingID, SettingValue?) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            switch SettingsSurfaceEmptyState.resolve(
                rows: rows, registryState: registryState) {
            case .registryFailure:
                Label("Settings are unavailable because registry validation failed.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.registry.failure")
            case .noMatches:
                ContentUnavailableView("No settings match",
                    systemImage: "magnifyingglass",
                    description: Text("Try another search or section."))
                    .accessibilityIdentifier("settings.search.noMatches")
            case .content:
                ForEach(rows) { RegistrySettingRow(row: $0, submit: submit) }
            }
        }
    }
}

private struct RegistrySettingRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let row: SettingsSurfaceRow
    let submit: (SettingID, SettingValue?) -> Void
    init(row: SettingsSurfaceRow, submit: @escaping (SettingID, SettingValue?) -> Void) {
        self.row = row; self.submit = submit
    }
    var body: some View {
        layout
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(row.accessibilityIdentifier)
            .accessibilityLabel(row.accessibilityLabel)
    }
    @ViewBuilder private var layout: some View {
        if SettingsVisualContract.layoutMode(for: typeSize) == .stacked {
            VStack(alignment: .leading, spacing: 8) { title; editor; metadata }
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16) {
                GridRow { title; editor }
                GridRow { metadata.gridCellColumns(2) }
            }
        }
    }
    private var title: some View {
        semanticText(row.title, role: SettingsVisualContract.titleRole).font(.headline)
    }
    @ViewBuilder private var editor: some View {
        switch (row.controlKind, row.availability) {
        case (.toggle, .editable):
            Toggle("", isOn: Binding(get: {
                if case .bool(let value)? = row.storedValue { return value }
                if case .bool(let value) = row.setting.definition.defaultValue { return value }
                return false
            }, set: { submit(row.id, .bool($0)) })).labelsHidden()
                .accessibilityIdentifier("settings.control." + row.id.rawValue)
                .accessibilityLabel(row.accessibilityLabel)
        case (.integer, .editable):
            SettingsIntegerEditor(row: row, allowsAutomatic: false, submit: submit)
        case (.optionalInteger, .editable):
            SettingsIntegerEditor(row: row, allowsAutomatic: true, submit: submit)
        case (.choice, .editable):
            Picker("Value", selection: Binding(get: {
                if case .choice(let value)? = row.storedValue { return value }
                if case .choice(let value) = row.setting.definition.defaultValue { return value }
                return ""
            }, set: { submit(row.id, .choice($0)) })) {
                if case .choices(let values) = row.setting.definition.rule {
                    ForEach(values, id: \.self) { Text($0).tag($0) }
                }
            }.accessibilityIdentifier("settings.control." + row.id.rawValue)
                .accessibilityLabel(row.accessibilityLabel)
        default:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange).accessibilityHidden(true)
        }
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            semanticText(row.help, role: SettingsVisualContract.metadataRole)
            semanticText("Default: " + row.defaultText, role: SettingsVisualContract.metadataRole)
            semanticText("Effective: " + row.effectiveText, role: SettingsVisualContract.metadataRole)
            semanticText("Source: " + row.sourceText, role: SettingsVisualContract.metadataRole)
            semanticText("Rule: " + row.ruleText, role: SettingsVisualContract.metadataRole)
            semanticText(row.consequence, role: SettingsVisualContract.metadataRole)
            semanticText(row.availabilityText, role:
                row.availability == .editable ? SettingsVisualContract.metadataRole :
                    SettingsVisualContract.unavailableRole)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("settings.metadata." + row.id.rawValue)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(SettingsAccessibility.value(for: row))
        .accessibilityHint(SettingsAccessibility.help(for: row))
    }
}

struct SettingsIntegerDraft: Equatable {
    private(set) var text: String
    let allowsAutomatic: Bool

    init(storedValue: SettingValue?, allowsAutomatic: Bool) {
        self.allowsAutomatic = allowsAutomatic
        if case .integer(let value)? = storedValue { text = String(value) }
        else { text = "" }
    }

    mutating func replaceText(_ value: String) { text = value }

    mutating func synchronize(storedValue: SettingValue?) {
        if case .integer(let value)? = storedValue { text = String(value) }
        else { text = "" }
    }

    var committedValue: SettingValue? {
        if allowsAutomatic && text.isEmpty { return .null }
        guard let value = Int64(text) else { return nil }
        return .integer(value)
    }
}

private struct SettingsIntegerEditor: View {
    let row: SettingsSurfaceRow
    let allowsAutomatic: Bool
    let submit: (SettingID, SettingValue?) -> Void
    @State private var draft: SettingsIntegerDraft
    @FocusState private var isFocused: Bool

    init(row: SettingsSurfaceRow, allowsAutomatic: Bool,
         submit: @escaping (SettingID, SettingValue?) -> Void) {
        self.row = row
        self.allowsAutomatic = allowsAutomatic
        self.submit = submit
        _draft = State(initialValue: SettingsIntegerDraft(
            storedValue: row.storedValue, allowsAutomatic: allowsAutomatic))
    }

    var body: some View {
        TextField(allowsAutomatic ? "Automatic" : "Value", text: Binding(
            get: { draft.text }, set: { draft.replaceText($0) }))
            .focused($isFocused)
            .onSubmit {
                if let value = draft.committedValue { submit(row.id, value) }
            }
            .onChange(of: row.storedValue) { _, value in
                if !isFocused { draft.synchronize(storedValue: value) }
            }
            .frame(minWidth: 96)
            .accessibilityIdentifier("settings.control." + row.id.rawValue)
            .accessibilityLabel(row.accessibilityLabel)
    }
}

enum SettingsAccessibility {
    static func value(for row: SettingsSurfaceRow) -> String {
        "Default: " + row.defaultText + ". Effective: " + row.effectiveText +
            ". Source: " + row.sourceText + ". Rule: " + row.ruleText
    }

    static func help(for row: SettingsSurfaceRow) -> String {
        row.help + " " + row.consequence + " " + row.availabilityText
    }
}

@ViewBuilder private func semanticText(_ value: String, role: SettingsSemanticTextRole) -> some View {
    switch role {
    case .primary: Text(value).foregroundStyle(.primary)
    case .secondary: Text(value).foregroundStyle(.secondary)
    case .warning: Label(value, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
    }
}

// Onboarding still references these legacy type names. They deliberately show the
// already-stored authority values without discovering or changing local identities.
struct CookieDomainsSection: View {
    @Binding var domains: [String]
    var body: some View {
        Section("Cookie domains") {
            if domains.isEmpty { Text("No domains are currently approved.") }
            ForEach(domains, id: \.self) { Text($0) }
            Text("Domain approval is available in a separate local-authority workflow.")
                .foregroundStyle(.secondary)
        }
    }
}

struct ProjectRootsSection: View {
    @Binding var roots: [String]
    var body: some View {
        Section("Project roots") {
            if roots.isEmpty { Text("No project roots are currently approved.") }
            ForEach(roots, id: \.self) { Text($0) }
            Text("Folder approval is available in a separate local-authority workflow.")
                .foregroundStyle(.secondary)
        }
    }
}

struct SimulatorApprovalSection: View {
    @Binding var approvedForDeletion: [String]
    var body: some View {
        Section("Simulator devices") {
            if approvedForDeletion.isEmpty { Text("No simulator devices are approved.") }
            ForEach(approvedForDeletion, id: \.self) { Text($0) }
            Text("Device approval is available in a separate local-authority workflow.")
                .foregroundStyle(.secondary)
        }
    }
}
