import Foundation

public enum ImmutableLimit: String, Hashable, Sendable {
    case manualGiB, manualItems, automaticGiB, automaticItems, walkWorkers, commandJobs, rawHistoryMiB
}

public enum PolicyDefaults {
    public static var rows: [SettingDefinition] {
        FeatureSettings.rows + CleanupSettings.rows + ScanSettings.rows + ExperienceSettings.rows
    }

    public static var hardLimits: [ImmutableLimit: Int64] {
        [.manualGiB: 100, .manualItems: 100, .automaticGiB: 5, .automaticItems: 20,
         .walkWorkers: 4, .commandJobs: 2, .rawHistoryMiB: 5]
    }

    public static func itemRows(catalogID: String) -> [SettingDefinition] {
        let known = Set(CleanCatalog.allItems.map(\.id))
        guard known.contains(catalogID) else { return [] }
        return FeatureSettings.itemRows(catalogID: catalogID)
    }

    public static func volumeRow(id: UUID) -> SettingDefinition {
        CleanupSettings.volumeRow(id: id)
    }

    public static func factory(_ template: String) throws -> PolicyValues {
        let order = FeatureSettings.ecosystemIDs
        func reordered(_ first: [String]) -> SettingValue {
            .strings(first + order.filter { !first.contains($0) })
        }
        func profile(target: Int64, first: [String], includesCost: Bool) -> PolicyValues {
            var fields: [SettingID: SettingValue] = [
                SettingID(rawValue: "headroom.targetGiB"): .integer(target),
                SettingID(rawValue: "scan.preset"): .choice("eco"),
                SettingID(rawValue: "scan.requestedWorkers"): .integer(1),
                SettingID(rawValue: "scan.readOnlyProcesses"): .integer(1),
                SettingID(rawValue: "ui.ecosystemOrder"): reordered(first)
            ]
            if includesCost {
                fields[SettingID(rawValue: "cleanup.costCeiling")] = .choice("low")
                fields[SettingID(rawValue: "cleanup.warmProjectCount")] = .integer(5)
            }
            return PolicyValues(fields: fields)
        }
        switch template {
        case "xcode": return profile(target: 15, first: ["apple"], includesCost: true)
        case "android": return profile(target: 20, first: ["android"], includesCost: true)
        case "flutter": return profile(target: 20, first: ["android", "apple"], includesCost: true)
        case "web": return profile(target: 5, first: ["node"], includesCost: true)
        case "localAI": return profile(target: 30, first: ["models"], includesCost: false)
        case "battery":
            return PolicyValues(fields: [
                SettingID(rawValue: "scan.preset"): .choice("eco"),
                SettingID(rawValue: "scan.requestedWorkers"): .integer(1),
                SettingID(rawValue: "scan.readOnlyProcesses"): .integer(1),
                SettingID(rawValue: "scan.onLowPower"): .choice("pauseAll"),
                SettingID(rawValue: "monitor.suppressHiddenSampling"): .bool(true),
                SettingID(rawValue: "scan.defaultScope"): .choice("quick")
            ])
        default:
            throw PolicyFieldError(id: SettingID(rawValue: "factory.\(template)"), reason: .unknownKey)
        }
    }
}
