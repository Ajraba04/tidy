import Foundation

extension AuthorityEffect: Equatable {}

public enum SettingsLoadDisposition: Equatable, Sendable {
    case newDefaults, migrated, loaded, recoveryReadOnly
}
public enum SettingsRecoveryReason: Equatable, Sendable {
    case malformed, unsupportedSchema(Int), unavailable, unsafeLocation, oversized
}
public struct SettingsEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: UInt64
    public let config: TidyConfig
    public let preferences: PolicyPreferences?
    public let activeProfileID: UUID?
    public let inertImports: [InertPortableSetting]

    public init(schemaVersion: Int, revision: UInt64, config: TidyConfig,
                preferences: PolicyPreferences? = nil, activeProfileID: UUID? = nil,
                inertImports: [InertPortableSetting] = []) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.config = config
        self.preferences = preferences
        self.activeProfileID = activeProfileID
        self.inertImports = inertImports
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, config, preferences, activeProfileID, inertImports
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        revision = try container.decode(UInt64.self, forKey: .revision)
        config = try container.decode(TidyConfig.self, forKey: .config)
        preferences = try container.decodeIfPresent(PolicyPreferences.self, forKey: .preferences)
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        inertImports = try container.decodeIfPresent([InertPortableSetting].self,
                                                      forKey: .inertImports) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(config, forKey: .config)
        if let preferences {
            try container.encode(preferences, forKey: .preferences)
            try container.encode(inertImports, forKey: .inertImports)
            try container.encodeIfPresent(activeProfileID, forKey: .activeProfileID)
        }
    }
}
public struct SettingsLoadResult: Equatable, Sendable {
    public let disposition: SettingsLoadDisposition
    public let envelope: SettingsEnvelope?
    public let recoveryReason: SettingsRecoveryReason?
}
public enum SettingsChange: Equatable, Sendable {
    case transcriptAgeDays(Int)
    case legacyPreferences(TidyConfig)
    case preferences(PolicyPreferences)
    case legacyPreferenceDelta(LegacyPreferenceDelta)
    case globalPreferenceDelta(GlobalPreferenceDelta)
    case preferencesDocument(PreferencesDocumentDelta)
}

public struct PreferenceFieldEdit: Codable, Equatable, Sendable {
    public let id: SettingID
    public let baseValue: SettingValue?
    public let editedValue: SettingValue?
    public init(id: SettingID, baseValue: SettingValue?, editedValue: SettingValue?) {
        self.id = id; self.baseValue = baseValue; self.editedValue = editedValue
    }
}

public enum ProfileDocumentEdit: Codable, Equatable, Sendable {
    case insert(SavedProfile)
    case update(id: UUID, base: SavedProfile, edited: SavedProfile)
    case delete(id: UUID, base: SavedProfile)
}

public struct InertImportEdit: Codable, Equatable, Sendable {
    public let item: InertPortableSetting
    public let presentInBase: Bool
    public let presentAfterEdit: Bool
    public init(item: InertPortableSetting, presentInBase: Bool, presentAfterEdit: Bool) {
        self.item = item; self.presentInBase = presentInBase; self.presentAfterEdit = presentAfterEdit
    }
}

public struct PreferencesDocumentDelta: Codable, Equatable, Sendable {
    public let baseRevision: UInt64
    public let global: [PreferenceFieldEdit]
    public let profiles: [ProfileDocumentEdit]
    public let activeProfileBase: UUID?
    public let activeProfileEdit: UUID?
    public let touchesActiveProfile: Bool
    public let inert: [InertImportEdit]
    public init(baseRevision: UInt64, global: [PreferenceFieldEdit] = [],
                profiles: [ProfileDocumentEdit] = [], activeProfileBase: UUID? = nil,
                activeProfileEdit: UUID? = nil, touchesActiveProfile: Bool = false,
                inert: [InertImportEdit] = []) {
        self.baseRevision = baseRevision; self.global = global; self.profiles = profiles
        self.activeProfileBase = activeProfileBase; self.activeProfileEdit = activeProfileEdit
        self.touchesActiveProfile = touchesActiveProfile; self.inert = inert
    }
}

