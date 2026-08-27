import Foundation

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

    public init(schemaVersion: Int, revision: UInt64, config: TidyConfig,
                preferences: PolicyPreferences? = nil) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.config = config
        self.preferences = preferences
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
    internal let identity: UUID

    internal init(config: TidyConfig, preferences: PolicyPreferences? = nil, identity: UUID) {
        self.config = config
        self.preferences = preferences
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
        var parser = SettingsJSON(bytes: Array(bytes))
        let root = try parser.parse().object()
        guard Set(root.keys) == ["schema", "storeID"],
              try required(root, "schema").integer() == 1,
              let id = UUID(uuidString: try required(root, "storeID").string()) else {
            throw Failure.malformed
        }
        return id
    }

    static func load(_ data: Data) throws -> SettingsLoadResult {
        guard data.count <= byteLimit else { throw Failure.oversized }
        guard String(data: data, encoding: .utf8) != nil else { throw Failure.malformed }
        var parser = SettingsJSON(bytes: Array(data))
        let root = try parser.parse().object()
        let version = try required(root, "schemaVersion").integer()
        guard version == 1 || version == 2 else { throw Failure.unsupportedSchema(version) }
        if version == 1 {
            return SettingsLoadResult(disposition: .migrated,
                envelope: SettingsEnvelope(schemaVersion: 2, revision: 0,
                    config: try config(root, legacy: true)), recoveryReason: nil)
        }
        let keys = Set(root.keys)
        guard keys == ["schemaVersion", "revision", "config"] ||
              keys == ["schemaVersion", "revision", "config", "preferences"] else {
            throw Failure.malformed
        }
        let revision = try required(root, "revision").unsignedInteger()
        let decodedPreferences = try root["preferences"].map(preferences)
        return SettingsLoadResult(disposition: .loaded,
            envelope: SettingsEnvelope(schemaVersion: 2, revision: revision,
                config: try config(required(root, "config").object(), legacy: false),
                preferences: decodedPreferences), recoveryReason: nil)
    }

    private static func required(_ object: [String: SettingsJSON.Value], _ key: String) throws -> SettingsJSON.Value {
        guard let value = object[key] else { throw Failure.malformed }
        return value
    }

    private static func config(_ object: [String: SettingsJSON.Value], legacy: Bool) throws -> TidyConfig {
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

    private static func preferences(_ value: SettingsJSON.Value) throws -> PolicyPreferences {
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

    private static func policyValues(_ value: SettingsJSON.Value) throws -> PolicyValues {
        let root = try value.object()
        guard Set(root.keys) == ["fields"] else { throw Failure.malformed }
        let encodedFields = try required(root, "fields").object()
        let fields = try Dictionary(uniqueKeysWithValues: encodedFields.map {
            (SettingID(rawValue: $0.key), try settingValue($0.value))
        })
        return PolicyValues(fields: fields)
    }

    private static func settingValue(_ value: SettingsJSON.Value) throws -> SettingValue {
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

    private static func volumeField(_ value: SettingsJSON.Value) throws -> VolumeField {
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

/// Keeps token types and duplicate decoded keys intact before any model is decoded.
/// Foundation's dictionary deserialization alone would silently discard duplicate keys.
private struct SettingsJSON {
    indirect enum Value {
        case object([String: Value]), array([Value]), string(String), number(String), bool(Bool), null
        func object() throws -> [String: Value] {
            guard case .object(let value) = self else { throw SettingsDecoding.Failure.malformed }; return value
        }
        func array() throws -> [Value] {
            guard case .array(let value) = self else { throw SettingsDecoding.Failure.malformed }; return value
        }
        func string() throws -> String {
            guard case .string(let value) = self else { throw SettingsDecoding.Failure.malformed }; return value
        }
        func strings() throws -> [String] { try array().map { try $0.string() } }
        func bool() throws -> Bool {
            guard case .bool(let value) = self else { throw SettingsDecoding.Failure.malformed }; return value
        }
        func integer() throws -> Int {
            guard case .number(let text) = self, let value = Int(text) else { throw SettingsDecoding.Failure.malformed }
            return value
        }
        func signedInteger() throws -> Int64 {
            guard case .number(let text) = self, let value = Int64(text) else {
                throw SettingsDecoding.Failure.malformed
            }
            return value
        }
        func unsignedInteger() throws -> UInt64 {
            guard case .number(let text) = self, let value = UInt64(text) else { throw SettingsDecoding.Failure.malformed }
            return value
        }
    }
    let bytes: [UInt8]
    private var index = 0
    init(bytes: [UInt8]) { self.bytes = bytes }
    mutating func parse() throws -> Value {
        let result = try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw SettingsDecoding.Failure.malformed }
        return result
    }
    private mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
    private mutating func value(depth: Int) throws -> Value {
        whitespace()
        guard index < bytes.count else { throw SettingsDecoding.Failure.malformed }
        switch bytes[index] {
        case 123:
            guard depth < 16 else { throw SettingsDecoding.Failure.malformed }
            index += 1
            var object: [String: Value] = [:]
            if consume(125) { return .object(object) }
            repeat {
                let key = try string()
                guard object[key] == nil, object.count < 1000, consume(58) else { throw SettingsDecoding.Failure.malformed }
                object[key] = try value(depth: depth + 1)
                if consume(125) { return .object(object) }
                guard consume(44) else { throw SettingsDecoding.Failure.malformed }
            } while true
        case 91:
            guard depth < 16 else { throw SettingsDecoding.Failure.malformed }
            index += 1
            var array: [Value] = []
            if consume(93) { return .array(array) }
            repeat {
                guard array.count < 1000 else { throw SettingsDecoding.Failure.malformed }
                array.append(try value(depth: depth + 1))
                if consume(93) { return .array(array) }
                guard consume(44) else { throw SettingsDecoding.Failure.malformed }
            } while true
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default: return .number(try number())
        }
    }
    private mutating func literal(_ text: String) throws {
        let expected = Array(text.utf8)
        guard bytes.count - index >= expected.count,
              Array(bytes[index..<index + expected.count]) == expected else { throw SettingsDecoding.Failure.malformed }
        index += expected.count
    }
    private mutating func string() throws -> String {
        whitespace()
        let start = index
        guard consume(34) else { throw SettingsDecoding.Failure.malformed }
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 {
                let result = try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                guard result.utf8.count <= 4096 else { throw SettingsDecoding.Failure.malformed }
                return result
            }
            if byte == 92 {
                guard index < bytes.count else { throw SettingsDecoding.Failure.malformed }
                index += 1 // JSONDecoder validates escapes and surrogate pairs in this token.
            } else if byte < 32 { throw SettingsDecoding.Failure.malformed }
        }
        throw SettingsDecoding.Failure.malformed
    }
    private mutating func number() throws -> String {
        let start = index
        if bytes[index] == 45 { index += 1 }
        guard index < bytes.count else { throw SettingsDecoding.Failure.malformed }
        if bytes[index] == 48 { index += 1 }
        else {
            guard (49...57).contains(bytes[index]) else { throw SettingsDecoding.Failure.malformed }
            digits()
        }
        var integral = true
        if index < bytes.count, bytes[index] == 46 {
            integral = false; index += 1
            let fractionStart = index; digits()
            guard index > fractionStart else { throw SettingsDecoding.Failure.malformed }
        }
        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            integral = false; index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            let exponentStart = index; digits()
            guard index > exponentStart else { throw SettingsDecoding.Failure.malformed }
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if integral {
            guard text.hasPrefix("-") ? Int64(text) != nil : UInt64(text) != nil else { throw SettingsDecoding.Failure.malformed }
        } else {
            guard let value = Double(text), value.isFinite else { throw SettingsDecoding.Failure.malformed }
        }
        return text
    }
    private mutating func digits() {
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
    }
}
