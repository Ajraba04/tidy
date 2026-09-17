import Foundation
import Darwin
import SwiftUI
import XCTest
@testable import TidyCore

private enum A3Failure: Error { case timeout, setup }

private struct A3Scratch {
    let root: URL
    var home: URL { root.appendingPathComponent("home", isDirectory: true) }
    var support: URL { root.appendingPathComponent("support/Tidy", isDirectory: true) }
    var paths: AppStoragePaths {
        AppStoragePaths(home: home, settings: support.appendingPathComponent("config.json"),
            journal: support.appendingPathComponent("execution", isDirectory: true))
    }
    init() throws {
        var chars = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath("/private/tmp", &chars) != nil else { throw A3Failure.setup }
        root = URL(fileURLWithPath: String(cString: chars), isDirectory: true)
            .appendingPathComponent("T05-A3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try Data("preserve".utf8).write(to: home.appendingPathComponent("sentinel"))
    }
    func seed(_ bytes: Data) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try bytes.write(to: paths.settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
            ofItemAtPath: paths.settings.path)
    }
    func intact() throws {
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent("sentinel")), Data("preserve".utf8))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private enum SettingsWorkflowGatePoint: Hashable {
    case analyzeA, analyzeB, analyzeCancel, issue, submit, rejectCancel
}

@MainActor private final class SettingsWorkflowAsyncGate {
    private var entered: Set<SettingsWorkflowGatePoint> = []
    private var blocked: [SettingsWorkflowGatePoint: CheckedContinuation<Void, Never>] = [:]
    private var entryWaiters: [SettingsWorkflowGatePoint: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<SettingsWorkflowGatePoint> = []
    private(set) var cancelledAnalysisIDs: [SettingsImportAnalysisID] = []
    private(set) var cancelledPreviewIDs: [SettingsImportPreviewID] = []

    func suspend(at point: SettingsWorkflowGatePoint) async {
        entered.insert(point)
        entryWaiters.removeValue(forKey: point)?.resume()
        if released.remove(point) != nil { return }
        await withCheckedContinuation { continuation in
            guard blocked[point] == nil else {
                XCTFail("Duplicate bounded blocker: \(point)")
                continuation.resume(); return
            }
            blocked[point] = continuation
        }
    }

    func waitUntilEntered(_ point: SettingsWorkflowGatePoint) async {
        if entered.contains(point) { return }
        await withCheckedContinuation { continuation in
            guard entryWaiters[point] == nil else {
                XCTFail("Duplicate bounded entry waiter: \(point)")
                continuation.resume(); return
            }
            entryWaiters[point] = continuation
        }
    }

    func release(_ point: SettingsWorkflowGatePoint) {
        guard let waiter = blocked.removeValue(forKey: point) else {
            released.insert(point); return
        }
        waiter.resume()
    }

    func recordAnalysisCancellation(_ id: SettingsImportAnalysisID) {
        cancelledAnalysisIDs.append(id)
    }

    func recordPreviewCancellation(_ id: SettingsImportPreviewID) {
        cancelledPreviewIDs.append(id)
    }
}

private enum SettingsWorkflowFixtureError: Error { case failedAnalysis, failedIssuance }

extension SharedSettingsWiringTests {
    private func workflowSummary(_ id: UUID,
                                 collisions: [ProfileImportCollision] = []) throws
        -> SettingsImportUISummary {
        try SettingsImportUISummary(SettingsImportAnalysis(analysisID: id, rows: [],
            collisions: collisions, committableImported: .init(), importedInert: [], current: .init()))
    }

    private func workflowPreview(_ summary: SettingsImportUISummary) -> SettingsImportPreview {
        SettingsImportPreview(id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            analysisID: summary.analysisID, rows: summary.rows,
            collisions: summary.collisions, choices: [:], candidate: .init(),
            sourceDigest: String(repeating: "a", count: 64),
            candidateDigest: String(repeating: "b", count: 64))
    }

