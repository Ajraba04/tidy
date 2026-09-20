import Foundation
import Testing
@testable import TidyCore

@Suite("Settings presentation registry")
struct SettingsPresentationTests {
    private let volumeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let expectedBasic = Set([
        "feature.headroom", "feature.buildPrep", "feature.projects", "feature.rescue",
        "feature.ecosystems", "feature.budgets", "feature.history", "feature.maintenance",
        "scan.preset", "scan.defaultScope", "cleanup.inactiveDays", "cleanup.costCeiling",
        "cleanup.requestedBatchGiB", "headroom.targetGiB", "headroom.warningGiB",
        "notifications.enabled", "ui.units", "ui.cards"
    ].map { SettingID(rawValue: $0) })

    private func expectedSection(_ id: SettingID) -> SettingsPresentationSection {
        let raw = id.rawValue
        if raw.hasPrefix("feature.") || raw.hasPrefix("ecosystem.") ||
            (raw.hasPrefix("item.") && raw.hasSuffix(".enabled")) { return .features }
        if raw.hasPrefix("scan.") || raw.hasPrefix("monitor.") || [
            "scope.projectRoots", "scope.externalVolumes", "scope.currentProject"
        ].contains(raw) { return .scan }
        if raw.hasPrefix("cleanup.") || raw.hasPrefix("headroom.") ||
            raw == "browsers.keepCookieDomains" || [
                "scope.excludedRoots", "scope.pinnedProjects"
            ].contains(raw) || (raw.hasPrefix("item.") && !raw.hasSuffix(".enabled")) {
            return .cleanup
        }
        return .experience
    }

