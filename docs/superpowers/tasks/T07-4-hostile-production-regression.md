# T07.4 Hostile Production Regression — Preimplementation Task Card

> **Status:** PREIMPLEMENTATION. Execute only after T07.2a, T07.2b, T07.3a, and T07.3b are GREEN.
>
> **Purpose:** close the accepted T07 settings-customization entry checkpoint with one hostile, production-wired regression. This card adds evidence; it does not add authority.

## Scope and non-goals

This is a deliberately narrow, test-only card. It sends one concrete hostile portable-settings document through the real durable import pipeline, carries the resulting durable state into the real review/admission boundary, and proves that neither a forged model-operation identity nor real quarantined command/custom actions become executable.

This card does **not**:

- add or modify any production API;
- add a local authorization ledger, permit, grant, or capability store;
- inject a command/effect client into `ExecutionCoordinator`;
- claim that the current denial-only `CleanEngine.execute` compatibility entry is an accepted effect adapter;
- implement local reassociation, background/login/notification consent, model deletion, or any T22 authority work;
- weaken `CapabilityRegistry`'s fixed default-deny behavior;
- edit the app, Xcode project, package manifest, process fixture, or existing tests.

Literal authorization-ledger bytes and an accepted coordinator-sealed effect adapter remain dependencies of **T22.4**. This card must not anticipate them.

The evidence deliberately joins three currently disconnected denial boundaries without pretending they form an accepted effect path. Imported portable state is durable, but it does not grant an `ExecutionCoordinator` capability; the coordinator rejects unknown/unavailable selections and never delegates a non-empty plan to `CleanEngine`; and the engine's internal compatibility `execute` maps every supplied row to quarantine without calling its command runner or registered custom executor. The test therefore proves fail-closed behavior at each real boundary, not authorization continuity between them. T22.4 remains responsible for the future ledger-to-sealed-adapter connection.

## Exact allowlist

Implementation may create exactly these two files:

1. `TidyCore/Tests/TidyCoreTests/HostileProductionRegressionTests.swift`
2. `docs/verification/T07-4-hostile-production-regression.md`

The verification note is created only after GREEN and contains commands, exit statuses, test counts, and the final `git diff --check` result. No existing file may change. SwiftPM discovers the new test automatically; there is no `Package.swift` or PBX delta.

If the final test cannot pass without a production change, stop. Record the failing assertion and route a new reviewed card; do not broaden this allowlist.

## Existing production signatures consumed unchanged

No new signature is approved. The regression uses these existing entry points exactly:

```swift
public actor SettingsStore {
    public init(url: URL)
    public func load() -> SettingsLoadResult
    public func analyzeImport(bytes: Data) throws -> SettingsImportAnalysis
    public func issueImportPreview(
        analysisID: SettingsImportAnalysisID,
        choices: [UUID: ProfileCollisionChoice]
    ) throws -> SettingsImportPreview
    public func commitImport(
        expectedRevision: UInt64,
        previewID: SettingsImportPreviewID
    ) throws -> SettingsEnvelope
}

public actor ExecutionCoordinator {
    public init(environment: CleanEnvironment, journalDirectory: URL)
    public func prepareReview(
        engine: CleanEngine,
        tier: Tier,
        selectDefaults: Bool
    ) async throws -> RegisteredReview
    public func setSelection(planID: UUID, selectedIDs: Set<String>) throws -> RegisteredReview
    public func confirm(binding: ReviewBinding) throws -> ConfirmedPlan
    public func execute(_ token: ConfirmedPlan, currentPolicyRevision: UInt64) async -> RunReport
}

public enum CapabilityRegistry {
    public static func denialReason(for action: CleanAction, itemID: String) -> String?
}

public actor CleanEngine {
    public init(sizeScanner: SizeScanner, commandRunner: any CleanupCommandRunning)
    public func register(_ operation: CustomOperationID,
                         executor: @escaping CustomActionExecutor)
    internal func execute(plan: CleanPlan, environment: CleanEnvironment) async -> RunReport
}
```

The `@testable import TidyCore` test also uses existing internal `SettingsDecoding.encode(_:)` solely to seed a valid durable envelope and compare deterministic durable/config bytes. This is not a new import bypass: hostile bytes still enter only through `SettingsStore.analyzeImport`.

