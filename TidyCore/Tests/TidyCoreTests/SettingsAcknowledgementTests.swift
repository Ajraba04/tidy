import Foundation
import Testing
@testable import TidyCore

@Suite("Side-effect-free persisted settings acknowledgement")
struct SettingsAcknowledgementTests {
    @Test func acceptsOnlyTheExactPositiveCurrentStoreEnvelope() async throws {
        let fixture = try SettingsAcknowledgementFixture(); defer { fixture.remove() }
        let store = SettingsStore(url: fixture.file)
        let defaults = try #require(await store.load().envelope)
        let beforeBootstrap = await store.schedulerBootstrapGeneration
        #expect(!(await store.acknowledgesPersistedEnvelope(defaults)))
        #expect(await store.schedulerBootstrapGeneration == beforeBootstrap)
        #expect(!FileManager.default.fileExists(atPath: fixture.file.path))
        let first = try await store.update(expectedRevision: defaults.revision, change: .transcriptAgeDays(90))
        #expect(await store.acknowledgesPersistedEnvelope(first))
        let second = try await store.update(expectedRevision: first.revision, change: .transcriptAgeDays(120))
        let currentGeneration = await store.schedulerBootstrapGeneration
        #expect(!(await store.acknowledgesPersistedEnvelope(first)))
        #expect(await store.acknowledgesPersistedEnvelope(second))
        #expect(await store.schedulerBootstrapGeneration == currentGeneration)
        let recovering = await store.isRecoveryRequired()
        #expect(!recovering)
    }

    @Test(arguments: ["sameBytes", "changedBytes", "malformed", "missing"])
    func rejectsExternalDiskChangesWithoutAdoptingOrLatchingThem(change: String) async throws {
        let fixture = try SettingsAcknowledgementFixture(); defer { fixture.remove() }
        let store = SettingsStore(url: fixture.file)
        let initial = try #require(await store.load().envelope)
        let saved = try await store.update(expectedRevision: initial.revision, change: .transcriptAgeDays(90))
        let originalImage = try #require(await store.schedulerBootstrapImageForIssue())
        let originalBytes = try Data(contentsOf: fixture.file)
        let held = fixture.root.appendingPathComponent("owned-original")
        try FileManager.default.moveItem(at: fixture.file, to: held)
        switch change {
        case "missing": break
        case "malformed": try Data("invalid owned fixture".utf8).write(to: fixture.file)
        case "changedBytes":
            var config = saved.config
            config.transcriptAgeThresholdDays = 121
            let changed = SettingsEnvelope(schemaVersion: 2, revision: saved.revision + 1, config: config,
                preferences: LegacyCompatibilityProjection.applyingLegacyEdit(from: saved.config,
                    to: config, saved: saved.preferences))
            try JSONEncoder().encode(changed).write(to: fixture.file)
        default: try originalBytes.write(to: fixture.file)
        }
        if change != "missing" {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.file.path)
        }
        let diskBefore = try? Data(contentsOf: fixture.file)
        let generation = await store.schedulerBootstrapGeneration
        #expect(!(await store.acknowledgesPersistedEnvelope(saved)))
        #expect(!(await store.acknowledgesPersistedEnvelope(saved)))
        let diskAfter = try? Data(contentsOf: fixture.file)
        #expect(diskAfter == diskBefore)
        #expect(await store.schedulerBootstrapGeneration == generation)
        #expect(await store.schedulerBootstrapImageForIssue() == originalImage)
        #expect(!(await store.isRecoveryRequired()))
        if change != "missing" { try FileManager.default.removeItem(at: fixture.file) }
        try FileManager.default.moveItem(at: held, to: fixture.file)
        // Restoring the exact original inode/bytes is recognized without a
        // reload, demonstrating that mismatch neither adopts nor poisons state.
        #expect(await store.acknowledgesPersistedEnvelope(saved))
    }

    @Test(arguments: ["rollback", "importAnalysis", "importPreview"])
    func preservesIssuedPreviewsAndBootstrapGeneration(kind: String) async throws {
        let fixture = try SettingsAcknowledgementFixture(); defer { fixture.remove() }
        let store = SettingsStore(url: fixture.file)
        let initial = try #require(await store.load().envelope)
        let first = try await store.update(expectedRevision: initial.revision, change: .transcriptAgeDays(90))
        let second = try await store.update(expectedRevision: first.revision, change: .transcriptAgeDays(120))
        let importBytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        switch kind {
        case "rollback":
            let preview = try await store.previewRollback()
            await assertNonmutatingChecks(store, current: second, stale: first)
            let rolledBack = try await store.rollback(expectedRevision: second.revision, preview: preview)
            #expect(rolledBack.config.transcriptAgeThresholdDays == 90)
        case "importAnalysis":
            let analysis = try await store.analyzeImport(bytes: importBytes)
            await assertNonmutatingChecks(store, current: second, stale: first)
            let analysisID = try #require(analysis.analysisID)
            let preview = try await store.issueImportPreview(analysisID: analysisID, choices: [:])
            let imported = try await store.commitImport(expectedRevision: second.revision, previewID: preview.id)
            #expect(imported.preferences?.global.fields[.init(rawValue: "ui.units")] == .choice("decimal"))
        default:
            let analysis = try await store.analyzeImport(bytes: importBytes)
            let analysisID = try #require(analysis.analysisID)
            let preview = try await store.issueImportPreview(analysisID: analysisID, choices: [:])
            await assertNonmutatingChecks(store, current: second, stale: first)
            let imported = try await store.commitImport(expectedRevision: second.revision, previewID: preview.id)
            #expect(imported.preferences?.global.fields[.init(rawValue: "ui.units")] == .choice("decimal"))
        }
    }

    private func assertNonmutatingChecks(_ store: SettingsStore, current: SettingsEnvelope,
                                         stale: SettingsEnvelope) async {
        let generation = await store.schedulerBootstrapGeneration
        #expect(await store.acknowledgesPersistedEnvelope(current))
        #expect(!(await store.acknowledgesPersistedEnvelope(stale)))
        #expect(await store.schedulerBootstrapGeneration == generation)
        #expect(!(await store.isRecoveryRequired()))
    }
}

private struct SettingsAcknowledgementFixture {
    let root: URL
    let file: URL
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/TidySettingsAcknowledgement-\(UUID().uuidString)")
        file = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
