import Foundation
import Testing
@testable import TidyCore

@Suite("ConfigStore")
struct ConfigStoreTests {
    @Test("loading from a missing file returns defaults, not a crash")
    func loadingMissingFileReturnsDefaults() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigStoreTests-missing-\(UUID().uuidString).json")
        let config = ConfigStore.load(from: url)
        #expect(config == TidyConfig())
    }

    @Test("round-trips a saved config")
    func roundTripsSavedConfig() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigStoreTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        var config = TidyConfig()
        config.hasCompletedOnboarding = true
        config.keepCookieDomains = ["apple.com", "example.com"]
        config.simulatorsApprovedForDeletion = ["Old iPhone"]
        config.gitRoots = ["/Users/tester/Developer"]
        config.staleNodeModulesThresholdDays = 90
        config.presets = [CustomPreset(name: "Weekly", itemIDs: ["safe.cache.homebrew-cache"])]

        ConfigStore.save(config, to: url)
        let loaded = ConfigStore.load(from: url)
        #expect(loaded == config)
    }

    @Test("creates the containing directory if it does not exist yet")
    func createsContainingDirectory() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigStoreTests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        ConfigStore.save(TidyConfig(), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a corrupt file falls back to defaults rather than crashing")
    func corruptFileFallsBackToDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigStoreTests-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json at all".utf8).write(to: url)

        let config = ConfigStore.load(from: url)
        #expect(config == TidyConfig())
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

        let environment = config.makeEnvironment(homeDirectory: "/Users/tester")
        #expect(environment.keepCookieDomains == ["apple.com"])
        #expect(environment.simulatorsApprovedForDeletion == ["Old Simulator"])
        #expect(environment.gitRoots == ["/Users/tester/Developer"])
        #expect(environment.staleNodeModulesThresholdDays == 12)
        #expect(environment.transcriptAgeThresholdDays == 34)
    }
}
