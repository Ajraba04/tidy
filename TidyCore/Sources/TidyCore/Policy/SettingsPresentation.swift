import Foundation

public enum SettingsPresentationSection: String, CaseIterable, Sendable {
    case features, scan, cleanup, experience
}

public enum SettingsPresentationTier: String, CaseIterable, Sendable {
    case basic, advanced
}

public enum SettingsPresentationPattern: Hashable, Sendable {
    case exact(SettingID)
    case catalogItem(suffix: String)
    case volumeOverride
}

public struct SettingsPresentationKeys: Equatable, Sendable {
    public let title: String
    public let help: String
    public let consequence: String
    public let applicability: String

    public init(title: String, help: String, consequence: String,
                applicability: String) {
        self.title = title
        self.help = help
        self.consequence = consequence
        self.applicability = applicability
    }
}

public struct SettingPresentation: Equatable, Sendable {
    public let pattern: SettingsPresentationPattern
    public let section: SettingsPresentationSection
    public let tier: SettingsPresentationTier
    public let order: Int
    public let keys: SettingsPresentationKeys

    public init(pattern: SettingsPresentationPattern,
                section: SettingsPresentationSection,
                tier: SettingsPresentationTier,
                order: Int,
                keys: SettingsPresentationKeys) {
        self.pattern = pattern
        self.section = section
        self.tier = tier
        self.order = order
        self.keys = keys
    }
}

public struct PresentedSetting: Equatable, Sendable {
    public let definition: SettingDefinition
    public let presentation: SettingPresentation
    public let order: Int

    public init(definition: SettingDefinition,
                presentation: SettingPresentation,
                order: Int) {
        self.definition = definition
        self.presentation = presentation
        self.order = order
    }
}

public enum SettingsPresentationCoverageError: Error, Equatable, Sendable {
    case missing(SettingID)
    case ambiguous(SettingID)
    case orphan(SettingsPresentationPattern)
    case duplicateOrder(SettingsPresentationSection, Int)
}

public enum SettingsPresentationRegistry {
    public static let validationVolumeID = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    public static let basicIDs = Set([
        "feature.headroom", "feature.buildPrep", "feature.projects", "feature.rescue",
        "feature.ecosystems", "feature.budgets", "feature.history", "feature.maintenance",
        "scan.preset", "scan.defaultScope", "cleanup.inactiveDays", "cleanup.costCeiling",
        "cleanup.requestedBatchGiB", "headroom.targetGiB", "headroom.warningGiB",
        "notifications.enabled", "ui.units", "ui.cards"
    ].map { SettingID(rawValue: $0) })

    private static let catalogIDs = Set(CleanCatalog.allItems.map(\.id))
    private static let catalogIDsInOrder = CleanCatalog.allItems.map(\.id)

