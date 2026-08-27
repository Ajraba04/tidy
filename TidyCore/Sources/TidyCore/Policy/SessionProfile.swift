import Foundation

public enum RestrictionRelation: Equatable, Sendable {
    case equal, stricter, weaker
}

public enum SessionProfileError: Error, Equatable, Sendable {
    case duplicateID(UUID), missingProfile(UUID), invalidName, tooManyProfiles
    case invalidFactory(String), nonProfileField(SettingID)
    case protectionWeakening(SettingID), restrictionResetRequiresPreview(SettingID)
    case notRestriction(SettingID)
    case profileIdentityMismatch(expected: UUID, actual: UUID)
}

public enum PolicyRestrictionValidator {
    public static var coveredSettingIDs: Set<SettingID> {
        Set(restrictionDefinitions.map(\.id))
    }

    public static func relation(candidate: SettingValue, baseline: SettingValue,
                                for id: SettingID) throws -> RestrictionRelation {
        guard let definition = PolicyValidator.definition(for: id) else {
            throw PolicyFieldError(id: id, reason: .unknownKey)
        }
        guard definition.resolution == .restriction else {
            throw SessionProfileError.notRestriction(id)
        }
        try PolicyValidator.validateStructure(
            PolicyValues(fields: [id: candidate]), at: validationLayer(for: definition))
        try PolicyValidator.validateStructure(
            PolicyValues(fields: [id: baseline]), at: validationLayer(for: definition))
        return try relation(candidate: candidate, baseline: baseline, definition: definition)
    }

    public static func validate(_ proposed: PolicyValues, inherited: PolicyValues,
                                at layer: PolicyLayer) throws {
        try PolicyValidator.validateStructure(proposed, at: layer)
        for (id, candidate) in proposed.fields {
            guard let definition = PolicyValidator.definition(for: id) else {
                throw PolicyFieldError(id: id, reason: .unknownKey)
            }
            guard definition.resolution == .restriction else { continue }
            let baseline = inherited.fields[id] ?? definition.defaultValue
            if try relation(candidate: candidate, baseline: baseline, for: id) == .weaker {
                throw SessionProfileError.protectionWeakening(id)
            }
        }
    }

    static func relation(candidate: SettingValue, baseline: SettingValue,
                         definition: SettingDefinition) throws -> RestrictionRelation {
        guard definition.resolution == .restriction else {
            throw SessionProfileError.notRestriction(definition.id)
        }
        switch definition.rule {
        case .boolean:
            guard case .bool(let candidateValue) = candidate,
                  case .bool(let baselineValue) = baseline else {
                throw PolicyFieldError(id: definition.id, reason: .invalidType)
            }
            guard candidateValue != baselineValue else { return .equal }
            if definition.id.rawValue == "monitor.suppressHiddenSampling" {
                return candidateValue ? .stricter : .weaker
            }
            return candidateValue ? .weaker : .stricter

        case .choices:
            guard definition.id.rawValue == "scan.onLowPower" ||
                    definition.id.rawValue == "scan.onSeriousThermal",
                  case .choice(let candidateValue) = candidate,
                  case .choice(let baselineValue) = baseline else {
                throw PolicyFieldError(id: definition.id, reason: .invalidType)
            }
            guard candidateValue != baselineValue else { return .equal }
            return candidateValue == "pauseAll" ? .stricter : .weaker

        case .exclusions, .pins, .domains:
            guard case .strings(let candidateValues) = candidate,
                  case .strings(let baselineValues) = baseline else {
                throw PolicyFieldError(id: definition.id, reason: .invalidType)
            }
            let candidateSet = Set(candidateValues)
            let baselineSet = Set(baselineValues)
            if candidateSet == baselineSet { return .equal }
            return candidateSet.isSuperset(of: baselineSet) ? .stricter : .weaker

        case .optionalInteger:
            switch (candidate, baseline) {
            case (.null, .null): return .equal
            case (.integer, .null): return .stricter
            case (.null, .integer): return .weaker
            case (.integer(let candidateValue), .integer(let baselineValue)):
                if candidateValue == baselineValue { return .equal }
                return candidateValue < baselineValue ? .stricter : .weaker
            default:
                throw PolicyFieldError(id: definition.id, reason: .invalidType)
            }

        default:
            throw PolicyFieldError(id: definition.id, reason: .invalidType)
        }
    }

    private static var restrictionDefinitions: [SettingDefinition] {
        (PolicyDefaults.rows + CleanCatalog.allItems.flatMap {
            PolicyDefaults.itemRows(catalogID: $0.id)
        }).filter { $0.resolution == .restriction }
    }