    @MainActor func testWorkflowPreviewConfirmCancelAndTwoWindows() async throws {
        try await run { _, services, _ in
            let store = services.configStore
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let c = SettingsWorkflowController(store: store,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            let id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
            let factoryID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
            let cloneID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
            var expectedRevision = store.settingsRevision
            let before = store.preferences
            try c.prepareProfile(.create(id: id, name: "Build", values: .init()))
            XCTAssertEqual(store.preferences, before)
            c.cancelConfirmation(); XCTAssertNil(c.confirmPreparedChange())
            XCTAssertEqual(store.preferences, before)
            try c.prepareProfile(.create(id: id, name: "Build", values: .init()))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain()
            expectedRevision += 1
            XCTAssertEqual(store.profiles.first?.id, id); XCTAssertNil(store.activeProfileID)
            XCTAssertEqual(store.settingsRevision, expectedRevision)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.rename(id: id, name: "Renamed"))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.profiles.first(where: { $0.id == id })?.name, "Renamed")
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            let workers = SettingID(rawValue: "scan.requestedWorkers")
            try c.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(2)])))
            guard case .profile(let updatePreview)? = c.confirmation else { return XCTFail() }
            XCTAssertEqual(updatePreview.kind, .update)
            XCTAssertEqual(updatePreview.fieldChanges.map(\.id), [workers])
            c.cancelConfirmation()
            XCTAssertNil(store.profiles.first(where: { $0.id == id })?.values.fields[workers])
            try c.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(2)])))
            guard case .some(.accepted(_, let updateTask)) = c.confirmPreparedChange(),
                  case .saved = await updateTask.value else { return XCTFail("Update not saved") }
            expectedRevision += 1
            XCTAssertEqual(store.profiles.first(where: { $0.id == id })?.values.fields[workers],
                           .integer(2))
            XCTAssertEqual(second.profiles, store.profiles)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.createFactory(key: "xcode", id: factoryID, name: "Xcode"))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertNotNil(store.profiles.first(where: { $0.id == factoryID }))
            XCTAssertNil(store.activeProfileID); XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.clone(sourceID: id, newID: cloneID, name: "Clone"))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.profiles.first(where: { $0.id == cloneID })?.values,
                           store.profiles.first(where: { $0.id == id })?.values)
            XCTAssertNil(store.activeProfileID); XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.activate(id))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            XCTAssertFalse(services.policyBridge.isExecutionEnabled)
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.activeProfileID, id); XCTAssertEqual(second.activeProfileID, id)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
            try c.prepareProfile(.activate(nil))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertNil(store.activeProfileID); XCTAssertNil(second.activeProfileID)
            try c.prepareProfile(.activate(id))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            try c.prepareProfile(.delete(id: factoryID))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertEqual(store.activeProfileID, id)
            XCTAssertNil(store.profiles.first(where: { $0.id == factoryID }))
            try c.prepareProfile(.delete(id: id))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain(); expectedRevision += 1
            XCTAssertNil(store.profiles.first(where: { $0.id == id }))
            XCTAssertEqual(Set(store.profiles.map(\.id)), Set([cloneID]))
            XCTAssertNil(store.activeProfileID)
            XCTAssertEqual(store.settingsRevision, expectedRevision)
            XCTAssertEqual(second.settingsRevision, expectedRevision)
        }
    }

    @MainActor func testStaleProfilePreviewsConflictAndPreserveOtherWindow() async throws {
        let id = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let original = SavedProfile(id: id, name: "Original", values: .init())
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [original])))

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let a = SettingsWorkflowController(store: first, bundle: bundle)
            let b = SettingsWorkflowController(store: second, bundle: bundle)
            try a.prepareProfile(.rename(id: id, name: "Stale rename"))
            try b.prepareProfile(.delete(id: id))
            guard case .some(.accepted(_, let bTask)) = b.confirmPreparedChange()
            else { return XCTFail("B delete rejected") }
            guard case .saved = await bTask.value else { return XCTFail("B delete not saved") }
            guard case .some(.rejected(_, .invalid)) = a.confirmPreparedChange()
            else { return XCTFail("A stale rename was not synchronously rejected") }
            await services.policyBridge.drain()
            XCTAssertTrue(first.profiles.isEmpty); XCTAssertTrue(second.profiles.isEmpty)
            let durable = await services.settings.load()
            XCTAssertTrue(durable.envelope?.preferences?.profiles.isEmpty == true)
        }

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let a = SettingsWorkflowController(store: first, bundle: bundle)
            let b = SettingsWorkflowController(store: second, bundle: bundle)
            try a.prepareProfile(.delete(id: id))
            try b.prepareProfile(.rename(id: id, name: "B wins"))
            guard case .some(.accepted(_, let bTask)) = b.confirmPreparedChange(),
                  case .saved = await bTask.value else { return XCTFail("B rename not saved") }
            guard case .some(.rejected(_, .invalid)) = a.confirmPreparedChange()
            else { return XCTFail("A stale delete was not synchronously rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles, [SavedProfile(id: id, name: "B wins", values: .init())])
            XCTAssertEqual(second.profiles, first.profiles)
            let durable = await services.settings.load()
            XCTAssertEqual(durable.envelope?.preferences?.profiles ?? [], first.profiles)
        }

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let a = SettingsWorkflowController(store: first, bundle: bundle)
            let b = SettingsWorkflowController(store: second, bundle: bundle)
            let workers = SettingID(rawValue: "scan.requestedWorkers")
            try a.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(2)])))
            try b.prepareProfile(.update(id: id,
                values: .init(fields: [workers: .integer(4)])))
            guard case .some(.accepted(_, let bTask)) = b.confirmPreparedChange(),
                  case .saved = await bTask.value else { return XCTFail("B update not saved") }
            guard case .some(.rejected(_, .invalid)) = a.confirmPreparedChange()
            else { return XCTFail("A stale value update was not rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles.first?.values.fields[workers], .integer(4))
            XCTAssertEqual(second.profiles, first.profiles)
            let durable = await services.settings.load()
            XCTAssertEqual(durable.envelope?.preferences?.profiles, first.profiles)
        }
    }

    @MainActor func testOlderUnrelatedPreviewRebasesAndPendingInterleaveConverges() async throws {
        let id = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let units = SettingID(rawValue: "ui.units")
        let original = SavedProfile(id: id, name: "Original", values: .init())
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [original])))

        try await run(seed: seed) { _, services, _ in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let a = SettingsWorkflowController(store: first,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            try a.prepareProfile(.rename(id: id, name: "A"))
            guard case .accepted(_, let bTask) = second.setGlobalPreference(
                units, to: .choice("decimal")), case .saved = await bTask.value
            else { return XCTFail("Unrelated B save failed") }
            guard case .some(.accepted(_, let aTask)) = a.confirmPreparedChange(),
                  case .saved = await aTask.value else {
                return XCTFail("Older unrelated A delta did not rebase")
            }
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles.first?.name, "A")
            XCTAssertEqual(first.preferences.global.fields[units], .choice("decimal"))
            XCTAssertEqual(second.preferences, first.preferences)
        }

        try await run(stops: ["config.1"], seed: seed) { _, services, io in
            let acknowledged = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: acknowledged, bridge: services.policyBridge)
            let a = SettingsWorkflowController(store: first,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            try a.prepareProfile(.rename(id: id, name: "Queued A"))
            guard case .accepted = second.setGlobalPreference(units, to: .choice("decimal"))
            else { return XCTFail("Queued B save rejected") }
            try await io.probe.waitFor("config.1")
            guard case .some(.accepted) = a.confirmPreparedChange()
            else { return XCTFail("Pending A save rejected") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 2)
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(first.profiles.first?.name, "Queued A")
            XCTAssertEqual(first.preferences.global.fields[units], .choice("decimal"))
            XCTAssertEqual(second.preferences, first.preferences)
            XCTAssertEqual(first.settingsRevision, 2)
            XCTAssertEqual(second.settingsRevision, 2)
        }
    }

    @MainActor func testImportTaxonomyIssueConfirmCancelAndNoActivation() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
            try c.prepareProfile(.create(id: profileID, name: "Collision", values: .init()))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain()
            let data = try services.configStore.exportPortableSettings()
            let before = services.configStore.preferences
            let revision = services.configStore.settingsRevision
            await c.beginImportSelection(bytes: data).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            let shown = SettingsWorkflowPresentation.importOutcomes(summary)
            XCTAssertEqual(shown.map(\.outcome), SettingsWorkflowPresentation.importOutcomeOrder)
            XCTAssertEqual(Set(shown.map(\.outcome.rawValue)), Set([
                SettingsImportOutcome.committable, .collision, .inert, .redacted, .requiresLocalReassociation,
                .rejectedAuthority, .rejectedProtectionWeakening, .rejectedInvalid,
                .rejectedNonPortable, .rejectedUnsupportedLayer].map(\.rawValue)))
            XCTAssertTrue(shown.allSatisfy { SettingsWorkflowPresentation.accessibilityID(
                for: $0.outcome) == "settings.import.outcome." + $0.outcome.rawValue })
            XCTAssertEqual(summary.collisions.map(\.profileID), [profileID])
            XCTAssertEqual(SettingsWorkflowPresentation.canIssuePreview(
                summary: summary, choices: [:]), false)
            c.chooseCollision(profileID: profileID, choice: .keepLocal)
            XCTAssertTrue(SettingsWorkflowPresentation.canIssuePreview(
                summary: summary, choices: c.collisionChoices))
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .idle); XCTAssertEqual(services.configStore.preferences, before)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            await c.beginImportSelection(bytes: data).value
            guard case .analysis(let secondAnalysis) = c.importState else { return XCTFail() }
            for collision in secondAnalysis.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .replace)
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation = c.importState else { return XCTFail() }
            await c.beginImportCancellation().value
            XCTAssertEqual(services.configStore.preferences, before)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            await c.beginImportSelection(bytes: data).value
            guard case .analysis(let thirdAnalysis) = c.importState else { return XCTFail() }
            let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
            for collision in thirdAnalysis.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            XCTAssertEqual(c.collisionChoices[profileID], .clone(cloneID))
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            let active = services.configStore.activeProfileID
            XCTAssertEqual(preview.candidate.preferences.projects, [:])
            XCTAssertNotNil(preview.candidate.preferences.profiles.first(where: {
                $0.id == cloneID
            }))
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertEqual(services.configStore.activeProfileID, active)
            XCTAssertNotNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            XCTAssertEqual(services.configStore.settingsRevision, revision + 1)
            let generation = services.policyBridge.updateGeneration
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
        }
    }

    @MainActor func testImportConfirmationAwaitsSavedAndConsumesTokenOnce() async throws {
        let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [
                SavedProfile(id: profileID, name: "Local", values: .init())])))
        try await run(stops: ["config.1"], seed: seed) { _, services, io in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            let retainedSummary = try XCTUnwrap(c.importReviewSummary)
            let retainedDigests = try XCTUnwrap(c.importReviewDigests)
            let revision = services.configStore.settingsRevision
            let confirmation = c.beginImportConfirmation()
            try await io.probe.waitFor("config.1")
            XCTAssertEqual(c.importState, .submitting(preview.id),
                           "UI claimed saved before the accepted outcome")
            XCTAssertEqual(c.importReviewSummary, retainedSummary)
            XCTAssertEqual(c.importReviewDigests, retainedDigests)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            io.probe.release("config.1")
            await confirmation.value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertNil(c.importReviewSummary); XCTAssertNil(c.importReviewDigests)
            XCTAssertEqual(services.configStore.settingsRevision, revision + 1)
            XCTAssertNotNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Consumed import token was accepted twice") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
        }
    }

    @MainActor func testImportConfirmationConflictAndPersistenceFailureNeverClaimSaved() async throws {
        let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [
                SavedProfile(id: profileID, name: "Local", values: .init())])))

        try await run(seed: seed) { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            guard case .accepted(_, let otherTask) = services.configStore.setGlobalPreference(
                SettingID(rawValue: "ui.units"), to: .choice("decimal")),
                  case .saved = await otherTask.value else { return XCTFail("Other save failed") }
            let revision = services.configStore.settingsRevision
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: bundle)))
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Invalidated token remained usable") }
        }

        try await run(seed: seed, fault: .configReplaceNumber(1)) { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let before = services.configStore.preferences
            let revision = services.configStore.settingsRevision
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            await c.beginImportConfirmation().value
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: bundle)))
            XCTAssertEqual(services.configStore.preferences, before)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Failed import token remained reusable") }
        }
    }

    @MainActor func testLiveRejectedConfirmationClearsIssuedBindingWithoutRetention() async throws {
        let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let cloneID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let seed = try SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [
                SavedProfile(id: profileID, name: "Local", values: .init())])))
        try await run(stops: ["config.1"], seed: seed) { _, services, io in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            for collision in summary.collisions {
                c.chooseCollision(profileID: collision.profileID, choice: .clone(cloneID))
            }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let oldPreview) = c.importState else { return XCTFail() }
            guard case .accepted = services.configStore.setGlobalPreference(
                SettingID(rawValue: "ui.units"), to: .choice("decimal"))
            else { return XCTFail("Unrelated write was not enqueued") }
            try await io.probe.waitFor("config.1")
            let retainedCount = services.policyBridge.pendingSnapshotCount
            let retainedBytes = services.policyBridge.pendingSnapshotBytes
            XCTAssertEqual(retainedCount, 1); XCTAssertGreaterThan(retainedBytes, 0)
            let rejection = c.beginImportConfirmation()
            XCTAssertEqual(c.importState, .submitting(oldPreview.id))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, retainedCount)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, retainedBytes,
                           "Rejected import retained payload bytes")
            io.probe.release("config.1")
            await rejection.value
            await services.policyBridge.drain()
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: bundle)))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            guard case .rejected(_, .invalid) = services.configStore.commitImport(oldPreview)
            else { return XCTFail("Cancelled issued preview binding remained reusable") }
            XCTAssertNil(services.configStore.profiles.first(where: { $0.id == cloneID }))
        }
    }

    @MainActor func testImportConfirmationHandlesEveryAcceptedNonSavedOutcome() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let summary = try self.workflowSummary(UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            let preview = self.workflowPreview(summary)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            let outcomes: [SettingsIntentOutcome] = [
                .conflict(intent), .invalid(intent), .failed(intent, recoveryRequired: true)
            ]
            for outcome in outcomes {
                var submissionCount = 0
                let operations = SettingsWorkflowImportOperations(
                    analyze: { _ in summary }, issue: { _, _ in preview },
                    cancelAnalysis: { _ in }, cancelPreview: { _ in },
                    submit: { _ in
                        submissionCount += 1
                        return .accepted(intent, Task { outcome })
                    })
                let c = SettingsWorkflowController(testing: services.configStore,
                    importOperations: operations, bundle: bundle)
                let revision = services.configStore.settingsRevision
                await c.beginImportSelection(bytes: Data([1])).value
                await c.beginImportPreviewIssuance().value
                await c.beginImportConfirmation().value
                XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                    "settings.import.failure", bundle: bundle)))
                XCTAssertEqual(submissionCount, 1)
                XCTAssertEqual(services.configStore.settingsRevision, revision)
                await c.beginImportConfirmation().value
                XCTAssertEqual(submissionCount, 1, "Non-saved preview was submitted twice")
            }
        }
    }

    @MainActor func testSynchronousImportRejectionCancelsIssuedPreviewExactlyOnce() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let summary = try self.workflowSummary(UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            let preview = self.workflowPreview(summary)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            let reasons: [SettingsSubmissionRejection] = [
                .invalid, .unsupportedAuthority, .queueFull, .unavailable
            ]
            for reason in reasons {
                let gate = SettingsWorkflowAsyncGate()
                let operations = SettingsWorkflowImportOperations(
                    analyze: { _ in summary }, issue: { _, _ in preview },
                    cancelAnalysis: { _ in },
                    cancelPreview: { id in
                        gate.recordPreviewCancellation(id)
                        await gate.suspend(at: .rejectCancel)
                    },
                    submit: { _ in .rejected(intent, reason) })
                let c = SettingsWorkflowController(testing: services.configStore,
                    importOperations: operations, bundle: bundle)
                await c.beginImportSelection(bytes: Data([1])).value
                await c.beginImportPreviewIssuance().value
                let confirmation = c.beginImportConfirmation()
                await gate.waitUntilEntered(.rejectCancel)
                XCTAssertEqual(c.importState, .submitting(preview.id),
                               "Failure was shown before cancellation for \(reason)")
                XCTAssertEqual(gate.cancelledPreviewIDs, [preview.id])
                gate.release(.rejectCancel); await confirmation.value
                XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                    "settings.import.failure", bundle: bundle)))
                XCTAssertEqual(gate.cancelledPreviewIDs, [preview.id])
                await c.beginImportConfirmation().value
                XCTAssertEqual(gate.cancelledPreviewIDs, [preview.id])
            }
        }
    }

    @MainActor func testImportGenerationSupersedesAndCancelsDeterministically() async throws {
        try await run { _, services, _ in
            let gate = SettingsWorkflowAsyncGate()
            let a = try self.workflowSummary(UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            let b = try self.workflowSummary(UUID(uuidString:
                "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
            let preview = self.workflowPreview(b)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            var acceptedSubmissionCount = 0
            let operations = SettingsWorkflowImportOperations(
                analyze: { data in
                    switch data.first {
                    case 1:
                        await gate.suspend(at: .analyzeA)
                        throw SettingsWorkflowFixtureError.failedAnalysis
                    case 2:
                        await gate.suspend(at: .analyzeB); return b
                    case 3:
                        await gate.suspend(at: .analyzeCancel); return a
                    default: return b
                    }
                },
                issue: { _, _ in await gate.suspend(at: .issue); return preview },
                cancelAnalysis: { gate.recordAnalysisCancellation($0) },
                cancelPreview: { gate.recordPreviewCancellation($0) },
                submit: { _ in
                    acceptedSubmissionCount += 1
                    return .accepted(intent, Task {
                        await gate.suspend(at: .submit); return .invalid(intent)
                    })
                })

            let testBundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(testing: services.configStore,
                                               importOperations: operations,
                                               bundle: testBundle)
            XCTAssertTrue(c.bundle === testBundle)
            let first = c.beginImportSelection(bytes: Data([1]))
            await gate.waitUntilEntered(.analyzeA)
            let second = c.beginImportSelection(bytes: Data([2]))
            await gate.waitUntilEntered(.analyzeB)
            gate.release(.analyzeB); await second.value
            XCTAssertEqual(c.importState, .analysis(b))
            gate.release(.analyzeA); await first.value
            XCTAssertEqual(c.importState, .analysis(b), "stale failure replaced newer success")

            let cancelDuringAnalysis = c.beginImportSelection(bytes: Data([3]))
            await gate.waitUntilEntered(.analyzeCancel)
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .idle)
            XCTAssertTrue(gate.cancelledAnalysisIDs.contains(b.analysisID))
            gate.release(.analyzeCancel); await cancelDuringAnalysis.value
            XCTAssertEqual(c.importState, .idle, "cancelled analysis completed into UI")
            XCTAssertTrue(gate.cancelledAnalysisIDs.contains(a.analysisID),
                          "stale returned analysis token was retained")

            await c.beginImportSelection(bytes: Data([9])).value
            XCTAssertEqual(c.importState, .analysis(b))
            let issuing = c.beginImportPreviewIssuance()
            await gate.waitUntilEntered(.issue)
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .idle)
            gate.release(.issue); await issuing.value
            XCTAssertEqual(c.importState, .idle, "cancelled issuance restored preview")
            XCTAssertTrue(gate.cancelledPreviewIDs.contains(preview.id))

            await c.beginImportSelection(bytes: Data([9])).value
            let issueForConfirmation = c.beginImportPreviewIssuance()
            await gate.waitUntilEntered(.issue); gate.release(.issue)
            await issueForConfirmation.value
            guard case .confirmation = c.importState else { return XCTFail() }
            let confirming = c.beginImportConfirmation()
            await gate.waitUntilEntered(.submit)
            let previewCancellationCount = gate.cancelledPreviewIDs.count
            await c.beginImportSelection(bytes: Data([9])).value
            await c.beginImportPreviewIssuance().value
            await c.beginImportConfirmation().value
            await c.beginImportCancellation().value
            XCTAssertEqual(c.importState, .submitting(preview.id),
                           "A public boundary superseded an accepted write")
            XCTAssertEqual(acceptedSubmissionCount, 1,
                           "Accepted preview was submitted more than once")
            XCTAssertEqual(gate.cancelledPreviewIDs.count, previewCancellationCount,
                           "Submitting cancellation touched an accepted token")
            gate.release(.submit); await confirming.value
            XCTAssertEqual(c.importState, .failed(SettingsCopy.resolve(
                "settings.import.failure", bundle: testBundle)),
                "Accepted invalid outcome was generation-suppressed")

            let cancellationCount = gate.cancelledAnalysisIDs.count
            let failing = SettingsWorkflowImportOperations(analyze: { _ in b },
                issue: { _, _ in throw SettingsWorkflowFixtureError.failedIssuance },
                cancelAnalysis: { gate.recordAnalysisCancellation($0) },
                cancelPreview: { gate.recordPreviewCancellation($0) },
                submit: { services.configStore.commitImport($0) })
            let failed = SettingsWorkflowController(testing: services.configStore,
                                                    importOperations: failing,
                                                    bundle: testBundle)
            await failed.beginImportSelection(bytes: Data([9])).value
            await failed.beginImportPreviewIssuance().value
            guard case .failed(let message) = failed.importState else { return XCTFail() }
            XCTAssertEqual(message, SettingsCopy.resolve("settings.import.failure",
                bundle: testBundle))
            XCTAssertEqual(gate.cancelledAnalysisIDs.count, cancellationCount + 1)
        }
    }

    @MainActor func testLiveImportIssuanceRejectsWhileSettingsWriteIsQueued() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore,
                bundle: bundle)
            XCTAssertTrue(c.bundle === bundle)
            let bytes = try services.configStore.exportPortableSettings()
            await c.beginImportSelection(bytes: bytes).value
            guard case .analysis(let summary) = c.importState else { return XCTFail() }
            await c.beginImportPreviewIssuance().value
            guard case .confirmation(let preview) = c.importState else { return XCTFail() }
            guard case .accepted = services.configStore.setGlobalPreference(
                SettingID(rawValue: "ui.units"), to: .choice("decimal"))
            else { return XCTFail("Queue head rejected") }
            try await io.probe.waitFor("config.1")
            let generation = services.policyBridge.updateGeneration
            let confirmation = c.beginImportConfirmation()
            XCTAssertEqual(c.importState, .submitting(preview.id))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 1)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            io.probe.release("config.1")
            await confirmation.value
            guard case .failed(let message) = c.importState else { return XCTFail() }
            XCTAssertEqual(message, SettingsCopy.resolve("settings.import.failure",
                bundle: bundle))
            await services.policyBridge.drain()
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Rejected issued preview was reusable") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            _ = summary // The issued analysis is intentionally no longer retained by the controller.
        }
    }

    @MainActor func testResetExportAndDeferredBoundaries() async throws {
        try await run { _, services, _ in
            let id = SettingID(rawValue: "cleanup.inactiveDays")
            _ = services.configStore.setGlobalPreference(id, to: .integer(90))
            await services.policyBridge.drain()
            let config = services.configStore.config, inert = services.configStore.inertImports
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let c = SettingsWorkflowController(store: services.configStore, bundle: bundle)
            try c.prepareReset(.init(globalPreferenceIDs: [id]))
            guard case .reset(let preview)? = c.confirmation else { return XCTFail() }
            XCTAssertEqual(preview.immutableBoundaries, Set(SettingsResetBoundary.allCases))
            XCTAssertTrue(preview.delta.inert.isEmpty && !preview.delta.touchesActiveProfile)
            c.cancelConfirmation(); XCTAssertEqual(services.configStore.config, config)
            XCTAssertEqual(services.configStore.inertImports, inert)
            let revision = services.configStore.settingsRevision
            try c.prepareReset(.init(globalPreferenceIDs: [id]))
            guard case .some(.accepted) = c.confirmPreparedChange() else { return XCTFail() }
            await services.policyBridge.drain()
            XCTAssertNil(services.configStore.preferences.global.fields[id])
            XCTAssertEqual(services.configStore.settingsRevision, revision + 1)
            XCTAssertEqual(services.configStore.config, config)
            XCTAssertEqual(services.configStore.inertImports, inert)
            let a = try services.configStore.exportPortableSettings()
            let b = try services.configStore.exportPortableSettings()
            XCTAssertEqual(a, b); XCTAssertLessThanOrEqual(a.count, 1_048_576)
            for deferred in SettingsDeferredWorkflow.allCases {
                let key = "settings.deferred.\(deferred.rawValue).explanation"
                XCTAssertEqual(SettingsWorkflowPresentation.deferredExplanationKey(deferred), key)
                let copy = SettingsWorkflowPresentation.deferredExplanation(
                    deferred, bundle: bundle)
                XCTAssertFalse(copy.isEmpty)
                XCTAssertNotEqual(copy, key)
                XCTAssertNotEqual(copy, "Description unavailable.")
                XCTAssertTrue(copy.localizedCaseInsensitiveContains("unavailable"))
            }
        }
    }

    func testSyntheticImportTaxonomyHasExactOrderCountsAndCollisions() throws {
        let order = SettingsWorkflowPresentation.importOutcomeOrder
        XCTAssertEqual(order, [.committable, .collision, .inert, .redacted,
            .requiresLocalReassociation, .rejectedAuthority, .rejectedProtectionWeakening,
            .rejectedInvalid, .rejectedNonPortable, .rejectedUnsupportedLayer])
        var rows: [SettingsImportRow] = []
        for (index, outcome) in order.enumerated() {
            rows += (0...index).map { occurrence in
                SettingsImportRow(scope: .global, profileID: nil,
                    id: "fixture.\(outcome.rawValue).\(occurrence)", idDigest: nil,
                    outcome: outcome, value: nil, valueKind: nil, valueDigest: nil)
            }
        }
        let collisions = [
            ProfileImportCollision(profileID: UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, localName: "A", importedName: "A2"),
            ProfileImportCollision(profileID: UUID(uuidString:
                "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, localName: "B", importedName: "B2"),
            ProfileImportCollision(profileID: UUID(uuidString:
                "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!, localName: "D", importedName: "D2")
        ]
        let analysis = SettingsImportAnalysis(analysisID: UUID(uuidString:
            "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!, rows: rows,
            collisions: collisions, committableImported: .init(), importedInert: [], current: .init())
        let summary = try SettingsImportUISummary(analysis)
        let shown = SettingsWorkflowPresentation.importOutcomes(summary)
        XCTAssertEqual(shown.map(\.outcome), order)
        XCTAssertEqual(shown.map(\.count), Array(1...10))
        XCTAssertEqual(summary.collisions, collisions)
        XCTAssertEqual(summary.collisions.count, 3)
        XCTAssertEqual(shown.first(where: { $0.outcome == .collision })?.count, 2)
        XCTAssertEqual(shown.map(\.id), order.map(\.rawValue))
    }

    func testWorkflowControlProjectionIsExhaustiveStableAndContiguous() throws {
        let a = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let b = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let globalField = SettingID(rawValue: "cleanup.inactiveDays")
        let profileField = SettingID(rawValue: "scan.requestedWorkers")
        let restriction = SettingID(rawValue: "feature.headroom")
        let collisions = [
            ProfileImportCollision(profileID: b, localName: "B", importedName: "Imported B"),
            ProfileImportCollision(profileID: a, localName: "A", importedName: "Imported A")
        ]
        let localize: (String) -> String = { "Resolved " + $0 }
        let empty = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [], activeProfileID: nil, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)
        let full = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [b, a, b], activeProfileID: a,
            profileEditor: .init(target: .profile(a),
                                 valueFieldIDs: [restriction, profileField, restriction]),
            importPhase: .analysis, collisions: collisions,
            hasCompleteCollisionChoices: true, hasPreparedProfile: true,
            resetGlobalFieldIDs: [globalField, globalField], resetProfileID: a,
            resetProfileFieldIDs: [restriction, profileField, restriction],
            ownedRestrictionFieldIDs: [restriction], hasResetSelection: true,
            hasPreparedReset: true), localize: localize)
        for controls in [empty, full] {
            XCTAssertEqual(controls.map(\.focusOrder), Array(controls.indices))
            XCTAssertEqual(Set(controls.map(\.id)).count, controls.count)
            XCTAssertTrue(controls.allSatisfy { !$0.label.isEmpty && $0.label != $0.titleKey })
            for descriptor in controls {
                if case .unavailable(let key, let label) = descriptor.availability {
                    XCTAssertFalse(key.isEmpty); XCTAssertFalse(label.isEmpty)
                    XCTAssertNotEqual(key, label)
                }
            }
        }
        XCTAssertEqual(Set(empty.map(\.role)).union(full.map(\.role)),
                       Set(SettingsWorkflowControlRole.allCases))
        XCTAssertEqual(SettingsWorkflowPresentation.maximumControlDescriptors, 3_423)
        XCTAssertLessThanOrEqual(full.count, SettingsWorkflowPresentation.maximumControlDescriptors)
        let factories = full.filter { $0.role == .createFactory }
        XCTAssertEqual(factories.count, 6)
        XCTAssertEqual(Set(factories.compactMap(\.identity)),
                       Set(SessionProfiles.factoryKeys.map {
                           SettingsWorkflowControlIdentity.factory($0)
                       }))
        for key in SessionProfiles.factoryKeys {
            let descriptor = try XCTUnwrap(factories.first { $0.identity == .factory(key) })
            XCTAssertEqual(descriptor.id, "settings.profile.factory." + key)
            XCTAssertTrue(descriptor.label.contains(key))
            XCTAssertEqual(descriptor.availability, .unavailable(
                reasonKey: "settings.control.unavailable.issuedPreview",
                label: "Resolved settings.control.unavailable.issuedPreview"))
        }
        for role in [SettingsWorkflowControlRole.cloneProfile, .renameProfile,
                     .deleteProfile, .activateProfile, .deactivateProfile] {
            let actions = full.filter { $0.role == role }
            XCTAssertEqual(actions.count, 2)
            XCTAssertEqual(actions.compactMap(\.identity), [
                SettingsWorkflowControlIdentity.profile(a), .profile(b)
            ])
            XCTAssertEqual(actions.map(\.id), [a, b].map {
                "settings.profile.action.\(role.rawValue).\($0.uuidString)"
            })
            XCTAssertTrue(actions.allSatisfy { descriptor in
                guard case .profile(let id)? = descriptor.identity else { return false }
                return descriptor.label.contains(id.uuidString)
            })
        }
        let name = try XCTUnwrap(full.first { $0.role == .profileNameEditor })
        XCTAssertEqual(name.id, "settings.profile.editor.name." + a.uuidString)
        XCTAssertEqual(name.identity, .profileName(.profile(a)))
        XCTAssertTrue(name.label.contains(a.uuidString))
        XCTAssertEqual(name.availability, .unavailable(
            reasonKey: "settings.control.unavailable.issuedPreview",
            label: "Resolved settings.control.unavailable.issuedPreview"))
        let values = full.filter { $0.role == .profileValueEditor }
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(Set(values.map(\.id)), Set([profileField, restriction].map {
            "settings.profile.editor.value.\(a.uuidString).\($0.rawValue)"
        }))
        XCTAssertTrue(values.allSatisfy { descriptor in
            descriptor.label.contains(a.uuidString) &&
                [profileField.rawValue, restriction.rawValue].contains(where: {
                    descriptor.label.contains($0)
                })
        })
        XCTAssertTrue(values.allSatisfy {
            $0.availability == .unavailable(
                reasonKey: "settings.control.unavailable.issuedPreview",
                label: "Resolved settings.control.unavailable.issuedPreview")
        })
        let newEditor = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [a], activeProfileID: nil,
            profileEditor: .init(target: .newProfile, valueFieldIDs: [profileField]),
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)
        XCTAssertEqual(newEditor.first { $0.role == .profileNameEditor }?.id,
                       "settings.profile.editor.name.new")
        XCTAssertEqual(newEditor.first { $0.role == .profileValueEditor }?.id,
                       "settings.profile.editor.value.new." + profileField.rawValue)
        XCTAssertTrue(newEditor.filter {
            $0.role == .profileNameEditor || $0.role == .profileValueEditor
        }.allSatisfy { $0.label.contains("new") })
        for (role, choice) in [
            (SettingsWorkflowControlRole.collisionKeepLocal,
             ProfileCollisionControlChoice.keepLocal),
            (.collisionReplace, .replace), (.collisionClone, .clone)
        ] {
            let choices = full.filter { $0.role == role }
            XCTAssertEqual(choices.count, 2)
            XCTAssertEqual(choices.compactMap(\.identity), [
                SettingsWorkflowControlIdentity.collision(a, choice), .collision(b, choice)
            ])
            XCTAssertEqual(choices.map(\.id), [a, b].map {
                "settings.import.collision.\($0.uuidString).\(choice.rawValue)"
            })
            XCTAssertTrue(choices.allSatisfy { descriptor in
                guard case .collision(let id, _)? = descriptor.identity else { return false }
                guard let collision = collisions.first(where: { $0.profileID == id }) else {
                    return false
                }
                return descriptor.label.contains(choice.rawValue) &&
                    descriptor.label.contains(id.uuidString) &&
                    descriptor.label.contains(collision.localName) &&
                    descriptor.label.contains(collision.importedName)
            })
            XCTAssertTrue(choices.allSatisfy { $0.availability == .enabled })
        }
        XCTAssertEqual(full.filter { $0.role == .resetGlobalField }.map(\.id),
                       ["settings.reset.global." + globalField.rawValue])
        let resetFields = full.filter {
            $0.role == .resetGlobalField || $0.role == .resetProfileField
        }
        XCTAssertTrue(resetFields.allSatisfy { descriptor in
            switch descriptor.identity {
            case .some(.globalResetField(let id)): return descriptor.label.contains(id.rawValue)
            case .some(.profileResetField(let profileID, let id)):
                return descriptor.label.contains(profileID.uuidString) &&
                    descriptor.label.contains(id.rawValue)
            default: return false
            }
        })
        XCTAssertTrue(resetFields.allSatisfy { $0.availability == .unavailable(
            reasonKey: "settings.control.unavailable.resetPreview",
            label: "Resolved settings.control.unavailable.resetPreview") })
        XCTAssertEqual(Set(full.filter { $0.role == .resetProfileField }.map(\.id)),
            Set([profileField, restriction].map {
                "settings.reset.profile.\(a.uuidString).\($0.rawValue)"
            }))
        let optIn = try XCTUnwrap(full.first { $0.role == .resetRestrictionOptIn })
        XCTAssertEqual(optIn.id,
            "settings.reset.restrictionOptIn.\(a.uuidString).\(restriction.rawValue)")
        XCTAssertTrue(optIn.label.contains(a.uuidString))
        XCTAssertTrue(optIn.label.contains(restriction.rawValue))
        XCTAssertEqual(optIn.availability, .unavailable(
            reasonKey: "settings.control.unavailable.resetPreview",
            label: "Resolved settings.control.unavailable.resetPreview"))
        XCTAssertEqual(full.first(where: { $0.role == .issueImport })?.availability, .enabled)
        XCTAssertEqual(full.first(where: { $0.role == .confirmProfile })?.availability, .enabled)
        guard case .some(.unavailable) = empty.first(where: {
            $0.role == .confirmProfile
        })?.availability
        else { return XCTFail("Profile confirmation enabled without a preview") }
        XCTAssertEqual(empty.first(where: { $0.role == .issueImport })?.availability,
                       .unavailable(reasonKey: "settings.control.unavailable.importAnalysis",
                                    label: "Resolved settings.control.unavailable.importAnalysis"))
        for role in [SettingsWorkflowControlRole.localReassociation,
                     .historyAndIndexClearing] {
            guard case .some(.unavailable) = full.first(where: {
                $0.role == role
            })?.availability
            else { return XCTFail("Deferred control became available: \(role)") }
        }
        var confirmationDescriptorIDs: [String] = []
        for phase in SettingsWorkflowImportPhase.allCases {
            let controls = try SettingsWorkflowPresentation.controls(context: .init(
                profileIDs: [a], activeProfileID: a,
                profileEditor: .init(target: .profile(a), valueFieldIDs: [profileField]),
                importPhase: phase, collisions: [collisions[1]],
                hasCompleteCollisionChoices: true, hasPreparedProfile: true,
                resetGlobalFieldIDs: [globalField], resetProfileID: a,
                resetProfileFieldIDs: [profileField], ownedRestrictionFieldIDs: [],
                hasResetSelection: true,
                hasPreparedReset: true), localize: localize)
            let enabled: (SettingsWorkflowControlRole) -> Bool = { role in
                controls.first(where: { $0.role == role })?.availability == .enabled
            }
            if phase == .confirmation { confirmationDescriptorIDs = controls.map(\.id) }
            if phase == .submitting {
                XCTAssertEqual(controls.map(\.id), confirmationDescriptorIDs,
                               "Submitting removed readable/focus-stable rows")
                for descriptor in controls {
                    if Set([SettingsWorkflowControlRole.localReassociation,
                            .historyAndIndexClearing]).contains(descriptor.role) {
                        XCTAssertEqual(descriptor.availability, .unavailable(
                            reasonKey: "settings.control.unavailable.deferred",
                            label: "Resolved settings.control.unavailable.deferred"))
                    } else {
                        XCTAssertEqual(descriptor.availability, .unavailable(
                            reasonKey: "settings.control.unavailable.submitting",
                            label: "Resolved settings.control.unavailable.submitting"),
                            descriptor.id)
                    }
                    XCTAssertFalse(descriptor.label.isEmpty)
                }
                continue
            }
            XCTAssertEqual(enabled(.issueImport), phase == .analysis)
            XCTAssertEqual(enabled(.confirmImport), phase == .confirmation)
            XCTAssertEqual(enabled(.cancelImport),
                Set([.analyzing, .analysis, .issuing, .confirmation]).contains(phase))
            for role in [SettingsWorkflowControlRole.collisionKeepLocal,
                         .collisionReplace, .collisionClone] {
                XCTAssertEqual(enabled(role), phase == .analysis)
            }
            XCTAssertTrue(enabled(.previewReset)); XCTAssertTrue(enabled(.confirmReset))
            XCTAssertFalse(enabled(.resetGlobalField)); XCTAssertFalse(enabled(.resetProfileField))
            XCTAssertFalse(enabled(.profileNameEditor)); XCTAssertFalse(enabled(.profileValueEditor))
        }
        let actionable = try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [a], activeProfileID: a, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)
        let activeActions = actionable.filter { $0.identity == .profile(a) }
        XCTAssertEqual(activeActions.first(where: { $0.role == .activateProfile })?.availability,
                       .unavailable(reasonKey: "settings.control.unavailable.activeProfile",
                                    label: "Resolved settings.control.unavailable.activeProfile"))
        XCTAssertEqual(activeActions.first(where: { $0.role == .deactivateProfile })?.availability,
                       .enabled)
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: [], activeProfileID: a, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError,
                               .invalidActiveProfile(a))
            }
        let tooMany = (0...50).map { index in UUID(uuidString: String(format:
            "A0000000-0000-0000-0000-%012d", index))! }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(context: .init(
            profileIDs: tooMany, activeProfileID: nil, profileEditor: nil,
            importPhase: .idle, collisions: [], hasCompleteCollisionChoices: false,
            hasPreparedProfile: false, resetGlobalFieldIDs: [], resetProfileID: nil,
            resetProfileFieldIDs: [], ownedRestrictionFieldIDs: [], hasResetSelection: false,
            hasPreparedReset: false), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyProfiles)
            }
    }

    func testWorkflowControlDynamicBoundsRejectWithoutTruncation() throws {
        let profile = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let localize: (String) -> String = { "Resolved " + $0 }
        func context(collisions: [ProfileImportCollision] = [],
                     editorFields: [SettingID] = [], resetGlobal: [SettingID] = [],
                     resetProfile: [SettingID] = [], restrictions: Set<SettingID> = [])
            -> SettingsWorkflowControlContext {
            .init(profileIDs: [profile], activeProfileID: nil,
                profileEditor: editorFields.isEmpty ? nil : .init(
                    target: .profile(profile), valueFieldIDs: editorFields),
                importPhase: .analysis, collisions: collisions,
                hasCompleteCollisionChoices: true, hasPreparedProfile: false,
                resetGlobalFieldIDs: resetGlobal,
                resetProfileID: resetProfile.isEmpty ? nil : profile,
                resetProfileFieldIDs: resetProfile,
                ownedRestrictionFieldIDs: restrictions,
                hasResetSelection: !resetGlobal.isEmpty || !resetProfile.isEmpty,
                hasPreparedReset: false)
        }
        let collision = ProfileImportCollision(profileID: profile,
            localName: "Local", importedName: "Imported")
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(collisions: [collision, collision]), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError,
                               .duplicateCollision(profile))
            }
        let tooManyCollisions = (0...50).map { index in
            ProfileImportCollision(profileID: UUID(uuidString: String(format:
                "B0000000-0000-0000-0000-%012d", index))!,
                localName: "L", importedName: "I")
        }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(collisions: tooManyCollisions), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyCollisions)
            }
        let tooManyFields = (0...1_000).map {
            SettingID(rawValue: "fixture.field.\($0)")
        }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(editorFields: tooManyFields), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyEditorFields)
            }
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(
            context: context(resetGlobal: tooManyFields), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError, .tooManyResetFields)
            }
        let preference = SettingID(rawValue: "scan.requestedWorkers")
        let restriction = SettingID(rawValue: "feature.headroom")
        XCTAssertThrowsError(try SettingsWorkflowPresentation.controls(context: context(
            resetProfile: [preference], restrictions: [restriction]), localize: localize)) {
                XCTAssertEqual($0 as? SettingsWorkflowPresentationError,
                               .invalidRestrictionOptIn(restriction))
            }
        let valid = try SettingsWorkflowPresentation.controls(context: context(
            editorFields: [preference], resetProfile: [preference, restriction],
            restrictions: [restriction]), localize: localize)
        XCTAssertLessThanOrEqual(valid.count,
            SettingsWorkflowPresentation.maximumControlDescriptors)
    }

    @MainActor func testWorkflowRenderDoesZeroWork() async throws {
        try await run { _, services, _ in
            let generation = services.policyBridge.updateGeneration
            let revision = services.configStore.settingsRevision
            let admission = services.coordinator.policyAdmission()
            for tab in SettingsWorkflowTab.allCases {
                for scheme in [ColorScheme.light, .dark] {
                    for width in [CGFloat(480), 620] {
                        for size in [DynamicTypeSize.large, .accessibility3] {
                            let view = SettingsWorkflowSurface(store: services.configStore,
                                bundle: Bundle(for: SharedSettingsWiringTests.self),
                                                               initialTab: tab)
                            .frame(width: width, height: 900)
                            .environment(services.configStore)
                            .environment(\.colorScheme, scheme)
                            .environment(\.dynamicTypeSize, size)
                            XCTAssertNotNil(ImageRenderer(content: view).cgImage,
                                "\(tab) \(scheme) \(width) \(size)")
                        }
                    }
                }
            }
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(services.configStore.settingsRevision, revision)
            XCTAssertEqual(services.coordinator.policyAdmission(), admission)
            XCTAssertFalse(services.configStore.hasPendingSettingsWrites)
        }
    }

    func testWorkflowLocalizationIsCompleteAndResolved() throws {
        let bundle = Bundle(for: SharedSettingsWiringTests.self)
        var keys = [
            "settings.workflow.tab.profiles", "settings.workflow.tab.transfer",
            "settings.workflow.tab.reset", "settings.workflow.revision",
            "settings.profile.create", "settings.profile.createFactory",
            "settings.profile.clone", "settings.profile.rename", "settings.profile.delete",
            "settings.profile.activate", "settings.profile.deactivate",
            "settings.profile.preview", "settings.profile.confirm", "settings.profile.cancel",
            "settings.profile.diff", "settings.profile.activeBefore",
            "settings.profile.activeAfter", "settings.profile.editor.name",
            "settings.profile.editor.value", "settings.import.choose", "settings.import.analyze",
            "settings.import.issue", "settings.import.confirm", "settings.import.cancel",
            "settings.import.failure", "settings.import.sourceDigest",
            "settings.import.candidateDigest", "settings.import.collision.keepLocal",
            "settings.import.collision.replace", "settings.import.collision.clone",
            "settings.export.choose", "settings.export.ready", "settings.export.failure",
            "settings.reset.select", "settings.reset.ownedRestrictionOptIn",
            "settings.reset.field.global", "settings.reset.field.profile",
            "settings.reset.preview", "settings.reset.confirm", "settings.reset.cancel",
            "settings.reset.immutable", "settings.control.unavailable.noProfile",
            "settings.control.unavailable.activeProfile",
            "settings.control.unavailable.importAnalysis",
            "settings.control.unavailable.issuedPreview",
            "settings.control.unavailable.resetSelection",
            "settings.control.unavailable.resetPreview",
            "settings.control.unavailable.deferred",
            "settings.control.unavailable.submitting"
        ]
        keys += SessionProfiles.factoryKeys.map { "settings.profile.factory." + $0 }
        keys += SettingsWorkflowPresentation.importOutcomeOrder.flatMap {
            ["settings.import.outcome.\($0.rawValue).title",
             "settings.import.outcome.\($0.rawValue).explanation"]
        }
        keys += SettingsResetBoundary.allCases.map {
            "settings.reset.boundary." + $0.rawValue
        }
        keys += SettingsDeferredWorkflow.allCases.flatMap {
            ["settings.deferred.\($0.rawValue).title",
             "settings.deferred.\($0.rawValue).explanation"]
        }
        XCTAssertEqual(keys.count, Set(keys).count)
        for key in keys {
            let value = SettingsCopy.resolve(key, bundle: bundle)
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertNotEqual(value, key)
            XCTAssertNotEqual(value, "Description unavailable.", key)
        }
    }

    func testWorkflowFixtureHostIsDeterministicBoundedAndInert() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "TidyUITestHost/TestHostApp.swift"), encoding: .utf8)
        for state in ["profilesEmpty", "profilesTwo", "profilesActive",
                      "activeDeleteConfirmation", "profileFieldDiff", "importAllOutcomes",
                      "importIncompleteCollision", "importIssuedConfirmation", "importSubmitting",
                      "importMalformedFailure", "resetEmpty", "resetSelected",
                      "resetOwnedRestriction", "immutableAndDeferred"] {
            XCTAssertTrue(source.contains("case " + state), state)
        }
        XCTAssertTrue(source.contains("settings.workflow.fixture.state"))
        XCTAssertTrue(source.contains("settings.workflow.fixture.workCount"))
        XCTAssertTrue(source.contains("Workflow fixture work: 0"))
        XCTAssertTrue(source.contains("SettingsWorkflowPresentation.controls(context:"))
        XCTAssertTrue(source.contains("settings.workflow.fixture.submitting.snapshot"))
        XCTAssertTrue(source.contains("settings.workflow.fixture.submitting.controlCount"))
        XCTAssertTrue(source.contains("descriptor.availability != .enabled"))
        XCTAssertTrue(source.contains("settings.workflow.fixture.projectionFailure"))
        for token in ["UUID()", "Date()", "Data(contentsOf:", "SettingsStore(",
                      "ExecutionPolicyBridge(", "SettingsTransfer.", "requestPlan",
                      "loadPlan", "CleanEngine", "SettingsWorkflowController(testing:"] {
            XCTAssertFalse(source.contains(token), token)
        }
    }

    func testRestrictionResetRequiresEveryMatchingOptInAndProfileFieldsAreExhaustive() {
        let first = SettingID(rawValue: "cleanup.hardBatchGiB")
        let second = SettingID(rawValue: "cleanup.hardBatchItems")
        let preference = SettingID(rawValue: "cleanup.inactiveDays")
        XCTAssertFalse(SettingsWorkflowPresentation.canPreviewReset(
            selectedProfileFieldIDs: [first, second],
            ownedRestrictionFieldIDs: [first, second],
            optedInRestrictionIDs: [first], hasOtherSelection: false),
            "An unrelated restriction opt-in authorized the other selected protection")
        XCTAssertTrue(SettingsWorkflowPresentation.canPreviewReset(
            selectedProfileFieldIDs: [preference, first, second],
            ownedRestrictionFieldIDs: [first, second],
            optedInRestrictionIDs: [first, second], hasOtherSelection: false))
        let expected = Set(SettingsPresentationRegistry.renderedUniverse(volumeIDs: [])
            .filter(SettingsWorkflowPresentation.isEditableProfileField)
            .map(\.id))
        XCTAssertEqual(Set(SettingsWorkflowPresentation.profileEditorFieldIDs), expected)
        XCTAssertEqual(SettingsWorkflowPresentation.profileEditorFieldIDs.count,
                       expected.count)
        XCTAssertFalse(expected.contains(SettingID(rawValue: "scope.currentProject")))
        for (offset, id) in SettingsWorkflowPresentation.profileEditorFieldIDs.enumerated() {
            let definition = try? XCTUnwrap(SettingsPresentationRegistry
                .renderedUniverse(volumeIDs: []).first(where: { $0.id == id }))
            guard let definition else { return XCTFail("Missing definition for \(id)") }
            XCTAssertNoThrow(try SessionProfiles.create(
                id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                               UInt8(truncatingIfNeeded: offset + 1), 1)),
                name: "Field \(offset)", values: .init(fields: [id: definition.defaultValue]),
                inherited: .init(), in: []), id.rawValue)
        }
    }

    func testWorkflowDeferredCopyAccessibilityAndProjectionFailureAreExplicit() throws {
        let bundle = Bundle(for: SharedSettingsWiringTests.self)
        let reassociation = SettingsWorkflowPresentation.deferredExplanation(
            .localReassociation, bundle: bundle)
        XCTAssertTrue(reassociation.contains("T22.3"))
        XCTAssertTrue(reassociation.contains("cannot authorize this Mac"))
        let clearing = SettingsWorkflowPresentation.deferredExplanation(
            .historyAndIndexClearing, bundle: bundle)
        for token in ["T07.3d", "T09", "mandatory safety journal", "never cleared"] {
            XCTAssertTrue(clearing.contains(token), token)
        }
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tidy/Settings/SettingsView.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains(".prefix(12)"))
        XCTAssertTrue(source.contains("settings.workflow.projectionFailure"))
        XCTAssertTrue(source.contains(".accessibilityHint(descriptor.accessibilityHint)"))
        XCTAssertTrue(source.contains(".accessibilityHint(tabHint)"))
        XCTAssertTrue(source.contains("String(describing: change.oldSource)"))
        XCTAssertTrue(source.contains("String(describing: change.newSource)"))
        XCTAssertTrue(source.contains("describe(change.defaultValue)"))
        XCTAssertTrue(source.contains("describe(change.effect)"))
    }

    func testImportFileReaderRejectsOversizeBeforeReadingPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tidy-import-reader-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accepted = directory.appendingPathComponent("accepted.json")
        let oversized = directory.appendingPathComponent("oversized.json")
        try Data(repeating: 0x61, count: SettingsImportFileReader.maximumByteCount)
            .write(to: accepted)
        try Data(repeating: 0x62, count: SettingsImportFileReader.maximumByteCount + 1)
            .write(to: oversized)
        XCTAssertEqual(try SettingsImportFileReader.read(accepted).count,
                       SettingsImportFileReader.maximumByteCount)
        XCTAssertThrowsError(try SettingsImportFileReader.read(oversized)) {
            XCTAssertEqual($0 as? SettingsImportFileReaderError, .tooLarge)
        }
    }

    @MainActor func testBackToBackCancellationCannotLoseRetainedActorToken() async throws {
        try await run { _, services, _ in
            let summary = try self.workflowSummary(UUID(uuidString:
                "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            let gate = SettingsWorkflowAsyncGate()
            let operations = SettingsWorkflowImportOperations(
                analyze: { _ in summary }, issue: { _, _ in self.workflowPreview(summary) },
                cancelAnalysis: { gate.recordAnalysisCancellation($0) },
                cancelPreview: { gate.recordPreviewCancellation($0) },
                submit: { services.configStore.commitImport($0) })
            let controller = SettingsWorkflowController(testing: services.configStore,
                importOperations: operations, bundle: Bundle(for: SharedSettingsWiringTests.self))
            await controller.beginImportSelection(bytes: Data([1])).value
            guard case .analysis = controller.importState else { return XCTFail() }
            let cancellation = controller.beginImportCancellation()
            let replacement = controller.beginImportSelection(bytes: Data([2]))
            await cancellation.value; await replacement.value
            XCTAssertEqual(gate.cancelledAnalysisIDs, [summary.analysisID])
            guard case .analysis = controller.importState else { return XCTFail() }
        }
    }

    func testWorkflowSourceHasNoOpenWorkOrSecondOwner() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Tidy/Settings/SettingsView.swift"), encoding: .utf8)
        for token in [".task", ".onAppear", ".onReceive", ".refreshable", "Timer",
                      "Process(", "Process.", "ProcessSurvey", "CookieDomainSuggester",
                      "GitRootDiscovery", "SimctlClient", "CleanEngine", "requestPlan",
                      "loadPlan", "FileManager", "URLSession", "NSWorkspace",
                      "DispatchSource", "NotificationCenter", "SettingsStore(",
                      "ExecutionPolicyBridge(", "SettingsTransfer.resolve"] {
            XCTAssertFalse(source.contains(token), token)
        }
        XCTAssertFalse(source.contains("Task.detached"))
        let begin = "// SETTINGS_WORKFLOW_TASK_BOUNDARIES_BEGIN"
        let end = "// SETTINGS_WORKFLOW_TASK_BOUNDARIES_END"
        XCTAssertEqual(source.components(separatedBy: begin).count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: end).count - 1, 1)
        let beginRange = try XCTUnwrap(source.range(of: begin))
        let endRange = try XCTUnwrap(source.range(of: end))
        XCTAssertLessThan(beginRange.lowerBound, endRange.lowerBound)
        let block = String(source[beginRange.lowerBound..<endRange.upperBound])
        let beforeBlock = String(source[..<beginRange.lowerBound])
        let afterBlock = String(source[endRange.upperBound...])
        XCTAssertEqual(block.components(separatedBy: "Task {").count - 1, 4)
        XCTAssertFalse(beforeBlock.contains("Task {"))
        XCTAssertFalse(afterBlock.contains("Task {"))
        var remainder = block
        for helper in ["beginImportSelection", "beginImportPreviewIssuance",
                       "beginImportConfirmation", "beginImportCancellation"] {
            let helperBegin = "// SETTINGS_WORKFLOW_TASK_BEGIN_" + helper
            let helperEnd = "// SETTINGS_WORKFLOW_TASK_END_" + helper
            XCTAssertEqual(block.components(separatedBy: helperBegin).count - 1, 1)
            XCTAssertEqual(block.components(separatedBy: helperEnd).count - 1, 1)
            let helperBeginRange = try XCTUnwrap(remainder.range(of: helperBegin))
            let helperEndRange = try XCTUnwrap(remainder.range(of: helperEnd))
            XCTAssertLessThan(helperBeginRange.lowerBound, helperEndRange.lowerBound)
            let extracted = String(remainder[
                helperBeginRange.lowerBound..<helperEndRange.upperBound])
            XCTAssertTrue(extracted.contains("func " + helper), helper)
            XCTAssertEqual(extracted.components(separatedBy: "Task {").count - 1, 1,
                           helper)
            if helper == "beginImportConfirmation" {
                let rejected = try XCTUnwrap(extracted.range(of: "case .rejected"))
                let cancellation = try XCTUnwrap(extracted.range(
                    of: "await importOperations.cancelPreview(preview.id)"))
                XCTAssertLessThan(rejected.lowerBound, cancellation.lowerBound)
            }
            let submitting = try XCTUnwrap(extracted.range(of: "case .submitting"))
            let increment = try XCTUnwrap(extracted.range(of: "operationGeneration &+="))
            XCTAssertLessThan(submitting.lowerBound, increment.lowerBound,
                "\(helper) must decide submitting no-op before generation supersession")
            remainder.replaceSubrange(
                helperBeginRange.lowerBound..<helperEndRange.upperBound, with: "")
        }
        remainder = remainder.replacingOccurrences(of: begin, with: "")
            .replacingOccurrences(of: end, with: "")
        XCTAssertTrue(remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "Statements exist outside the four task helpers")
        XCTAssertTrue(source.contains("fileImporter")); XCTAssertTrue(source.contains("fileExporter"))
        XCTAssertTrue(source.contains("startAccessingSecurityScopedResource"))
        XCTAssertTrue(source.contains("stopAccessingSecurityScopedResource"))
        XCTAssertFalse(source.contains("Data(contentsOf:"))
        XCTAssertTrue(source.contains("seekToEnd()"))
        XCTAssertTrue(source.contains("read(upToCount: 1_048_577)"))
        XCTAssertTrue(source.contains("operationGeneration &+="))
        XCTAssertTrue(source.contains("let bundle: Bundle"))
        XCTAssertTrue(source.contains("bundle: Bundle = .main"))
        XCTAssertTrue(source.contains("SettingsImportUISummary"))
        XCTAssertTrue(source.contains("SettingsWorkflowPresentation.controls(context:"))
        XCTAssertTrue(source.contains("descriptorControls"))
        XCTAssertTrue(source.contains("LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))])"))
        XCTAssertTrue(source.contains(".accessibilityLabel(descriptor.label)"))
        XCTAssertTrue(source.contains("case .failed(let message)"))
        XCTAssertTrue(source.contains("profileValueEditor(descriptor)"))
        XCTAssertTrue(source.contains(".update(id:"))
        XCTAssertTrue(source.contains("resetProfileField"))
        XCTAssertTrue(source.contains("resetRestrictionOptIn"))
        XCTAssertTrue(source.contains("importReviewSummary"))
        XCTAssertTrue(source.contains("importReviewDigests"))
        XCTAssertFalse(source.contains("ForEach(store.preferences.global.fields.keys"))
        XCTAssertTrue(source.contains("beginImportConfirmation"))
        XCTAssertTrue(source.contains("deferredExplanationKey"))
        XCTAssertTrue(source.contains("deferredExplanation("))
        XCTAssertTrue(source.contains("bundle: bundle"))
        XCTAssertFalse(source.contains("case analysis(SettingsImportAnalysis)"))
        XCTAssertFalse(source.contains("case issuingPreview(SettingsImportAnalysis)"))
        XCTAssertFalse(source.contains("PortableSettingsState"))
        XCTAssertFalse(source.contains("var importBytes"))
        XCTAssertFalse(source.contains("var sourceBytes"))
        XCTAssertFalse(source.contains("SettingsWorkflowController(testing:"))
        XCTAssertTrue(source.contains("store.commitImport"))
        XCTAssertTrue(source.contains("store.commitProfileWorkflow"))
        XCTAssertTrue(source.contains("store.commitSelectiveReset"))
        for id in ["settings.deferred.localReassociation",
                   "settings.deferred.historyAndIndexClearing",
                   "settings.profile.confirm", "settings.import.confirm",
                   "settings.reset.confirm"] {
            XCTAssertTrue(source.contains(id), id)
        }
    }
}