public enum PreferencesDocumentProjectionError: Error, Equatable, Sendable {
    case stale, invalid, unsupportedAuthority
}

public enum PreferencesDocumentEffect {
    static func inspect(_ id: SettingID, _ value: SettingValue,
                        layer: PolicyLayer, invalidates: inout Bool) throws {
        guard let definition = PolicyValidator.definition(for: id) else {
            throw PreferencesDocumentProjectionError.invalid
        }
        let classification: PortableClassification
        do { classification = try PortableSettingPolicy.classify(id: id, value: value, layer: layer) }
        catch { throw PreferencesDocumentProjectionError.invalid }
        guard classification == .portable, definition.resolution != .authority,
              definition.effect != .consent else {
            throw PreferencesDocumentProjectionError.unsupportedAuthority
        }
        if definition.effect == .invalidate { invalidates = true }
    }

    private static func profilesByID(_ profiles: [SavedProfile]) throws -> [UUID: SavedProfile] {
        var result: [UUID: SavedProfile] = [:]
        for profile in profiles {
            guard result.updateValue(profile, forKey: profile.id) == nil else {
                throw PreferencesDocumentProjectionError.invalid
            }
        }
        return result
    }

    public static func classify(before: SettingsEnvelope,
                                after: SettingsEnvelope) throws -> AuthorityEffect {
        var invalidates = before.activeProfileID != after.activeProfileID
        let beforeGlobal = before.preferences?.global.fields ?? [:]
        let afterGlobal = after.preferences?.global.fields ?? [:]
        for id in Set(beforeGlobal.keys).union(afterGlobal.keys)
            where beforeGlobal[id] != afterGlobal[id] {
            guard let value = afterGlobal[id] ?? beforeGlobal[id] else {
                throw PreferencesDocumentProjectionError.invalid
            }
            try inspect(id, value, layer: .global, invalidates: &invalidates)
        }
        let beforeProfiles = try profilesByID(before.preferences?.profiles ?? [])
        let afterProfiles = try profilesByID(after.preferences?.profiles ?? [])
        for profileID in Set(beforeProfiles.keys).union(afterProfiles.keys) {
            let lhs = beforeProfiles[profileID]?.values.fields ?? [:]
            let rhs = afterProfiles[profileID]?.values.fields ?? [:]
            for id in Set(lhs.keys).union(rhs.keys) where lhs[id] != rhs[id] {
                guard let value = rhs[id] ?? lhs[id] else {
                    throw PreferencesDocumentProjectionError.invalid
                }
                try inspect(id, value, layer: .profile, invalidates: &invalidates)
            }
        }
        return invalidates ? .invalidate : .none
    }
}

public struct AppliedPreferencesDocument: Equatable, Sendable {
    public let envelope: SettingsEnvelope
    public let effect: AuthorityEffect
    public init(envelope: SettingsEnvelope, effect: AuthorityEffect) {
        self.envelope = envelope; self.effect = effect
    }
}

public enum PreferencesDocumentProjection {
    private struct InertKey: Hashable {
        let scope: InertScope
        let profileID: UUID?
        let id: String
        init(_ item: InertPortableSetting) {
            scope = item.scope; profileID = item.profileID; id = item.id
        }
    }

