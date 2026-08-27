import Foundation
import Testing
@testable import TidyCore

@Suite struct PolicyPersistenceTests {
    @Test func twoVolumesSurviveEveryLegacyEditAndRelaunch() async throws {
        let root = URL(fileURLWithPath:"/private/tmp",isDirectory:true)
            .appendingPathComponent("T06-Policy-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("config.json")
        let store = SettingsStore(url:url)
        let initial = try #require(await store.load().envelope)
        let original = PolicyPreferences(global:values([
            "ui.units":.choice("decimal"),"scan.preset":.choice("custom"),
            "scan.requestedWorkers":.integer(4),"scan.readOnlyProcesses":.integer(2),
            "headroom.volumeOverrides.\(volumeA.uuidString)":.volume(.init(target:.fixedGiB(12),warning:.automatic,clear:.inherit)),
            "headroom.volumeOverrides.\(volumeB.uuidString)":.volume(.init(target:.fixedGiB(30),warning:.inherit,clear:.automatic))]),
            profiles:[],projects:[:])
        let one = try await store.update(expectedRevision:initial.revision,change:.preferences(original))
        #expect(one.revision == initial.revision+1)
        let two = try await store.update(expectedRevision:one.revision,change:.transcriptAgeDays(90))
        var expected = original
        expected.global.fields[key("cleanup.transcriptDays")] = .integer(90)
        #expect(two.preferences == expected)
        expected.global.fields[key("item.normal.extras.stale-node-modules.inactiveDays")] = .integer(150)
        let registryUpdated = try await store.update(expectedRevision:two.revision,change:.preferences(expected))
        var stale = two.config
        stale.transcriptAgeThresholdDays = 120
        do {
            _ = try await store.update(expectedRevision:two.revision,change:.legacyPreferences(stale))
            Issue.record("Stale whole-config edit was accepted")
        } catch let error as SettingsStoreError { #expect(error == .staleRevision) }
        var legacy = registryUpdated.config
        legacy.transcriptAgeThresholdDays = 120
        let three = try await store.update(expectedRevision:registryUpdated.revision,
            change:.legacyPreferences(legacy))
        expected.global.fields[key("cleanup.transcriptDays")] = .integer(120)
        #expect(three.preferences == expected)
        #expect(three.config.staleNodeModulesThresholdDays == 150)
        let reopened = SettingsStore(url:url)
        let loaded = try #require(await reopened.load().envelope)
        #expect(loaded.preferences == expected); #expect(loaded.revision == initial.revision+4)
        for (volume, amount) in [(volumeA,Int64(12)),(volumeB,Int64(30))] {
            let resolved = try PolicyResolver.resolve(input([.global:try #require(loaded.preferences).global],selected:volume))
            #expect(resolved.fields[key("headroom.targetGiB")]?.value == .bytes(amount*GiB))
        }
        let preview = try await reopened.previewRollback()
        #expect(preview.preferences == registryUpdated.preferences)
        let restored = try await reopened.rollback(expectedRevision:loaded.revision,preview:preview)
        #expect(restored.preferences == registryUpdated.preferences)
        #expect(restored.revision == loaded.revision+1)
        #expect(await SettingsStore(url:url).load().envelope?.preferences == registryUpdated.preferences)
    }

    @Test func absentAndTaggedInheritanceRemainDistinct() throws {
        let original = PolicyPreferences(global:values([
            "headroom.targetGiB":.null,
            "headroom.volumeOverrides.\(volumeB.uuidString)":.volume(.init(target:.inherit,warning:.automatic,clear:.fixedGiB(35)))]),
            profiles:[],projects:[:])
        let encoded = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(PolicyPreferences.self,from:encoded) == original)
        #expect(original.global.fields[key("headroom.warningGiB")] == nil)
        #expect(original.global.fields[key("headroom.targetGiB")] == .null)
    }

    @Test func globalReverseProjectionIsAtomicAndProjectValuesStayInert() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let preferences = PolicyPreferences(global: values([
            "cleanup.transcriptDays": .integer(111),
            "item.normal.extras.stale-node-modules.inactiveDays": .integer(222),
            "browsers.keepCookieDomains": .strings(["keep.invalid"]),
            "rescue.showAdvancedMemoryActions": .bool(true)]), profiles: [], projects: [
                "fixture-project": values([
                    "cleanup.transcriptDays": .integer(333),
                    "item.normal.extras.stale-node-modules.inactiveDays": .integer(334)])])
        let saved = try await store.update(expectedRevision: initial.revision,
                                           change: .preferences(preferences))
        #expect(saved.preferences == preferences)
        #expect(saved.config.transcriptAgeThresholdDays == 111)
        #expect(saved.config.staleNodeModulesThresholdDays == 222)
        #expect(saved.config.keepCookieDomains == ["keep.invalid"])
        #expect(saved.config.allowRestartToReclaimSwap)
        #expect(saved.config.transcriptAgeThresholdDays != 333)
    }

    @Test func replacingGlobalPreferencesResetsRemovedLegacyProjectionsAndRollsBackAtomically() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let explicit = PolicyPreferences(global: values([
            "cleanup.transcriptDays": .integer(111),
            "item.normal.extras.stale-node-modules.inactiveDays": .integer(222),
            "browsers.keepCookieDomains": .strings(["keep.invalid"]),
            "rescue.showAdvancedMemoryActions": .bool(true)
        ]))
        let prior = try await store.update(expectedRevision: initial.revision,
                                           change: .preferences(explicit))
        #expect(prior.config.transcriptAgeThresholdDays == 111)
        #expect(prior.config.staleNodeModulesThresholdDays == 222)
        #expect(prior.config.keepCookieDomains == ["keep.invalid"])
        #expect(prior.config.allowRestartToReclaimSwap)

        let replacement = PolicyPreferences()
        let replaced = try await store.update(expectedRevision: prior.revision,
                                              change: .preferences(replacement))
        #expect(replaced.config.transcriptAgeThresholdDays == 45)
        #expect(replaced.config.staleNodeModulesThresholdDays == 60)
        #expect(replaced.config.keepCookieDomains.isEmpty)
        #expect(!replaced.config.allowRestartToReclaimSwap)
        #expect(replaced.preferences == replacement)

        let reloadedStore = SettingsStore(url: scratch.file)
        let reloaded = try #require(await reloadedStore.load().envelope)
        #expect(reloaded.config == replaced.config)
        #expect(reloaded.preferences == replacement)
        #expect(PolicyPreferences.project(legacy: reloaded.config, saved: reloaded.preferences)
            .global.fields.isEmpty)

        let preview = try await reloadedStore.previewRollback()
        #expect(preview.config == prior.config)
        #expect(preview.preferences == explicit)
        let restored = try await reloadedStore.rollback(expectedRevision: reloaded.revision,
                                                        preview: preview)
        #expect(restored.revision == reloaded.revision + 1)
        #expect(restored.config == prior.config)
        #expect(restored.preferences == explicit)
        let restoredFromDisk = try #require(await SettingsStore(url: scratch.file).load().envelope)
        #expect(restoredFromDisk == restored)
    }

    @Test func replacementPreservesLegacyOnlyNondefaultWhenNeitherTypedDocumentOwnsIt() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let legacy = TidyConfig(transcriptAgeThresholdDays: 120)
        let priorPreferences = PolicyPreferences(global: values(["ui.units": .choice("decimal")]))
        try scratch.seed(try JSONEncoder().encode(SettingsEnvelope(
            schemaVersion: 2, revision: 7, config: legacy, preferences: priorPreferences)))
        let store = SettingsStore(url: scratch.file)
        _ = try #require(await store.load().envelope)

        let replacement = PolicyPreferences(global: values(["ui.density": .choice("detailed")]))
        let saved = try await store.update(expectedRevision: 7, change: .preferences(replacement))
        #expect(saved.config.transcriptAgeThresholdDays == 120)
        #expect(saved.preferences == replacement)
        #expect(try #require(await SettingsStore(url: scratch.file).load().envelope)
            .config.transcriptAgeThresholdDays == 120)
    }

    @Test func firstLegacyEditProjectsEveryExistingNondefaultBeforeItsDelta() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let legacy = TidyConfig(schemaVersion: 2, staleNodeModulesThresholdDays: 90,
                                transcriptAgeThresholdDays: 120)
        try scratch.seed(try JSONEncoder().encode(SettingsEnvelope(
            schemaVersion: 2, revision: 7, config: legacy)))
        let store = SettingsStore(url: scratch.file)
        let loaded = try #require(await store.load().envelope)
        #expect(loaded.preferences == nil)
        let saved = try await store.update(expectedRevision: 7, change: .transcriptAgeDays(121))
        #expect(saved.preferences?.global.fields == values([
            "cleanup.transcriptDays": .integer(121),
            "item.normal.extras.stale-node-modules.inactiveDays": .integer(90)]).fields)
    }

    @Test(arguments: PolicyMalformedPreferenceFixture.allCases)
    func malformedPreferenceExtensionsAreReadOnlyAndPreserveBytes(
        fixture: PolicyMalformedPreferenceFixture
    ) async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let bytes = fixture.bytes
        try scratch.seed(bytes)
        let store = SettingsStore(url: scratch.file)
        let result = await store.load()
        #expect(result.disposition == .recoveryReadOnly)
        #expect(result.envelope == nil)
        do {
            _ = try await store.update(expectedRevision: 7, change: .transcriptAgeDays(90))
            Issue.record("Malformed preference bytes became writable")
        } catch let error as SettingsStoreError {
            #expect(error == .readOnlyRecovery)
        }
        #expect(try Data(contentsOf: scratch.file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: scratch.backup.path))
    }

    @Test func aggregatePreferenceFieldCountRejectsBeforePublication() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let document = values([
            "cleanup.transcriptDays": .integer(45),
            "cleanup.inactiveDays": .integer(60),
            "cleanup.recentProtectionDays": .integer(7),
            "cleanup.warmProjectCount": .integer(5),
            "cleanup.minimumItemMiB": .integer(1)])
        let preferences = PolicyPreferences(projects: Dictionary(uniqueKeysWithValues:
            (0..<1_000).map { ("project-\($0)", document) }))
        do {
            _ = try await store.update(expectedRevision: initial.revision,
                                       change: .preferences(preferences))
            Issue.record("Aggregate preference field bound was not enforced")
        } catch let error as SettingsStoreError {
            #expect(error == .invalidChange)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path).isEmpty)
        #expect(await store.load().disposition == .newDefaults)
    }

    @Test func compactPreferenceGraphBelowAggregateFieldLimitPersists() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let document = values([
            "cleanup.transcriptDays": .integer(45),
            "cleanup.inactiveDays": .integer(60),
            "cleanup.recentProtectionDays": .integer(7),
            "cleanup.warmProjectCount": .integer(5),
            "cleanup.minimumItemMiB": .integer(1)])
        let preferences = PolicyPreferences(projects: Dictionary(uniqueKeysWithValues:
            (0..<800).map { ("p\($0)", document) }))
        let saved = try await store.update(expectedRevision: initial.revision,
                                           change: .preferences(preferences))
        #expect(saved.preferences == preferences)
        #expect(saved.revision == initial.revision + 1)
        let reloaded = try #require(await SettingsStore(url: scratch.file).load().envelope)
        #expect(reloaded.preferences == preferences)
    }

    @Test func legacyDeltaUsesItsCapturedBaseAndPreservesUnrelatedTypedEdits() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        var edited = initial.config
        edited.transcriptAgeThresholdDays = 72
        let delta = LegacyPreferenceDelta(baseRevision: initial.revision,
                                          base: initial.config, edited: edited)

        let typed = PolicyPreferences(global: values(["ui.units": .choice("decimal")]))
        let intervening = try await store.update(expectedRevision: initial.revision,
                                                 change: .preferences(typed))
        let saved = try await store.update(expectedRevision: intervening.revision,
                                           change: .legacyPreferenceDelta(delta))

        #expect(saved.config.transcriptAgeThresholdDays == 72)
        #expect(saved.preferences?.global.fields[key("ui.units")] == .choice("decimal"))
        #expect(saved.preferences?.global.fields[key("cleanup.transcriptDays")] == .integer(72))
    }

    @Test func typedDeltaTreatsAbsentAsDifferentFromDefaultAndRejectsTouchedConflict() async throws {
        let scratch = try PolicySettingsScratch(); defer { scratch.remove() }
        let store = SettingsStore(url: scratch.file)
        let initial = try #require(await store.load().envelope)
        let id = key("ui.units")
        let delta = GlobalPreferenceDelta(baseRevision: initial.revision, id: id,
                                          baseValue: nil, editedValue: .choice("binary"))
        let intervening = try await store.update(expectedRevision: initial.revision,
            change: .preferences(PolicyPreferences(global: values(["ui.units": .choice("decimal")]))))

        do {
            _ = try await store.update(expectedRevision: intervening.revision,
                                       change: .globalPreferenceDelta(delta))
            Issue.record("A touched typed-field conflict was accepted")
        } catch let error as SettingsStoreError {
            #expect(error == .staleRevision)
        }
        let unchanged = try #require(await store.load().envelope)
        #expect(unchanged == intervening)
    }
}