## Concrete hostile document and required outcomes

Use fixed imported profile ID `CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC` and hostile volume ID `BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB`. The UTF-8 document is:

```json
{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"},"item.models.erase-unknown.enabled":{"bool":true},"item.models.erase-unknown.identities":{"strings":["/Users/attacker/Models/private.gguf"]},"maintenance.mode":{"choice":"authorizedCaches"},"maintenance.maxGiB":{"integer":5},"maintenance.maxItems":{"integer":20},"maintenance.deadlineSeconds":{"integer":120},"maintenance.minimumAgeDays":{"integer":365},"maintenance.minimumIntervalHours":{"integer":168},"notifications.enabled":{"bool":true},"app.launchAtLogin":{"bool":true},"monitor.backgroundEnabled":{"bool":true},"scope.projectRoots":{"strings":["/Users/attacker/project"]},"scope.externalVolumes":{"strings":["/Volumes/Attacker"]},"scope.currentProject":{"choice":"attacker-project"},"tools.approvedExecutables":{"strings":["/usr/local/bin/attacker-tool"]},"docker.approvedEndpoints":{"strings":["unix:///private/attacker.sock"]},"simulators.approvedDeletionUDIDs":{"strings":["ATTACKER-DEVICE"]},"rescue.approvedApplications":{"strings":["com.attacker.agent"]},"headroom.volumeOverrides.BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB":{"volume":{"target":{"fixedGiB":12},"warning":{"automatic":true},"clear":{"inherit":true}}}}},"profiles":[{"id":"cccccccc-cccc-cccc-cccc-cccccccccccc","name":"Hostile Imported","values":{"fields":{"ui.density":{"choice":"compact"},"item.models.erase-profile.enabled":{"bool":true},"item.models.erase-profile.identities":{"strings":["/Users/attacker/Models/profile.gguf"]},"maintenance.mode":{"choice":"authorizedCaches"},"scope.projectRoots":{"strings":["/Users/attacker/profile-project"]}}}}],"inertImports":[]}
```

The analysis must contain exactly 25 rows and no collisions. Analysis rows intentionally expose `value == nil` for both safe and redacted unknowns; the exact safe payload is available only in the analysis's internal imported-inert quarantine state under `@testable`. Identify rows by `(scope, profileID, id)` rather than collapsing duplicate IDs:

| Scope | ID | Outcome |
|---|---|---|
| global | `ui.units` | `committable` |
| global | `item.models.erase-unknown.enabled` | `inert`, row value nil |
| global | `item.models.erase-unknown.identities` | `redacted`, kind `.strings`, non-nil digest, no value |
| global | `maintenance.mode` | `rejectedAuthority` |
| global | `maintenance.maxGiB` | `rejectedAuthority` |
| global | `maintenance.maxItems` | `rejectedAuthority` |
| global | `maintenance.deadlineSeconds` | `rejectedAuthority` |
| global | `maintenance.minimumAgeDays` | `rejectedAuthority` |
| global | `maintenance.minimumIntervalHours` | `rejectedAuthority` |
| global | `notifications.enabled` | `rejectedAuthority` |
| global | `app.launchAtLogin` | `rejectedAuthority` |
| global | `monitor.backgroundEnabled` | `rejectedAuthority` |
| global | `scope.projectRoots` | `requiresLocalReassociation` |
| global | `scope.externalVolumes` | `requiresLocalReassociation` |
| global | `scope.currentProject` | `requiresLocalReassociation` |
| global | `tools.approvedExecutables` | `requiresLocalReassociation` |
| global | `docker.approvedEndpoints` | `requiresLocalReassociation` |
| global | `simulators.approvedDeletionUDIDs` | `requiresLocalReassociation` |
| global | `rescue.approvedApplications` | `requiresLocalReassociation` |
| global | `headroom.volumeOverrides.BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB` | `requiresLocalReassociation` |
| imported profile | `ui.density` | `committable` |
| imported profile | `item.models.erase-profile.enabled` | `inert`, row value nil |
| imported profile | `item.models.erase-profile.identities` | `redacted`, kind `.strings`, non-nil digest, no value |
| imported profile | `maintenance.mode` | `rejectedAuthority` |
| imported profile | `scope.projectRoots` | `requiresLocalReassociation` |