    public static func apply(_ delta: PreferencesDocumentDelta,
                             to envelope: SettingsEnvelope) throws -> AppliedPreferencesDocument {
        guard delta.baseRevision <= envelope.revision else {
            throw PreferencesDocumentProjectionError.stale
        }
        var preferences = envelope.preferences ?? PolicyPreferences()
        guard Set(preferences.profiles.map(\.id)).count == preferences.profiles.count else {
            throw PreferencesDocumentProjectionError.invalid
        }
        var globalIDs = Set<SettingID>()
        for edit in delta.global {
            guard globalIDs.insert(edit.id).inserted else {
                throw PreferencesDocumentProjectionError.invalid
            }
            guard preferences.global.fields[edit.id] == edit.baseValue else {
                throw PreferencesDocumentProjectionError.stale
            }
            var ignored = false
            guard let touchedValue = edit.editedValue ?? edit.baseValue ??
                    PolicyValidator.definition(for: edit.id)?.defaultValue else {
                throw PreferencesDocumentProjectionError.invalid
            }
            try PreferencesDocumentEffect.inspect(edit.id, touchedValue,
                                                   layer: .global, invalidates: &ignored)
            preferences.global.fields[edit.id] = edit.editedValue
        }

        var touchedProfiles = Set<UUID>()
        var deletedProfiles = Set<UUID>()
        for edit in delta.profiles {
            let id: UUID
            switch edit {
            case .insert(let profile): id = profile.id
            case .update(let profileID, _, _), .delete(let profileID, _): id = profileID
            }
            guard touchedProfiles.insert(id).inserted else {
                throw PreferencesDocumentProjectionError.invalid
            }
            switch edit {
            case .insert(let profile):
                guard !preferences.profiles.contains(where: { $0.id == profile.id }) else {
                    throw PreferencesDocumentProjectionError.stale
                }
                preferences.profiles.append(profile)
            case .update(let id, let base, let edited):
                guard edited.id == id else { throw PreferencesDocumentProjectionError.invalid }
                guard let index = preferences.profiles.firstIndex(where: { $0.id == id }),
                      preferences.profiles[index] == base else {
                    throw PreferencesDocumentProjectionError.stale
                }
                preferences.profiles[index] = edited
            case .delete(let id, let base):
                guard let index = preferences.profiles.firstIndex(where: { $0.id == id }),
                      preferences.profiles[index] == base else {
                    throw PreferencesDocumentProjectionError.stale
                }
                preferences.profiles.remove(at: index); deletedProfiles.insert(id)
            }
            let touched: SavedProfile
            switch edit {
            case .insert(let profile): touched = profile
            case .update(_, let base, let edited):
                var ignored = false
                for fieldID in Set(base.values.fields.keys).union(edited.values.fields.keys) {
                    guard let value = edited.values.fields[fieldID] ?? base.values.fields[fieldID] else {
                        throw PreferencesDocumentProjectionError.invalid
                    }
                    try PreferencesDocumentEffect.inspect(fieldID, value,
                        layer: .profile, invalidates: &ignored)
                }
                continue
            case .delete(_, let base): touched = base
            }
            var ignored = false
            for (fieldID, value) in touched.values.fields {
                try PreferencesDocumentEffect.inspect(fieldID, value,
                    layer: .profile, invalidates: &ignored)
            }
        }
        guard Set(preferences.profiles.map(\.id)).count == preferences.profiles.count else {
            throw PreferencesDocumentProjectionError.invalid
        }

        var active = envelope.activeProfileID
        if delta.touchesActiveProfile {
            guard envelope.activeProfileID == delta.activeProfileBase else {
                throw PreferencesDocumentProjectionError.stale
            }
            active = delta.activeProfileEdit
        }
        if let selected = envelope.activeProfileID, deletedProfiles.contains(selected) {
            guard delta.touchesActiveProfile, delta.activeProfileBase == selected,
                  delta.activeProfileEdit == nil else {
                throw PreferencesDocumentProjectionError.invalid
            }
        }
        if let active, !preferences.profiles.contains(where: { $0.id == active }) {
            throw PreferencesDocumentProjectionError.invalid
        }

        var inert: [InertKey: InertPortableSetting] = [:]
        for item in envelope.inertImports {
            guard inert.updateValue(item, forKey: InertKey(item)) == nil else {
                throw PreferencesDocumentProjectionError.invalid
            }
        }
        var touchedInert = Set<InertKey>()
        for edit in delta.inert {
            let key = InertKey(edit.item)
            guard touchedInert.insert(key).inserted else {
                throw PreferencesDocumentProjectionError.invalid
            }
            if edit.presentInBase {
                guard inert[key] == edit.item else { throw PreferencesDocumentProjectionError.stale }
            } else if inert[key] != nil { throw PreferencesDocumentProjectionError.stale }
            if edit.presentAfterEdit { inert[key] = edit.item } else { inert.removeValue(forKey: key) }
        }
        let inertImports = inert.values.sorted {
            [$0.scope.rawValue, $0.profileID?.uuidString ?? "", $0.id]
                .lexicographicallyPrecedes([$1.scope.rawValue, $1.profileID?.uuidString ?? "", $1.id])
        }
        let config = LegacyCompatibilityProjection.reverseProject(envelope.config,
            replacing: envelope.preferences?.global, with: preferences.global)
        let candidate = SettingsEnvelope(schemaVersion: envelope.schemaVersion,
            revision: envelope.revision, config: config, preferences: preferences,
            activeProfileID: active, inertImports: inertImports)
        let effect = try PreferencesDocumentEffect.classify(before: envelope, after: candidate)
        do {
            try SettingsTransfer.validatePersistedState(.init(preferences: preferences,
                                                              inertImports: inertImports))
        } catch { throw PreferencesDocumentProjectionError.invalid }
        if delta.touchesActiveProfile { return .init(envelope: candidate, effect: .invalidate) }
        return .init(envelope: candidate, effect: effect)
    }
}

