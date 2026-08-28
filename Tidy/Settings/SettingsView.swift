import Foundation
import SwiftUI
import TidyCore

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
            let availability: SettingsRowAvailability
            if definition.resolution == .authority {
                availability = .deferred("Requires a separately accepted local-authority workflow.")
            } else if !definition.layers.contains(.global) {
                availability = .unavailable("This setting is not editable at the global layer.")
            } else if kind == .readOnly {
                availability = .unavailable(
                    "This value needs a bounded editor that is deferred from T07.3a.")
            } else { availability = .editable }
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
              definition.layers.contains(.global), control(for: definition) != .readOnly
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
        let availability: SettingsRowAvailability
        if definition.resolution == .authority {
            availability = .deferred("Requires a separately accepted local-authority workflow.")
        } else if !definition.layers.contains(.global) {
            availability = .unavailable("This setting is not editable at the global layer.")
        } else if kind == .readOnly {
            availability = .unavailable("This value needs a bounded editor that is deferred from T07.3a.")
        } else { availability = .editable }
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

struct SettingsView: View {
    @Environment(AppConfigStore.self) private var store
    @State private var selectedSection = SettingsPresentationSection.features
    @State private var query = ""
    @State private var showsAdvanced = false
    var body: some View {
        let model = SettingsSurfaceModel(store: store)
        let rows = model.rows(query: query, showsAdvanced: showsAdvanced,
                              section: selectedSection)
        VStack(alignment: .leading, spacing: 12) {
            Picker("Settings section", selection: $selectedSection) {
                ForEach(SettingsPresentationSection.allCases, id: \.self) { section in
                    Text(section.rawValue.capitalized).tag(section)
                        .accessibilityIdentifier("settings.section." + section.rawValue)
                }
            }.pickerStyle(.segmented)
            TextField("Search settings", text: $query).accessibilityIdentifier("settings.search")
            Toggle("Show Advanced", isOn: $showsAdvanced)
                .accessibilityIdentifier("settings.showAdvanced")
            RegistrySettingsSurface(rows: rows) { id, value in
                _ = model.submit(id: id, value: value)
            }
        }.padding().frame(minWidth: 480, minHeight: 520).navigationTitle("Settings")
    }
}

struct RegistrySettingsSurface: View {
    let rows: [SettingsSurfaceRow]
    var registryState: SettingsRegistryState = SettingsSurfaceModel.registryState
    let submit: (SettingID, SettingValue?) -> Void
    var body: some View {
        ScrollView {
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
}

private struct RegistrySettingRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let row: SettingsSurfaceRow
    let submit: (SettingID, SettingValue?) -> Void
    init(row: SettingsSurfaceRow, submit: @escaping (SettingID, SettingValue?) -> Void) {
        self.row = row; self.submit = submit
    }
    var body: some View {
        layout.accessibilityIdentifier(row.accessibilityIdentifier)
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
