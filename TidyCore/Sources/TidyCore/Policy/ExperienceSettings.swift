import Foundation

public struct PolicyValues: Equatable, Codable, Sendable {
    public var fields: [SettingID: SettingValue]
    public init(fields: [SettingID: SettingValue] = [:]) { self.fields = fields }
}

public struct SavedProfile: Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var values: PolicyValues

    public init(id: UUID, name: String, values: PolicyValues) {
        self.id = id
        self.name = name
        self.values = values
    }
}

public struct PolicyPreferences: Equatable, Codable, Sendable {
    public var global: PolicyValues
    public var profiles: [SavedProfile]
    public var projects: [String: PolicyValues]

    public init(global: PolicyValues = .init(), profiles: [SavedProfile] = [],
                projects: [String: PolicyValues] = [:]) {
        self.global = global
        self.profiles = profiles
        self.projects = projects
    }

    public static func project(legacy: TidyConfig, saved: PolicyPreferences?) -> PolicyPreferences {
        var result = saved ?? PolicyPreferences()
        func fill(_ id: String, _ value: SettingValue) {
            let key = SettingID(rawValue: id)
            if result.global.fields[key] == nil { result.global.fields[key] = value }
        }
        if legacy.transcriptAgeThresholdDays != 45 {
            fill("cleanup.transcriptDays", .integer(Int64(legacy.transcriptAgeThresholdDays)))
        }
        if legacy.staleNodeModulesThresholdDays != 60 {
            fill("item.normal.extras.stale-node-modules.inactiveDays", .integer(Int64(legacy.staleNodeModulesThresholdDays)))
        }
        if !legacy.keepCookieDomains.isEmpty {
            fill("browsers.keepCookieDomains", .strings(legacy.keepCookieDomains))
        }
        if legacy.allowRestartToReclaimSwap {
            fill("rescue.showAdvancedMemoryActions", .bool(true))
        }
        return result
    }

    public mutating func selectPreset(_ preset: String, profileID: UUID? = nil) throws {
        let id = SettingID(rawValue: "scan.preset")
        guard ["eco", "balanced", "custom"].contains(preset) else {
            throw PolicyFieldError(id: id, reason: .outOfRange)
        }
        if let profileID {
            guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
                throw PolicyFieldError(id: id, reason: .invalidIdentity)
            }
            profiles[index].values.fields[id] = .choice(preset)
        } else {
            global.fields[id] = .choice(preset)
        }
    }
}

enum ExperienceSettings {
    static let budgetIDs = ["apple-derived-data", "apple-simulators", "android", "docker", "package-caches", "models", "ides", "git", "data", "other"]

    static var rows: [SettingDefinition] {
        let global: Set<PolicyLayer> = [.global, .profile]
        var result: [SettingDefinition] = [
            row("rescue.approvedApplications", .localIdentityList, .strings([]), .identityList, .authority, .consent, [], "rescue"),
            row("rescue.showAdvancedMemoryActions", .bool, .bool(false), .boolean, .preference, .invalidate, global, "rescue"),
            row("rescue.quitTimeoutSeconds", .integer, .integer(15), .integer(5, 60), .preference, .invalidate, global, "rescue")
        ]
        for budget in budgetIDs {
            result.append(row("budget.\(budget).enabled", .bool, .bool(false), .boolean, .restriction, .invalidate, global, "budget"))
        }
        let highs: [String: Int64] = ["apple-derived-data": 15, "apple-simulators": 25,
                                      "docker": 30, "package-caches": 10, "models": 50]
        for budget in budgetIDs {
            result.append(row("budget.\(budget).highGiB", .optionalInteger,
                              highs[budget].map(SettingValue.integer) ?? .null, .budgetHigh,
                              .preference, .invalidate, global, "budget"))
        }
        for budget in budgetIDs {
            result.append(row("budget.\(budget).lowGiB", .optionalInteger, .null, .budgetLow,
                              .preference, .invalidate, global, "budget"))
        }
        result += [
            row("notifications.enabled", .bool, .bool(false), .boolean, .authority, .consent, [], "notifications"),
            row("notifications.pressureSustainSeconds", .integer, .integer(60), .integer(30, 600), .preference, .none, global, "notifications"),
            row("notifications.recoverySeconds", .integer, .integer(120), .integer(60, 900), .preference, .none, global, "notifications"),
            row("notifications.cooldownMinutes", .integer, .integer(60), .integer(15, 1_440), .preference, .none, global, "notifications"),
            row("notifications.quietHoursEnabled", .bool, .bool(false), .boolean, .preference, .none, global, "notifications"),
            row("notifications.quietStart", .clock, .choice("22:00"), .clock, .preference, .none, global, "notifications"),
            row("notifications.quietEnd", .clock, .choice("08:00"), .quietEnd, .preference, .none, global, "notifications"),
            row("maintenance.mode", .choice, .choice("off"), .choices(["off", "notifyOnly", "authorizedCaches"]), .authority, .consent, [], "maintenance"),
            row("maintenance.maxGiB", .integer, .integer(1), .integer(1, 5), .authority, .consent, [], "maintenance"),
            row("maintenance.maxItems", .integer, .integer(5), .integer(1, 20), .authority, .consent, [], "maintenance"),
            row("maintenance.deadlineSeconds", .integer, .integer(60), .integer(30, 120), .authority, .consent, [], "maintenance"),
            row("maintenance.minimumAgeDays", .integer, .integer(30), .integer(30, 365), .authority, .consent, [], "maintenance"),
            row("maintenance.minimumIntervalHours", .integer, .integer(24), .integer(24, 168), .authority, .consent, [], "maintenance"),
            row("app.launchAtLogin", .bool, .bool(false), .boolean, .authority, .consent, [], "experience"),
            row("history.enabled", .bool, .bool(true), .boolean, .preference, .none, global, "history"),
            row("history.retentionDays", .integer, .integer(30), .integer(1, 90), .preference, .none, global, "history"),
            row("history.maxMiB", .integer, .integer(10), .integer(1, 50), .preference, .none, global, "history"),
            row("ui.density", .choice, .choice("compact"), .choices(["compact", "detailed"]), .preference, .none, global, "ui"),
            row("ui.units", .choice, .choice("binary"), .choices(["binary", "decimal"]), .preference, .none, global, "ui"),
            row("ui.cards", .orderedIDs, .strings(["disk", "memoryPressure", "swap", "thermal", "power"]), .cards, .preference, .none, global, "ui"),
            row("ui.ecosystemOrder", .orderedIDs, .strings(FeatureSettings.ecosystemIDs), .ecosystemOrder, .preference, .none, global, "ui"),
            row("ui.showBadges", .bool, .bool(true), .boolean, .preference, .none, global, "ui"),
            row("ui.advancedSettings", .bool, .bool(false), .boolean, .preference, .none, global, "ui"),
            row("export.redactDiagnostics", .bool, .bool(true), .boolean, .preference, .none, global, "data")
        ]
        return result
    }
}
