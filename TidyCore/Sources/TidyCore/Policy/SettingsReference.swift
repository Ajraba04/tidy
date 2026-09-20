import Foundation

public enum SettingConsumerSupport: Equatable, Sendable {
    case connected(String)
    case unavailable(String)

    public var summary: String {
        switch self {
        case .connected(let consumer): return "Available: " + consumer
        case .unavailable(let reason): return "Unavailable: " + reason
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

public extension SettingsPresentationRegistry {
    static func consumerSupport(for definition: SettingDefinition) -> SettingConsumerSupport {
        let raw = definition.id.rawValue
        if definition.resolution == .authority {
            if raw == "monitor.backgroundEnabled" {
                return .unavailable("Local background-monitor consent is not implemented.")
            }
            return .unavailable("A separately accepted machine-local authority workflow is not implemented.")
        }
        if raw == "feature.headroom" {
            return .connected("SystemMonitor and Headroom presentation")
        }
        if raw == "feature.history" || raw.hasPrefix("history.") {
            return .connected("Bounded optional completed-run history")
        }
        if ["feature.buildPrep", "feature.projects"].contains(raw)
            || raw == "scope.currentProject"
            || raw == "scope.pinnedProjects" {
            return .unavailable("R09 project inventory, ranking, and Build Prep are not implemented.")
        }
        if raw.hasPrefix("cleanup.") {
            return .unavailable("R02-R04 accepted cleanup effects and bounds, plus the relevant R09-R10 workflow consumer, are not implemented.")
        }
        if raw == "feature.ecosystems" || raw.hasPrefix("ecosystem.")
            || raw.hasPrefix("item.") || raw == "browsers.keepCookieDomains" {
            return .unavailable("R10 ecosystem adapter behavior is not implemented.")
        }
        if ["feature.rescue", "feature.budgets", "feature.maintenance"].contains(raw)
            || raw.hasPrefix("rescue.") || raw.hasPrefix("budget.")
            || raw.hasPrefix("notifications.") || raw.hasPrefix("maintenance.")
            || raw == "app.launchAtLogin" {
            return .unavailable("R11 notifications and assistance are not implemented.")
        }
        if raw.hasPrefix("scan.cache") {
            return .connected("App-owned incremental scan index")
        }
        if raw.hasPrefix("scan.") || raw == "scope.excludedRoots" {
            return .connected("Explicit scan scope and scheduler policy")
        }
        if raw.hasPrefix("monitor.") {
            return .connected("SystemMonitor sampling and bounded signal history")
        }
        if raw.hasPrefix("headroom.") {
            return .connected("Measured-volume Headroom target resolution")
        }
        if raw == "ui.units" || raw == "ui.cards" {
            return .connected("Headroom and menu bar presentation")
        }
        if raw == "ui.advancedSettings" {
            return .connected("Settings search and advanced-row visibility")
        }
        if raw.hasPrefix("ui.") {
            return .unavailable("This presentation preference has no application consumer.")
        }
        if raw == "export.redactDiagnostics" {
            return .unavailable("Metadata-only diagnostics are available; optional cosmetic redaction is not implemented.")
        }
        return .unavailable("No verified production consumer is registered for this setting.")
    }
}

public enum SettingsReferenceRenderer {
    public static func render() throws -> String {
        let settings = try SettingsPresentationRegistry.all(
            volumeIDs: [SettingsPresentationRegistry.validationVolumeID])
        var lines = [
            "# Settings reference",
            "",
            "Generated from the tested Tidy settings registry. MiB and GiB values use powers of 1024. An unavailable row remains part of the durable schema but its control is disabled until the named production consumer is accepted.",
            "",
            "| Stable ID | Default | Allowed values | Resolution / effect | Layers | Production consumer |",
            "|---|---|---|---|---|---|"
        ]
        for setting in settings {
            let definition = setting.definition
            let id = displayID(definition.id.rawValue)
            let columns = [id, describe(definition.defaultValue), describe(definition.rule),
                definition.resolution.rawValue + " / " + definition.effect.rawValue,
                layers(definition.layers),
                SettingsPresentationRegistry.consumerSupport(for: definition).summary]
            lines.append("|" + columns.map(escape).joined(separator: "|") + "|")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func displayID(_ raw: String) -> String {
        raw == "headroom.volumeOverrides." + SettingsPresentationRegistry.validationVolumeID.uuidString
            ? "headroom.volumeOverrides.<volumeID>" : raw
    }

    private static func describe(_ value: SettingValue) -> String {
        switch value {
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .choice(let value): return value
        case .strings(let values): return values.isEmpty ? "[]" : "[" + values.joined(separator: ", ") + "]"
        case .null: return "null / automatic"
        case .volume: return "inherit"
        }
    }

    private static func describe(_ rule: Rule) -> String {
        switch rule {
        case .boolean: return "boolean"
        case .integer(let low, let high): return "integer " + String(low) + "..." + String(high)
        case .optionalInteger(let low, let high): return "null or integer " + String(low) + "..." + String(high)
        case .choices(let values): return values.joined(separator: ", ")
        case .identityList: return "bounded local identity list"
        case .domains: return "canonical domain list"
        case .projectID: return "project identity or null"
        case .exclusions: return "canonical absolute-path exclusions"
        case .pins: return "project identity set"
        case .headroomTarget: return "automatic or 1...1024 GiB within volume bounds"
        case .headroomWarning: return "automatic or fixed below clear"
        case .headroomClear: return "automatic or fixed at or below capacity"
        case .volumeOverride: return "inherit, automatic, or fixed GiB fields"
        case .budgetHigh: return "null or 1...1024 GiB within volume bounds"
        case .budgetLow: return "null or value below high"
        case .cards: return "ordered subset of disk, memoryPressure, swap, thermal, power"
        case .ecosystemOrder: return "permutation of ecosystem IDs"
        case .clock: return "HH:mm"
        case .quietEnd: return "HH:mm distinct from quiet start"
        }
    }

    private static func layers(_ layers: Set<PolicyLayer>) -> String {
        let ordered = PolicyLayer.allCases.filter(layers.contains).map(\.rawValue)
        return ordered.isEmpty ? "machine-local authority only" : ordered.joined(separator: ", ")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