    private static func validationLayer(for definition: SettingDefinition) -> PolicyLayer {
        if definition.layers.contains(.profile) { return .profile }
        if definition.layers.contains(.global) { return .global }
        if definition.layers.contains(.project) { return .project }
        return .run
    }
}

public enum ProfileValueSource: Equatable, Sendable {
    case explicit, inherited, registryDefault
}

public struct ProfileFieldDiff: Equatable, Sendable {
    public let id: SettingID
    public let oldValue: SettingValue?
    public let newValue: SettingValue?
    public let defaultValue: SettingValue
    public let resolution: ResolutionClass
    public let effect: AuthorityEffect
    public let rule: Rule
    public let oldSource: ProfileValueSource
    public let newSource: ProfileValueSource

    public init(id: SettingID, oldValue: SettingValue?, newValue: SettingValue?,
                defaultValue: SettingValue, resolution: ResolutionClass,
                effect: AuthorityEffect, rule: Rule, oldSource: ProfileValueSource,
                newSource: ProfileValueSource) {
        self.id = id
        self.oldValue = oldValue
        self.newValue = newValue
        self.defaultValue = defaultValue
        self.resolution = resolution
        self.effect = effect
        self.rule = rule
        self.oldSource = oldSource
        self.newSource = newSource
    }
}

public struct ProfileResetPreview: Equatable, Sendable {
    public let profileID: UUID
    public let base: SavedProfile
    public let candidate: SavedProfile
    public let changes: [ProfileFieldDiff]

    public init(profileID: UUID, base: SavedProfile, candidate: SavedProfile,
                changes: [ProfileFieldDiff]) {
        self.profileID = profileID
        self.base = base
        self.candidate = candidate
        self.changes = changes
    }
}

public enum SessionProfiles {
    public static let maximumCount = 50
    public static let factoryKeys = ["xcode", "android", "flutter", "web", "localAI", "battery"]

    public static func create(id: UUID, name: String, values: PolicyValues,
                              inherited: PolicyValues,
                              in profiles: [SavedProfile]) throws -> [SavedProfile] {
        try validateCollection(profiles, inherited: inherited)
        if profiles.contains(where: { $0.id == id }) { throw SessionProfileError.duplicateID(id) }
        guard profiles.count < maximumCount else { throw SessionProfileError.tooManyProfiles }
        let profile = SavedProfile(id: id, name: try normalizedName(name), values: values)
        try validateProfile(profile, inherited: inherited)
        return profiles + [profile]
    }

    public static func clone(sourceID: UUID, newID: UUID, name: String,
                             inherited: PolicyValues,
                             in profiles: [SavedProfile]) throws -> [SavedProfile] {
        try validateCollection(profiles, inherited: inherited)
        guard let source = profiles.first(where: { $0.id == sourceID }) else {
            throw SessionProfileError.missingProfile(sourceID)
        }
        if profiles.contains(where: { $0.id == newID }) {
            throw SessionProfileError.duplicateID(newID)
        }
        guard profiles.count < maximumCount else { throw SessionProfileError.tooManyProfiles }
        let profile = SavedProfile(id: newID, name: try normalizedName(name), values: source.values)
        try validateProfile(profile, inherited: inherited)
        return profiles + [profile]
    }

    public static func createFactory(key: String, id: UUID, name: String,
                                     inherited: PolicyValues,
                                     in profiles: [SavedProfile]) throws -> [SavedProfile] {
        try validateCollection(profiles, inherited: inherited)
        guard factoryKeys.contains(key) else { throw SessionProfileError.invalidFactory(key) }
        return try createFactory(key: key, id: id, name: name, inherited: inherited,
                                 in: profiles, provider: PolicyDefaults.factory)
    }

    static func createFactory(key: String, id: UUID, name: String,
                              inherited: PolicyValues, in profiles: [SavedProfile],
                              provider: (String) throws -> PolicyValues) throws -> [SavedProfile] {
        try validateCollection(profiles, inherited: inherited)
        if profiles.contains(where: { $0.id == id }) { throw SessionProfileError.duplicateID(id) }
        guard profiles.count < maximumCount else { throw SessionProfileError.tooManyProfiles }
        let normalized = try normalizedName(name)
        let values: PolicyValues
        do { values = try provider(key) }
        catch { throw SessionProfileError.invalidFactory(key) }
        let profile = SavedProfile(id: id, name: normalized, values: values)
        try validateProfile(profile, inherited: inherited)
        return profiles + [profile]
    }