    public static let entries: [SettingPresentation] = [
        exact("feature.headroom", .features, .basic, 0),
        exact("feature.buildPrep", .features, .basic, 1),
        exact("feature.projects", .features, .basic, 2),
        exact("feature.rescue", .features, .basic, 3),
        exact("feature.ecosystems", .features, .basic, 4),
        exact("feature.budgets", .features, .basic, 5),
        exact("feature.history", .features, .basic, 6),
        exact("feature.maintenance", .features, .basic, 7),
        exact("ecosystem.apple.inventory", .features, .advanced, 8),
        exact("ecosystem.apple.manualActions", .features, .advanced, 9),
        exact("ecosystem.android.inventory", .features, .advanced, 10),
        exact("ecosystem.android.manualActions", .features, .advanced, 11),
        exact("ecosystem.node.inventory", .features, .advanced, 12),
        exact("ecosystem.node.manualActions", .features, .advanced, 13),
        exact("ecosystem.languages.inventory", .features, .advanced, 14),
        exact("ecosystem.languages.manualActions", .features, .advanced, 15),
        exact("ecosystem.homebrew.inventory", .features, .advanced, 16),
        exact("ecosystem.homebrew.manualActions", .features, .advanced, 17),
        exact("ecosystem.docker.inventory", .features, .advanced, 18),
        exact("ecosystem.docker.manualActions", .features, .advanced, 19),
        exact("ecosystem.ides.inventory", .features, .advanced, 20),
        exact("ecosystem.ides.manualActions", .features, .advanced, 21),
        exact("ecosystem.models.inventory", .features, .advanced, 22),
        exact("ecosystem.models.manualActions", .features, .advanced, 23),
        exact("ecosystem.git.inventory", .features, .advanced, 24),
        exact("ecosystem.git.manualActions", .features, .advanced, 25),
        exact("ecosystem.data.inventory", .features, .advanced, 26),
        exact("ecosystem.data.manualActions", .features, .advanced, 27),
        exact("scope.projectRoots", .scan, .advanced, 0),
        exact("scope.externalVolumes", .scan, .advanced, 1),
        exact("scope.currentProject", .scan, .advanced, 2),
        exact("scan.preset", .scan, .basic, 3),
        exact("scan.requestedWorkers", .scan, .advanced, 4),
        exact("scan.readOnlyProcesses", .scan, .advanced, 5),
        exact("scan.defaultScope", .scan, .basic, 6),
        exact("scan.sliceSeconds", .scan, .advanced, 7),
        exact("scan.uiBatchesPerSecond", .scan, .advanced, 8),
        exact("scan.onLowPower", .scan, .advanced, 9),
        exact("scan.onSeriousThermal", .scan, .advanced, 10),
        exact("scan.resumeAfterCriticalSeconds", .scan, .advanced, 11),
        exact("scan.cacheEnabled", .scan, .advanced, 12),
        exact("scan.cacheMiB", .scan, .advanced, 13),
        exact("scan.cacheExpiryHours", .scan, .advanced, 14),
        exact("monitor.backgroundEnabled", .scan, .advanced, 15),
        exact("monitor.visibleIntervalSeconds", .scan, .advanced, 16),
        exact("monitor.hiddenIntervalSeconds", .scan, .advanced, 17),
        exact("monitor.rawHistoryEnabled", .scan, .advanced, 18),
        exact("monitor.rawHistoryHours", .scan, .advanced, 19),
        exact("monitor.suppressHiddenSampling", .scan, .advanced, 20),
        exact("browsers.keepCookieDomains", .cleanup, .advanced, 0),
        exact("scope.excludedRoots", .cleanup, .advanced, 1),
        exact("scope.pinnedProjects", .cleanup, .advanced, 2),
        exact("cleanup.inactiveDays", .cleanup, .basic, 3),
        exact("cleanup.transcriptDays", .cleanup, .advanced, 4),
        exact("cleanup.recentProtectionDays", .cleanup, .advanced, 5),
        exact("cleanup.warmProjectCount", .cleanup, .advanced, 6),
        exact("cleanup.minimumCandidateMiB", .cleanup, .advanced, 7),
        exact("cleanup.minimumItemMiB", .cleanup, .advanced, 8),
        exact("cleanup.retainRecentArtifacts", .cleanup, .advanced, 9),
        exact("cleanup.costCeiling", .cleanup, .basic, 10),
        exact("cleanup.requestedBatchGiB", .cleanup, .basic, 11),
        exact("cleanup.requestedBatchItems", .cleanup, .advanced, 12),
        exact("cleanup.hardBatchGiB", .cleanup, .advanced, 13),
        exact("cleanup.hardBatchItems", .cleanup, .advanced, 14),
        exact("cleanup.manualInactiveAcknowledgementMinutes", .cleanup, .advanced, 15),
        exact("headroom.targetGiB", .cleanup, .basic, 16),
        exact("headroom.warningGiB", .cleanup, .basic, 17),
        exact("headroom.clearGiB", .cleanup, .advanced, 18),
        exact("simulators.approvedDeletionUDIDs", .experience, .advanced, 0),
        exact("tools.approvedExecutables", .experience, .advanced, 1),
        exact("docker.approvedEndpoints", .experience, .advanced, 2),
        exact("rescue.approvedApplications", .experience, .advanced, 3),
        exact("rescue.showAdvancedMemoryActions", .experience, .advanced, 4),
        exact("rescue.quitTimeoutSeconds", .experience, .advanced, 5),
        exact("budget.apple-derived-data.enabled", .experience, .advanced, 6),
        exact("budget.apple-derived-data.highGiB", .experience, .advanced, 7),
        exact("budget.apple-derived-data.lowGiB", .experience, .advanced, 8),
        exact("budget.apple-simulators.enabled", .experience, .advanced, 9),
        exact("budget.apple-simulators.highGiB", .experience, .advanced, 10),
        exact("budget.apple-simulators.lowGiB", .experience, .advanced, 11),
        exact("budget.android.enabled", .experience, .advanced, 12),
        exact("budget.android.highGiB", .experience, .advanced, 13),
        exact("budget.android.lowGiB", .experience, .advanced, 14),
        exact("budget.docker.enabled", .experience, .advanced, 15),
        exact("budget.docker.highGiB", .experience, .advanced, 16),
        exact("budget.docker.lowGiB", .experience, .advanced, 17),
        exact("budget.package-caches.enabled", .experience, .advanced, 18),
        exact("budget.package-caches.highGiB", .experience, .advanced, 19),
        exact("budget.package-caches.lowGiB", .experience, .advanced, 20),
        exact("budget.models.enabled", .experience, .advanced, 21),
        exact("budget.models.highGiB", .experience, .advanced, 22),
        exact("budget.models.lowGiB", .experience, .advanced, 23),
        exact("budget.ides.enabled", .experience, .advanced, 24),
        exact("budget.ides.highGiB", .experience, .advanced, 25),
        exact("budget.ides.lowGiB", .experience, .advanced, 26),
        exact("budget.git.enabled", .experience, .advanced, 27),
        exact("budget.git.highGiB", .experience, .advanced, 28),
        exact("budget.git.lowGiB", .experience, .advanced, 29),
        exact("budget.data.enabled", .experience, .advanced, 30),
        exact("budget.data.highGiB", .experience, .advanced, 31),
        exact("budget.data.lowGiB", .experience, .advanced, 32),
        exact("budget.other.enabled", .experience, .advanced, 33),
        exact("budget.other.highGiB", .experience, .advanced, 34),
        exact("budget.other.lowGiB", .experience, .advanced, 35),
        exact("notifications.enabled", .experience, .basic, 36),
        exact("notifications.pressureSustainSeconds", .experience, .advanced, 37),
        exact("notifications.recoverySeconds", .experience, .advanced, 38),
        exact("notifications.cooldownMinutes", .experience, .advanced, 39),
        exact("notifications.quietHoursEnabled", .experience, .advanced, 40),
        exact("notifications.quietStart", .experience, .advanced, 41),
        exact("notifications.quietEnd", .experience, .advanced, 42),
        exact("maintenance.mode", .experience, .advanced, 43),
        exact("maintenance.maxGiB", .experience, .advanced, 44),
        exact("maintenance.maxItems", .experience, .advanced, 45),
        exact("maintenance.deadlineSeconds", .experience, .advanced, 46),
        exact("maintenance.minimumAgeDays", .experience, .advanced, 47),
        exact("maintenance.minimumIntervalHours", .experience, .advanced, 48),
        exact("app.launchAtLogin", .experience, .advanced, 49),
        exact("history.enabled", .experience, .advanced, 50),
        exact("history.retentionDays", .experience, .advanced, 51),
        exact("history.maxMiB", .experience, .advanced, 52),
        exact("ui.density", .experience, .advanced, 53),
        exact("ui.units", .experience, .basic, 54),
        exact("ui.cards", .experience, .basic, 55),
        exact("ui.ecosystemOrder", .experience, .advanced, 56),
        exact("ui.showBadges", .experience, .advanced, 57),
        exact("ui.advancedSettings", .experience, .advanced, 58),
        exact("export.redactDiagnostics", .experience, .advanced, 59),
        dynamic(.catalogItem(suffix: "enabled"), order: 100_000),
        dynamic(.catalogItem(suffix: "inactiveDays"), order: 100_001),
        dynamic(.catalogItem(suffix: "minimumItemMiB"), order: 100_002),
        dynamic(.catalogItem(suffix: "retainRecentArtifacts"), order: 100_003),
        dynamic(.volumeOverride, order: 200_000)
    ]