private actor T081BridgeGate: ExecutionPolicyBridgeTestHook, SchedulerTestHook {
    enum Point: Hashable {
        case invalidatingAdmission
        case invalidatingTerminal
        case presentationPrepared
        case presentationAdmission
        case queuedPermit
        case durablySavedBeforeCommit
    }

    private var blocked: Set<Point> = []
    private var entered: Set<Point> = []
    private var continuations: [Point: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [Point: CheckedContinuation<Void, Never>] = [:]

    func block(_ point: Point) { blocked.insert(point) }

    func wait(for point: Point) async {
        if entered.contains(point) { return }
        await withCheckedContinuation { continuation in
            waiters[point] = continuation
        }
    }

    func release(_ point: Point) {
        blocked.remove(point)
        continuations.removeValue(forKey: point)?.resume()
    }

    func releaseAll() {
        for continuation in continuations.values { continuation.resume() }
        continuations.removeAll(); blocked.removeAll()
    }

    private func hit(_ point: Point) async {
        entered.insert(point)
        waiters.removeValue(forKey: point)?.resume()
        guard blocked.contains(point) else { return }
        await withCheckedContinuation { continuation in
            continuations[point] = continuation
        }
    }

    func receive(_ event: ExecutionPolicyBridgeTestPoint) async {
        switch event {
        case .acceptedAfterBarrierBeforePrepareAndSave:
            await hit(.invalidatingAdmission)
        case .terminalBeforeAdmissionHoldRelease:
            await hit(.invalidatingTerminal)
        case .acceptedAfterPresentationPrepareBeforeSave:
            await hit(.presentationAdmission)
        case .durablySavedBeforeCommit:
            await hit(.durablySavedBeforeCommit)
        }
    }

    func receive(_ event: SchedulerTestEvent) async {
        switch event {
        case .presentationPrepared:
            await hit(.presentationPrepared)
        case .enqueued:
            await hit(.queuedPermit)
        default:
            break
        }
    }
}

private actor T081PermitGate {
    private var entered: Set<Int> = []
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func hold(_ value: Int, _ probe: SchedulerCancellationProbe) async throws {
        try await probe.checkCancellation()
        entered.insert(value)
        waiters.removeValue(forKey: value)?.resume()
        await withCheckedContinuation { continuation in
            continuations[value] = continuation
        }
    }

    func wait(for value: Int) async {
        if entered.contains(value) { return }
        await withCheckedContinuation { continuation in
            waiters[value] = continuation
        }
    }

    func hasEntered(_ value: Int) -> Bool { entered.contains(value) }

    func release(_ value: Int) { continuations.removeValue(forKey: value)?.resume() }
}

extension SharedSettingsWiringTests {
    private func t081Envelope(revision: UInt64 = 1) -> Data {
        let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
        return try! SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: revision,
            config: .init(), preferences: .init(global: .init(fields: [rate: .integer(4)]))))
    }

    private func t081EnvelopeWithActiveProfileAndInertImport() -> Data {
        let profileID = UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
        let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
        let profile = SavedProfile(id: profileID, name: "Active", values: .init())
        let inert = InertPortableSetting(scope: .global, profileID: nil,
            id: "future.flag", value: .bool(true), valueKind: nil,
            valueDigest: nil, redacted: false)
        return try! SettingsDecoding.encode(SettingsEnvelope(schemaVersion: 2, revision: 1,
            config: .init(), preferences: .init(global: .init(fields: [rate: .integer(4)]),
                                                profiles: [profile]),
            activeProfileID: profileID, inertImports: [inert]))
    }

    private func t081Bridge(_ scratch: A3Scratch, _ services: AppExecutionServices,
                            hook: T081BridgeGate) -> ExecutionPolicyBridge {
        ExecutionPolicyBridge(coordinator: services.coordinator, settings: services.settings,
            loaded: services.settingsLoad, homeDirectory: scratch.home.path, detectedTools: [],
            pendingByteLimit: 32 * 1_048_576, schedulerTestHook: hook, testHook: hook)
    }

    private func t081HeadroomRequirements() throws -> SchedulerRequirements {
        try SchedulerRequirements(features: [.headroom])
    }

    func testT081bGlobalCandidatePreservesActiveProfileAndInertImports() async throws {
        try await run(seed: t081EnvelopeWithActiveProfileAndInertImport()) { scratch, services, _ in
            let bridge = self.t081Bridge(scratch, services, hook: T081BridgeGate())
            await bridge.drain()
            let sessions = bridge.explicitSessions
            let batch = SettingID(rawValue: "cleanup.requestedBatchGiB")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: batch, baseValue: nil, editedValue: .integer(12))),
                  case .saved(_, let saved) = await completion.value else {
                return XCTFail("global update did not durably save")
            }
            let loadResult = await services.settings.load()
            let durable = try XCTUnwrap(loadResult.envelope)
            XCTAssertEqual(saved, durable)
            XCTAssertNotNil(durable.activeProfileID)
            XCTAssertEqual(durable.inertImports.count, 1)
            let snapshot = await sessions.snapshot()
            XCTAssertEqual(snapshot.settingsRevision, durable.revision)
            _ = try await sessions.beginSession(requirements: self.t081HeadroomRequirements())
        }
    }

    func testT081bCancellationAfterDurablePublicationAcknowledgesExactEnvelope() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            await hook.block(.durablySavedBeforeCommit)
            let batch = SettingID(rawValue: "cleanup.requestedBatchGiB")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: batch, baseValue: nil, editedValue: .integer(12))) else {
                return XCTFail("durable-cancellation setup was not admitted")
            }
            await hook.wait(for: .durablySavedBeforeCommit)

            let loadResult = await services.settings.load()
            let published = try XCTUnwrap(loadResult.envelope)
            XCTAssertEqual(published.revision, 2)
            completion.cancel()
            await hook.release(.durablySavedBeforeCommit)

            guard case .saved(_, let saved) = await completion.value else {
                return XCTFail("the published envelope was not acknowledged")
            }
            XCTAssertEqual(saved, published)
            let snapshot = await bridge.explicitSessions.snapshot()
            XCTAssertEqual(snapshot.settingsRevision, published.revision)
        }
    }

    func testT081bQueuedPermitStaysClosedAcrossTwoAcceptedInvalidatingHandoffs() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let sessions = bridge.explicitSessions
            let requirements = try self.t081HeadroomRequirements()
            let active = try await sessions.beginSession(requirements: requirements)
            let queued = try await sessions.beginSession(requirements: requirements)
            let permits = T081PermitGate()
            let activeTask = Task { try await sessions.withPermit(session: active) {
                try await permits.hold(1, $0)
            } }
            await permits.wait(for: 1)
            let queuedTask = Task { try await sessions.withPermit(session: queued) {
                try await permits.hold(2, $0)
            } }
            await hook.wait(for: .queuedPermit)

            await hook.block(.invalidatingTerminal)
            let units = SettingID(rawValue: "ui.units")
            let batch = SettingID(rawValue: "cleanup.requestedBatchGiB")
            guard case .accepted(_, let first) = bridge.submit(global: .init(baseRevision: 1,
                id: units, baseValue: nil, editedValue: .choice("decimal"))),
                  case .accepted(_, let second) = bridge.submit(global: .init(baseRevision: 1,
                id: batch, baseValue: nil, editedValue: .integer(12))) else {
                return XCTFail("serialized invalidating handoffs were not admitted")
            }
            await hook.wait(for: .invalidatingTerminal)

            await permits.release(1)
            _ = try await activeTask.value
            let queuedHasEntered = await permits.hasEntered(2)
            XCTAssertFalse(queuedHasEntered)
            let pending = await sessions.snapshot()
            XCTAssertEqual(pending.queued, 1)

            await hook.release(.invalidatingTerminal)
            guard case .saved(_, let firstSaved) = await first.value,
                  case .saved(_, let secondSaved) = await second.value else {
                return XCTFail("serialized handoffs did not acknowledge durable envelopes")
            }
            XCTAssertEqual(firstSaved.revision, 2)
            XCTAssertEqual(secondSaved.revision, 3)
            await permits.wait(for: 2)
            await permits.release(2)
            _ = try await queuedTask.value
        }
    }

    func testT081bInvalidatingAdmissionClosesFacadeBeforePrepareAndExactSave() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let sessions = bridge.explicitSessions
            let requirements = try self.t081HeadroomRequirements()
            let active = try await sessions.beginSession(requirements: requirements)
            let queued = try await sessions.beginSession(requirements: requirements)
            let permits = T081PermitGate()
            let activeTask = Task { try await sessions.withPermit(session: active) {
                try await permits.hold(1, $0)
            } }
            await permits.wait(for: 1)
            let queuedTask = Task { try await sessions.withPermit(session: queued) {
                try await permits.hold(2, $0)
            } }
            await hook.wait(for: .queuedPermit)

            let before = try Data(contentsOf: scratch.paths.settings)
            await hook.block(.invalidatingAdmission)
            let id = SettingID(rawValue: "cleanup.requestedBatchGiB")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: id, baseValue: nil, editedValue: .integer(12))) else {
                return XCTFail("valid invalidating edit was not admitted")
            }
            await hook.wait(for: .invalidatingAdmission)

            do {
                _ = try await sessions.beginSession(requirements: requirements)
                XCTFail("a session crossed the synchronous scheduler barrier")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUpdating)
            }
            do {
                _ = try await sessions.withPermit(session: active) { _ in
                    XCTFail("a permit crossed the synchronous scheduler barrier")
                }
                XCTFail("new permit unexpectedly crossed the scheduler barrier")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUpdating)
            }
            let queuedHasRun = await permits.hasEntered(2)
            XCTAssertFalse(queuedHasRun)
            XCTAssertEqual(try Data(contentsOf: scratch.paths.settings), before)
            let unchanged = await services.settings.load()
            XCTAssertEqual(unchanged.envelope?.revision, 1)

            await hook.release(.invalidatingAdmission)
            guard case .saved(_, let saved) = await completion.value else {
                return XCTFail("the exact durable acknowledgement did not save")
            }
            XCTAssertEqual(saved.revision, 2)
            await permits.release(1)
            _ = try await activeTask.value
            await permits.wait(for: 2)
            await permits.release(2)
            _ = try await queuedTask.value
            let afterSave = await sessions.snapshot()
            XCTAssertEqual(afterSave.settingsRevision, 2)
        }
    }

    func testT081bConflictAndWriteFailureLeaveTheFacadeUnavailable() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let external = SettingsStore(url: scratch.paths.settings)
            _ = await external.load()
            _ = try await external.update(expectedRevision: 1, change: .transcriptAgeDays(120))
            let id = SettingID(rawValue: "cleanup.requestedBatchGiB")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: id, baseValue: nil, editedValue: .integer(12))),
                  case .conflict = await completion.value else {
                return XCTFail("real external advance did not produce a conflict")
            }
            do {
                _ = try await bridge.explicitSessions.beginSession(
                    requirements: self.t081HeadroomRequirements())
                XCTFail("conflict reopened scheduler admission")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUnavailable)
            }
        }

        try await run(seed: t081Envelope(), fault: .configReplace) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let id = SettingID(rawValue: "cleanup.requestedBatchGiB")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: id, baseValue: nil, editedValue: .integer(12))),
                  case .failed = await completion.value else {
                return XCTFail("actual publication failure did not reach the bridge")
            }
            do {
                _ = try await bridge.explicitSessions.beginSession(
                    requirements: self.t081HeadroomRequirements())
                XCTFail("write failure reopened scheduler admission")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUnavailable)
            }
        }
    }

    func testT081bCancellationNeverCommitsAPreparedSchedulerHandoff() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let before = try Data(contentsOf: scratch.paths.settings)
            await hook.block(.invalidatingAdmission)
            let batch = SettingID(rawValue: "cleanup.requestedBatchGiB")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: batch, baseValue: nil, editedValue: .integer(12))) else {
                return XCTFail("invalidating cancellation setup was not admitted")
            }
            await hook.wait(for: .invalidatingAdmission)
            completion.cancel()
            await hook.release(.invalidatingAdmission)
            guard case .failed(_, recoveryRequired: false) = await completion.value else {
                return XCTFail("cancelled invalidating handoff committed")
            }
            XCTAssertEqual(try Data(contentsOf: scratch.paths.settings), before)
            do {
                _ = try await bridge.explicitSessions.beginSession(
                    requirements: self.t081HeadroomRequirements())
                XCTFail("cancelled invalidating handoff reopened scheduler admission")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUnavailable)
            }
        }

        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let before = try Data(contentsOf: scratch.paths.settings)
            let generation = await bridge.explicitSessions.snapshot().generation
            await hook.block(.presentationAdmission)
            let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: rate, baseValue: .integer(4), editedValue: .integer(1))) else {
                return XCTFail("presentation cancellation setup was not admitted")
            }
            await hook.wait(for: .presentationAdmission)
            completion.cancel()
            await hook.release(.presentationAdmission)
            guard case .failed(_, recoveryRequired: false) = await completion.value else {
                return XCTFail("cancelled presentation handoff committed")
            }
            XCTAssertEqual(try Data(contentsOf: scratch.paths.settings), before)
            let after = await bridge.explicitSessions.snapshot()
            XCTAssertEqual(after.generation, generation)
            _ = try await bridge.explicitSessions.beginSession(
                requirements: self.t081HeadroomRequirements())
        }
    }

    func testT081bDocumentRatePlusAnotherTouchUsesTheClosingPath() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let sessions = bridge.explicitSessions
            let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
            let batch = SettingID(rawValue: "cleanup.requestedBatchGiB")
            await hook.block(.invalidatingAdmission)
            guard case .accepted(_, let completion) = bridge.submit(document: .init(baseRevision: 1,
                global: [.init(id: rate, baseValue: .integer(4), editedValue: .integer(1)),
                         .init(id: batch, baseValue: nil, editedValue: .integer(12))])) else {
                return XCTFail("multi-touch rate document was not admitted")
            }
            await hook.wait(for: .invalidatingAdmission)
            do {
                _ = try await sessions.beginSession(requirements: self.t081HeadroomRequirements())
                XCTFail("a document rate-plus-another-touch used presentation admission")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUpdating)
            }
            await hook.release(.invalidatingAdmission)
            guard case .saved(_, let saved) = await completion.value else {
                return XCTFail("multi-touch document did not save through invalidation")
            }
            XCTAssertEqual(saved.revision, 2)
            XCTAssertEqual(try Data(contentsOf: scratch.paths.settings),
                           try SettingsDecoding.encode(saved))
        }
    }

    func testT081bInitialZeroRevisionAndRecoveryKeepFacadeUnavailable() async throws {
        try await run { scratch, services, _ in
            let bridge = self.t081Bridge(scratch, services, hook: T081BridgeGate())
            await bridge.drain()
            do {
                _ = try await bridge.explicitSessions.beginSession(
                    requirements: self.t081HeadroomRequirements())
                XCTFail("revision-zero defaults installed a scheduler policy")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUnavailable)
            }
        }

        try await run(seed: Data("{broken".utf8)) { scratch, services, _ in
            XCTAssertEqual(services.settingsLoad.disposition, .recoveryReadOnly)
            let bridge = self.t081Bridge(scratch, services, hook: T081BridgeGate())
            await bridge.drain()
            do {
                _ = try await bridge.explicitSessions.beginSession(
                    requirements: self.t081HeadroomRequirements())
                XCTFail("recovery mode installed a scheduler policy")
            } catch let error as WorkSchedulerError {
                XCTAssertEqual(error, .admissionUnavailable)
            }
        }
    }

    func testT081bPresentationConflictAndWriteFailureDiscardWithoutClosing() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let bridge = self.t081Bridge(scratch, services, hook: T081BridgeGate())
            await bridge.drain()
            let external = SettingsStore(url: scratch.paths.settings)
            _ = await external.load()
            _ = try await external.update(expectedRevision: 1, change: .transcriptAgeDays(120))
            let before = try Data(contentsOf: scratch.paths.settings)
            let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: rate, baseValue: .integer(4), editedValue: .integer(1))),
                  case .conflict = await completion.value else {
                return XCTFail("presentation conflict was not delivered")
            }
            XCTAssertEqual(try Data(contentsOf: scratch.paths.settings), before)
            _ = try await bridge.explicitSessions.beginSession(
                requirements: self.t081HeadroomRequirements())
        }

        try await run(seed: t081Envelope(), fault: .configReplace) { scratch, services, _ in
            let bridge = self.t081Bridge(scratch, services, hook: T081BridgeGate())
            await bridge.drain()
            let before = try Data(contentsOf: scratch.paths.settings)
            let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: rate, baseValue: .integer(4), editedValue: .integer(1))),
                  case .failed(_, recoveryRequired: true) = await completion.value else {
                return XCTFail("presentation write failure was not delivered")
            }
            XCTAssertEqual(try Data(contentsOf: scratch.paths.settings), before)
            _ = try await bridge.explicitSessions.beginSession(
                requirements: self.t081HeadroomRequirements())
        }
    }

    func testT081bOnlyRateDeltaUsesNonClosingPresentationPreparation() async throws {
        try await run(seed: t081Envelope()) { scratch, services, _ in
            let hook = T081BridgeGate()
            let bridge = self.t081Bridge(scratch, services, hook: hook)
            await bridge.drain()
            let sessions = bridge.explicitSessions
            let requirements = try self.t081HeadroomRequirements()
            let before = await sessions.snapshot()
            let active = try await sessions.beginSession(requirements: requirements)
            let queued = try await sessions.beginSession(requirements: requirements)
            let permits = T081PermitGate()
            let activeTask = Task { try await sessions.withPermit(session: active) {
                try await permits.hold(1, $0)
            } }
            await permits.wait(for: 1)
            let queuedTask = Task { try await sessions.withPermit(session: queued) {
                try await permits.hold(2, $0)
            } }
            await hook.wait(for: .queuedPermit)

            await hook.block(.presentationPrepared)
            await hook.block(.presentationAdmission)
            let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
            guard case .accepted(_, let completion) = bridge.submit(global: .init(baseRevision: 1,
                id: rate, baseValue: .integer(4), editedValue: .integer(1))) else {
                return XCTFail("valid presentation delta was not admitted")
            }
            await hook.wait(for: .presentationPrepared)
            _ = try await sessions.beginSession(requirements: requirements)
            await permits.release(1)
            _ = try await activeTask.value
            await permits.wait(for: 2)
            let pendingLoad = await services.settings.load()
            let pendingSnapshot = await sessions.snapshot()
            XCTAssertEqual(pendingLoad.envelope?.revision, 1)
            XCTAssertEqual(pendingSnapshot.generation, before.generation)

            await hook.release(.presentationPrepared)
            await hook.wait(for: .presentationAdmission)
            await hook.release(.presentationAdmission)
            guard case .saved(_, let saved) = await completion.value else {
                return XCTFail("presentation save did not receive exact acknowledgement")
            }
            XCTAssertEqual(saved.revision, 2)
            let after = await sessions.snapshot()
            XCTAssertEqual(after.generation, before.generation)
            XCTAssertEqual(after.settingsRevision, 2)
            await permits.release(2)
            _ = try await queuedTask.value

            let malformed = bridge.submit(global: .init(baseRevision: 2, id: rate,
                baseValue: .integer(1), editedValue: .bool(true)))
            guard case .rejected(_, .invalid) = malformed else {
                return XCTFail("wrong-tag rate candidate was not rejected before save")
            }
        }
    }
}