    public static func rename(id: UUID, name: String, inherited: PolicyValues,
                              in profiles: [SavedProfile]) throws -> [SavedProfile] {
        try validateCollection(profiles, inherited: inherited)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw SessionProfileError.missingProfile(id)
        }
        var result = profiles
        result[index].name = try normalizedName(name)
        try validateProfile(result[index], inherited: inherited)
        return result
    }

    public static func delete(id: UUID, inherited: PolicyValues,
                              in profiles: [SavedProfile]) throws -> [SavedProfile] {
        try validateCollection(profiles, inherited: inherited)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw SessionProfileError.missingProfile(id)
        }
        var result = profiles
        result.remove(at: index)
        return result
    }

    public static func diff(base: SavedProfile, candidate: SavedProfile,
                            inherited: PolicyValues) throws -> [ProfileFieldDiff] {
        guard base.id == candidate.id else {
            throw SessionProfileError.profileIdentityMismatch(expected: base.id, actual: candidate.id)
        }
        try validateProfile(base, inherited: inherited)
        try validateProfile(candidate, inherited: inherited)
        let ids = Set(base.values.fields.keys).union(candidate.values.fields.keys)
        return try ids.compactMap { id in
            let oldValue = base.values.fields[id]
            let newValue = candidate.values.fields[id]
            guard oldValue != newValue else { return nil }
            guard let definition = PolicyValidator.definition(for: id) else {
                throw PolicyFieldError(id: id, reason: .unknownKey)
            }
            return ProfileFieldDiff(id: id, oldValue: oldValue, newValue: newValue,
                defaultValue: definition.defaultValue, resolution: definition.resolution,
                effect: definition.effect, rule: definition.rule,
                oldSource: source(for: oldValue, id: id, inherited: inherited),
                newSource: source(for: newValue, id: id, inherited: inherited))
        }.sorted { utf8Less($0.id.rawValue, $1.id.rawValue) }
    }

    public static func previewReset(id: UUID, fieldIDs: Set<SettingID>,
                                    includeOwnedRestrictions: Bool,
                                    inherited: PolicyValues,
                                    in profiles: [SavedProfile]) throws -> ProfileResetPreview {
        try validateCollection(profiles, inherited: inherited)
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw SessionProfileError.missingProfile(id)
        }
        if fieldIDs.isEmpty {
            return ProfileResetPreview(profileID: id, base: profile, candidate: profile, changes: [])
        }
        for fieldID in fieldIDs.sorted(by: { utf8Less($0.rawValue, $1.rawValue) }) {
            guard profile.values.fields[fieldID] != nil else {
                throw SessionProfileError.nonProfileField(fieldID)
            }
            guard let definition = PolicyValidator.definition(for: fieldID) else {
                throw PolicyFieldError(id: fieldID, reason: .unknownKey)
            }
            if definition.resolution == .restriction && !includeOwnedRestrictions {
                throw SessionProfileError.restrictionResetRequiresPreview(fieldID)
            }
        }
        var candidate = profile
        for fieldID in fieldIDs { candidate.values.fields.removeValue(forKey: fieldID) }
        try validateProfile(candidate, inherited: inherited)
        return ProfileResetPreview(profileID: id, base: profile, candidate: candidate,
            changes: try diff(base: profile, candidate: candidate, inherited: inherited))
    }

    private static func validateCollection(_ profiles: [SavedProfile],
                                           inherited: PolicyValues) throws {
        var ids = Set<UUID>()
        for profile in profiles where !ids.insert(profile.id).inserted {
            throw SessionProfileError.duplicateID(profile.id)
        }
        guard profiles.count <= maximumCount else { throw SessionProfileError.tooManyProfiles }
        for profile in profiles { try validateProfile(profile, inherited: inherited) }
    }

    private static func validateProfile(_ profile: SavedProfile,
                                        inherited: PolicyValues) throws {
        guard try normalizedName(profile.name) == profile.name else {
            throw SessionProfileError.invalidName
        }
        try PolicyRestrictionValidator.validate(profile.values, inherited: inherited, at: .profile)
        for id in profile.values.fields.keys {
            guard let definition = PolicyValidator.definition(for: id) else {
                throw PolicyFieldError(id: id, reason: .unknownKey)
            }
            if definition.kind == .volumeOverride || definition.kind == .optionalProjectID {
                throw SessionProfileError.nonProfileField(id)
            }
        }
    }

    private static func normalizedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 4_096 else {
            throw SessionProfileError.invalidName
        }
        return trimmed
    }

    private static func source(for value: SettingValue?, id: SettingID,
                               inherited: PolicyValues) -> ProfileValueSource {
        if value != nil { return .explicit }
        return inherited.fields[id] == nil ? .registryDefault : .inherited
    }

    private static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}