    public static func validationUniverse() -> [SettingDefinition] {
        renderedUniverse(volumeIDs: [validationVolumeID])
    }

    public static func renderedUniverse(volumeIDs: [UUID]) -> [SettingDefinition] {
        var result = PolicyDefaults.rows
        for item in CleanCatalog.allItems {
            result += PolicyDefaults.itemRows(catalogID: item.id)
        }
        var seen: Set<UUID> = []
        for id in volumeIDs where seen.insert(id).inserted {
            result.append(PolicyDefaults.volumeRow(id: id))
        }
        return result
    }

    public static func validateCoverage(
        entries candidateEntries: [SettingPresentation],
        definitions: [SettingDefinition]
    ) throws {
        for definition in definitions {
            let found = candidateEntries.filter { matches($0.pattern, definition.id) }
            guard !found.isEmpty else {
                throw SettingsPresentationCoverageError.missing(definition.id)
            }
            guard found.count == 1 else {
                throw SettingsPresentationCoverageError.ambiguous(definition.id)
            }
        }
        for entry in candidateEntries where
            !definitions.contains(where: { matches(entry.pattern, $0.id) }) {
            throw SettingsPresentationCoverageError.orphan(entry.pattern)
        }

        let volumeOrder = stableVolumeIDs(in: definitions)
        var occupied: Set<OrderKey> = []
        for definition in definitions {
            guard let presentation = candidateEntries.first(where: {
                matches($0.pattern, definition.id)
            }) else {
                throw SettingsPresentationCoverageError.missing(definition.id)
            }
            let order = try finalOrder(for: definition, presentation: presentation,
                                       volumeIDs: volumeOrder)
            let key = OrderKey(section: presentation.section, order: order)
            guard occupied.insert(key).inserted else {
                throw SettingsPresentationCoverageError.duplicateOrder(
                    presentation.section, order)
            }
        }
    }

