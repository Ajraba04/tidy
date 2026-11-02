import Foundation
import Testing
@testable import TidyCore

@Suite("First global edit preserves legacy preferences")
struct FirstGlobalPreferenceMigrationTests {
    @Test(arguments: ["schema1-bridge", "schema2-bridge", "schema1-store", "schema2-store"])
    @MainActor func firstHistoryEditProjectsAllLegacyCompatibilityFields(route: String) async throws {
        let fixture = try FirstGlobalMigrationFixture(schema1: route.hasPrefix("schema1"))
        defer { fixture.remove() }
        let store = SettingsStore(url: fixture.file)
        let load = await store.load()
        let before = try #require(load.envelope)
        #expect(load.disposition == (fixture.schema1 ? .migrated : .loaded))
        #expect(before.schemaVersion == 2)
        #expect(before.revision == (fixture.schema1 ? 0 : 7))
        #expect(before.preferences == nil)
        #expect(before.config.keepCookieDomains == ["fixture.invalid"])
        let delta = GlobalPreferenceDelta(baseRevision: before.revision,
            id: .init(rawValue: "feature.history"), baseValue: nil, editedValue: .bool(true))
        let saved: SettingsEnvelope
        if route.hasSuffix("bridge") {
            let coordinator = ExecutionCoordinator(environment: .init(homeDirectory: fixture.root.path),
                journalDirectory: fixture.root.appendingPathComponent("execution"))
            let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: store, loaded: load,
                homeDirectory: fixture.root.path, detectedTools: [])
            await bridge.drain()
            guard case .accepted(_, let pending) = bridge.submit(global: delta) else {
                Issue.record("First global edit was rejected before save"); return
            }
            guard case .saved(_, let envelope) = await pending.value else {
                Issue.record("First global edit failed instead of saving legacy preferences"); return
            }
            await bridge.drain()
            saved = envelope
            #expect(bridge.acknowledgedEnvelope == saved)
            #expect(bridge.persistenceError == nil)
            #expect(bridge.isExecutionEnabled)
        } else {
            saved = try await store.update(expectedRevision: before.revision, change: .globalPreferenceDelta(delta))
        }
        var expected = PolicyPreferences.project(legacy: before.config, saved: nil)
        expected.global.fields[.init(rawValue: "feature.history")] = .bool(true)
        #expect(saved.revision == before.revision + 1)
        #expect(saved.config == before.config)
        #expect(saved.preferences == expected)
        #expect(saved.preferences?.global.fields[.init(rawValue: "browsers.keepCookieDomains")] == .strings(["fixture.invalid"]))
        let reopened = await SettingsStore(url: fixture.file).load()
        #expect(reopened.disposition == .loaded)
        #expect(reopened.envelope == saved)
    }

    @Test(arguments: [false, true])
    @MainActor func legacyProjectionDoesNotReplaceRawCompareAndSwap(useBridge: Bool) async throws {
        let fixture = try FirstGlobalMigrationFixture(schema1: false)
        defer { fixture.remove() }
        let store = SettingsStore(url: fixture.file)
        let load = await store.load()
        let before = try #require(load.envelope)
        let bytes = try Data(contentsOf: fixture.file)
        let id = SettingID(rawValue: "browsers.keepCookieDomains")
        // The legacy projection is not an existing raw typed value. A caller
        // presenting that projection as its CAS base must still be rejected.
        let wrongBase = GlobalPreferenceDelta(baseRevision: before.revision, id: id,
            baseValue: .strings(["fixture.invalid"]), editedValue: .strings(["replacement.invalid"]))
        let correctBase = GlobalPreferenceDelta(baseRevision: before.revision, id: id,
            baseValue: nil, editedValue: .strings(["replacement.invalid"]))
        let saved: SettingsEnvelope
        if useBridge {
            let coordinator = ExecutionCoordinator(environment: .init(homeDirectory: fixture.root.path),
                journalDirectory: fixture.root.appendingPathComponent("execution"))
            let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: store, loaded: load,
                homeDirectory: fixture.root.path, detectedTools: [])
            await bridge.drain()
            guard case .rejected(_, .invalid) = bridge.submit(global: wrongBase) else {
                Issue.record("Projected legacy data was accepted as a stored raw CAS base"); return
            }
            let afterRejected = try Data(contentsOf: fixture.file)
            #expect(afterRejected == bytes)
            guard case .accepted(_, let pending) = bridge.submit(global: correctBase),
                  case .saved(_, let result) = await pending.value else {
                Issue.record("A valid first edit to a legacy-compatible field failed"); return
            }
            saved = result
        } else {
            await #expect(throws: SettingsStoreError.staleRevision) {
                _ = try await store.update(expectedRevision: before.revision, change: .globalPreferenceDelta(wrongBase))
            }
            let afterRejected = try Data(contentsOf: fixture.file)
            #expect(afterRejected == bytes)
            saved = try await store.update(expectedRevision: before.revision, change: .globalPreferenceDelta(correctBase))
        }
        var expectedConfig = before.config
        expectedConfig.keepCookieDomains = ["replacement.invalid"]
        var expectedPreferences = PolicyPreferences.project(legacy: before.config, saved: nil)
        expectedPreferences.global.fields[id] = .strings(["replacement.invalid"])
        #expect(saved.config == expectedConfig)
        #expect(saved.preferences == expectedPreferences)
        #expect(saved.revision == before.revision + 1)
    }

    @Test func existingTypedDocumentIsNotReprojectedAndInvalidTypesStayReadOnly() async throws {
        let fixture = try FirstGlobalMigrationFixture(schema1: false)
        defer { fixture.remove() }
        let original = try JSONDecoder().decode(SettingsEnvelope.self, from: Data(contentsOf: fixture.file))
        let sparse = PolicyPreferences(global: .init(fields: [.init(rawValue: "ui.units"): .choice("decimal")]))
        let seeded = SettingsEnvelope(schemaVersion: 2, revision: 7, config: original.config, preferences: sparse)
        try JSONEncoder().encode(seeded).write(to: fixture.file)
        let store = SettingsStore(url: fixture.file)
        let before = try #require(await store.load().envelope)
        let saved = try await store.update(expectedRevision: before.revision,
            change: .globalPreferenceDelta(.init(baseRevision: before.revision,
                id: .init(rawValue: "feature.history"), baseValue: nil, editedValue: .bool(true))))
        var expected = sparse
        expected.global.fields[.init(rawValue: "feature.history")] = .bool(true)
        #expect(saved.preferences == expected)
        #expect(saved.config == original.config)

        var invalid = sparse
        invalid.global.fields[.init(rawValue: "browsers.keepCookieDomains")] = .bool(true)
        let malformed = try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2, revision: 9,
            config: original.config, preferences: invalid))
        let malformedFile = fixture.root.appendingPathComponent("malformed.json")
        try malformed.write(to: malformedFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: malformedFile.path)
        let rejected = await SettingsStore(url: malformedFile).load()
        #expect(rejected.disposition == .recoveryReadOnly)
        #expect(rejected.envelope == nil)
        let retained = try Data(contentsOf: malformedFile)
        #expect(retained == malformed)
    }

}

private struct FirstGlobalMigrationFixture {
    let root: URL
    let file: URL
    let schema1: Bool
    init(schema1: Bool) throws {
        self.schema1 = schema1
        root = URL(fileURLWithPath: "/private/tmp/TidyFirstGlobalMigration-\(UUID().uuidString)")
        file = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        var config = TidyConfig(schemaVersion: schema1 ? 1 : 2)
        config.hasCompletedOnboarding = true
        config.keepCookieDomains = ["fixture.invalid"]
        config.staleNodeModulesThresholdDays = 90
        config.transcriptAgeThresholdDays = 120
        config.allowRestartToReclaimSwap = true
        config.gitRoots = [root.appendingPathComponent("legacy-project").path]
        config.appsApprovedForQuit = ["Legacy inert application"]
        config.simulatorsApprovedForDeletion = ["Legacy inert simulator"]
        let bytes = schema1 ? try JSONEncoder().encode(config)
            : try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2, revision: 7, config: config))
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
