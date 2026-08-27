import Foundation

enum ScanSettings {
    static var rows: [SettingDefinition] {
        let global: Set<PolicyLayer> = [.global, .profile]
        return [
            row("scan.preset", .choice, .choice("eco"), .choices(["eco", "balanced", "custom"]), .preference, .invalidate, global, "scan"),
            row("scan.requestedWorkers", .integer, .integer(1), .integer(1, 4), .preference, .invalidate, global, "scan"),
            row("scan.readOnlyProcesses", .integer, .integer(1), .integer(1, 2), .preference, .invalidate, global, "scan"),
            row("scan.defaultScope", .choice, .choice("quick"), .choices(["quick", "selectedProjects"]), .preference, .invalidate, global, "scan"),
            row("scan.sliceSeconds", .integer, .integer(300), .integer(30, 1_800), .preference, .invalidate, global, "scan"),
            row("scan.uiBatchesPerSecond", .integer, .integer(4), .integer(1, 4), .preference, .none, global, "scan"),
            row("scan.onLowPower", .choice, .choice("pauseDiscretionary"), .choices(["pauseAll", "pauseDiscretionary"]), .restriction, .invalidate, global, "scan"),
            row("scan.onSeriousThermal", .choice, .choice("pauseDiscretionary"), .choices(["pauseAll", "pauseDiscretionary"]), .restriction, .invalidate, global, "scan"),
            row("scan.resumeAfterCriticalSeconds", .integer, .integer(120), .integer(120, 900), .preference, .invalidate, global, "scan"),
            row("scan.cacheEnabled", .bool, .bool(true), .boolean, .preference, .invalidate, global, "scan"),
            row("scan.cacheMiB", .integer, .integer(64), .integer(8, 128), .preference, .invalidate, global, "scan"),
            row("scan.cacheExpiryHours", .integer, .integer(24), .integer(1, 48), .preference, .invalidate, global, "scan"),
            row("monitor.backgroundEnabled", .bool, .bool(false), .boolean, .authority, .consent, [], "monitor"),
            row("monitor.visibleIntervalSeconds", .integer, .integer(5), .integer(2, 60), .preference, .none, global, "monitor"),
            row("monitor.hiddenIntervalSeconds", .integer, .integer(60), .integer(60, 900), .preference, .none, global, "monitor"),
            row("monitor.rawHistoryEnabled", .bool, .bool(false), .boolean, .preference, .none, global, "monitor"),
            row("monitor.rawHistoryHours", .integer, .integer(24), .integer(1, 24), .preference, .none, global, "monitor"),
            row("monitor.suppressHiddenSampling", .bool, .bool(false), .boolean, .restriction, .none, global, "monitor")
        ]
    }
}