private struct PolicySettingsScratch {
    let root: URL
    var file: URL { root.appendingPathComponent("config.json") }
    var backup: URL { root.appendingPathComponent("config.backup.json") }

    init() throws {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("T06-Policy-Bounds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    func seed(_ bytes: Data) throws {
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

enum PolicyMalformedPreferenceFixture: String, CaseIterable, CustomTestStringConvertible {
    case unknownKey, unknownTag, unknownVersion, duplicateKey, excessiveDepth, oversized, invalidUTF8
    case overlongProfileName, overlongProjectID, noncanonicalProfileUUID

    var testDescription: String { rawValue }

    var bytes: Data {
        let config = #"{"schemaVersion":2,"hasCompletedOnboarding":false,"keepCookieDomains":[],"simulatorsApprovedForDeletion":[],"gitRoots":[],"staleNodeModulesThresholdDays":60,"transcriptAgeThresholdDays":45,"appsApprovedForQuit":[],"allowRestartToReclaimSwap":false,"presets":[]}"#
        let fields: String
        switch self {
        case .unknownKey:
            fields = #"{"ui.future":{"bool":true}}"#
        case .unknownTag:
            fields = #"{"ui.units":{"future":"binary"}}"#
        case .unknownVersion:
            return Data(#"{"schemaVersion":2,"revision":7,"config":\#(config),"preferences":{"version":2,"global":{"fields":{}},"profiles":[],"projects":{}}}"#.utf8)
        case .duplicateKey:
            return Data(#"{"schemaVersion":2,"revision":7,"config":\#(config),"preferences":{"global":{"fields":{}},"global":{"fields":{}},"profiles":[],"projects":{}}}"#.utf8)
        case .excessiveDepth:
            fields = #"{"ui.units":{"choice":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":{"next":"binary"}}}}}}}}}}}}}}}}}"#
        case .oversized:
            return Data(repeating: 0x20, count: SettingsDecoding.byteLimit + 1)
        case .invalidUTF8:
            var bytes = Data(#"{"schemaVersion":2,"revision":7,"config":\#(config),"preferences":{"global":{"fields":{}},"profiles":[],"projects":{}}}"#.utf8)
            bytes.append(0xff)
            return bytes
        case .overlongProfileName:
            let name = String(repeating: "😀", count: 1_025)
            return Data(#"{"schemaVersion":2,"revision":7,"config":\#(config),"preferences":{"global":{"fields":{}},"profiles":[{"id":"33333333-3333-3333-3333-333333333333","name":"\#(name)","values":{"fields":{}}}],"projects":{}}}"#.utf8)
        case .overlongProjectID:
            let id = String(repeating: "😀", count: 1_025)
            return Data(#"{"schemaVersion":2,"revision":7,"config":\#(config),"preferences":{"global":{"fields":{}},"profiles":[],"projects":{"\#(id)":{"fields":{}}}}}"#.utf8)
        case .noncanonicalProfileUUID:
            return Data(#"{"schemaVersion":2,"revision":7,"config":\#(config),"preferences":{"global":{"fields":{}},"profiles":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","name":"fixture","values":{"fields":{}}}],"projects":{}}}"#.utf8)
        }
        return Data(#"{"schemaVersion":2,"revision":7,"config":\#(config),"preferences":{"global":{"fields":\#(fields)},"profiles":[],"projects":{}}}"#.utf8)
    }
}