// Observation/pause only. The finite watchdog releases this fixture's wait;
// it never closes an FD, signals a process, invents success or cancels storage.
private final class A3Probe: @unchecked Sendable {
    private let condition = NSCondition()
    private let stops: Set<String>
    private var released: Set<String> = []
    private var open = false
    private var events: [(String, Bool)] = []
    private var timeout = false
    init(stops: Set<String> = []) { self.stops = stops }
    func hit(_ name: String) {
        condition.lock(); defer { condition.unlock() }
        events.append((name, Thread.isMainThread))
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while stops.contains(name), !released.contains(name), !open {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                timeout = true
                break
            }
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    func release(_ name: String) {
        condition.lock(); released.insert(name); condition.broadcast(); condition.unlock()
    }
    func releaseAll() {
        condition.lock(); open = true; condition.broadcast(); condition.unlock()
    }
    func seen(_ name: String) -> Bool {
        condition.lock(); defer { condition.unlock() }
        return events.contains { $0.0 == name }
    }
    var names: [String] {
        condition.lock(); defer { condition.unlock() }; return events.map { $0.0 }
    }
    var allOffMain: Bool {
        condition.lock(); defer { condition.unlock() }; return !events.isEmpty && events.allSatisfy { !$0.1 }
    }
    var watchdogFired: Bool {
        condition.lock(); defer { condition.unlock() }; return timeout
    }
    func waitFor(_ name: String) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while !seen(name) {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw A3Failure.timeout }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private final class A3RealIO: JournalPOSIXIO, @unchecked Sendable {
    enum Fault: Equatable { case none, configReplace, configReplaceNumber(Int), configDirectorySync }
    private let real = DarwinJournalIO()
    private let lock = NSLock()
    let probe: A3Probe
    private let fault: Fault
    private var replacements = 0
    private var awaitingConfigSync = false
    private var observedErrno: Int32?
    init(probe: A3Probe, fault: Fault = .none) { self.probe = probe; self.fault = fault }
    var configAttempts: Int { lock.lock(); defer { lock.unlock() }; return replacements }
    var failureErrno: Int32? { lock.lock(); defer { lock.unlock() }; return observedErrno }
    private func record(_ error: Error) {
        lock.lock(); observedErrno = (error as? POSIXError)?.code.rawValue; lock.unlock()
    }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        probe.hit("write")
        return try real.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { probe.hit("syncFile"); try real.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        guard destination == "config.json" else {
            try real.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
            return
        }
        lock.lock(); replacements += 1; let number = replacements; lock.unlock()
        probe.hit("config.\(number)") // immediately BEFORE actual config publication
        do {
            // EBADF comes from actual renameat(-1,...), not a synthesized error/success.
            let fail: Bool
            switch fault {
            case .configReplace: fail = true
            case .configReplaceNumber(let target): fail = number == target
            case .none, .configDirectorySync: fail = false
            }
            try real.replace(directoryFD: fail ? -1 : directoryFD,
                temporary: temporary, destination: destination)
        } catch { record(error); throw error }
        lock.lock(); awaitingConfigSync = true; lock.unlock()
        probe.hit("config.done.\(number)")
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock()
        let directoryFault: Bool
        if case .configDirectorySync = fault { directoryFault = true } else { directoryFault = false }
        let fail = awaitingConfigSync && directoryFault
        awaitingConfigSync = false; lock.unlock()
        probe.hit("syncDirectory")
        do { try real.syncDirectory(fd: fail ? -1 : fd) }
        catch { record(error); throw error }
    }
}

@MainActor
final class SharedSettingsWiringTests: XCTestCase {
    @MainActor func testAcknowledgedPolicyObserverPublishesOnlyDurableRevisions() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            var revisions: [UInt64] = []
            var headroomEnabled: [Bool] = []
            let token = services.configStore.observeAcknowledgedPolicy { revision, policy in
                revisions.append(revision)
                headroomEnabled.append(policy?.allowedFeatures.contains("headroom") == true)
            }
            defer { services.configStore.removeAcknowledgedPolicyObserver(token) }
            XCTAssertEqual(revisions, [0])
            XCTAssertEqual(headroomEnabled, [true])

            guard case .accepted(_, let outcome) = services.configStore.setGlobalPreference(
                SettingID(rawValue: "feature.headroom"), to: .bool(false))
            else { return XCTFail("settings edit rejected") }
            try await io.probe.waitFor("config.1")
            XCTAssertEqual(revisions, [0], "optimistic state is not an acknowledged policy")
            io.probe.release("config.1")
            guard case .saved = await outcome.value else { return XCTFail("settings edit not saved") }
            XCTAssertEqual(revisions, [0, 1])
            XCTAssertEqual(headroomEnabled, [true, false])
        }
    }

    @MainActor func testMeasuredVolumeIdentityAndCapacityResolveHeadroomWithoutPathApproval() async throws {
        try await run { _, services, _ in
            let store = services.configStore
            let volumeID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            store.updateSelectedVolume(identity: volumeID.uuidString,
                capacityBytes: 100 * 1_073_741_824,
                observedAt: Date(timeIntervalSince1970: 20))
            XCTAssertEqual(resolvedHeadroomTargetBytes(store.effectivePolicy),
                           10 * 1_073_741_824)

            store.updateSelectedVolume(identity: "/path/is/not/authority",
                capacityBytes: 100 * 1_073_741_824,
                observedAt: Date(timeIntervalSince1970: 21))
            XCTAssertNil(resolvedHeadroomTargetBytes(store.effectivePolicy))

            store.updateSelectedVolume(identity: volumeID.uuidString,
                capacityBytes: 200 * 1_073_741_824,
                observedAt: Date(timeIntervalSince1970: 19))
            XCTAssertNil(resolvedHeadroomTargetBytes(store.effectivePolicy),
                         "an older observation cannot replace the newer unavailable state")
        }
    }