public struct GlobalPreferenceDelta: Equatable, Sendable {
    public let baseRevision: UInt64
    public let id: SettingID
    public let baseValue: SettingValue?
    public let editedValue: SettingValue?

    public init(baseRevision: UInt64, id: SettingID, baseValue: SettingValue?,
                editedValue: SettingValue?) {
        self.baseRevision = baseRevision
        self.id = id
        self.baseValue = baseValue
        self.editedValue = editedValue
    }
}

public struct LegacyPreferenceDelta: Equatable, Sendable {
    public let baseRevision: UInt64
    public let base: TidyConfig
    public let edited: TidyConfig
    /// Exact captured typed compatibility bases. `nil` is intentionally distinct
    /// from the registry default and participates in stale-edit detection.
    public let touchedCompatibilityBase: [GlobalPreferenceDelta]

    public init(baseRevision: UInt64, base: TidyConfig, edited: TidyConfig,
                compatibilityBase: PolicyValues? = nil) {
        self.baseRevision = baseRevision
        self.base = base
        self.edited = edited
        var touched: [GlobalPreferenceDelta] = []
        func append(_ rawID: String, changed: Bool, _ after: SettingValue?) {
            guard changed else { return }
            let id = SettingID(rawValue: rawID)
            touched.append(GlobalPreferenceDelta(baseRevision: baseRevision,
                id: id, baseValue: compatibilityBase?.fields[id], editedValue: after))
        }
        append("browsers.keepCookieDomains", changed: base.keepCookieDomains != edited.keepCookieDomains,
               .strings(edited.keepCookieDomains))
        append("cleanup.transcriptDays", changed: base.transcriptAgeThresholdDays != edited.transcriptAgeThresholdDays,
               .integer(Int64(edited.transcriptAgeThresholdDays)))
        append("item.normal.extras.stale-node-modules.inactiveDays",
               changed: base.staleNodeModulesThresholdDays != edited.staleNodeModulesThresholdDays,
               .integer(Int64(edited.staleNodeModulesThresholdDays)))
        append("rescue.showAdvancedMemoryActions",
               changed: base.allowRestartToReclaimSwap != edited.allowRestartToReclaimSwap,
               .bool(edited.allowRestartToReclaimSwap))
        self.touchedCompatibilityBase = touched.sorted { $0.id.rawValue < $1.id.rawValue }
    }
}

/// Pure compatibility projection shared by durable settings, bridge prediction,
/// and app-visible optimistic replay. This does not resolve effective policy or
/// alter authority; it only keeps the four historical `TidyConfig` fields and
/// their raw global preference representations in lockstep.
public enum LegacyCompatibilityProjection {
    public static func applyingLegacyEdit(from base: TidyConfig, to edited: TidyConfig,
                                          saved: PolicyPreferences?) -> PolicyPreferences {
        var preferences = PolicyPreferences.project(legacy: base, saved: saved)
        func set(_ id: String, _ value: SettingValue) {
            preferences.global.fields[SettingID(rawValue: id)] = value
        }
        if base.transcriptAgeThresholdDays != edited.transcriptAgeThresholdDays {
            set("cleanup.transcriptDays", .integer(Int64(edited.transcriptAgeThresholdDays)))
        }
        if base.staleNodeModulesThresholdDays != edited.staleNodeModulesThresholdDays {
            set("item.normal.extras.stale-node-modules.inactiveDays",
                .integer(Int64(edited.staleNodeModulesThresholdDays)))
        }
        if base.keepCookieDomains != edited.keepCookieDomains {
            set("browsers.keepCookieDomains", .strings(edited.keepCookieDomains))
        }
        if base.allowRestartToReclaimSwap != edited.allowRestartToReclaimSwap {
            set("rescue.showAdvancedMemoryActions", .bool(edited.allowRestartToReclaimSwap))
        }
        return preferences
    }

