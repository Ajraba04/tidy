import Foundation
import Darwin
import Testing
@testable import TidyCore

@Suite("SettingsStore cutover")
struct SettingsStoreCutoverTests {
    private func scratch() throws -> URL {
        var chars = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath("/private/tmp", &chars) != nil else { throw SettingsStoreError.unavailable }
        let root = URL(fileURLWithPath: String(cString: chars), isDirectory: true)
            .appendingPathComponent("T05-Cutover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        return root
    }
    @Test func missingLoadIsInMemoryOnlyAndDefaultSchemaIsTwo() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("missing/config.json")
        let store = SettingsStore(url: url), loaded = await store.load()
        #expect(TidyConfig.currentSchemaVersion == 2)
        #expect(loaded.disposition == .newDefaults)
        #expect(loaded.envelope?.config == TidyConfig())
        #expect(loaded.envelope?.revision == 0)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
    @Test func explicitSaveRoundTripsEnvelopeAndUnknownPresetAsInertData() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json"), store = SettingsStore(url: url)
        _ = await store.load()
        var config = TidyConfig(); config.hasCompletedOnboarding = true
        config.keepCookieDomains = ["example.invalid"]
        config.simulatorsApprovedForDeletion = ["Old iPhone"]
        config.gitRoots = [root.appendingPathComponent("Developer").path]
        config.staleNodeModulesThresholdDays = 90
        config.presets = [CustomPreset(name: "Saved", itemIDs: ["unknown.preset.id"])]
        let saved = try await store.update(expectedRevision: 0, change: .legacyPreferences(config))
        let actual = await SettingsStore(url: url).load()
        #expect(actual.disposition == .loaded && actual.envelope == saved)
        #expect(saved.schemaVersion == 2 && saved.revision == 1 && saved.config == config)
        #expect(actual.envelope?.config.simulatorsApprovedForDeletion == ["Old iPhone"])
        #expect(actual.envelope?.config.gitRoots == [root.appendingPathComponent("Developer").path])
        #expect(actual.envelope?.config.staleNodeModulesThresholdDays == 90)
    }
    @Test func firstExplicitSaveCreatesParents() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("missing/parents/config.json")
        let store = SettingsStore(url: url); _ = await store.load()
        _ = try await store.update(expectedRevision: 0, change: .legacyPreferences(TidyConfig()))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
    @Test func corruptSettingsStayReadOnlyAndBytePreserved() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json"), bytes = Data("not json at all".utf8)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let store = SettingsStore(url: url), loaded = await store.load()
        #expect(loaded.disposition == .recoveryReadOnly && loaded.envelope == nil)
        do {
            _ = try await store.update(expectedRevision: 0, change: .legacyPreferences(TidyConfig()))
            Issue.record("Recovery wrote defaults")
        } catch let error as SettingsStoreError { #expect(error == .readOnlyRecovery) }
        #expect(try Data(contentsOf: url) == bytes)
    }
}

@Suite("TidyConfig")
struct TidyConfigTests {
    @Test("ships with every collection empty and onboarding not yet completed")
    func shipsWithEmptyDefaults() {
        let config = TidyConfig()
        #expect(config.keepCookieDomains.isEmpty)
        #expect(config.simulatorsApprovedForDeletion.isEmpty)
        #expect(config.gitRoots.isEmpty)
        #expect(config.presets.isEmpty)
        #expect(!config.hasCompletedOnboarding)
        #expect(config.schemaVersion == TidyConfig.currentSchemaVersion)
    }

    @Test("makeEnvironment carries every configured field through")
    func makeEnvironmentCarriesFieldsThrough() {
        var config = TidyConfig()
        config.keepCookieDomains = ["apple.com"]
        config.simulatorsApprovedForDeletion = ["Old Simulator"]
        config.gitRoots = ["/Users/tester/Developer"]
        config.staleNodeModulesThresholdDays = 12
        config.transcriptAgeThresholdDays = 34

        let environment = config.makePolicyEnvironment(homeDirectory: "/Users/tester", detectedTools: [])
        #expect(environment.keepCookieDomains == ["apple.com"])
        #expect(environment.simulatorsApprovedForDeletion == ["Old Simulator"])
        #expect(environment.gitRoots == ["/Users/tester/Developer"])
        #expect(environment.staleNodeModulesThresholdDays == 12)
        #expect(environment.transcriptAgeThresholdDays == 34)
    }
}