    @MainActor func testVisibleHeadroomAppliesAcknowledgedFeatureDisableImmediately() async throws {
        try await run { _, services, _ in
            let model = HeadroomViewModel(monitor: services.systemMonitor,
                cardOrder: resolvedUICardOrder(services.configStore.acknowledgedEffectivePolicy))
            model.onAppear()
            var deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if await services.systemMonitor.isTimerRunningForTesting() { break }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let runningBeforeDisable = await services.systemMonitor.isTimerRunningForTesting()
            XCTAssertTrue(runningBeforeDisable)

            guard case .accepted(_, let completion) = services.configStore.setGlobalPreference(
                SettingID(rawValue: "feature.headroom"), to: .bool(false)),
                  case .saved = await completion.value else {
                return XCTFail("feature disable was not acknowledged")
            }
            deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                let running = await services.systemMonitor.isTimerRunningForTesting()
                if !running { break }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let runningAfterDisable = await services.systemMonitor.isTimerRunningForTesting()
            XCTAssertFalse(runningAfterDisable)
            model.refreshNow()
            deadline = Date().addingTimeInterval(2)
            while model.snapshot?.unavailableReason == nil, Date() < deadline {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertEqual(model.snapshot?.unavailableReason, SystemMonitor.featureDisabledReason)
            model.onDisappear()
        }
    }

    private func run(stops: Set<String> = [], seed: Data? = nil,
                     fault: A3RealIO.Fault = .none,
                     _ body: (A3Scratch, AppExecutionServices, A3RealIO) async throws -> Void) async throws {
        let s = try A3Scratch()
        defer { s.remove() }
        if let seed { try s.seed(seed) }
        let probe = A3Probe(stops: stops)
        let io = A3RealIO(probe: probe, fault: fault)
        let store = SettingsStore(url: s.paths.settings, io: io)
        let services = await AppExecutionServices.bootstrap(paths: s.paths, settings: store,
            observe: { probe.hit($0.rawValue) })
        do { try await body(s, services, io) }
        catch {
            probe.releaseAll()
            await services.policyBridge.drain() // no cleanup until actual chain finished
            throw error
        }
        probe.releaseAll()
        await services.policyBridge.drain()
        XCTAssertFalse(probe.watchdogFired)
        try s.intact()
    }

    private func noOpReview(_ services: AppExecutionServices) async throws -> RegisteredReview {
        try await services.coordinator.prepareReview(engine: services.engine, tier: .safe,
            selectDefaults: false) // real catalog, scratch paths, unknown tools; no fake rows
    }

    func testRealPublicationOffMainAndOldSaveCannotEnableNewerEdit() async throws {
        try await run(stops: ["config.1", "config.2"]) { s, services, io in
            let bridge = services.policyBridge, c = services.coordinator
            let review = try await self.noOpReview(services)
            let token = try await c.confirm(binding: review.binding)
            let a = services.configStore, b = services.configStore
            XCTAssertTrue(a === b)
            a.config.transcriptAgeThresholdDays = 60
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 2)) // no await
            XCTAssertFalse(services.isExecutionEnabled)
            try await io.probe.waitFor("config.1")
            XCTAssertTrue(io.probe.allOffMain)
            XCTAssertFalse(io.probe.seen("config.done.1"))
            var eventProcessed = false
            await Task { @MainActor in
                XCTAssertTrue(Thread.isMainThread)
                eventProcessed = true
            }.value
            XCTAssertTrue(eventProcessed)
            XCTAssertFalse(io.probe.watchdogFired)
            b.config.transcriptAgeThresholdDays = 90 // while first real publication suspended
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 3))
            XCTAssertEqual(a.config.transcriptAgeThresholdDays, 90)
            XCTAssertFalse(services.isExecutionEnabled)
            let stale = await c.execute(token, currentPolicyRevision: 1)
            XCTAssertEqual(stale.disposition, .stalePolicy)
            do { _ = try await c.confirm(binding: review.binding); XCTFail("Old binding survived") }
            catch let error as ConfirmationError { XCTAssertEqual(error, .stalePolicy) }
            io.probe.release("config.1")
            try await io.probe.waitFor("config.2")
            // First update returned actual success, second has not published.
            let firstDisk = try JSONDecoder().decode(SettingsEnvelope.self,
                from: Data(contentsOf: s.paths.settings))
            XCTAssertEqual(firstDisk.revision, 1)
            XCTAssertEqual(firstDisk.config.transcriptAgeThresholdDays, 60)
            XCTAssertEqual(bridge.durableSettingsRevision, 1)
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 3))
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertFalse(io.probe.seen("config.done.2"))
            io.probe.release("config.2")
            await bridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 2)
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 90)
            XCTAssertEqual(bridge.durableSettingsRevision, 2)
            XCTAssertEqual(c.policyAdmission(), .ready(revision: 3))
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertNil(bridge.persistenceError)
            let fresh = try await self.noOpReview(services)
            XCTAssertEqual(fresh.binding.policyRevision, 3)
            let freshToken = try await c.confirm(binding: fresh.binding)
            let report = await c.execute(freshToken, currentPolicyRevision: 3)
            XCTAssertEqual(report.disposition, .noWork)
            XCTAssertEqual(report.coordinatorMeasurementsAvailable, false)
            XCTAssertEqual(bridge.pendingSnapshotCount, 0)
            XCTAssertEqual(bridge.pendingSnapshotBytes, 0)
        }
    }

    func testBootstrapIsOffMainSharedAndHasNoEnabledDefaultInterval() async throws {
        let s = try A3Scratch(); defer { s.remove() }
        let probe = A3Probe(stops: ["beforeSettingsLoad", "beforeCoordinatorConstruction"])
        let store = SettingsStore(url: s.paths.settings)
        let state = AppBootstrapState()
        XCTAssertEqual(state.status, .notStarted); XCTAssertNil(state.services)
        let started = state.start(paths: s.paths, settings: store, observe: { probe.hit($0.rawValue) })
        XCTAssertEqual(state.status, .loading); XCTAssertNil(state.services)
        let secondWindow = state.start(paths: s.paths, settings: store, observe: { probe.hit($0.rawValue) })
        do {
            try await probe.waitFor("beforeSettingsLoad")
            XCTAssertNil(state.services)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.support.path))
            var handled = false
            await Task { @MainActor in handled = true }.value
            XCTAssertTrue(handled)
            probe.release("beforeSettingsLoad")
            try await probe.waitFor("beforeCoordinatorConstruction")
            XCTAssertNil(state.services)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.support.path))
            XCTAssertFalse(probe.watchdogFired)
            probe.release("beforeCoordinatorConstruction")
            await started.value; await secondWindow.value
            let services = try XCTUnwrap(state.services)
            XCTAssertEqual(state.status, .ready)
            XCTAssertEqual(services.settingsLoad.disposition, .newDefaults)
            XCTAssertEqual(services.initialJournalAdmission, .ready)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertEqual(probe.names, ["beforeSettingsLoad", "afterSettingsLoad",
                "beforeCoordinatorConstruction", "afterCoordinatorConstruction"])
            XCTAssertTrue(probe.allOffMain)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.paths.settings.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                s.paths.journal.appendingPathComponent("unfinished-effects.json").path))
            let reopened = state.start(paths: s.paths)
            await reopened.value
            XCTAssertTrue(state.services === services)
            services.configStore.config.transcriptAgeThresholdDays = 61
            await services.policyBridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 1)
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 61)
        } catch {
            probe.releaseAll(); await started.value; await secondWindow.value
            if let services = state.services { await services.policyBridge.drain() }
            throw error
        }
        probe.releaseAll(); await started.value; await secondWindow.value
        if let services = state.services { await services.policyBridge.drain() }
        XCTAssertFalse(probe.watchdogFired)
        try s.intact()
    }

    func testCorruptAndFutureBootstrapRemainReadOnlyAfterActualSetter() async throws {
        for bytes in [Data("{broken".utf8), Data(#"{"schemaVersion":999,"keep":"future"}"#.utf8)] {
            try await run(seed: bytes) { s, services, io in
                XCTAssertEqual(services.settingsLoad.disposition, .recoveryReadOnly)
                XCTAssertNil(services.settingsLoad.envelope)
                XCTAssertNil(services.policyBridge.durableSettingsRevision)
                XCTAssertFalse(services.isExecutionEnabled)
                services.configStore.config.transcriptAgeThresholdDays = 75
                XCTAssertFalse(services.isExecutionEnabled)
                await services.policyBridge.drain()
                XCTAssertFalse(services.isExecutionEnabled)
                XCTAssertNotNil(services.persistenceError)
                XCTAssertEqual(io.configAttempts, 0)
                XCTAssertEqual(try Data(contentsOf: s.paths.settings), bytes)
                XCTAssertFalse(FileManager.default.fileExists(atPath:
                    s.support.appendingPathComponent("config.lock").path))
                do { _ = try await self.noOpReview(services); XCTFail("Recovery admitted review") }
                catch let error as ConfirmationError { XCTAssertEqual(error, .stalePolicy) }
            }
        }
    }

    func testKnownSchema2WithoutMetadataLoadsWithoutSettingsWrite() async throws {
        let config = TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 88)
        let bytes = try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2, revision: 41, config: config))
        try await run(seed: bytes) { s, services, io in
            XCTAssertEqual(services.settingsLoad.disposition, .loaded)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 41)
            XCTAssertEqual(services.configStore.config, config)
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertEqual(try Data(contentsOf: s.paths.settings), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                s.support.appendingPathComponent("config.lock").path))
            services.configStore.config.transcriptAgeThresholdDays = 89
            await services.policyBridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 42)
            XCTAssertEqual(try Data(contentsOf: s.support.appendingPathComponent("config.backup.json")), bytes)
        }
    }

    func testSchema1BootstrapMigratesSharedControlsWithoutWritingUntilExplicitEdit() async throws {
        let legacy = Data(#"""
        {"schemaVersion":1,"hasCompletedOnboarding":true,"keepCookieDomains":["example.invalid","keep.invalid"],"simulatorsApprovedForDeletion":["Old simulator name"],"gitRoots":["/fixture/Developer","/fixture/Other"],"staleNodeModulesThresholdDays":90,"transcriptAgeThresholdDays":120,"appsApprovedForQuit":["Old application name"],"allowRestartToReclaimSwap":true,"presets":[{"name":"Weekly","itemIDs":["safe.tool.npm-cache-clean","unknown.preset.id","deep.simulator.erase-all"]}]}
        """#.utf8)
        let migrated = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true,
            keepCookieDomains: ["example.invalid", "keep.invalid"],
            simulatorsApprovedForDeletion: ["Old simulator name"],
            gitRoots: ["/fixture/Developer", "/fixture/Other"],
            staleNodeModulesThresholdDays: 90, transcriptAgeThresholdDays: 120,
            appsApprovedForQuit: ["Old application name"], allowRestartToReclaimSwap: true,
            presets: [CustomPreset(name: "Weekly", itemIDs: [
                "safe.tool.npm-cache-clean", "unknown.preset.id", "deep.simulator.erase-all"
            ])])
        try await run(seed: legacy) { s, services, io in
            XCTAssertEqual(services.settingsLoad.disposition, .migrated)
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(services.settingsLoad.envelope?.schemaVersion, 2)
            XCTAssertEqual(services.settingsLoad.envelope?.revision, 0)
            XCTAssertEqual(services.settingsLoad.envelope?.config, migrated)
            XCTAssertEqual(services.configStore.config, migrated) // shared app controls preserve every migrated field
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertEqual(try Data(contentsOf: s.paths.settings), legacy)
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                s.support.appendingPathComponent("config.backup.json").path))

            services.configStore.config.transcriptAgeThresholdDays = 121
            await services.policyBridge.drain()
            let saved = await services.settings.load()
            var expected = migrated; expected.transcriptAgeThresholdDays = 121
            XCTAssertEqual(saved.disposition, .loaded)
            XCTAssertEqual(saved.envelope?.schemaVersion, 2)
            XCTAssertEqual(saved.envelope?.revision, 1)
            XCTAssertEqual(saved.envelope?.config, expected)
            XCTAssertEqual(services.configStore.config, expected)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 1)
            XCTAssertEqual(io.configAttempts, 1)
            XCTAssertEqual(try Data(contentsOf:
                s.support.appendingPathComponent("config.backup.json")), legacy)
        }
    }

    func testPartialSettingsBootstrapAndUninitializedJournalDoNotBecomeReady() async throws {
        for partialSettings in [true, false] {
            let s = try A3Scratch(); defer { s.remove() }
            try s.seed(try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2,
                revision: 7, config: TidyConfig(schemaVersion: 2))))
            let target: URL
            if partialSettings { target = s.support.appendingPathComponent("config.lock") }
            else {
                try FileManager.default.createDirectory(at: s.paths.journal,
                    withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                target = s.paths.journal.appendingPathComponent("mutation.lock")
            }
            let bytes = Data("incomplete initialized state".utf8)
            try bytes.write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            let state = AppBootstrapState()
            await state.start(paths: s.paths).value
            let services = try XCTUnwrap(state.services)
            XCTAssertEqual(state.status, .recovery)
            XCTAssertFalse(services.isExecutionEnabled)
            if partialSettings { XCTAssertNil(services.settingsLoad.envelope) }
            else { XCTAssertEqual(services.initialJournalAdmission, .storageUnavailable) }
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: partialSettings
                ? s.support.appendingPathComponent("config.store.json").path
                : s.paths.journal.appendingPathComponent("unfinished-effects.json").path))
            services.configStore.config.transcriptAgeThresholdDays = 77
            await services.policyBridge.drain()
            XCTAssertFalse(services.isExecutionEnabled) // a saved setting cannot repair journal admission
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: partialSettings
                ? s.support.appendingPathComponent("config.store.json").path
                : s.paths.journal.appendingPathComponent("unfinished-effects.json").path))
            try s.intact()
        }
    }

    func testActualReplaceAndPostRenameSyncFailuresNeverCommit() async throws {
        let initial = try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2,
            revision: 7, config: TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 45)))
        for fault in [A3RealIO.Fault.configReplace, .configDirectorySync] {
            try await run(seed: initial, fault: fault) { s, services, io in
                let c = services.coordinator, bridge = services.policyBridge
                let old = try await self.noOpReview(services)
                let token = try await c.confirm(binding: old.binding)
                services.configStore.config.transcriptAgeThresholdDays = 90
                XCTAssertEqual(c.policyAdmission(), .updating(revision: 2))
                await bridge.drain()
                XCTAssertEqual(io.failureErrno, EBADF)
                XCTAssertEqual(io.configAttempts, 1)
                let diagnostic = await services.settings.lastPublicationFailure()
                XCTAssertEqual(diagnostic?.stage, fault == .configReplace ? "config.replace" : "config.syncDirectory")
                XCTAssertEqual(diagnostic?.errno, EBADF)
                XCTAssertEqual(bridge.durableSettingsRevision, 7)
                XCTAssertEqual(c.policyAdmission(), .updating(revision: 2))
                XCTAssertFalse(services.isExecutionEnabled)
                XCTAssertNotNil(services.persistenceError)
                let rejected = await c.execute(token, currentPolicyRevision: 1)
                XCTAssertEqual(rejected.disposition, .stalePolicy)
                if fault == .configReplace {
                    XCTAssertEqual(try Data(contentsOf: s.paths.settings), initial)
                } else {
                    let actual = try JSONDecoder().decode(SettingsEnvelope.self,
                        from: Data(contentsOf: s.paths.settings))
                    XCTAssertEqual(actual.revision, 8) // readable bytes != durable success
                    XCTAssertEqual(actual.config.transcriptAgeThresholdDays, 90)
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath:
                    s.support.appendingPathComponent("config.pending.json").path))
                let loaded = await services.settings.load()
                XCTAssertEqual(loaded.disposition, .recoveryReadOnly)
                services.configStore.config.transcriptAgeThresholdDays = 91
                await bridge.drain()
                XCTAssertEqual(io.configAttempts, 1) // no automatic or implicit recovery retry
                XCTAssertEqual(bridge.durableSettingsRevision, 7)
                XCTAssertFalse(services.isExecutionEnabled)
            }
        }
    }

    func testBounded32SnapshotQueueOverflowPreservesAcceptedAdmissionUntilExplicitResave() async throws {
        try await run(stops: ["config.1"]) { s, services, io in
            let bridge = services.policyBridge, c = services.coordinator
            services.configStore.config.transcriptAgeThresholdDays = 60
            try await io.probe.waitFor("config.1")
            for day in 61...91 { services.configStore.config.transcriptAgeThresholdDays = day }
            XCTAssertEqual(bridge.pendingSnapshotCount, 32)
            XCTAssertGreaterThan(bridge.pendingSnapshotBytes, 0)
            XCTAssertLessThanOrEqual(bridge.pendingSnapshotBytes, 32 * 1_048_576)
            let acceptedGeneration = bridge.updateGeneration
            services.configStore.config.transcriptAgeThresholdDays = 92
            XCTAssertEqual(c.policyAdmission(), .updating(revision: 33))
            XCTAssertEqual(bridge.updateGeneration, acceptedGeneration)
            XCTAssertEqual(bridge.pendingSnapshotCount, 32)
            XCTAssertEqual(bridge.persistenceError, "Settings changes are pending; wait and save again.")
            io.probe.releaseAll(); await bridge.drain()
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.revision, 32)
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 91)
            XCTAssertEqual(io.configAttempts, 32)
            XCTAssertEqual(bridge.durableSettingsRevision, 32)
            XCTAssertEqual(c.policyAdmission(), .ready(revision: 33))
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertEqual(bridge.persistenceError, "Settings changes are pending; wait and save again.")
            XCTAssertEqual(bridge.pendingSnapshotCount, 0)
            XCTAssertEqual(bridge.pendingSnapshotBytes, 0)
            services.configStore.config.transcriptAgeThresholdDays = 92 // explicit user resave
            await bridge.drain()
            let retry = await services.settings.load()
            XCTAssertEqual(retry.envelope?.revision, 33)
            XCTAssertEqual(retry.envelope?.config.transcriptAgeThresholdDays, 92)
            XCTAssertEqual(c.policyAdmission(), .ready(revision: 34))
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertNil(bridge.persistenceError)
        }
    }

    func testOversizedAndInvalidSnapshotsAreNotRetainedOrPersistedThenValidEditWorks() async throws {
        try await run { s, services, io in
            let review = try await self.noOpReview(services)
            let token = try await services.coordinator.confirm(binding: review.binding)
            let generation = services.policyBridge.updateGeneration
            let original = services.configStore.config
            var oversized = services.configStore.config
            oversized.keepCookieDomains = Array(repeating: String(repeating: "a", count: 4096), count: 257)
            services.configStore.config = oversized
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertEqual(services.configStore.config, original)
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertNotNil(services.persistenceError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.paths.settings.path))
            let report = await services.coordinator.execute(token, currentPolicyRevision: 1)
            XCTAssertEqual(report.disposition, .noWork)
            var invalid = TidyConfig(schemaVersion: 2); invalid.transcriptAgeThresholdDays = 366
            services.configStore.config = invalid
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 0)
            XCTAssertTrue(services.isExecutionEnabled)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(services.configStore.config, original)
            services.configStore.config = TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 75)
            await services.policyBridge.drain()
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 1)
            XCTAssertTrue(services.isExecutionEnabled)
        }
    }

    func testRejectedInvalidatingBasesAndRelationalPresentationEditPreserveFrozenAdmission() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let bridge = services.policyBridge
            let review = try await self.noOpReview(services)
            let token = try await services.coordinator.confirm(binding: review.binding)
            let generation = bridge.updateGeneration
            let displayed = services.configStore.preferences
            let invalidatingID = SettingID(rawValue: "cleanup.requestedBatchGiB")
            for badBase in [SettingValue.integer(99), .integer(8)] {
                let rejected = bridge.submit(global: GlobalPreferenceDelta(baseRevision: 0,
                    id: invalidatingID, baseValue: badBase, editedValue: .integer(12)))
                guard case .rejected(_, .invalid) = rejected else {
                    return XCTFail("Invalid or mismatched base was retained")
                }
                XCTAssertEqual(bridge.pendingSnapshotCount, 0)
                XCTAssertEqual(bridge.pendingSnapshotBytes, 0)
                XCTAssertEqual(bridge.updateGeneration, generation)
                XCTAssertEqual(services.coordinator.policyAdmission(),
                               .ready(revision: review.binding.policyRevision))
                XCTAssertTrue(services.isExecutionEnabled)
                XCTAssertEqual(services.configStore.preferences, displayed)
            }
            let report = await services.coordinator.execute(token,
                currentPolicyRevision: review.binding.policyRevision)
            XCTAssertEqual(report.disposition, .noWork)

            services.configStore.setGlobalPreference(
                SettingID(rawValue: "notifications.quietEnd"), to: .choice("09:00"))
            try await io.probe.waitFor("config.1")
            let beforeCollision = services.configStore.preferences
            let collision = services.configStore.setGlobalPreference(
                SettingID(rawValue: "notifications.quietStart"), to: .choice("09:00"))
            guard case .rejected(_, .invalid) = collision else {
                return XCTFail("Relationally invalid global document was retained")
            }
            XCTAssertEqual(bridge.pendingSnapshotCount, 1)
            XCTAssertEqual(services.configStore.preferences, beforeCollision)
            io.probe.releaseAll()
            await bridge.drain()
            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "notifications.quietEnd")], .choice("09:00"))
            XCTAssertNil(saved.preferences?.global.fields[
                SettingID(rawValue: "notifications.quietStart")])
        }
    }

    func testPresentationFailureCannotHealGenuineAcceptedInvalidatingConflict() async throws {
        try await run { s, services, _ in
            let bridge = services.policyBridge
            let review = try await self.noOpReview(services)
            let token = try await services.coordinator.confirm(binding: review.binding)
            let external = SettingsStore(url: s.paths.settings)
            _ = await external.load()
            _ = try await external.update(expectedRevision: 0, change: .transcriptAgeDays(120))

            let invalidatingID = SettingID(rawValue: "cleanup.requestedBatchGiB")
            let conflicting = GlobalPreferenceDelta(baseRevision: 0, id: invalidatingID,
                baseValue: nil, editedValue: .integer(12))
            guard case .accepted(_, let invalidatingCompletion) = bridge.submit(global: conflicting) else {
                return XCTFail("Valid invalidating edit was not admitted")
            }
            guard case .conflict = await invalidatingCompletion.value else {
                return XCTFail("External durable advance did not create a genuine conflict")
            }
            XCTAssertFalse(bridge.isExecutionEnabled)
            let blockingAdmission = services.coordinator.policyAdmission()
            let blockingMessage = try XCTUnwrap(bridge.persistenceError)
            let stale = await services.coordinator.execute(token,
                currentPolicyRevision: review.binding.policyRevision)
            XCTAssertEqual(stale.disposition, .stalePolicy)

            let units = SettingID(rawValue: "ui.units")
            let presentation = GlobalPreferenceDelta(baseRevision: 0, id: units,
                baseValue: nil, editedValue: .choice("decimal"))
            guard case .accepted(_, let presentationCompletion) = bridge.submit(global: presentation) else {
                return XCTFail("Presentation edit was not admitted")
            }
            guard case .conflict = await presentationCompletion.value else {
                return XCTFail("Stale storage actor unexpectedly persisted presentation edit")
            }
            XCTAssertFalse(bridge.isExecutionEnabled)
            XCTAssertEqual(bridge.persistenceError, blockingMessage)
            XCTAssertEqual(services.coordinator.policyAdmission(), blockingAdmission)
            let saved = await services.settings.load()
            XCTAssertNil(saved.envelope?.preferences?.global.fields[units])
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 120)
            XCTAssertEqual(bridge.pendingSnapshotCount, 0)
            XCTAssertEqual(bridge.pendingSnapshotBytes, 0)
        }
    }

    func testSharedStoreReconcilesFailedHeadAndFailedTailInAcceptedOrder() async throws {
        try await run(stops: ["config.1"], fault: .configReplace) { _, services, io in
            let original = services.configStore.config
            services.configStore.config.transcriptAgeThresholdDays = 60
            try await io.probe.waitFor("config.1")
            services.configStore.config.transcriptAgeThresholdDays = 90
            XCTAssertEqual(services.configStore.config.transcriptAgeThresholdDays, 90)
            io.probe.releaseAll()
            await services.policyBridge.drain()
            XCTAssertEqual(services.configStore.config, original)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertTrue(services.policyUpdatePending == false)
            XCTAssertFalse(services.isExecutionEnabled)
        }

        try await run(stops: ["config.1"], fault: .configReplaceNumber(2)) { s, services, io in
            services.configStore.config.transcriptAgeThresholdDays = 60
            try await io.probe.waitFor("config.1")
            services.configStore.config.transcriptAgeThresholdDays = 90
            io.probe.releaseAll()
            await services.policyBridge.drain()
            XCTAssertEqual(services.configStore.config.transcriptAgeThresholdDays, 60)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 1)
            let disk = try JSONDecoder().decode(SettingsEnvelope.self,
                from: Data(contentsOf: s.paths.settings))
            XCTAssertEqual(disk.revision, 1)
            XCTAssertEqual(disk.config.transcriptAgeThresholdDays, 60)
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertFalse(services.storageUpdatePending)
            XCTAssertFalse(services.policyUpdatePending)
            XCTAssertFalse(services.isExecutionEnabled)
        }
    }

    func testSourceCompatibleWholeSubmissionUsesExactQueuedTypedPrediction() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let transcript = SettingID(rawValue: "cleanup.transcriptDays")
            let typed = GlobalPreferenceDelta(baseRevision: 0, id: transcript,
                baseValue: nil, editedValue: .integer(60))
            guard case .accepted(_, let typedCompletion) =
                    services.policyBridge.submit(global: typed) else {
                return XCTFail("Valid typed compatibility edit was not accepted")
            }
            try await io.probe.waitFor("config.1")

            var whole = TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 60)
            whole.keepCookieDomains = ["preserve.invalid"]
            let wholeCompletion = services.policyBridge.submit(config: whole)
            io.probe.releaseAll()
            guard case .saved = await typedCompletion.value else {
                return XCTFail("Typed head did not persist")
            }
            await wholeCompletion.value
            await services.policyBridge.drain()

            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.revision, 2)
            XCTAssertEqual(saved.config.transcriptAgeThresholdDays, 60)
            XCTAssertEqual(saved.config.keepCookieDomains, ["preserve.invalid"])
            XCTAssertEqual(saved.preferences?.global.fields[transcript], .integer(60))
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "browsers.keepCookieDomains")],
                .strings(["preserve.invalid"]))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
        }
    }

    func testConflictedLegacyHeadConflictsDependentWholeDeltaThenResubmitPreservesFields() async throws {
        try await run { s, services, _ in
            var outcomes: [SettingsIntentOutcome] = []
            let observer = services.policyBridge.observeOutcomes { outcomes.append($0) }
            defer { services.policyBridge.removeOutcomeObserver(observer) }

            let staleBase = TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 50)
            let intendedHead = TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 60)
            let staleHead = LegacyPreferenceDelta(baseRevision: 0, base: staleBase,
                edited: intendedHead)
            var dependent = intendedHead
            dependent.keepCookieDomains = ["preserve.invalid"]

            guard case .accepted = services.policyBridge.submit(legacy: staleHead) else {
                return XCTFail("Valid-shape stale legacy head was not admitted")
            }
            _ = services.policyBridge.submit(config: dependent)
            await services.policyBridge.drain()
            XCTAssertEqual(outcomes.count, 2)
            guard case .conflict = outcomes[0], case .conflict = outcomes[1] else {
                return XCTFail("Conflicted head did not invalidate its base-bound dependent delta")
            }
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: s.paths.settings.path))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)

            _ = services.policyBridge.submit(config: dependent)
            await services.policyBridge.drain()
            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.revision, 1)
            XCTAssertEqual(saved.config.transcriptAgeThresholdDays, 60)
            XCTAssertEqual(saved.config.keepCookieDomains, ["preserve.invalid"])
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "cleanup.transcriptDays")], .integer(60))
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "browsers.keepCookieDomains")],
                .strings(["preserve.invalid"]))
        }
    }

    func testFailedPresentationConflictReconcilesDisplayWithoutChangingAdmission() async throws {
        try await run { s, services, _ in
            let review = try await self.noOpReview(services)
            let token = try await services.coordinator.confirm(binding: review.binding)
            let admission = services.coordinator.policyAdmission()
            let generation = services.policyBridge.updateGeneration
            let original = services.configStore.preferences
            let external = SettingsStore(url: s.paths.settings)
            _ = await external.load()
            _ = try await external.update(expectedRevision: 0, change: .transcriptAgeDays(120))

            guard case .accepted = services.configStore.setGlobalPreference(
                SettingID(rawValue: "ui.units"), to: .choice("decimal")) else {
                return XCTFail("Valid presentation edit was not accepted")
            }
            XCTAssertEqual(services.configStore.preferences.global.fields[
                SettingID(rawValue: "ui.units")], .choice("decimal"))
            await services.policyBridge.drain()
            XCTAssertEqual(services.configStore.preferences, original)
            XCTAssertEqual(services.coordinator.policyAdmission(), admission)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertTrue(services.isExecutionEnabled)
            let report = await services.coordinator.execute(token,
                currentPolicyRevision: review.binding.policyRevision)
            XCTAssertEqual(report.disposition, .noWork)
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
        }
    }

    func testClosingOneActualWindowDoesNotCancelSharedPendingSaveOrOtherWindow() async throws {
        try await run(stops: ["config.1"]) { s, services, io in
            let clean = CleanViewModel(tier: .safe, services: services)
            let custom = CustomViewModel(services: services)
            await clean.requestLoad().value; await custom.requestLoad().value
            XCTAssertNotNil(clean.registeredReview); XCTAssertNotNil(custom.registeredReview)
            services.configStore.config.transcriptAgeThresholdDays = 74
            clean.policyDidChange(); custom.policyDidChange() // real view notification handlers
            try await io.probe.waitFor("config.1")
            let closed = clean.teardown()
            await closed.value
            XCTAssertNil(clean.selection)
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertFalse(custom.selection?.canConfirm ?? false)
            custom.confirm() // denied while actual save suspended; no mutation/log effect
            io.probe.releaseAll(); await services.policyBridge.drain()
            await custom.requestLoad().value
            XCTAssertNotNil(custom.registeredReview)
            XCTAssertNotNil(custom.selection)
            XCTAssertFalse(custom.selection?.canConfirm ?? true) // all denied, not positive cleanup
            await clean.requestLoad().value
            XCTAssertNil(clean.selection) // closed lifetime never reopens
            await custom.teardown().value
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.config.transcriptAgeThresholdDays, 74)
            XCTAssertEqual(saved.envelope?.revision, 1)
        }
    }

    func testTypedPresentationEditPersistsWithoutInvalidatingExistingConfirmation() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let review = try await self.noOpReview(services)
            let basePolicyRevision = review.binding.policyRevision

            services.configStore.setGlobalPreference(SettingID(rawValue: "ui.units"),
                                                     to: .choice("decimal"))
            XCTAssertTrue(services.storageUpdatePending)
            XCTAssertFalse(services.policyUpdatePending)
            XCTAssertEqual(services.coordinator.policyAdmission(),
                           .ready(revision: basePolicyRevision))
            XCTAssertEqual(services.configStore.preferences.global.fields[
                SettingID(rawValue: "ui.units")], .choice("decimal"))
            _ = try await services.coordinator.confirm(binding: review.binding)

            try await io.probe.waitFor("config.1")
            io.probe.releaseAll()
            await services.policyBridge.drain()
            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.revision, 1)
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "ui.units")], .choice("decimal"))
            XCTAssertEqual(services.coordinator.policyAdmission(),
                           .ready(revision: basePolicyRevision))
            XCTAssertFalse(services.storageUpdatePending)
            XCTAssertTrue(services.isExecutionEnabled)
        }
    }

    func testTypedInvalidatingEditRejectsFrozenConfirmationBeforePersistence() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let review = try await self.noOpReview(services)
            let oldRevision = review.binding.policyRevision

            services.configStore.setGlobalPreference(
                SettingID(rawValue: "cleanup.requestedBatchGiB"), to: .integer(12))
            XCTAssertTrue(services.storageUpdatePending)
            XCTAssertTrue(services.policyUpdatePending)
            XCTAssertEqual(services.coordinator.policyAdmission(),
                           .updating(revision: oldRevision + 1))
            XCTAssertFalse(services.isExecutionEnabled)
            do {
                _ = try await services.coordinator.confirm(binding: review.binding)
                XCTFail("Frozen confirmation survived an invalidating edit")
            } catch let error as ConfirmationError {
                XCTAssertEqual(error, .stalePolicy)
            }

            try await io.probe.waitFor("config.1")
            io.probe.releaseAll()
            await services.policyBridge.drain()
            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.revision, 1)
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "cleanup.requestedBatchGiB")], .integer(12))
            XCTAssertEqual(services.coordinator.policyAdmission(),
                           .ready(revision: oldRevision + 1))
            XCTAssertFalse(services.storageUpdatePending)
            XCTAssertFalse(services.policyUpdatePending)
            XCTAssertTrue(services.isExecutionEnabled)
        }
    }

    func testQueuedTypedEditsReplayInOrderAcrossSharedWindows() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let firstWindow = services.configStore
            let secondWindow = services.configStore
            XCTAssertTrue(firstWindow === secondWindow)

            firstWindow.setGlobalPreference(SettingID(rawValue: "ui.units"),
                                            to: .choice("decimal"))
            try await io.probe.waitFor("config.1")
            secondWindow.setGlobalPreference(SettingID(rawValue: "ui.density"),
                                             to: .choice("detailed"))
            XCTAssertEqual(firstWindow.preferences.global.fields[
                SettingID(rawValue: "ui.units")], .choice("decimal"))
            XCTAssertEqual(secondWindow.preferences.global.fields[
                SettingID(rawValue: "ui.density")], .choice("detailed"))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 2)

            io.probe.releaseAll()
            await services.policyBridge.drain()
            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.revision, 2)
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "ui.units")], .choice("decimal"))
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "ui.density")], .choice("detailed"))
            XCTAssertEqual(firstWindow.preferences, saved.preferences)
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
        }
    }

    func testLegacyPredictionProjectsAbsentCompatibilityBeforeQueuedTypedEdit() async throws {
        let initial = SettingsEnvelope(schemaVersion: 2, revision: 7,
            config: TidyConfig(schemaVersion: 2, transcriptAgeThresholdDays: 88))
        let bytes = try JSONEncoder().encode(initial)
        try await run(stops: ["config.1"], seed: bytes) { _, services, io in
            let originalPolicyRevision = services.coordinator.policyAdmission()
            services.configStore.config.hasCompletedOnboarding = true
            try await io.probe.waitFor("config.1")
            services.configStore.setGlobalPreference(
                SettingID(rawValue: "cleanup.transcriptDays"), to: .integer(90))
            XCTAssertEqual(services.configStore.preferences.global.fields[
                SettingID(rawValue: "cleanup.transcriptDays")], .integer(90))

            io.probe.releaseAll()
            await services.policyBridge.drain()
            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.revision, 9)
            XCTAssertTrue(saved.config.hasCompletedOnboarding)
            XCTAssertEqual(saved.config.transcriptAgeThresholdDays, 90)
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "cleanup.transcriptDays")], .integer(90))
            XCTAssertEqual(services.configStore.config, saved.config)
            XCTAssertEqual(services.configStore.preferences,
                           PolicyPreferences.project(legacy: saved.config, saved: saved.preferences))
            if case .ready(let revision) = originalPolicyRevision {
                XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: revision + 2))
            } else { XCTFail("Initial policy was not ready") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertFalse(services.storageUpdatePending)
            XCTAssertFalse(services.policyUpdatePending)
        }
    }

    func testTypedCompatibilityPredictionReverseProjectsBeforeQueuedLegacyEdit() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            guard case .ready(let originalPolicyRevision) =
                    services.coordinator.policyAdmission() else {
                return XCTFail("Initial policy was not ready")
            }
            services.configStore.setGlobalPreference(
                SettingID(rawValue: "cleanup.transcriptDays"), to: .integer(60))
            XCTAssertEqual(services.configStore.config.transcriptAgeThresholdDays, 60)
            try await io.probe.waitFor("config.1")
            services.configStore.config.hasCompletedOnboarding = true
            XCTAssertEqual(services.configStore.config.transcriptAgeThresholdDays, 60)
            XCTAssertTrue(services.configStore.config.hasCompletedOnboarding)

            io.probe.releaseAll()
            await services.policyBridge.drain()
            let loaded = await services.settings.load()
            let saved = try XCTUnwrap(loaded.envelope)
            XCTAssertEqual(saved.revision, 2)
            XCTAssertEqual(saved.config.transcriptAgeThresholdDays, 60)
            XCTAssertTrue(saved.config.hasCompletedOnboarding)
            XCTAssertEqual(saved.preferences?.global.fields[
                SettingID(rawValue: "cleanup.transcriptDays")], .integer(60))
            XCTAssertEqual(services.configStore.config, saved.config)
            XCTAssertEqual(services.coordinator.policyAdmission(),
                           .ready(revision: originalPolicyRevision + 2))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertFalse(services.storageUpdatePending)
            XCTAssertFalse(services.policyUpdatePending)
        }
    }

    func testUnavailableProductionPathStateCreatesNoServices() {
        let state = AppBootstrapState()
        state.storagePathUnavailable()
        XCTAssertEqual(state.status, .unavailable)
        XCTAssertNil(state.services)
    }
}

extension SharedSettingsWiringTests {
    private func t07ID(_ raw: String) -> SettingID { .init(rawValue: raw) }
    private func t07Values(_ pairs: [(String, SettingValue)]) -> PolicyValues {
        .init(fields: Dictionary(uniqueKeysWithValues: pairs.map { (t07ID($0.0), $0.1) }))
    }
    private func t07Profile(_ id: UUID, _ name: String,
                            _ pairs: [(String, SettingValue)] = []) -> SavedProfile {
        .init(id: id, name: name, values: t07Values(pairs))
    }

    func testDocumentActivationInvalidatesSynchronouslyResolvesAndRelaunches() async throws {
        try await run(stops: ["config.2"]) { s, services, io in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let profile = self.t07Profile(profileID, "Work", [("ui.units", .choice("decimal"))])
            let app = services.configStore
            let inserted = app.submit(document: .init(baseRevision: 0,
                                                       profiles: [.insert(profile)]))
            guard case .accepted = inserted else { return XCTFail("Profile insert rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertNil(app.activeProfileID)

            let activation = app.submit(document: .init(baseRevision: 1,
                activeProfileBase: nil, activeProfileEdit: profileID,
                touchesActiveProfile: true))
            guard case .accepted = activation else { return XCTFail("Activation rejected") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertEqual(app.activeProfileID, profileID)
            XCTAssertEqual(app.effectivePolicy?.fields[self.t07ID("ui.units")]?.value,
                           .stored(.choice("decimal")))
            try await io.probe.waitFor("config.2")
            io.probe.release("config.2")
            await services.policyBridge.drain()
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 2))
            XCTAssertTrue(services.isExecutionEnabled)
            let loadResult = await services.settings.load()
            let loaded = try XCTUnwrap(loadResult.envelope)
            XCTAssertEqual(loaded.activeProfileID, profileID)
            let reopened = await AppExecutionServices.bootstrap(paths: s.paths)
            XCTAssertEqual(reopened.configStore.activeProfileID, profileID)
            XCTAssertEqual(reopened.configStore.effectivePolicy?
                .fields[self.t07ID("ui.units")]?.value, .stored(.choice("decimal")))
        }
    }

    func testNameAndInertAreStorageOnlyButMixedFieldInvalidates() async throws {
        try await run(stops: ["config.3"]) { _, services, io in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let original = self.t07Profile(profileID, "Original")
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.insert(original)])) else { return XCTFail("Insert rejected") }
            await services.policyBridge.drain()
            let beforeGeneration = services.policyBridge.updateGeneration
            let inert = InertPortableSetting(scope: .profile, profileID: profileID,
                id: "future.flag", value: .bool(true), valueKind: nil,
                valueDigest: nil, redacted: false)
            let renamed = self.t07Profile(profileID, "Renamed")
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 1,
                profiles: [.update(id: profileID, base: original, edited: renamed)],
                inert: [.init(item: inert, presentInBase: false, presentAfterEdit: true)]))
            else { return XCTFail("Storage-only edit rejected") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
            await services.policyBridge.drain()
            XCTAssertEqual(services.configStore.inertImports, [inert])

            let invalidating = self.t07Profile(profileID, "Renamed",
                                                [("scan.preset", .choice("eco"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 2,
                profiles: [.update(id: profileID, base: renamed, edited: invalidating)]))
            else { return XCTFail("Mixed invalidating edit rejected") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            try await io.probe.waitFor("config.3")
            io.probe.release("config.3")
        }
    }

    func testDeletingActiveProfileFallsBackToGlobalAndInvalidates() async throws {
        try await run { _, services, _ in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let profile = self.t07Profile(profileID, "Work", [("ui.units", .choice("decimal"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                global: [.init(id: self.t07ID("ui.units"), baseValue: nil,
                               editedValue: .choice("binary"))], profiles: [.insert(profile)],
                activeProfileBase: nil, activeProfileEdit: profileID,
                touchesActiveProfile: true)) else { return XCTFail("Setup rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(services.configStore.effectivePolicy?
                .fields[self.t07ID("ui.units")]?.value, .stored(.choice("decimal")))
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 1,
                profiles: [.delete(id: profileID, base: profile)],
                activeProfileBase: profileID, activeProfileEdit: nil,
                touchesActiveProfile: true)) else { return XCTFail("Delete rejected") }
            XCTAssertNil(services.configStore.activeProfileID)
            XCTAssertEqual(services.configStore.effectivePolicy?
                .fields[self.t07ID("ui.units")]?.value, .stored(.choice("binary")))
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 3))
            await services.policyBridge.drain()
            let loadResult = await services.settings.load()
            XCTAssertEqual(loadResult.envelope?.activeProfileID, nil)
        }
    }

    func testTwoWindowStoresSynchronizeOrderedSavedDocuments() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let loaded = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: loaded, bridge: services.policyBridge)
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let profile = self.t07Profile(profileID, "First")
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                profiles: [.insert(profile)])) else { return XCTFail("First-window edit rejected") }
            XCTAssertEqual(first.preferences.profiles, [profile])
            XCTAssertTrue(second.preferences.profiles.isEmpty)
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(second.preferences.profiles, [profile])
            let renamed = self.t07Profile(profileID, "Second")
            guard case .accepted = second.submit(document: .init(baseRevision: 1,
                profiles: [.update(id: profileID, base: profile, edited: renamed)]))
            else { return XCTFail("Second-window edit rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(first.preferences.profiles, [renamed])
            XCTAssertEqual(second.preferences.profiles, [renamed])
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
        }
    }

    func testFailedDocumentHeadConflictsDependentTailWithoutVanishingState() async throws {
        try await run(stops: ["config.1"], fault: .configReplaceNumber(1)) { _, services, io in
            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let first = self.t07Profile(profileID, "First",
                                        [("scan.preset", .choice("eco"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.insert(first)])) else { return XCTFail("Head rejected") }
            let second = self.t07Profile(profileID, "Second",
                                         [("scan.preset", .choice("eco"))])
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.update(id: profileID, base: first, edited: second)]))
            else { return XCTFail("Tail rejected") }
            XCTAssertEqual(services.configStore.preferences.profiles, [second])
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertTrue(services.configStore.preferences.profiles.isEmpty)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertFalse(services.isExecutionEnabled)
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testDocumentAuthorityRejectsBeforeRetentionAndQueueBoundIsShared() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let authority = PreferenceFieldEdit(id: self.t07ID("maintenance.mode"),
                baseValue: nil, editedValue: .choice("authorizedCaches"))
            guard case .rejected(_, .unsupportedAuthority) = services.configStore.submit(
                document: .init(baseRevision: 0, global: [authority]))
            else { return XCTFail("Authority delta was not rejected exactly") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(io.configAttempts, 0)

            let forbiddenID = UUID()
            let forbidden = self.t07Profile(forbiddenID, "Forbidden",
                [("scope.projectRoots", .strings(["/private/project"]))])
            for delta in [PreferencesDocumentDelta(baseRevision: 0,
                                                    profiles: [.insert(forbidden)])] {
                let generation = services.policyBridge.updateGeneration
                guard case .rejected(_, .unsupportedAuthority) =
                    services.configStore.submit(document: delta)
                else { return XCTFail("Profile authority/local delta was not rejected exactly") }
                XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
                XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
                XCTAssertEqual(services.policyBridge.updateGeneration, generation)
                XCTAssertEqual(io.configAttempts, 0)
            }

            let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            var base = self.t07Profile(profileID, "P0")
            guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                profiles: [.insert(base)])) else { return XCTFail("Queue head rejected") }
            try await io.probe.waitFor("config.1")
            for index in 1..<32 {
                let edited = self.t07Profile(profileID, "P\(index)")
                guard case .accepted = services.configStore.submit(document: .init(baseRevision: 0,
                    profiles: [.update(id: profileID, base: base, edited: edited)]))
                else { return XCTFail("Queue item \(index) rejected") }
                base = edited
            }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 32)
            let overflow = self.t07Profile(profileID, "overflow")
            guard case .rejected(_, .queueFull) = services.configStore.submit(document: .init(
                baseRevision: 0, profiles: [.update(id: profileID, base: base, edited: overflow)]))
            else { return XCTFail("33rd document was retained") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 32)
            XCTAssertLessThanOrEqual(services.policyBridge.pendingSnapshotBytes, 32 * 1_048_576)
            io.probe.release("config.1")
        }
    }

    func testProfileUpdateAuthorityRejectsBeforeRetention() async throws {
        let profileID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let clean = self.t07Profile(profileID, "Clean")
        let seedEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 0, config: .init(),
            preferences: .init(profiles: [clean]))
        let seed = try SettingsDecoding.encode(seedEnvelope)
        try await run(seed: seed) { _, services, io in
            let forbidden = self.t07Profile(profileID, "Clean",
                [("scope.projectRoots", .strings(["/private/project"]))])
            let generation = services.policyBridge.updateGeneration
            let delta = PreferencesDocumentDelta(baseRevision: 0, profiles: [
                .update(id: profileID, base: clean, edited: forbidden)
            ])
            guard case .rejected(_, .unsupportedAuthority) =
                services.configStore.submit(document: delta)
            else { return XCTFail("Profile update authority/local delta was not rejected") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 0)
        }
    }

    func testIssuedImportFlowsThroughBridgeAndNeverActivatesImportedProfile() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let importedID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
            let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"scan.preset":{"choice":"eco"}}},"profiles":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","name":"Imported","values":{"fields":{"ui.units":{"choice":"decimal"}}}}],"inertImports":[]}"#.utf8)
            let analysis = try await services.configStore.analyzeImport(bytes: bytes)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.commitImport(preview)
            else { return XCTFail("Issued import was not admitted") }
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            XCTAssertNil(services.configStore.activeProfileID)
            XCTAssertEqual(services.configStore.preferences.profiles.first?.id, importedID)
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            let loadResult = await services.settings.load()
            let durable = try XCTUnwrap(loadResult.envelope)
            XCTAssertEqual(durable.preferences?.profiles.first?.id, importedID)
            XCTAssertNil(durable.activeProfileID)
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testStorageOnlyImportDoesNotInvalidatePolicy() async throws {
        try await run(stops: ["config.1"]) { _, services, io in
            let generation = services.policyBridge.updateGeneration
            let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
            let analysis = try await services.configStore.analyzeImport(bytes: bytes)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.commitImport(preview)
            else { return XCTFail("Storage-only import rejected") }
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testImportPreviewRejectsStaleCancelledReusedForeignAndQueuedBeforeEffects() async throws {
        let portable = Data(#"{"schemaVersion":1,"global":{"fields":{"scan.preset":{"choice":"eco"}}},"profiles":[],"inertImports":[]}"#.utf8)

        try await run { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            let profile = self.t07Profile(UUID(), "Storage only")
            guard case .accepted = services.configStore.submit(document: .init(
                baseRevision: 0, profiles: [.insert(profile)])) else {
                return XCTFail("Intervening save rejected")
            }
            await services.policyBridge.drain()
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Stale preview was admitted") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 1)
        }

        try await run { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            await services.configStore.cancelImport(previewID: preview.id)
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Cancelled preview was admitted") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 0)
        }

        try await run { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            let foreign = SettingsImportPreview(id: preview.id, analysisID: preview.analysisID,
                rows: preview.rows, collisions: preview.collisions, choices: preview.choices,
                candidate: preview.candidate, sourceDigest: preview.sourceDigest + "x",
                candidateDigest: preview.candidateDigest)
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(foreign)
            else { return XCTFail("Mutated/foreign preview was admitted") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 0)
        }

        try await run(stops: ["config.1"]) { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.submit(document: .init(
                baseRevision: 0, profiles: [.insert(self.t07Profile(UUID(), "Queued"))]))
            else { return XCTFail("Queue head rejected") }
            try await io.probe.waitFor("config.1")
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Preview entered a nonempty queue") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 1)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 1)
            io.probe.release("config.1")
        }

        try await run(stops: ["config.1"]) { _, services, io in
            let analysis = try await services.configStore.analyzeImport(bytes: portable)
            let preview = try await services.configStore.issueImportPreview(
                analysisID: try XCTUnwrap(analysis.analysisID), choices: [:])
            guard case .accepted = services.configStore.commitImport(preview)
            else { return XCTFail("First commit rejected") }
            let generation = services.policyBridge.updateGeneration
            guard case .rejected(_, .invalid) = services.configStore.commitImport(preview)
            else { return XCTFail("Preview was admitted twice") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 1)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            await services.policyBridge.drain()
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testForeignSavedAcknowledgementReplaysLocalPendingTransform() async throws {
        try await run(stops: ["config.1", "config.2"]) { _, services, io in
            let loaded = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: loaded, bridge: services.policyBridge)
            let aID = UUID(), bID = UUID()
            let a = self.t07Profile(aID, "A")
            let b = self.t07Profile(bID, "B")
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                profiles: [.insert(a)])) else { return XCTFail("A rejected") }
            guard case .accepted = second.submit(document: .init(baseRevision: 0,
                profiles: [.insert(b)])) else { return XCTFail("B rejected") }
            XCTAssertEqual(Set(second.preferences.profiles.map(\.id)), Set([bID]))
            try await io.probe.waitFor("config.1")
            io.probe.release("config.1")
            try await io.probe.waitFor("config.2")
            XCTAssertEqual(Set(second.preferences.profiles.map(\.id)), Set([aID, bID]))
            io.probe.release("config.2")
            await services.policyBridge.drain()
            XCTAssertEqual(Set(first.preferences.profiles.map(\.id)), Set([aID, bID]))
            XCTAssertEqual(Set(second.preferences.profiles.map(\.id)), Set([aID, bID]))
        }
    }

    func testForeignFailureAndDependentConflictDoNotBlockLaterSavedAcknowledgement() async throws {
        let seedEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: TidyConfig(schemaVersion: 2))
        let seed = try SettingsDecoding.encode(seedEnvelope)
        try await run(seed: seed) { s, services, io in
            let loaded = try XCTUnwrap(services.settingsLoad.envelope)
            let first = services.configStore
            let second = AppConfigStore(loaded: loaded, bridge: services.policyBridge)
            // Replace the exact same acknowledged bytes before admission. This is
            // a recoverable disk-identity conflict; unlike a failed atomic rename,
            // it does not make durability uncertain or latch read-only recovery.
            try seed.write(to: s.paths.settings, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                ofItemAtPath: s.paths.settings.path)
            let id = UUID()
            let head = self.t07Profile(id, "Head", [("scan.preset", .choice("eco"))])
            let tail = self.t07Profile(id, "Tail", [("scan.preset", .choice("eco"))])
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                profiles: [.insert(head)])) else { return XCTFail("Head rejected") }
            guard case .accepted = second.submit(document: .init(baseRevision: 0,
                profiles: [.update(id: id, base: head, edited: tail)]))
            else { return XCTFail("Dependent tail rejected before exact execution") }
            await services.policyBridge.drain()
            XCTAssertTrue(first.preferences.profiles.isEmpty)
            XCTAssertTrue(second.preferences.profiles.isEmpty)
            _ = await services.settings.load()

            let units = PreferenceFieldEdit(id: self.t07ID("ui.units"), baseValue: nil,
                                            editedValue: .choice("decimal"))
            guard case .accepted = first.submit(document: .init(baseRevision: 0,
                global: [units])) else { return XCTFail("Fresh unrelated save rejected") }
            await services.policyBridge.drain()
            XCTAssertEqual(second.preferences.global.fields[self.t07ID("ui.units")],
                           .choice("decimal"))
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertEqual(io.configAttempts, 1)
        }
    }

    func testImportAccountingIsExactDeterministicBoundedAndOverflowSafe() async throws {
        let ids = [
            UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        ]
        let localProfiles = ids.enumerated().map {
            self.t07Profile($0.element, "Local-\($0.offset)")
        }
        let seedEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 0, config: .init(),
            preferences: .init(profiles: localProfiles))
        let seed = try SettingsDecoding.encode(seedEnvelope)
        let importedProfiles = ids.enumerated().map {
            self.t07Profile($0.element, "Imported-\($0.offset)", [
                ("ui.units", .choice($0.offset == 0 ? "decimal" : "binary"))
            ])
        }
        let imported = PortableSettingsState(preferences: .init(global: self.t07Values([
            ("scan.preset", .choice("eco")), ("history.enabled", .bool(true)),
            ("history.retentionDays", .integer(30))
        ]), profiles: importedProfiles), inertImports: [
            .init(scope: .global, profileID: nil, id: "future.bool", value: .bool(true),
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "future.integer", value: .integer(7),
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .profile, profileID: ids[0], id: "future.null", value: .null,
                  valueKind: nil, valueDigest: nil, redacted: false),
            .init(scope: .global, profileID: nil, id: "future.redacted", value: nil,
                  valueKind: .choice, valueDigest: String(repeating: "a", count: 64),
                  redacted: true)
        ])
        let importBytes = try SettingsTransfer.export(imported)
        let choices: [UUID: ProfileCollisionChoice] = [
            ids[0]: .keepLocal, ids[1]: .replace,
            ids[2]: .clone(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!)
        ]

        try await run(seed: seed) { s, services, io in
            @MainActor func bridge(limit: Int) -> ExecutionPolicyBridge {
                ExecutionPolicyBridge(coordinator: services.coordinator,
                    settings: services.settings, loaded: services.settingsLoad,
                    homeDirectory: s.home.path, detectedTools: [],
                    pendingByteLimit: limit)
            }
            @MainActor func issue(_ bridge: ExecutionPolicyBridge) async throws -> SettingsImportPreview {
                let app = AppConfigStore(loaded: try XCTUnwrap(services.settingsLoad.envelope),
                                         bridge: bridge)
                let analysis = try await app.analyzeImport(bytes: importBytes)
                return try await app.issueImportPreview(
                    analysisID: try XCTUnwrap(analysis.analysisID), choices: choices)
            }
            func copy(_ value: SettingsImportPreview, id: UUID? = nil,
                      analysisID: UUID? = nil, rows: [SettingsImportRow]? = nil,
                      collisions: [ProfileImportCollision]? = nil,
                      choices: [UUID: ProfileCollisionChoice]? = nil,
                      candidate: PortableSettingsState? = nil,
                      sourceDigest: String? = nil,
                      candidateDigest: String? = nil) -> SettingsImportPreview {
                SettingsImportPreview(id: id ?? value.id,
                    analysisID: analysisID ?? value.analysisID,
                    rows: rows ?? value.rows, collisions: collisions ?? value.collisions,
                    choices: choices ?? value.choices, candidate: candidate ?? value.candidate,
                    sourceDigest: sourceDigest ?? value.sourceDigest,
                    candidateDigest: candidateDigest ?? value.candidateDigest)
            }

            let reference = bridge(limit: 32 * 1_048_576)
            let referencePreview = try await issue(reference)
            let intent = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            let accounting = try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0, preview: referencePreview)
            XCTAssertEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0, preview: referencePreview))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: UUID(), expectedRevision: 0, preview: referencePreview))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 1, preview: referencePreview))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, id: UUID(), analysisID: UUID())))
            var rows = referencePreview.rows
            let firstRow = try XCTUnwrap(rows.first)
            rows[0] = .init(scope: firstRow.scope, profileID: firstRow.profileID,
                id: (firstRow.id ?? "nil") + "x", idDigest: firstRow.idDigest,
                outcome: firstRow.outcome, value: firstRow.value,
                valueKind: firstRow.valueKind, valueDigest: firstRow.valueDigest)
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, rows: rows)))
            let rowVariants: [SettingsImportRow] = [
                .init(scope: firstRow.scope == .global ? .profile : .global,
                      profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: UUID(), id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: (firstRow.idDigest ?? "none") + "x",
                      outcome: firstRow.outcome, value: firstRow.value,
                      valueKind: firstRow.valueKind, valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest,
                      outcome: firstRow.outcome == .committable ? .inert : .committable,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: .choice("changed"), valueKind: firstRow.valueKind,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value,
                      valueKind: firstRow.valueKind == .strings ? .choice : .strings,
                      valueDigest: firstRow.valueDigest),
                .init(scope: firstRow.scope, profileID: firstRow.profileID, id: firstRow.id,
                      idDigest: firstRow.idDigest, outcome: firstRow.outcome,
                      value: firstRow.value, valueKind: firstRow.valueKind,
                      valueDigest: (firstRow.valueDigest ?? "none") + "x")
            ]
            for variant in rowVariants {
                var changedRows = referencePreview.rows
                changedRows[0] = variant
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, rows: changedRows)))
            }
            var collisions = referencePreview.collisions
            let firstCollision = try XCTUnwrap(collisions.first)
            collisions[0] = .init(profileID: firstCollision.profileID,
                                  localName: firstCollision.localName + "x",
                                  importedName: firstCollision.importedName)
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, collisions: collisions)))
            for changedCollision in [
                ProfileImportCollision(profileID: UUID(), localName: firstCollision.localName,
                    importedName: firstCollision.importedName),
                ProfileImportCollision(profileID: firstCollision.profileID,
                    localName: firstCollision.localName,
                    importedName: firstCollision.importedName + "x")
            ] {
                var changed = referencePreview.collisions
                changed[0] = changedCollision
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, collisions: changed)))
            }
            var changedChoices = referencePreview.choices
            changedChoices[ids[0]] = .replace
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, choices: changedChoices)))
            var rekeyedChoices = referencePreview.choices
            let movedChoice = rekeyedChoices.removeValue(forKey: ids[0])
            rekeyedChoices[UUID()] = try XCTUnwrap(movedChoice)
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, choices: rekeyedChoices)))
            var changedGlobal = referencePreview.candidate
            changedGlobal.preferences.global.fields[self.t07ID("ui.units")] = .choice("decimal")
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, candidate: changedGlobal)))
            let baseProfile = try XCTUnwrap(referencePreview.candidate.preferences.profiles.first)
            var changedProfileIdentity = referencePreview.candidate
            changedProfileIdentity.preferences.profiles[0] = .init(id: UUID(),
                name: baseProfile.name, values: baseProfile.values)
            var changedProfileName = referencePreview.candidate
            changedProfileName.preferences.profiles[0] = .init(id: baseProfile.id,
                name: baseProfile.name + "x", values: baseProfile.values)
            var profileValues = baseProfile.values
            profileValues.fields[self.t07ID("history.enabled")] = .bool(false)
            var changedProfileValues = referencePreview.candidate
            changedProfileValues.preferences.profiles[0] = .init(id: baseProfile.id,
                name: baseProfile.name, values: profileValues)
            for candidate in [changedProfileIdentity, changedProfileName, changedProfileValues] {
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, candidate: candidate)))
            }
            var changedCandidate = referencePreview.candidate
            changedCandidate.inertImports.append(.init(scope: .global, profileID: nil,
                id: "future.extra", value: .bool(false), valueKind: nil,
                valueDigest: nil, redacted: false))
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, candidate: changedCandidate)))
            let baseInert = try XCTUnwrap(referencePreview.candidate.inertImports.first)
            let inertVariants: [InertPortableSetting] = [
                .init(scope: baseInert.scope == .global ? .profile : .global,
                      profileID: baseInert.profileID, id: baseInert.id, value: baseInert.value,
                      valueKind: baseInert.valueKind, valueDigest: baseInert.valueDigest,
                      redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: UUID(), id: baseInert.id,
                      value: baseInert.value, valueKind: baseInert.valueKind,
                      valueDigest: baseInert.valueDigest, redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID,
                      id: baseInert.id + "x", value: baseInert.value,
                      valueKind: baseInert.valueKind, valueDigest: baseInert.valueDigest,
                      redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: .integer(99), valueKind: baseInert.valueKind,
                      valueDigest: baseInert.valueDigest, redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: baseInert.value, valueKind: .choice,
                      valueDigest: baseInert.valueDigest, redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: baseInert.value, valueKind: baseInert.valueKind,
                      valueDigest: "digest-x", redacted: baseInert.redacted),
                .init(scope: baseInert.scope, profileID: baseInert.profileID, id: baseInert.id,
                      value: baseInert.value, valueKind: baseInert.valueKind,
                      valueDigest: baseInert.valueDigest, redacted: !baseInert.redacted)
            ]
            for variant in inertVariants {
                var candidate = referencePreview.candidate
                candidate.inertImports[0] = variant
                XCTAssertNotEqual(accounting,
                    try ExecutionPolicyBridge.retainedImportAccountingData(
                        intentID: intent, expectedRevision: 0,
                        preview: copy(referencePreview, candidate: candidate)))
            }
            XCTAssertNotEqual(accounting, try ExecutionPolicyBridge.retainedImportAccountingData(
                intentID: intent, expectedRevision: 0,
                preview: copy(referencePreview, sourceDigest: referencePreview.sourceDigest + "x",
                              candidateDigest: referencePreview.candidateDigest + "x")))
            await reference.cancelImport(previewID: referencePreview.id)

            let limited = bridge(limit: accounting.count - 1)
            let limitedPreview = try await issue(limited)
            let limitedApp = AppConfigStore(loaded: try XCTUnwrap(services.settingsLoad.envelope),
                                            bridge: limited)
            let generation = limited.updateGeneration
            guard case .rejected(_, .queueFull) = limitedApp.commitImport(limitedPreview)
            else { return XCTFail("Below-exact import byte limit admitted") }
            XCTAssertEqual(limited.pendingSnapshotCount, 0)
            XCTAssertEqual(limited.pendingSnapshotBytes, 0)
            XCTAssertEqual(limited.updateGeneration, generation)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(io.configAttempts, 0)
            await limitedApp.cancelImport(previewID: limitedPreview.id)

            let exact = bridge(limit: accounting.count)
            let exactPreview = try await issue(exact)
            let exactApp = AppConfigStore(loaded: try XCTUnwrap(services.settingsLoad.envelope),
                                          bridge: exact)
            guard case .accepted(_, let completion) = exactApp.commitImport(exactPreview)
            else { return XCTFail("Exact import byte limit rejected") }
            guard case .saved = await completion.value
            else { return XCTFail("Exact-limit import did not save") }
            await exact.drain()
            XCTAssertEqual(exact.pendingSnapshotCount, 0)
            XCTAssertEqual(exact.pendingSnapshotBytes, 0)
            XCTAssertEqual(io.configAttempts, 1)
            XCTAssertThrowsError(try ExecutionPolicyBridge.checkedRetainedTotalForTesting(
                Int.max, adding: 1))
        }
    }

    func testAdversarialDocumentInputsRejectWithoutTrapRetentionOrInvalidation() async throws {
        let duplicateID = UUID()
        let duplicate = self.t07Profile(duplicateID, "Duplicate")
        let duplicateProfiles = SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [duplicate, duplicate]))
        XCTAssertThrowsError(try PreferencesDocumentEffect.classify(
            before: duplicateProfiles, after: duplicateProfiles)) { error in
            XCTAssertEqual(error as? PreferencesDocumentProjectionError, .invalid)
        }
        let activationWithDuplicates = SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [duplicate, duplicate]),
            activeProfileID: duplicateID)
        XCTAssertThrowsError(try PreferencesDocumentEffect.classify(
            before: .init(schemaVersion: 2, revision: 0, config: .init()),
            after: activationWithDuplicates)) { error in
            XCTAssertEqual(error as? PreferencesDocumentProjectionError, .invalid)
        }

        let inert = InertPortableSetting(scope: .global, profileID: nil,
            id: "future.flag", value: .bool(true), valueKind: nil,
            valueDigest: nil, redacted: false)
        let duplicateInert = SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(), inertImports: [inert, inert])
        XCTAssertThrowsError(try PreferencesDocumentProjection.apply(
            .init(baseRevision: 0), to: duplicateInert)) { error in
            XCTAssertEqual(error as? PreferencesDocumentProjectionError, .invalid)
        }

        let authorityProfile = self.t07Profile(duplicateID, "Authority", [
            ("notifications.enabled", .bool(false))
        ])
        let authorityEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [authorityProfile]))
        let activationWithAuthority = SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(profiles: [authorityProfile]),
            activeProfileID: duplicateID)
        XCTAssertThrowsError(try PreferencesDocumentEffect.classify(
            before: .init(schemaVersion: 2, revision: 0, config: .init()),
            after: activationWithAuthority)) { error in
            XCTAssertEqual(error as? PreferencesDocumentProjectionError,
                           .unsupportedAuthority)
        }
        let renamed = self.t07Profile(duplicateID, "Renamed", [
            ("notifications.enabled", .bool(false))
        ])
        XCTAssertThrowsError(try PreferencesDocumentProjection.apply(.init(baseRevision: 0,
            profiles: [.update(id: duplicateID, base: authorityProfile, edited: renamed)]),
            to: authorityEnvelope)) { error in
            XCTAssertEqual(error as? PreferencesDocumentProjectionError, .unsupportedAuthority)
        }

        try await run { _, services, io in
            let generation = services.policyBridge.updateGeneration
            for id in ["notifications.enabled", "future.unknown"] {
                let delta = PreferencesDocumentDelta(baseRevision: 0,
                    global: [.init(id: self.t07ID(id), baseValue: nil, editedValue: nil)])
                guard case .rejected = services.configStore.submit(document: delta)
                else { return XCTFail("No-op forbidden/unknown field was admitted: \(id)") }
            }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(io.configAttempts, 0)
        }
    }

    func testAggregateOversizedDocumentRejectsBeforeRetentionTicketAndWrite() async throws {
        let paths = (0..<235).map { index in
            "/private/" + String(repeating: "p", count: 3_980) +
                String(format: "%010d", index)
        }
        let seedEnvelope = SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: .init(), preferences: .init(global: self.t07Values([
                ("scope.excludedRoots", .strings(paths))
            ])))
        let seed = try SettingsDecoding.encode(seedEnvelope)
        XCTAssertLessThan(seed.count, SettingsDecoding.byteLimit)
        let profiles = (0..<30).map { index in
            self.t07Profile(UUID(), String(repeating: "n", count: 4_080) +
                String(format: "%010d", index))
        }
        try await run(seed: seed) { _, services, io in
            let generation = services.policyBridge.updateGeneration
            let delta = PreferencesDocumentDelta(baseRevision: 0,
                profiles: profiles.map(ProfileDocumentEdit.insert))
            guard case .rejected = services.configStore.submit(document: delta)
            else { return XCTFail("Aggregate document above persisted byte limit was admitted") }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertEqual(services.policyBridge.updateGeneration, generation)
            XCTAssertEqual(services.coordinator.policyAdmission(), .ready(revision: 1))
            XCTAssertEqual(io.configAttempts, 0)
        }
    }

    func testProductionQueueCeilingCannotBeRaisedByInternalTestLimit() async throws {
        try await run { s, services, _ in
            let bridge = ExecutionPolicyBridge(coordinator: services.coordinator,
                settings: services.settings, loaded: services.settingsLoad,
                homeDirectory: s.home.path, detectedTools: [], pendingByteLimit: Int.max)
            XCTAssertEqual(bridge.pendingByteLimitForTesting, 32 * 1_048_576)
        }
    }

    func testSupersedingImportLifecycleCannotResurrectOlderPreview() async throws {
        let bytes = Data(#"{"schemaVersion":1,"global":{"fields":{"ui.units":{"choice":"decimal"}}},"profiles":[],"inertImports":[]}"#.utf8)
        try await run { _, services, io in
            let first = try await services.configStore.analyzeImport(bytes: bytes)
            let firstID = try XCTUnwrap(first.analysisID)
            let issuance = Task { @MainActor in
                try? await services.configStore.issueImportPreview(analysisID: firstID, choices: [:])
            }
            await Task.yield()
            _ = try await services.configStore.analyzeImport(bytes: bytes)
            if let oldPreview = await issuance.value {
                guard case .rejected(_, .invalid) = services.configStore.commitImport(oldPreview)
                else { return XCTFail("Superseded preview binding was resurrected") }
            }
            XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
            XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
            XCTAssertEqual(io.configAttempts, 0)
        }
    }
}

extension SharedSettingsWiringTests {
    private func expectedSettingsControl(_ definition: SettingDefinition)
        -> SettingsControlKind {
        switch (definition.kind, definition.rule) {
        case (.bool, .boolean): return .toggle
        case (.integer, .integer(_, _)): return .integer
        case (.optionalInteger, .optionalInteger(_, _)),
             (.optionalInteger, .headroomTarget),
             (.optionalInteger, .headroomWarning),
             (.optionalInteger, .headroomClear),
             (.optionalInteger, .budgetHigh),
             (.optionalInteger, .budgetLow): return .optionalInteger
        case (.choice, .choices(_)): return .choice
        default: return .readOnly
        }
    }

    @MainActor
    func testSettingsRowsAreReachableSearchAdvancedAndAuthorityIsDeferred() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let model = SettingsSurfaceModel(store: services.configStore, bundle: bundle)
            let basic = model.rows(query: "", showsAdvanced: false)
            let all = model.rows(query: "", showsAdvanced: true)
            let universe = try SettingsPresentationRegistry.all(volumeIDs: [])
            XCTAssertEqual(Set(all.map(\.id)), Set(universe.map(\.definition.id)))
            XCTAssertEqual(Set(basic.map(\.id)), SettingsPresentationRegistry.basicIDs)
            XCTAssertTrue(basic.allSatisfy { $0.setting.presentation.tier == .basic })
            XCTAssertFalse(basic.contains { $0.setting.presentation.tier == .advanced })

            let advanced = try XCTUnwrap(all.first { row in
                row.setting.presentation.tier == .advanced
            })
            let searchFields = [advanced.id.rawValue, advanced.title, advanced.help,
                advanced.consequence, advanced.defaultText, advanced.effectiveText,
                advanced.sourceText, advanced.ruleText, advanced.availabilityText]
            for field in searchFields where !field.isEmpty {
                XCTAssertTrue(model.rows(query: field, showsAdvanced: false)
                    .contains { $0.id == advanced.id }, "search missed \(field)")
            }
            XCTAssertEqual(SettingsSearch.normalize("  RÉSUMÉ  VALUE "), "resume value")

            let beforePreferences = services.configStore.preferences
            let beforeGeneration = services.policyBridge.updateGeneration
            let beforeAdmission = services.coordinator.policyAdmission()
            let beforeExecutionEnabled = services.policyBridge.isExecutionEnabled
            let beforeRevision = services.policyBridge.durableSettingsRevision
            let authorityRows = all.filter {
                $0.setting.definition.resolution == .authority
            }
            XCTAssertFalse(authorityRows.isEmpty)
            for row in authorityRows {
                guard case .deferred = row.availability else {
                    return XCTFail("authority row not deferred: \(row.id.rawValue)")
                }
                XCTAssertNil(model.submit(id: row.id,
                    value: row.setting.definition.defaultValue))
                XCTAssertEqual(services.configStore.preferences, beforePreferences)
                XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
                XCTAssertEqual(services.coordinator.policyAdmission(), beforeAdmission)
                XCTAssertEqual(services.policyBridge.isExecutionEnabled, beforeExecutionEnabled)
                XCTAssertEqual(services.policyBridge.durableSettingsRevision, beforeRevision)
                XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
                XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
                XCTAssertFalse(services.policyBridge.storageUpdatePending)
                XCTAssertFalse(services.policyBridge.policyUpdatePending)
            }

            let readOnlyGlobalRows = all.filter { row in
                let definition = row.setting.definition
                return definition.resolution != .authority &&
                    definition.layers.contains(.global) && row.controlKind == .readOnly
            }
            XCTAssertFalse(readOnlyGlobalRows.isEmpty)
            for row in readOnlyGlobalRows {
                guard case .unavailable = row.availability else {
                    return XCTFail("read-only global P/R row not unavailable: \(row.id.rawValue)")
                }
                XCTAssertNil(model.submit(id: row.id,
                    value: row.setting.definition.defaultValue))
                XCTAssertEqual(services.configStore.preferences, beforePreferences)
                XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
                XCTAssertEqual(services.coordinator.policyAdmission(), beforeAdmission)
                XCTAssertEqual(services.policyBridge.isExecutionEnabled, beforeExecutionEnabled)
                XCTAssertEqual(services.policyBridge.durableSettingsRevision, beforeRevision)
                XCTAssertEqual(services.policyBridge.pendingSnapshotCount, 0)
                XCTAssertEqual(services.policyBridge.pendingSnapshotBytes, 0)
                XCTAssertFalse(services.policyBridge.storageUpdatePending)
                XCTAssertFalse(services.policyBridge.policyUpdatePending)
            }
            XCTAssertTrue(basic.contains { $0.id.rawValue == "ui.cards" })
            let volume = PolicyDefaults.volumeRow(id:
                UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
            XCTAssertNil(model.submit(id: volume.id, value: .volume(.init(
                target: .automatic, warning: .automatic, clear: .automatic))))
            XCTAssertEqual(services.configStore.preferences, beforePreferences)
            XCTAssertEqual(services.policyBridge.updateGeneration, beforeGeneration)
            XCTAssertEqual(services.coordinator.policyAdmission(), beforeAdmission)
            XCTAssertEqual(services.policyBridge.isExecutionEnabled, beforeExecutionEnabled)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, beforeRevision)

            for row in all where row.setting.definition.resolution != .authority &&
                row.setting.definition.layers.contains(.global) && row.controlKind != .readOnly {
                XCTAssertEqual(row.controlKind,
                               expectedSettingsControl(row.setting.definition))
                let support = SettingsPresentationRegistry.consumerSupport(
                    for: row.setting.definition)
                if support.isConnected {
                    guard case .editable = row.availability else {
                        return XCTFail("connected global P/R row is not editable: \(row.id.rawValue)")
                    }
                } else {
                    guard case .unavailable = row.availability else {
                        return XCTFail("unimplemented row is not visibly unavailable: \(row.id.rawValue)")
                    }
                    XCTAssertNil(model.submit(id: row.id,
                        value: row.setting.definition.defaultValue))
                }
            }
            for row in all {
                XCTAssertEqual(row.controlKind,
                               expectedSettingsControl(row.setting.definition))
            }

            for row in all {
                XCTAssertNotEqual(row.title, row.setting.presentation.keys.title)
                XCTAssertNotEqual(row.help, row.setting.presentation.keys.help)
                XCTAssertNotEqual(row.consequence, row.setting.presentation.keys.consequence)
                XCTAssertNotEqual(row.availabilityText,
                                  row.setting.presentation.keys.applicability)
            }
        }
    }

    @MainActor
    func testSettingsRepresentativeGlobalControlsUseSharedStore() async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let first = SettingsSurfaceModel(store: services.configStore, bundle: bundle)
            let second = SettingsSurfaceModel(store: services.configStore, bundle: bundle)
            let edits: [(String, SettingValue)] = [
                ("feature.headroom", .bool(false)),
                ("scan.preset", .choice("balanced")),
                ("monitor.visibleIntervalSeconds", .integer(6)),
                ("ui.units", .choice("decimal"))
            ]

            for (raw, value) in edits {
                let id = SettingID(rawValue: raw)
                let row = try XCTUnwrap(first.rows(query: raw, showsAdvanced: false)
                    .first { $0.id == id })
                guard case .editable = row.availability else {
                    return XCTFail("representative control unavailable: \(raw)")
                }
                let admission = try XCTUnwrap(first.submit(id: id, value: value))
                let outcome: SettingsIntentOutcome
                switch admission {
                case .accepted(_, let task): outcome = await task.value
                case .rejected(_, let reason):
                    return XCTFail("unexpected rejection for \(raw): \(reason)")
                }
                guard case .saved = outcome else { return XCTFail("\(raw) was not saved") }
                await services.policyBridge.drain()
                XCTAssertEqual(services.configStore.preferences.global.fields[id], value)
                XCTAssertEqual(second.rows(query: raw, showsAdvanced: false)
                    .first { $0.id == id }?.storedValue, value)
            }

            let unavailableID = SettingID(rawValue: "feature.buildPrep")
            let unavailable = try XCTUnwrap(first.rows(query: unavailableID.rawValue,
                showsAdvanced: false).first { $0.id == unavailableID })
            guard case .unavailable(let reason) = unavailable.availability else {
                return XCTFail("Build Prep must be visibly unavailable")
            }
            XCTAssertTrue(reason.contains("R09"))
            XCTAssertNil(first.submit(id: unavailableID, value: .bool(true)))
        }
    }

    @MainActor
    func testSettingsAccessibilityFocusAndSemanticContrastContract() async throws {
        try await run { _, services, _ in
            let model = SettingsSurfaceModel(store: services.configStore,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            let rows = model.rows(query: "", showsAdvanced: true)

            XCTAssertEqual(rows.map(\.focusIndex), Array(rows.indices))
            XCTAssertEqual(Set(rows.map(\.accessibilityIdentifier)).count, rows.count)
            XCTAssertEqual(Set(rows.map(\.accessibilityLabel)).count, rows.count)
            XCTAssertTrue(rows.allSatisfy {
                $0.accessibilityLabel.contains($0.title) &&
                $0.accessibilityLabel.contains($0.id.rawValue)
            })
            XCTAssertTrue(rows.allSatisfy { $0.accessibilityIdentifier ==
                "settings.row." + $0.id.rawValue })
            XCTAssertTrue(rows.allSatisfy { !$0.defaultText.isEmpty && !$0.effectiveText.isEmpty &&
                !$0.sourceText.isEmpty && !$0.ruleText.isEmpty && !$0.consequence.isEmpty })
            XCTAssertEqual(SettingsVisualContract.titleRole, .primary)
            XCTAssertEqual(SettingsVisualContract.metadataRole, .secondary)
            XCTAssertEqual(SettingsVisualContract.unavailableRole, .warning)
            XCTAssertEqual(SettingsVisualContract.layoutMode(for: .large), .columns)
            XCTAssertEqual(SettingsVisualContract.layoutMode(for: .accessibility1), .stacked)

            for section in SettingsPresentationSection.allCases {
                let sectionRows = model.rows(query: "", showsAdvanced: true,
                                             section: section)
                XCTAssertEqual(sectionRows.map(\.focusIndex), Array(sectionRows.indices))
                XCTAssertTrue(sectionRows.allSatisfy {
                    $0.setting.presentation.section == section
                })
            }
            XCTAssertTrue(rows.allSatisfy { !$0.availabilityText.isEmpty })
        }
    }

    @MainActor
    func testSettingsFormatsPolicySemanticsWithoutDuplicatingPolicyTruth() async throws {
        try await run { _, services, _ in
            let rows = SettingsSurfaceModel(store: services.configStore,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
                .rows(query: "", showsAdvanced: true)
            let none = try XCTUnwrap(rows.first { $0.setting.definition.effect == .none })
            let invalidate = try XCTUnwrap(rows.first {
                $0.setting.definition.effect == .invalidate
            })
            let consent = try XCTUnwrap(rows.first { $0.setting.definition.effect == .consent })
            XCTAssertNotEqual(none.consequence, invalidate.consequence)
            XCTAssertNotEqual(none.consequence, consent.consequence)
            XCTAssertNotEqual(invalidate.consequence, consent.consequence)
            XCTAssertTrue(none.consequence.localizedCaseInsensitiveContains("no plan invalidation"))
            XCTAssertTrue(invalidate.consequence.localizedCaseInsensitiveContains("invalidates"))
            XCTAssertTrue(consent.consequence.localizedCaseInsensitiveContains("separate consent"))
            for row in rows {
                XCTAssertTrue(row.availabilityText.contains(
                    row.setting.definition.resolution.rawValue))
                for layer in row.setting.definition.layers {
                    XCTAssertTrue(row.availabilityText.contains(layer.rawValue))
                }
            }
            XCTAssertEqual(SettingsRowAvailability.notApplicable("fixture"),
                           .notApplicable("fixture"))
            XCTAssertFalse(SettingsSearch.haystack(for: none).isEmpty)
        }
    }

    @MainActor
    func testSettingsCachesValidatedRegistryAndLocalizedPresentationAcrossSearch() async throws {
        try await run { _, services, _ in
            let model = SettingsSurfaceModel(store: services.configStore,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
            let beforeValidation = SettingsSurfaceModel.registryValidationCount
            _ = model.rows(query: "", showsAdvanced: true, section: .features)
            let afterFirstValidation = SettingsSurfaceModel.registryValidationCount
            let afterFirstLocalization = SettingsSurfaceModel.localizationResolutionCount
            _ = model.rows(query: "cache", showsAdvanced: false, section: .features)
            _ = model.rows(query: "CACHE", showsAdvanced: true, section: .features)
            XCTAssertLessThanOrEqual(afterFirstValidation - beforeValidation, 1)
            XCTAssertEqual(SettingsSurfaceModel.registryValidationCount,
                           afterFirstValidation)
            XCTAssertEqual(SettingsSurfaceModel.localizationResolutionCount,
                           afterFirstLocalization)
        }
    }

    func testSettingsIntegerDraftCommitsOnceAndSynchronizesExternalValue() {
        var draft = SettingsIntegerDraft(storedValue: .integer(10), allowsAutomatic: false)
        var submissions: [SettingValue] = []
        draft.replaceText("")
        draft.replaceText("2")
        draft.replaceText("20")
        XCTAssertTrue(submissions.isEmpty)
        if let value = draft.committedValue { submissions.append(value) }
        XCTAssertEqual(submissions, [.integer(20)])
        draft.synchronize(storedValue: .integer(35))
        XCTAssertEqual(draft.text, "35")

        var optional = SettingsIntegerDraft(storedValue: .integer(7), allowsAutomatic: true)
        optional.replaceText("")
        XCTAssertEqual(optional.committedValue, .null)
        XCTAssertEqual(submissions.count, 1)
    }

    @MainActor
    func testSettingsEmptyStatesSeparateNoMatchFromRegistryFailure() {
        XCTAssertEqual(SettingsSurfaceEmptyState.resolve(rows: [], registryState: .valid),
                       .noMatches)
        XCTAssertEqual(SettingsSurfaceEmptyState.resolve(rows: [],
            registryState: .invalid("fixture")), .registryFailure("fixture"))
        XCTAssertEqual(SettingsSurfaceEmptyState.resolve(rows:
            SettingsSurfaceModel.fixtureRows(bundle: Bundle(for: SharedSettingsWiringTests.self)),
            registryState: .valid), .content)
    }

    @MainActor
    func testSettingsLocalizedConsequenceConsumesEffectAndAccessibilityIsComplete()
        async throws {
        try await run { _, services, _ in
            let bundle = Bundle(for: SharedSettingsWiringTests.self)
            let presentation = try XCTUnwrap(SettingsPresentationRegistry.entries.first)
            let none = SettingsCopy.resolve(presentation.keys.consequence,
                arguments: [describe(AuthorityEffect.none)], bundle: bundle)
            let invalidate = SettingsCopy.resolve(presentation.keys.consequence,
                arguments: [describe(AuthorityEffect.invalidate)], bundle: bundle)
            let consent = SettingsCopy.resolve(presentation.keys.consequence,
                arguments: [describe(AuthorityEffect.consent)], bundle: bundle)
            XCTAssertNotEqual(none, invalidate)
            XCTAssertNotEqual(none, consent)
            XCTAssertNotEqual(invalidate, consent)

            let rows = SettingsSurfaceModel(store: services.configStore, bundle: bundle)
                .rows(query: "", showsAdvanced: true)
            for row in rows {
                let value = SettingsAccessibility.value(for: row)
                let help = SettingsAccessibility.help(for: row)
                XCTAssertTrue(value.contains(row.defaultText))
                XCTAssertTrue(value.contains(row.effectiveText))
                XCTAssertTrue(value.contains(row.sourceText))
                XCTAssertTrue(value.contains(row.ruleText))
                XCTAssertTrue(help.contains(row.consequence))
                XCTAssertTrue(help.contains(row.availabilityText))
            }
            for row in rows where row.setting.definition.layers.isEmpty {
                XCTAssertTrue(row.availabilityText.contains("none; local authority only"))
                XCTAssertFalse(row.availabilityText.contains("Layers: ."))
            }
        }
    }

    @MainActor
    func testSettingsAccessibilityTextLayoutRendersAtMinimumWidth() async throws {
        try await run { _, services, _ in
            let rows = SettingsSurfaceModel(store: services.configStore,
                bundle: Bundle(for: SharedSettingsWiringTests.self))
                .rows(query: "", showsAdvanced: false)
            var submissions = 0
            let view = RegistrySettingsSurface(rows: rows) { _, _ in submissions += 1 }
                .environment(\.dynamicTypeSize, .accessibility3)
                .frame(width: 480, height: 900)
            let renderer = ImageRenderer(content: view)

            XCTAssertNotNil(renderer.cgImage)
            XCTAssertEqual(submissions, 0, "rendering/opening must not submit an edit")
        }
    }

    func testSettingsLocalizationCatalogCoversEveryRegistryKey() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf:
            repository.appendingPathComponent("Tidy/Resources/Localizable.xcstrings"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data)
            as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        var required = Set(SettingsPresentationRegistry.entries.flatMap { entry in
            [entry.keys.title, entry.keys.help, entry.keys.consequence,
             entry.keys.applicability]
        })
        required.insert("settings.copy.missing")
        XCTAssertTrue(required.isSubset(of: Set(strings.keys)))
        for key in required {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let english = try XCTUnwrap(localizations["en"] as? [String: Any])
            let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty)
            XCTAssertNotEqual(value, key)
        }
    }

    func testSettingsDynamicLocalizationInterpolatesIdentityAndFallsBackSafely() throws {
        let bundle = Bundle(for: SharedSettingsWiringTests.self)
        func keys(_ presentation: SettingPresentation) -> [String] {
            [presentation.keys.title, presentation.keys.help,
             presentation.keys.consequence, presentation.keys.applicability]
        }
        func resolved(_ presentation: SettingPresentation,
                      definition: SettingDefinition, identity: String) -> [String] {
            keys(presentation).map { key in
                let arguments: [CVarArg] = key == presentation.keys.consequence
                    ? [identity, describe(definition.effect)] : [identity]
                return SettingsCopy.resolve(key, arguments: arguments, bundle: bundle)
            }
        }

        let items = Array(CleanCatalog.allItems.prefix(2))
        XCTAssertEqual(items.count, 2)
        let firstItem = try XCTUnwrap(items.first)
        let secondItem = try XCTUnwrap(items.last)
        XCTAssertNotEqual(firstItem.id, secondItem.id)
        let firstDefinitions = PolicyDefaults.itemRows(catalogID: firstItem.id)
        let secondDefinitions = PolicyDefaults.itemRows(catalogID: secondItem.id)
        XCTAssertEqual(firstDefinitions.count, 4)
        XCTAssertEqual(secondDefinitions.count, 4)
        for (firstDefinition, secondDefinition) in zip(firstDefinitions, secondDefinitions) {
            let firstPresentation = try SettingsPresentationRegistry.presentation(
                for: firstDefinition)
            let secondPresentation = try SettingsPresentationRegistry.presentation(
                for: secondDefinition)
            XCTAssertEqual(firstPresentation.pattern, secondPresentation.pattern,
                           "paired catalog rows must use the same suffix presentation")
            let firstCopy = resolved(firstPresentation, definition: firstDefinition,
                                     identity: firstItem.id)
            let secondCopy = resolved(secondPresentation, definition: secondDefinition,
                                      identity: secondItem.id)
            XCTAssertEqual(firstCopy.count, 4)
            XCTAssertEqual(secondCopy.count, 4)
            XCTAssertTrue(firstCopy.allSatisfy { $0.contains(firstItem.id) })
            XCTAssertTrue(secondCopy.allSatisfy { $0.contains(secondItem.id) })
            for (firstOutput, secondOutput) in zip(firstCopy, secondCopy) {
                XCTAssertNotEqual(firstOutput, secondOutput,
                                  "corresponding suffix/key output must include its identity")
            }
        }

        let sentinel = SettingsPresentationRegistry.validationVolumeID
        let other = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let sentinelDefinition = PolicyDefaults.volumeRow(id: sentinel)
        let otherDefinition = PolicyDefaults.volumeRow(id: other)
        let sentinelCopy = resolved(try SettingsPresentationRegistry.presentation(
            for: sentinelDefinition), definition: sentinelDefinition,
            identity: sentinel.uuidString)
        let otherCopy = resolved(try SettingsPresentationRegistry.presentation(
            for: otherDefinition), definition: otherDefinition, identity: other.uuidString)
        XCTAssertTrue(sentinelCopy.allSatisfy { $0.contains(sentinel.uuidString) })
        XCTAssertTrue(otherCopy.allSatisfy { $0.contains(other.uuidString) })
        XCTAssertNotEqual(sentinelCopy, otherCopy)

        XCTAssertEqual(SettingsCopy.resolve("settings.copy.missing", bundle: bundle),
                       "Description unavailable.")
        let missing = SettingsCopy.resolve("settings.fixture.does-not-exist", bundle: bundle)
        XCTAssertEqual(missing, "Description unavailable.")
        XCTAssertFalse(missing.contains("settings.fixture.does-not-exist"))
    }

    func testSettingsSourceHasNoOnOpenWorkTrigger() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf:
            repository.appendingPathComponent("Tidy/Settings/SettingsView.swift"),
            encoding: .utf8)
        let forbidden = [
            ".task", "Task.detached", ".onAppear", ".onReceive",
            ".refreshable", "Timer", "Process(", "Process.", "ProcessSurvey",
            "CookieDomainSuggester", "GitRootDiscovery", "SimctlClient", "CleanEngine",
            "requestPlan", "loadPlan", "FileManager", "URLSession", "NSWorkspace",
            "DispatchSource", "NotificationCenter"
        ]
        for token in forbidden {
            XCTAssertFalse(source.contains(token), "Settings on-open source contains \(token)")
        }
        let taskBoundaryBegin = "// SETTINGS_WORKFLOW_TASK_BOUNDARIES_BEGIN"
        let taskBoundaryEnd = "// SETTINGS_WORKFLOW_TASK_BOUNDARIES_END"
        XCTAssertEqual(source.components(separatedBy: taskBoundaryBegin).count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: taskBoundaryEnd).count - 1, 1)
        let taskBeginRange = try XCTUnwrap(source.range(of: taskBoundaryBegin))
        let taskEndRange = try XCTUnwrap(source.range(of: taskBoundaryEnd))
        let taskBlock = String(source[taskBeginRange.lowerBound..<taskEndRange.upperBound])
        XCTAssertEqual(taskBlock.components(separatedBy: "Task {").count - 1, 4)
        XCTAssertFalse(source[..<taskBeginRange.lowerBound].contains("Task {"))
        XCTAssertFalse(source[taskEndRange.upperBound...].contains("Task {"))
        var taskRemainder = taskBlock
        for helper in ["beginImportSelection", "beginImportPreviewIssuance",
                       "beginImportConfirmation", "beginImportCancellation"] {
            let helperBegin = "// SETTINGS_WORKFLOW_TASK_BEGIN_" + helper
            let helperEnd = "// SETTINGS_WORKFLOW_TASK_END_" + helper
            let helperBeginRange = try XCTUnwrap(taskRemainder.range(of: helperBegin))
            let helperEndRange = try XCTUnwrap(taskRemainder.range(of: helperEnd))
            let extracted = String(taskRemainder[
                helperBeginRange.lowerBound..<helperEndRange.upperBound])
            XCTAssertEqual(extracted.components(separatedBy: "Task {").count - 1, 1)
            taskRemainder.replaceSubrange(
                helperBeginRange.lowerBound..<helperEndRange.upperBound, with: "")
        }
        taskRemainder = taskRemainder.replacingOccurrences(of: taskBoundaryBegin, with: "")
            .replacingOccurrences(of: taskBoundaryEnd, with: "")
        XCTAssertTrue(taskRemainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(source.contains("ExecutionPolicyBridge"))
        XCTAssertFalse(source.contains("SettingsStore"))
        XCTAssertFalse(source.contains("Color(red:"))
        XCTAssertFalse(source.contains(".opacity("))
        XCTAssertTrue(source.contains("SettingsVisualContract.titleRole"))
        XCTAssertTrue(source.contains("SettingsVisualContract.layoutMode"))
        XCTAssertTrue(source.contains("store.setGlobalPreference"))
        XCTAssertTrue(source.contains("String.LocalizationValue(key)"))
        XCTAssertTrue(source.contains("String(localized:"))
        XCTAssertFalse(source.contains("accessibilityElement(children: .combine)"))
        XCTAssertTrue(source.contains("semanticText(row.availabilityText"))
        XCTAssertFalse(source.contains("@State private var integerText"))
        XCTAssertFalse(source.contains("@State private var optionalText"))
        XCTAssertTrue(source.contains(".onSubmit"))
        XCTAssertTrue(source.contains("No settings match"))
        XCTAssertTrue(source.contains("settings.registry.failure"))
    }
}