    public static func reverseProject(_ config: TidyConfig, replacing prior: PolicyValues?,
                                      with global: PolicyValues) -> TidyConfig {
        var result = config
        let transcript = SettingID(rawValue: "cleanup.transcriptDays")
        if case .integer(let value)? = global.fields[transcript], let exact = Int(exactly: value) {
            result.transcriptAgeThresholdDays = exact
        } else if prior?.fields[transcript] != nil {
            result.transcriptAgeThresholdDays = 45
        }

        let stale = SettingID(rawValue: "item.normal.extras.stale-node-modules.inactiveDays")
        if case .integer(let value)? = global.fields[stale], let exact = Int(exactly: value) {
            result.staleNodeModulesThresholdDays = exact
        } else if prior?.fields[stale] != nil {
            result.staleNodeModulesThresholdDays = 60
        }

        let domains = SettingID(rawValue: "browsers.keepCookieDomains")
        if case .strings(let values)? = global.fields[domains] {
            result.keepCookieDomains = values
        } else if prior?.fields[domains] != nil {
            result.keepCookieDomains = []
        }

        let advanced = SettingID(rawValue: "rescue.showAdvancedMemoryActions")
        if case .bool(let visible)? = global.fields[advanced] {
            result.allowRestartToReclaimSwap = visible
        } else if prior?.fields[advanced] != nil {
            result.allowRestartToReclaimSwap = false
        }
        return result
    }
}

public enum SettingsStoreError: Error, Equatable, Sendable {
    case readOnlyRecovery, staleRevision, changedExternally, invalidChange
    case unavailable, unsafeLocation, oversized, revisionOverflow, writeFailed, durabilityUncertain, finalizationBlocked
}
struct SettingsPublicationFailure: Equatable, Sendable {
    let stage: String
    let errno: Int32
}
public struct SettingsRollbackPreview: Sendable {
    public let config: TidyConfig
    public let preferences: PolicyPreferences?
    public let activeProfileID: UUID?
    public let inertImports: [InertPortableSetting]
    internal let identity: UUID

    internal init(config: TidyConfig, preferences: PolicyPreferences? = nil,
                  activeProfileID: UUID? = nil,
                  inertImports: [InertPortableSetting] = [], identity: UUID) {
        self.config = config
        self.preferences = preferences
        self.activeProfileID = activeProfileID
        self.inertImports = inertImports
        self.identity = identity
    }
}

/// Bounded historical compatibility decoding, never an effective-policy resolver.
enum SettingsDecoding {
    static let byteLimit = 1_048_576
    enum Failure: Error { case malformed, oversized, unsupportedSchema(Int) }