    public static func validateCoverage() throws {
        try validateCoverage(entries: entries, definitions: validationUniverse())
    }

    public static func all(volumeIDs: [UUID] = []) throws -> [PresentedSetting] {
        try validateCoverage()
        let definitions = renderedUniverse(volumeIDs: volumeIDs)
        let volumeOrder = stableVolumeIDs(in: definitions)
        var result: [PresentedSetting] = []
        var occupied: Set<OrderKey> = []
        for definition in definitions {
            let presentation = try presentation(for: definition)
            let order = try finalOrder(for: definition, presentation: presentation,
                                       volumeIDs: volumeOrder)
            let key = OrderKey(section: presentation.section, order: order)
            guard occupied.insert(key).inserted else {
                throw SettingsPresentationCoverageError.duplicateOrder(
                    presentation.section, order)
            }
            result.append(PresentedSetting(definition: definition,
                                           presentation: presentation, order: order))
        }
        return result.sorted {
            let left = sectionIndex($0.presentation.section)
            let right = sectionIndex($1.presentation.section)
            if left != right { return left < right }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.definition.id.rawValue.utf8.lexicographicallyPrecedes(
                $1.definition.id.rawValue.utf8)
        }
    }

    public static func presentation(
        for definition: SettingDefinition
    ) throws -> SettingPresentation {
        let found = entries.filter { matches($0.pattern, definition.id) }
        guard !found.isEmpty else {
            throw SettingsPresentationCoverageError.missing(definition.id)
        }
        guard found.count == 1 else {
            throw SettingsPresentationCoverageError.ambiguous(definition.id)
        }
        return found[0]
    }

    public static func accessibilityIdentifier(for id: SettingID) -> String {
        "settings.row." + id.rawValue
    }

    private struct OrderKey: Hashable {
        let section: SettingsPresentationSection
        let order: Int
    }