    @Test("fixed validation and rendered universes are separate and deterministic")
    func exhaustiveCoverage() throws {
        let universe = SettingsPresentationRegistry.validationUniverse()
        try SettingsPresentationRegistry.validateCoverage()
        #expect(SettingsPresentationRegistry.validationVolumeID == volumeID)
        #expect(universe.filter { $0.id == PolicyDefaults.volumeRow(id: volumeID).id }.count == 1)

        let withoutVolume = try SettingsPresentationRegistry.all()
        let withVolume = try SettingsPresentationRegistry.all(volumeIDs: [volumeID])
        let duplicateVolume = try SettingsPresentationRegistry.all(volumeIDs: [volumeID, volumeID])

        #expect(withoutVolume.allSatisfy {
            !$0.definition.id.rawValue.hasPrefix("headroom.volumeOverrides.")
        })
        #expect(withVolume.count == withoutVolume.count + 1)
        #expect(withVolume == duplicateVolume)
        #expect(Set(withVolume.map(\.definition.id)) == Set(universe.map(\.id)))
        #expect(Set(withVolume.map(\.definition.id)).count == universe.count)
        for section in SettingsPresentationSection.allCases {
            let orders = withVolume.filter { $0.presentation.section == section }.map(\.order)
            #expect(orders == orders.sorted())
            #expect(Set(orders).count == orders.count)
        }
        #expect(withVolume.filter { $0.presentation.pattern == .volumeOverride }
            .allSatisfy { (200_000..<300_000).contains($0.order) })
        #expect(withVolume.filter {
            if case .catalogItem = $0.presentation.pattern { return true }
            return false
        }.allSatisfy { (100_000..<200_000).contains($0.order) })
        #expect(withVolume.filter {
            if case .exact = $0.presentation.pattern { return true }
            return false
        }.allSatisfy { (0..<100_000).contains($0.order) })
        #expect(SettingsPresentationRegistry.basicIDs == expectedBasic)
        #expect(withVolume.allSatisfy {
            $0.presentation.section == expectedSection($0.definition.id)
        })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.title.isEmpty })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.help.isEmpty })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.consequence.isEmpty })
        #expect(withVolume.allSatisfy { !$0.presentation.keys.applicability.isEmpty })

        for item in CleanCatalog.allItems {
            let expected = Set(PolicyDefaults.itemRows(catalogID: item.id).map(\.id))
            #expect(expected.count == 4)
            #expect(expected.isSubset(of: Set(withVolume.map(\.definition.id))))
        }
    }

    @Test("missing, ambiguous, orphan, and duplicate order entries reject")
    func negativeCoverage() throws {
        let universe = SettingsPresentationRegistry.validationUniverse()
        let first = try #require(SettingsPresentationRegistry.entries.first)
        let matching = universe.filter { definition in
            (try? SettingsPresentationRegistry.validateCoverage(
                entries: [first], definitions: [definition])) != nil
        }
        let matched = try #require(matching.first)

        #expect(throws: SettingsPresentationCoverageError.missing(matched.id)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: SettingsPresentationRegistry.entries.filter { $0 != first },
                definitions: universe)
        }
        #expect(throws: SettingsPresentationCoverageError.ambiguous(matched.id)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: SettingsPresentationRegistry.entries + [first],
                definitions: universe)
        }

        let orphan = SettingPresentation(
            pattern: .exact(SettingID(rawValue: "fixture.unknown")),
            section: .experience, tier: .advanced, order: Int.max,
            keys: SettingsPresentationKeys(
                title: "fixture.title", help: "fixture.help",
                consequence: "fixture.consequence",
                applicability: "fixture.applicability"))
        #expect(throws: SettingsPresentationCoverageError.orphan(orphan.pattern)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: SettingsPresentationRegistry.entries + [orphan],
                definitions: universe)
        }

        let firstDefinition = try #require(PolicyDefaults.rows.first)
        let firstPresentation = try SettingsPresentationRegistry.presentation(for: firstDefinition)
        let secondDefinition = try #require(PolicyDefaults.rows.dropFirst().first { definition in
            guard let candidate = try? SettingsPresentationRegistry.presentation(for: definition)
            else { return false }
            return candidate.section == firstPresentation.section
        })
        let secondPresentation = try SettingsPresentationRegistry.presentation(for: secondDefinition)
        let collision = SettingPresentation(
            pattern: secondPresentation.pattern, section: secondPresentation.section,
            tier: secondPresentation.tier, order: firstPresentation.order,
            keys: secondPresentation.keys)
        #expect(throws: SettingsPresentationCoverageError.duplicateOrder(
            firstPresentation.section, firstPresentation.order)) {
            try SettingsPresentationRegistry.validateCoverage(
                entries: [firstPresentation, collision],
                definitions: [firstDefinition, secondDefinition])
        }
    }

    @Test("dynamic patterns reject lookalikes and are stable")
    func exactDynamicGrammar() throws {
        let item = try #require(CleanCatalog.allItems.first)
        let real = try #require(PolicyDefaults.itemRows(catalogID: item.id).first)
        _ = try SettingsPresentationRegistry.presentation(for: real)
        _ = try SettingsPresentationRegistry.presentation(for: PolicyDefaults.volumeRow(id: volumeID))

        let lookalikes = [
            "item.unknown.enabled",
            "item.\(item.id).enabled.extra",
            "headroom.volumeOverrides.00000000-0000-0000-0000-000000000001.extra",
            "headroom.volumeOverrides.aaaaaaaa-0000-0000-0000-000000000001"
        ]
        for raw in lookalikes {
            let definition = SettingDefinition(
                id: SettingID(rawValue: raw), kind: .bool, defaultValue: .bool(false),
                rule: .boolean, resolution: .preference, effect: .none,
                layers: [.global], group: "fixture")
            #expect(throws: SettingsPresentationCoverageError.missing(definition.id)) {
                _ = try SettingsPresentationRegistry.presentation(for: definition)
            }
        }
    }

    @Test("stable accessibility IDs do not depend on copy")
    func stableAccessibilityIDs() {
        let id = SettingID(rawValue: "item.safe.cache.swiftpm-cache.inactiveDays")
        #expect(SettingsPresentationRegistry.accessibilityIdentifier(for: id)
                == "settings.row.item.safe.cache.swiftpm-cache.inactiveDays")
    }

    @Test("every registry row has an explicit truthful production-consumer contract")
    func everyRowHasConsumerContract() throws {
        let settings = try SettingsPresentationRegistry.all(volumeIDs: [volumeID])
        #expect(settings.allSatisfy {
            let support = SettingsPresentationRegistry.consumerSupport(for: $0.definition)
            return !support.summary.isEmpty
        })
        let headroom = try #require(settings.first {
            $0.definition.id.rawValue == "feature.headroom"
        })
        #expect(SettingsPresentationRegistry.consumerSupport(for: headroom.definition)
                == .connected("SystemMonitor and Headroom presentation"))
        let buildPrep = try #require(settings.first {
            $0.definition.id.rawValue == "feature.buildPrep"
        })
        #expect(SettingsPresentationRegistry.consumerSupport(for: buildPrep.definition)
                == .connected("Scoped project inventory and target-limited Build Prep planning"))
        let notification = try #require(settings.first {
            $0.definition.id.rawValue == "notifications.cooldownMinutes"
        })
        #expect(SettingsPresentationRegistry.consumerSupport(for: notification.definition)
                == .connected("Local assistance, budget hysteresis and consent-gated notifications"))
    }

    @Test("committed settings reference is byte-for-byte generated from registry metadata")
    func committedReferenceMatchesRenderer() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let committed = try String(contentsOf:
            repository.appendingPathComponent("docs/settings-reference.md"), encoding: .utf8)
        let generated = try SettingsReferenceRenderer.render()
        #expect(committed == generated)
    }
}