    static func encode(_ envelope: SettingsEnvelope) throws -> Data {
        let config = envelope.config
        guard envelope.schemaVersion == 2, config.schemaVersion == 2,
              (7...365).contains(config.staleNodeModulesThresholdDays),
              (7...365).contains(config.transcriptAgeThresholdDays),
              config.presets.count <= 50 else { throw SettingsStoreError.invalidChange }
        var budget = 0
        func strings(_ values: [String]) throws {
            guard values.count <= 1000 else { throw SettingsStoreError.invalidChange }
            for value in values {
                guard value.utf8.count <= 4096 else { throw SettingsStoreError.invalidChange }
                let (next, overflow) = budget.addingReportingOverflow(value.utf8.count)
                guard !overflow, next <= byteLimit else { throw SettingsStoreError.oversized }
                budget = next
            }
        }
        try strings(config.keepCookieDomains)
        try strings(config.simulatorsApprovedForDeletion)
        try strings(config.gitRoots)
        try strings(config.appsApprovedForQuit)
        for preset in config.presets {
            try strings([preset.name]); try strings(Array(preset.itemIDs))
        }
        if let preferences = envelope.preferences {
            do { try validate(preferences, stringBudget: &budget) }
            catch is PolicyFieldError { throw SettingsStoreError.invalidChange }
            guard envelope.activeProfileID == nil ||
                  preferences.profiles.contains(where: { $0.id == envelope.activeProfileID }) else {
                throw SettingsStoreError.invalidChange
            }
            do {
                try SettingsTransfer.validatePersistedState(.init(preferences: preferences,
                                                                  inertImports: envelope.inertImports))
            } catch { throw SettingsStoreError.invalidChange }
        } else if envelope.activeProfileID != nil || !envelope.inertImports.isEmpty {
            throw SettingsStoreError.invalidChange
        }
        // The raw-string budget also bounds encoder allocation before the exact byte check.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(envelope)
        guard bytes.count <= byteLimit else { throw SettingsStoreError.oversized }
        _ = try load(bytes)
        return bytes
    }

    static func storeIdentity(_ bytes: Data) throws -> UUID {
        guard bytes.count <= 1024, String(data: bytes, encoding: .utf8) != nil else {
            throw Failure.malformed
        }
        do {
            let root = try StrictJSON.parse(bytes).object()
            guard Set(root.keys) == ["schema", "storeID"],
                  try required(root, "schema").integer() == 1,
                  let id = UUID(uuidString: try required(root, "storeID").string()) else {
                throw Failure.malformed
            }
            return id
        } catch is StrictJSONError {
            throw Failure.malformed
        }
    }

    static func load(_ data: Data) throws -> SettingsLoadResult {
        guard data.count <= byteLimit else { throw Failure.oversized }
        guard String(data: data, encoding: .utf8) != nil else { throw Failure.malformed }
        do { return try loadParsed(data) }
        catch is StrictJSONError { throw Failure.malformed }
    }

    private static func loadParsed(_ data: Data) throws -> SettingsLoadResult {
        let root = try StrictJSON.parse(data).object()
        let version = try required(root, "schemaVersion").integer()
        guard version == 1 || version == 2 else { throw Failure.unsupportedSchema(version) }
        if version == 1 {
            return SettingsLoadResult(disposition: .migrated,
                envelope: SettingsEnvelope(schemaVersion: 2, revision: 0,
                    config: try config(root, legacy: true)), recoveryReason: nil)
        }
        let keys = Set(root.keys)
        let legacy = Set(["schemaVersion", "revision", "config"])
        let withPreferences = legacy.union(["preferences"])
        let withInert = withPreferences.union(["inertImports"])
        let withActive = withInert.union(["activeProfileID"])
        guard keys == legacy || keys == withPreferences || keys == withInert || keys == withActive else {
            throw Failure.malformed
        }
        let revision = try required(root, "revision").unsignedInteger()
        let decodedPreferences = try root["preferences"].map(preferences)
        let decodedInert = try root["inertImports"].map(inertImports) ?? []
        let activeProfileID: UUID?
        if let value = root["activeProfileID"] {
            let text = try value.string()
            guard let id = UUID(uuidString: text), text == id.uuidString else { throw Failure.malformed }
            activeProfileID = id
        } else { activeProfileID = nil }
        if let decodedPreferences {
            guard activeProfileID == nil ||
                  decodedPreferences.profiles.contains(where: { $0.id == activeProfileID }) else {
                throw Failure.malformed
            }
            do {
                try SettingsTransfer.validatePersistedState(.init(preferences: decodedPreferences,
                                                                  inertImports: decodedInert))
            } catch { throw Failure.malformed }
        } else if activeProfileID != nil || !decodedInert.isEmpty { throw Failure.malformed }
        return SettingsLoadResult(disposition: .loaded,
            envelope: SettingsEnvelope(schemaVersion: 2, revision: revision,
                config: try config(required(root, "config").object(), legacy: false),
                preferences: decodedPreferences, activeProfileID: activeProfileID,
                inertImports: decodedInert), recoveryReason: nil)
    }

