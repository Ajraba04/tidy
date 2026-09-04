import Foundation

public struct SettingID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum PolicyLayer: String, Codable, CaseIterable, Hashable, Sendable {
    case global, profile, project, run
}

public enum ResolutionClass: String, Codable, Sendable {
    case preference, restriction, authority
}

public enum AuthorityEffect: String, Codable, Sendable {
    case none, invalidate, consent
}

public enum SettingValue: Equatable, Codable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case choice(String)
    case strings([String])
    case null
    case volume(VolumeOverride)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PolicyCodingKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "A setting value requires exactly one tagged case"))
        }
        switch key.stringValue {
        case "bool": self = .bool(try container.decode(Bool.self, forKey: key))
        case "integer": self = .integer(try container.decode(Int64.self, forKey: key))
        case "choice": self = .choice(try container.decode(String.self, forKey: key))
        case "strings": self = .strings(try container.decode([String].self, forKey: key))
        case "null":
            guard try container.decode(Bool.self, forKey: key) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container,
                    debugDescription: "The null tag must be true")
            }
            self = .null
        case "volume": self = .volume(try container.decode(VolumeOverride.self, forKey: key))
        default:
            throw DecodingError.dataCorruptedError(forKey: key, in: container,
                debugDescription: "Unknown setting value tag")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PolicyCodingKey.self)
        switch self {
        case .bool(let value): try container.encode(value, forKey: .init("bool"))
        case .integer(let value): try container.encode(value, forKey: .init("integer"))
        case .choice(let value): try container.encode(value, forKey: .init("choice"))
        case .strings(let value): try container.encode(value, forKey: .init("strings"))
        case .null: try container.encode(true, forKey: .init("null"))
        case .volume(let value): try container.encode(value, forKey: .init("volume"))
        }
    }
}

struct PolicyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

public enum ValueKind: String, Codable, Sendable {
    case bool, integer, optionalInteger, choice, orderedIDs, setIDs, domains
    case optionalProjectID, volumeOverride, localIdentityList, clock
}

public enum Rule: Equatable, Codable, Sendable {
    case boolean
    case integer(Int64, Int64)
    case optionalInteger(Int64, Int64)
    case choices([String])
    case identityList
    case domains
    case projectID
    case exclusions
    case pins
    case headroomTarget
    case headroomWarning
    case headroomClear
    case volumeOverride
    case budgetHigh
    case budgetLow
    case cards
    case ecosystemOrder
    case clock
    case quietEnd
}

public struct SettingDefinition: Equatable, Sendable {
    public let id: SettingID
    public let kind: ValueKind
    public let defaultValue: SettingValue
    public let rule: Rule
    public let resolution: ResolutionClass
    public let effect: AuthorityEffect
    public let layers: Set<PolicyLayer>
    public let group: String

    public init(id: SettingID, kind: ValueKind, defaultValue: SettingValue, rule: Rule,
                resolution: ResolutionClass, effect: AuthorityEffect,
                layers: Set<PolicyLayer>, group: String) {
        self.id = id
        self.kind = kind
        self.defaultValue = defaultValue
        self.rule = rule
        self.resolution = resolution
        self.effect = effect
        self.layers = layers
        self.group = group
    }
}

enum FeatureSettings {
    static let featureIDs = ["headroom", "buildPrep", "projects", "rescue", "ecosystems", "budgets", "history"]
    static let ecosystemIDs = ["apple", "android", "node", "languages", "homebrew", "docker", "ides", "models", "git", "data"]

    static var rows: [SettingDefinition] {
        var result = featureIDs.map {
            row("feature.\($0)", .bool, .bool(true), .boolean, .restriction, .invalidate, [.global, .profile], "features")
        }
        result.append(row("feature.maintenance", .bool, .bool(false), .boolean, .restriction, .invalidate,
                          [.global, .profile], "features"))
        for ecosystem in ecosystemIDs {
            result.append(row("ecosystem.\(ecosystem).inventory", .bool, .bool(true), .boolean,
                              .restriction, .invalidate, [.global, .profile], "features"))
            result.append(row("ecosystem.\(ecosystem).manualActions", .bool, .bool(false), .boolean,
                              .restriction, .invalidate, [.global, .profile], "features"))
        }
        result += [
            row("scope.projectRoots", .localIdentityList, .strings([]), .identityList, .authority, .consent, [], "scope"),
            row("scope.externalVolumes", .localIdentityList, .strings([]), .identityList, .authority, .consent, [], "scope"),
            row("browsers.keepCookieDomains", .domains, .strings([]), .domains, .restriction, .invalidate,
                [.global, .profile], "browsers"),
            row("simulators.approvedDeletionUDIDs", .localIdentityList, .strings([]), .identityList, .authority, .consent, [], "simulators"),
            row("tools.approvedExecutables", .localIdentityList, .strings([]), .identityList, .authority, .consent, [], "tools"),
            row("docker.approvedEndpoints", .localIdentityList, .strings([]), .identityList, .authority, .consent, [], "docker")
        ]
        return result
    }

    static func itemRows(catalogID: String) -> [SettingDefinition] {
        [
            row("item.\(catalogID).enabled", .bool, .bool(true), .boolean, .restriction, .invalidate,
                [.global, .profile], "cleanup"),
            row("item.\(catalogID).inactiveDays", .optionalInteger, .null, .optionalInteger(7, 365),
                .preference, .invalidate, Set(PolicyLayer.allCases), "cleanup"),
            row("item.\(catalogID).minimumItemMiB", .optionalInteger, .null, .optionalInteger(0, 102_400),
                .preference, .invalidate, Set(PolicyLayer.allCases), "cleanup"),
            row("item.\(catalogID).retainRecentArtifacts", .optionalInteger, .null, .optionalInteger(0, 100),
                .preference, .invalidate, Set(PolicyLayer.allCases), "cleanup")
        ]
    }
}

func row(_ id: String, _ kind: ValueKind, _ defaultValue: SettingValue, _ rule: Rule,
         _ resolution: ResolutionClass, _ effect: AuthorityEffect,
         _ layers: Set<PolicyLayer>, _ group: String) -> SettingDefinition {
    SettingDefinition(id: SettingID(rawValue: id), kind: kind, defaultValue: defaultValue,
                      rule: rule, resolution: resolution, effect: effect, layers: layers, group: group)
}