    private static func exact(_ raw: String, _ section: SettingsPresentationSection,
                              _ tier: SettingsPresentationTier, _ order: Int)
        -> SettingPresentation {
        SettingPresentation(pattern: .exact(SettingID(rawValue: raw)),
            section: section, tier: tier, order: order, keys: keys(base: "settings." + raw))
    }

    private static func dynamic(_ pattern: SettingsPresentationPattern, order: Int)
        -> SettingPresentation {
        let base: String
        let section: SettingsPresentationSection
        switch pattern {
        case .catalogItem(let suffix):
            base = "settings.item." + suffix
            section = suffix == "enabled" ? .features : .cleanup
        case .volumeOverride:
            base = "settings.headroom.volumeOverride"
            section = .cleanup
        case .exact(let id):
            base = "settings." + id.rawValue
            section = .experience
        }
        return SettingPresentation(pattern: pattern, section: section, tier: .advanced,
            order: order, keys: keys(base: base))
    }

    private static func keys(base: String) -> SettingsPresentationKeys {
        SettingsPresentationKeys(title: base + ".title", help: base + ".help",
            consequence: base + ".consequence", applicability: base + ".applicability")
    }

    private static func matches(_ pattern: SettingsPresentationPattern,
                                _ id: SettingID) -> Bool {
        switch pattern {
        case .exact(let expected):
            return expected == id
        case .catalogItem(let suffix):
            let prefix = "item."
            let ending = "." + suffix
            guard id.rawValue.hasPrefix(prefix), id.rawValue.hasSuffix(ending),
                  id.rawValue.count > prefix.count + ending.count else { return false }
            let catalogID = String(id.rawValue.dropFirst(prefix.count).dropLast(ending.count))
            return catalogIDs.contains(catalogID)
        case .volumeOverride:
            let prefix = "headroom.volumeOverrides."
            guard id.rawValue.hasPrefix(prefix) else { return false }
            let tail = String(id.rawValue.dropFirst(prefix.count))
            guard let parsed = UUID(uuidString: tail) else { return false }
            return parsed.uuidString == tail
        }
    }

    private static func sectionIndex(_ section: SettingsPresentationSection) -> Int {
        switch section {
        case .features: 0
        case .scan: 1
        case .cleanup: 2
        case .experience: 3
        }
    }

    private static func finalOrder(for definition: SettingDefinition,
                                   presentation: SettingPresentation,
                                   volumeIDs: [UUID]) throws -> Int {
        switch presentation.pattern {
        case .exact:
            return presentation.order
        case .catalogItem(let suffix):
            let prefix = "item."
            let ending = "." + suffix
            let catalogID = String(definition.id.rawValue.dropFirst(prefix.count)
                .dropLast(ending.count))
            guard let index = catalogIDsInOrder.firstIndex(of: catalogID) else {
                throw SettingsPresentationCoverageError.missing(definition.id)
            }
            let (offset, overflowA) = index.multipliedReportingOverflow(by: 4)
            let (order, overflowB) = presentation.order.addingReportingOverflow(offset)
            guard !overflowA, !overflowB, order < 200_000 else {
                throw SettingsPresentationCoverageError.duplicateOrder(.cleanup, order)
            }
            return order
        case .volumeOverride:
            let prefix = "headroom.volumeOverrides."
            let tail = String(definition.id.rawValue.dropFirst(prefix.count))
            guard let id = UUID(uuidString: tail),
                  let index = volumeIDs.firstIndex(of: id) else {
                throw SettingsPresentationCoverageError.missing(definition.id)
            }
            let (order, overflow) = presentation.order.addingReportingOverflow(index)
            guard !overflow, order < 300_000 else {
                throw SettingsPresentationCoverageError.duplicateOrder(.cleanup, order)
            }
            return order
        }
    }

    private static func stableVolumeIDs(in definitions: [SettingDefinition]) -> [UUID] {
        let prefix = "headroom.volumeOverrides."
        var result: [UUID] = []
        var seen: Set<UUID> = []
        for definition in definitions where definition.id.rawValue.hasPrefix(prefix) {
            let tail = String(definition.id.rawValue.dropFirst(prefix.count))
            if let id = UUID(uuidString: tail), id.uuidString == tail,
               seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }
}