    private static func required(_ object: [String: StrictJSON.Value], _ key: String) throws -> StrictJSON.Value {
        guard let value = object[key] else { throw Failure.malformed }
        return value
    }

    private static func config(_ object: [String: StrictJSON.Value], legacy: Bool) throws -> TidyConfig {
        let keys: Set<String> = ["schemaVersion", "hasCompletedOnboarding", "keepCookieDomains",
            "simulatorsApprovedForDeletion", "gitRoots", "staleNodeModulesThresholdDays",
            "transcriptAgeThresholdDays", "appsApprovedForQuit", "allowRestartToReclaimSwap", "presets"]
        guard legacy || Set(object.keys) == keys,
              try required(object, "schemaVersion").integer() == (legacy ? 1 : 2) else {
            throw Failure.malformed
        }
        let stale = try required(object, "staleNodeModulesThresholdDays").integer()
        let transcript = try required(object, "transcriptAgeThresholdDays").integer()
        guard (7...365).contains(stale), (7...365).contains(transcript) else { throw Failure.malformed }
        let presets = try required(object, "presets").array()
        guard presets.count <= 50 else { throw Failure.malformed }
        let decodedPresets = try presets.map { value -> CustomPreset in
            let preset = try value.object()
            guard legacy || Set(preset.keys) == ["name", "itemIDs"] else { throw Failure.malformed }
            return CustomPreset(name: try required(preset, "name").string(),
                itemIDs: Set(try required(preset, "itemIDs").strings()))
        }
        return TidyConfig(schemaVersion: 2,
            hasCompletedOnboarding: try required(object, "hasCompletedOnboarding").bool(),
            keepCookieDomains: try required(object, "keepCookieDomains").strings(),
            simulatorsApprovedForDeletion: try required(object, "simulatorsApprovedForDeletion").strings(),
            gitRoots: try required(object, "gitRoots").strings(),
            staleNodeModulesThresholdDays: stale, transcriptAgeThresholdDays: transcript,
            appsApprovedForQuit: try object["appsApprovedForQuit"]?.strings() ?? [],
            allowRestartToReclaimSwap: try object["allowRestartToReclaimSwap"]?.bool() ?? false,
            presets: decodedPresets)
    }

    private static func validate(_ preferences: PolicyPreferences,
                                 stringBudget: inout Int) throws {
        guard preferences.profiles.count <= 50,
              preferences.projects.count <= 1_000,
              Set(preferences.profiles.map(\.id)).count == preferences.profiles.count else {
            throw SettingsStoreError.invalidChange
        }

        var totalFields = 0
        func consume(_ value: String) throws {
            let bytes = value.utf8.count
            guard bytes <= 4_096 else { throw SettingsStoreError.invalidChange }
            let (next, overflow) = stringBudget.addingReportingOverflow(bytes)
            guard !overflow, next <= byteLimit else { throw SettingsStoreError.oversized }
            stringBudget = next
        }
        func document(_ values: PolicyValues, at layer: PolicyLayer) throws {
            guard values.fields.count <= 1_000 else { throw SettingsStoreError.invalidChange }
            let (next, overflow) = totalFields.addingReportingOverflow(values.fields.count)
            guard !overflow, next <= 4_096 else { throw SettingsStoreError.invalidChange }
            totalFields = next
            for (id, value) in values.fields {
                try consume(id.rawValue)
                switch value {
                case .choice(let string): try consume(string)
                case .strings(let strings):
                    guard strings.count <= 1_000 else { throw SettingsStoreError.invalidChange }
                    for string in strings { try consume(string) }
                case .bool, .integer, .null, .volume: break
                }
            }
            try PolicyValidator.validateStructure(values, at: layer)
        }

        try document(preferences.global, at: .global)
        for profile in preferences.profiles {
            try consume(profile.id.uuidString)
            try consume(profile.name)
            try document(profile.values, at: .profile)
        }
        for (project, values) in preferences.projects {
            guard !project.isEmpty else { throw SettingsStoreError.invalidChange }
            try consume(project)
            try document(values, at: .project)
        }
    }