After issuing and committing the real preview:

- the existing active profile remains active;
- `Hostile Imported` exists but is inactive and contains only `ui.density=compact`;
- `ui.units=decimal` is the only imported known global value;
- the exact four quarantine tuples—including scope, profile ownership, `.bool(true)`, redacted `.strings` kind, and each row's corresponding digest—match in analysis imported state, preview candidate, committed envelope, and reopened envelope;
- analyze and preview issuance leave both settings bytes and the complete companion-directory name/byte snapshot unchanged;
- preview, committed, and reopened global fields equal exactly seeded `ui.density=detailed` plus imported `ui.units=decimal`;
- preview, commit, and reopen contain the exact complete `PolicyPreferences`: unchanged project map; exactly ordered profiles `[Active Local, Hostile Imported]`; no drop, duplicate, or reorder; and the exact global fields above;
- no A/local field or value enters any global, profile, or project policy layer;
- complete `TidyConfig` equality and deterministic sorted-key JSON encoding are byte-identical before/after/reopen;
- existing projects, roots, simulator approvals, app approvals, preset IDs, and legacy authority-like config fields remain identical;
- raw durable settings contain neither sensitive unknown string value nor any rejected A/local hostile value;
- preview replay returns `SettingsStoreError.invalidChange` without changing durable bytes.
- production portable export of reopened state reuses the complete hostile raw-value exclusion list and additionally excludes the seeded local-project path, scratch-home prefix, and local config identities; production re-analysis has no projects or local identity material and preserves the exact four inert/redacted tuples without recognizing or making any committable.

## RED first

Create the test declarations before the test-local harness implementation:

```swift
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
```

Run `swift test --jobs 2 --filter HostileProductionRegressionTests`. Required RED: `T074HostileHarness` is not in scope. This is a missing test-local integration harness, not a fabricated production seam.

## GREEN implementation — complete final test file

```swift
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
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
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
        #expect(saved.config == before.config && try configBytes(saved.config) == configBefore)
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
        #expect(reopened == saved && try configBytes(reopened.config) == configBefore)
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
```

## Verification sequence

Run one heavy command at a time:

```bash
swift test --jobs 2 --filter HostileProductionRegressionTests
swift test --jobs 2 --filter SettingsProfilePersistenceTests
swift test --jobs 2 --filter ConfirmedExecutionTests
swift test --jobs 2 --filter LegacyQuarantineTests
swift test --jobs 2
git diff --check
```

The focused suite must report exactly two passing tests. Record commands, exit statuses, test counts, and diff evidence in the verification note. Only the two allowlisted new files may be card work. Do not commit, push, tag, build a DMG, or publish a release.

## Acceptance checklist

- [ ] Real `SettingsStore.analyzeImport` received the exact hostile bytes.
- [ ] Exact 25 outcomes and zero collisions were asserted.
- [ ] Analyze and issue preserved settings bytes and companion-directory snapshots.
- [ ] Real issue/commit was used and preview replay rejected without a write.
- [ ] Commit advanced the durable revision by exactly one.
- [ ] Complete `TidyConfig` equality and deterministic encoding matched before/after/reopen.
- [ ] Imported profile persisted inactive; projects and local config identity remained unchanged.
- [ ] Exact four inert tuples matched analysis, preview, commit, and reopen.
- [ ] Exact global fields and exhaustive A/local absence covered every policy layer.
- [ ] Preview, commit, and reopen matched exact complete preferences with ordered `[local, imported]` profiles and unchanged projects.
- [ ] Sensitive unknown strings persisted only as redacted digest markers.
- [ ] Production export omitted the centralized hostile raw-value list, seeded project/home paths, local config identities, and forbidden fields; production re-analysis had no projects/local identity material and preserved exactly four unrecognized inert/redacted tuples with none committable.
- [ ] Imported unknown model selection failed `.unknownSelectedID`.
- [ ] Real quarantined catalog selection failed `.unavailableSelection`.
- [ ] Forged binding failed `.staleReview`.
- [ ] Same real engine used the exact imported model ID command row and simulator custom row; both recorders stayed zero.
- [ ] No authorization ledger or coordinator effect-client injection was added; T22.4 remains explicit.
- [ ] Focused, compatibility, full-suite, and `git diff --check` evidence was recorded.
