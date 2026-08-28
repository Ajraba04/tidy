import Foundation
import Testing
@testable import TidyCore

@Suite("T07.4 hostile production regression")
struct HostileProductionRegressionTests {
    @Test func hostileImport() async throws {
        try await T074HostileHarness().proveDurableImport()
    }
    @Test func hostileExecution() async throws {
        try await T074HostileHarness().proveExecutionDenial()
    }
}

private actor T074CommandRecorder: CleanupCommandRunning {
    private var calls: [String] = []
    func run(executableName: String, arguments: [String], timeout: TimeInterval) async
        -> CleanupCommandOutput {
        calls.append(([executableName] + arguments).joined(separator: " "))
        return CleanupCommandOutput(succeeded: true, standardOutput: "forged success")
    }
    func count() -> Int { calls.count }
}

private actor T074CustomRecorder {
    private var calls = 0
    func invoke() -> CustomActionOutcome {
        calls += 1
        return CustomActionOutcome(freedBytes: 999, reclaimedMemoryBytes: 999,
                                   succeeded: true, message: "forged success")
    }
    func count() -> Int { calls }
}

private struct T074Scratch {
    let root: URL
    let home: URL
    let journal: URL
    let settingsDirectory: URL
    let settings: URL
    let sentinel: URL

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("T07-4-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        journal = root.appendingPathComponent("journal", isDirectory: true)
        settingsDirectory = root.appendingPathComponent("settings", isDirectory: true)
        settings = settingsDirectory.appendingPathComponent("config.json")
        sentinel = home.appendingPathComponent("sentinel.bin")
        for directory in [home, journal, settingsDirectory] {
            try FileManager.default.createDirectory(at: directory,
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try Data("preserve exact sentinel".utf8).write(to: sentinel)
    }

    func seed(_ envelope: SettingsEnvelope) throws {
        try SettingsDecoding.encode(envelope).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: settings.path)
    }
    func settingsSnapshot() throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: settingsDirectory.path).sorted()
        return try Dictionary(uniqueKeysWithValues: names.map {
            ($0, try Data(contentsOf: settingsDirectory.appendingPathComponent($0)))
        })
    }
    func assertSentinel() throws {
        #expect(try Data(contentsOf: sentinel) == Data("preserve exact sentinel".utf8))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private struct T074HostileHarness {
    private let localID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let importedID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private func id(_ raw: String) -> SettingID { .init(rawValue: raw) }
    private func values(_ pairs: [(String, SettingValue)]) -> PolicyValues {
        .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (id($0.0), $0.1) }))
    }

    private func seed(_ s: T074Scratch) -> SettingsEnvelope {
        let config = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true,
            keepCookieDomains: ["keep.local.example"],
            simulatorsApprovedForDeletion: ["LOCAL-SIMULATOR"],
            gitRoots: [s.home.appendingPathComponent("local-repository").path],
            staleNodeModulesThresholdDays: 91, transcriptAgeThresholdDays: 73,
            appsApprovedForQuit: ["Local Editor"], allowRestartToReclaimSwap: true,
            presets: [.init(name: "Local preset", itemIDs: ["safe.cache.swiftpm-cache",
                "unknown.local.preset", "deep.simulator.erase-all"])])
        let profile = SavedProfile(id: localID, name: "Active Local",
            values: values([("cleanup.inactiveDays", .integer(60))]))
        return SettingsEnvelope(schemaVersion: 2, revision: 41, config: config,
            preferences: .init(global: values([("ui.density", .choice("detailed"))]),
                profiles: [profile], projects: [s.home.appendingPathComponent("local-project").path:
                    values([("cleanup.inactiveDays", .integer(75))])]),
            activeProfileID: localID, inertImports: [])
    }

    private var hostile: Data { Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"},"item.models.erase-unknown.enabled":{"bool":true},"item.models.erase-unknown.identities":{"strings":["/Users/attacker/Models/private.gguf"]},"maintenance.mode":{"choice":"authorizedCaches"},"maintenance.maxGiB":{"integer":5},"maintenance.maxItems":{"integer":20},"maintenance.deadlineSeconds":{"integer":120},"maintenance.minimumAgeDays":{"integer":365},"maintenance.minimumIntervalHours":{"integer":168},"notifications.enabled":{"bool":true},"app.launchAtLogin":{"bool":true},"monitor.backgroundEnabled":{"bool":true},"scope.projectRoots":{"strings":["/Users/attacker/project"]},"scope.externalVolumes":{"strings":["/Volumes/Attacker"]},"scope.currentProject":{"choice":"attacker-project"},"tools.approvedExecutables":{"strings":["/usr/local/bin/attacker-tool"]},"docker.approvedEndpoints":{"strings":["unix:///private/attacker.sock"]},"simulators.approvedDeletionUDIDs":{"strings":["ATTACKER-DEVICE"]},"rescue.approvedApplications":{"strings":["com.attacker.agent"]},"headroom.volumeOverrides.BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB":{"volume":{"target":{"fixedGiB":12},"warning":{"automatic":true},"clear":{"inherit":true}}}}},"profiles":[{"id":"cccccccc-cccc-cccc-cccc-cccccccccccc","name":"Hostile Imported","values":{"fields":{"ui.density":{"choice":"compact"},"item.models.erase-profile.enabled":{"bool":true},"item.models.erase-profile.identities":{"strings":["/Users/attacker/Models/profile.gguf"]},"maintenance.mode":{"choice":"authorizedCaches"},"scope.projectRoots":{"strings":["/Users/attacker/profile-project"]}}}}],"inertImports":[]}"#.utf8) }

    private var forbidden: Set<SettingID> { Set([
        "maintenance.mode", "maintenance.maxGiB", "maintenance.maxItems",
        "maintenance.deadlineSeconds", "maintenance.minimumAgeDays",
        "maintenance.minimumIntervalHours", "notifications.enabled", "app.launchAtLogin",
        "monitor.backgroundEnabled", "scope.projectRoots", "scope.externalVolumes",
        "scope.currentProject", "tools.approvedExecutables", "docker.approvedEndpoints",
        "simulators.approvedDeletionUDIDs", "rescue.approvedApplications",
        "browsers.keepCookieDomains",
        "headroom.volumeOverrides.BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    ].map(id)) }
    private var hostileRawValues: [String] {
        [
            "/Users/attacker/Models/private.gguf",
            "/Users/attacker/Models/profile.gguf",
            "authorizedCaches",
            "/Users/attacker/project",
            "/Volumes/Attacker",
            "attacker-project",
            "/usr/local/bin/attacker-tool",
            "unix:///private/attacker.sock",
            "ATTACKER-DEVICE",
            "com.attacker.agent",
            "/Users/attacker/profile-project",
            "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        ]
    }
    private func assertAbsent(_ p: PolicyPreferences) {
        for layer in [p.global] + p.profiles.map(\.values) + Array(p.projects.values) {
            #expect(forbidden.isDisjoint(with: Set(layer.fields.keys)))
        }
    }
    private func configBytes(_ value: TidyConfig) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(value)) as? [String: Any])
        if var presets = object["presets"] as? [[String: Any]] {
            for index in presets.indices {
                if let ids = presets[index]["itemIDs"] as? [String] {
                    presets[index]["itemIDs"] = ids.sorted()
                }
            }
            object["presets"] = presets
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func committed(in s: T074Scratch) async throws
        -> (SettingsStore, SettingsEnvelope, SettingsEnvelope) {
        let original = seed(s); try s.seed(original)
        let store = SettingsStore(url: s.settings)
        let before = try #require(await store.load().envelope)
        let analysis = try await store.analyzeImport(bytes: hostile)
        let preview = try await store.issueImportPreview(
            analysisID: try #require(analysis.analysisID), choices: [:])
        let saved = try await store.commitImport(expectedRevision: before.revision,
                                                 previewID: preview.id)
        return (store, before, saved)
    }

    func proveDurableImport() async throws {
        let s = try T074Scratch(); defer { s.remove() }
        let original = seed(s); try s.seed(original)
        let bytesBefore = try Data(contentsOf: s.settings)
        let directoryBefore = try s.settingsSnapshot()
        let configBefore = try configBytes(original.config)
        let store = SettingsStore(url: s.settings)
        let before = try #require(await store.load().envelope)
        #expect(before == original)

        let analysis = try await store.analyzeImport(bytes: hostile)
        #expect(analysis.collisions.isEmpty && analysis.rows.count == 25)
        let bytesAfterAnalyze = try Data(contentsOf: s.settings)
        let directoryAfterAnalyze = try s.settingsSnapshot()
        #expect(bytesAfterAnalyze == bytesBefore && directoryAfterAnalyze == directoryBefore)

        struct Key: Hashable { let scope: InertScope; let profile: UUID?; let id: String }
        let rows = Dictionary(uniqueKeysWithValues: analysis.rows.compactMap { row in
            row.id.map { (Key(scope: row.scope, profile: row.profileID, id: $0), row) }
        })
        let global: [(String, SettingsImportOutcome)] = [
            ("ui.units", .committable), ("item.models.erase-unknown.enabled", .inert),
            ("item.models.erase-unknown.identities", .redacted),
            ("maintenance.mode", .rejectedAuthority), ("maintenance.maxGiB", .rejectedAuthority),
            ("maintenance.maxItems", .rejectedAuthority),
            ("maintenance.deadlineSeconds", .rejectedAuthority),
            ("maintenance.minimumAgeDays", .rejectedAuthority),
            ("maintenance.minimumIntervalHours", .rejectedAuthority),
            ("notifications.enabled", .rejectedAuthority),
            ("app.launchAtLogin", .rejectedAuthority),
            ("monitor.backgroundEnabled", .rejectedAuthority),
            ("scope.projectRoots", .requiresLocalReassociation),
            ("scope.externalVolumes", .requiresLocalReassociation),
            ("scope.currentProject", .requiresLocalReassociation),
            ("tools.approvedExecutables", .requiresLocalReassociation),
            ("docker.approvedEndpoints", .requiresLocalReassociation),
            ("simulators.approvedDeletionUDIDs", .requiresLocalReassociation),
            ("rescue.approvedApplications", .requiresLocalReassociation),
            ("headroom.volumeOverrides.BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
             .requiresLocalReassociation)
        ]
        let profile: [(String, SettingsImportOutcome)] = [
            ("ui.density", .committable), ("item.models.erase-profile.enabled", .inert),
            ("item.models.erase-profile.identities", .redacted),
            ("maintenance.mode", .rejectedAuthority),
            ("scope.projectRoots", .requiresLocalReassociation)
        ]
        for (raw, outcome) in global {
            #expect(rows[Key(scope: .global, profile: nil, id: raw)]?.outcome == outcome)
        }
        for (raw, outcome) in profile {
            #expect(rows[Key(scope: .profile, profile: importedID, id: raw)]?.outcome == outcome)
        }
        #expect(rows.count == global.count + profile.count)
        let gs = try #require(rows[Key(scope: .global, profile: nil,
            id: "item.models.erase-unknown.enabled")])
        let gr = try #require(rows[Key(scope: .global, profile: nil,
            id: "item.models.erase-unknown.identities")])
        let ps = try #require(rows[Key(scope: .profile, profile: importedID,
            id: "item.models.erase-profile.enabled")])
        let pr = try #require(rows[Key(scope: .profile, profile: importedID,
            id: "item.models.erase-profile.identities")])
        #expect([gs, gr, ps, pr].allSatisfy { $0.value == nil })
        #expect(gs.valueKind == nil && gs.valueDigest == nil)
        #expect(ps.valueKind == nil && ps.valueDigest == nil)
        #expect(gr.valueKind == .strings && gr.valueDigest?.count == 64)
        #expect(pr.valueKind == .strings && pr.valueDigest?.count == 64)
        let inert: [InertPortableSetting] = [
            .init(scope: .global, profileID: nil, id: "item.models.erase-unknown.enabled",
                  value: .bool(true), valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "item.models.erase-unknown.identities",
                  value: nil, valueKind: .strings,
                  valueDigest: try #require(gr.valueDigest), redacted: true),
            .init(scope: .profile, profileID: importedID,
                  id: "item.models.erase-profile.enabled", value: .bool(true),
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .profile, profileID: importedID,
                  id: "item.models.erase-profile.identities", value: nil,
                  valueKind: .strings, valueDigest: try #require(pr.valueDigest), redacted: true)
        ]
        #expect(analysis.importedInert == inert)

        let preview = try await store.issueImportPreview(
            analysisID: try #require(analysis.analysisID), choices: [:])
        let bytesAfterIssue = try Data(contentsOf: s.settings)
        let directoryAfterIssue = try s.settingsSnapshot()
        #expect(bytesAfterIssue == bytesBefore && directoryAfterIssue == directoryBefore)
        let exactGlobal = values([("ui.density", .choice("detailed")),
                                  ("ui.units", .choice("decimal"))]).fields
        let beforePreferences = try #require(before.preferences)
        let localProfile = try #require(beforePreferences.profiles.first { $0.id == localID })
        let importedProfile = SavedProfile(id: importedID, name: "Hostile Imported",
            values: values([("ui.density", .choice("compact"))]))
        let exactPreferences = PolicyPreferences(global: .init(fields: exactGlobal),
            profiles: [localProfile, importedProfile], projects: beforePreferences.projects)
        #expect(preview.candidate.preferences == exactPreferences)
        #expect(preview.candidate.inertImports == inert)
        assertAbsent(preview.candidate.preferences)

        let saved = try await store.commitImport(expectedRevision: before.revision,
                                                 previewID: preview.id)
        #expect(saved.revision == before.revision + 1)
        #expect(saved.config == before.config)
        #expect(try configBytes(saved.config) == configBefore)
        #expect(saved.activeProfileID == localID)
        let preferences = try #require(saved.preferences)
        #expect(preferences == exactPreferences)
        #expect(preferences.profiles.map(\.id) == [localID, importedID])
        #expect(Set(preferences.profiles.map(\.id)).count == 2)
        assertAbsent(preferences)
        let imported = try #require(preferences.profiles.first { $0.id == importedID })
        #expect(imported.name == "Hostile Imported")
        #expect(imported.values == values([("ui.density", .choice("compact"))]))
        #expect(saved.activeProfileID != imported.id && saved.inertImports == inert)
        let durable = try Data(contentsOf: s.settings)
        let text = String(decoding: durable, as: UTF8.self)
        for forbiddenValue in hostileRawValues {
            #expect(!text.contains(forbiddenValue))
        }
        let reopened = try #require(await SettingsStore(url: s.settings).load().envelope)
        #expect(reopened == saved)
        #expect(try configBytes(reopened.config) == configBefore)
        let reopenedPreferences = try #require(reopened.preferences)
        #expect(reopenedPreferences == exactPreferences)
        #expect(reopenedPreferences.profiles.map(\.id) == [localID, importedID])
        #expect(reopened.inertImports == inert)
        assertAbsent(reopenedPreferences)

        let exported = try SettingsTransfer.export(.init(
            preferences: reopenedPreferences, inertImports: reopened.inertImports))
        let exportedText = String(decoding: exported, as: UTF8.self)
        let forbiddenExportStrings = hostileRawValues + [
            s.home.appendingPathComponent("local-project").path,
            s.home.path,
            "keep.local.example",
            "LOCAL-SIMULATOR",
            "Local Editor",
            "maintenance.mode", "maintenance.maxGiB", "maintenance.maxItems",
            "maintenance.deadlineSeconds", "maintenance.minimumAgeDays",
            "maintenance.minimumIntervalHours", "notifications.enabled",
            "app.launchAtLogin", "monitor.backgroundEnabled", "scope.projectRoots",
            "scope.externalVolumes", "scope.currentProject", "tools.approvedExecutables",
            "docker.approvedEndpoints", "simulators.approvedDeletionUDIDs",
            "rescue.approvedApplications", "browsers.keepCookieDomains",
            "headroom.volumeOverrides.BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        ]
        for forbiddenExport in forbiddenExportStrings {
            #expect(!exportedText.contains(forbiddenExport))
        }
        let reparsed = try SettingsTransfer.analyze(bytes: exported, current: .init())
        #expect(reparsed.collisions.isEmpty)
        #expect(reparsed.importedInert == inert)
        #expect(reparsed.committableImported.projects.isEmpty)
        #expect(reparsed.rows.allSatisfy {
            $0.outcome != .requiresLocalReassociation && $0.outcome != .rejectedAuthority
        })
        assertAbsent(reparsed.committableImported)
        let inertIDs = Set(inert.map(\.id))
        let reparsedInertRows = reparsed.rows.filter { row in
            row.id.map(inertIDs.contains) == true
        }
        #expect(reparsedInertRows.count == 4)
        #expect(reparsedInertRows.allSatisfy {
            $0.value == nil && ($0.outcome == .inert || $0.outcome == .redacted) &&
            $0.outcome != .committable &&
            $0.id.map { PolicyValidator.definition(for: id($0)) == nil } == true
        })
        for expected in inert {
            let row = try #require(reparsedInertRows.first {
                $0.scope == expected.scope && $0.profileID == expected.profileID &&
                $0.id == expected.id
            })
            #expect(row.outcome == (expected.redacted ? .redacted : .inert))
            #expect(row.valueKind == expected.valueKind)
            #expect(row.valueDigest == expected.valueDigest)
        }
        do {
            _ = try await store.commitImport(expectedRevision: saved.revision, previewID: preview.id)
            Issue.record("Single-use preview committed twice")
        } catch let error as SettingsStoreError { #expect(error == .invalidChange) }
        #expect(try Data(contentsOf: s.settings) == durable)
        try s.assertSentinel()
    }

    func proveExecutionDenial() async throws {
        let s = try T074Scratch(); defer { s.remove() }
        let (_, _, saved) = try await committed(in: s)
        #expect(saved.activeProfileID == localID)
        #expect(saved.preferences?.profiles.contains { $0.id == importedID } == true)
        let environment = saved.config.makePolicyEnvironment(homeDirectory: s.home.path,
            detectedTools: Set(ToolchainID.allCases))
        let commands = T074CommandRecorder(), custom = T074CustomRecorder()
        let engine = CleanEngine(sizeScanner: SizeScanner(), commandRunner: commands)
        await engine.register(.simulatorPrune) { _, _ in await custom.invoke() }
        let coordinator = ExecutionCoordinator(environment: environment, journalDirectory: s.journal)
        let review = try await coordinator.prepareReview(engine: engine, tier: .deep,
                                                         selectDefaults: false)
        do {
            _ = try await coordinator.setSelection(planID: review.binding.planID,
                selectedIDs: ["item.models.erase-unknown.enabled"])
            Issue.record("Unknown imported model ID entered review")
        } catch let error as ConfirmationError { #expect(error == .unknownSelectedID) }
        let denied = try #require(review.plan.reviewItems.first {
            $0.id == "deep.simulator.erase-all"
        })
        do {
            _ = try await coordinator.setSelection(planID: review.binding.planID,
                                                   selectedIDs: [denied.id])
            Issue.record("Quarantined row became selectable")
        } catch let error as ConfirmationError { #expect(error == .unavailableSelection) }
        let forged = ReviewBinding(planID: review.binding.planID,
            planRevision: review.binding.planRevision,
            policyRevision: review.binding.policyRevision, selectedIDs: [denied.id])
        do {
            _ = try await coordinator.confirm(binding: forged)
            Issue.record("Forged binding confirmed")
        } catch let error as ConfirmationError { #expect(error == .staleReview) }
        let token = try await coordinator.confirm(binding: review.binding)
        #expect(await coordinator.execute(token,
            currentPolicyRevision: review.binding.policyRevision).disposition == .noWork)

        let command = PlannedItem(id: "item.models.erase-unknown.enabled",
            title: "Imported unknown model operation", tier: .deep,
            dangerNote: nil, costNote: nil, targets: [], estimatedBytes: 999,
            action: .runTool(.init(.git, ["clean", "-ffdx"])), declaredRoot: s.home.path)
        let simulator = PlannedItem(id: "deep.simulator.erase-all", title: "Simulator",
            tier: .deep, dangerNote: nil, costNote: nil,
            targets: [.init(path: "ATTACKER-DEVICE", isFilesystemPath: false)],
            estimatedBytes: 999, action: .custom(.simulatorPrune), declaredRoot: s.home.path)
        for row in [command, simulator] {
            #expect(CapabilityRegistry.denialReason(for: row.action, itemID: row.id) ==
                    CapabilityRegistry.quarantineReason)
        }
        let report = await engine.execute(plan: .init(tier: .deep,
            plannedItems: [command, simulator]), environment: environment)
        #expect(report.disposition == .unavailableSelection && report.results.count == 2)
        #expect(report.results.allSatisfy { !$0.succeeded && $0.freedBytes == 0 &&
            $0.message == CapabilityRegistry.quarantineReason })
        #expect(await commands.count() == 0)
        #expect(await custom.count() == 0)
        try s.assertSentinel()
    }
}