    private static func preferences(_ value: StrictJSON.Value) throws -> PolicyPreferences {
        let root = try value.object()
        guard Set(root.keys) == ["global", "profiles", "projects"] else { throw Failure.malformed }
        let global = try policyValues(required(root, "global"))
        let profileValues = try required(root, "profiles").array()
        guard profileValues.count <= 50 else { throw Failure.malformed }
        var profiles: [SavedProfile] = []
        var profileIDs = Set<UUID>()
        for value in profileValues {
            let object = try value.object()
            let rawID = try required(object, "id").string()
            guard Set(object.keys) == ["id", "name", "values"],
                  let id = UUID(uuidString: rawID), rawID == id.uuidString,
                  profileIDs.insert(id).inserted else { throw Failure.malformed }
            profiles.append(SavedProfile(id: id, name: try required(object, "name").string(),
                values: try policyValues(required(object, "values"))))
        }
        let projectValues = try required(root, "projects").object()
        var projects: [String: PolicyValues] = [:]
        for (id, value) in projectValues {
            guard !id.isEmpty else { throw Failure.malformed }
            projects[id] = try policyValues(value)
        }
        let result = PolicyPreferences(global: global, profiles: profiles, projects: projects)
        var stringBudget = 0
        do { try validate(result, stringBudget: &stringBudget) }
        catch { throw Failure.malformed }
        return result
    }

    private static func inertImports(_ value: StrictJSON.Value) throws -> [InertPortableSetting] {
        let rows = try value.array()
        guard rows.count <= 1_000 else { throw Failure.malformed }
        for row in rows {
            let object = try row.object()
            guard Set(object.keys) == ["scope", "profileID", "id", "value", "valueKind",
                                       "valueDigest", "redacted"] else { throw Failure.malformed }
            switch try required(object, "value") {
            case .null: break
            case .object(let value):
                guard value.count == 1, let tag = value.keys.first,
                      ["bool", "integer", "null"].contains(tag) else {
                    throw Failure.malformed
                }
            default: throw Failure.malformed
            }
            if case .string(let text) = try required(object, "profileID") {
                guard let id = UUID(uuidString: text), text == id.uuidString else {
                    throw Failure.malformed
                }
            }
        }
        do {
            return try JSONDecoder().decode([InertPortableSetting].self,
                from: StrictJSON.canonicalData(.array(rows)))
        } catch { throw Failure.malformed }
    }

    private static func policyValues(_ value: StrictJSON.Value) throws -> PolicyValues {
        let root = try value.object()
        guard Set(root.keys) == ["fields"] else { throw Failure.malformed }
        let encodedFields = try required(root, "fields").object()
        let fields = try Dictionary(uniqueKeysWithValues: encodedFields.map {
            (SettingID(rawValue: $0.key), try settingValue($0.value))
        })
        return PolicyValues(fields: fields)
    }

    private static func settingValue(_ value: StrictJSON.Value) throws -> SettingValue {
        let object = try value.object()
        guard object.count == 1, let (tag, payload) = object.first else { throw Failure.malformed }
        switch tag {
        case "bool": return .bool(try payload.bool())
        case "integer": return .integer(try payload.signedInteger())
        case "choice": return .choice(try payload.string())
        case "strings": return .strings(try payload.strings())
        case "null": guard try payload.bool() else { throw Failure.malformed }; return .null
        case "volume":
            let fields = try payload.object()
            guard Set(fields.keys) == ["target", "warning", "clear"] else { throw Failure.malformed }
            return .volume(VolumeOverride(target: try volumeField(required(fields, "target")),
                warning: try volumeField(required(fields, "warning")),
                clear: try volumeField(required(fields, "clear"))))
        default: throw Failure.malformed
        }
    }

    private static func volumeField(_ value: StrictJSON.Value) throws -> VolumeField {
        let object = try value.object()
        guard object.count == 1, let (tag, payload) = object.first else { throw Failure.malformed }
        switch tag {
        case "inherit": guard try payload.bool() else { throw Failure.malformed }; return .inherit
        case "automatic": guard try payload.bool() else { throw Failure.malformed }; return .automatic
        case "fixedGiB": return .fixedGiB(try payload.signedInteger())
        default: throw Failure.malformed
        }
    }
}
