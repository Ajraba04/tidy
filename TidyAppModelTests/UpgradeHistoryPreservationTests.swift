import Foundation
import Darwin
import Dispatch
import XCTest
@testable import TidyCore

@MainActor
final class UpgradeHistoryPreservationTests: XCTestCase {
    func testMaintenanceRetriesBusyPresentationEditStartedInsideActualAcknowledgementValidation() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .legacy)
        defer { f.remove() }
        let settings = SettingsStore(url: f.settings)
        let ownedLock = HistoryOwnedAdvisoryLock()
        defer { ownedLock.release() }
        let injected = expectation(description: "B admitted inside A's maintenance validation")
        let injector = HistoryMaintenanceValidationRaceInjector(lock: ownedLock,
            lockPath: f.support.appendingPathComponent("config.lock"),
            history: f.history, originalHistory: f.historyBytes, onInjected: { injected.fulfill() })
        let services = await AppExecutionServices.bootstrap(paths: f.paths, settings: settings,
            observe: { _ in }, observeBeforeHistoryAcknowledgement: { revision in
                MainActor.assumeIsolated { injector.observe(revision: revision) }
            })
        defer { services.disposeMonitoring() }
        await services.awaitPolicyMaintenance()
        injector.services = services
        let base = services.configStore.config
        var edited = base; edited.transcriptAgeThresholdDays = 46
        guard case .accepted(_, let first) = services.policyBridge.submit(legacy: .init(
            baseRevision: 0, base: base, edited: edited, compatibilityBase: nil)) else {
            XCTFail("Real A was not admitted"); return
        }
        guard case .saved(_, let saved) = await first.value else {
            await services.policyBridge.drain(); XCTFail("A did not become durable"); return
        }
        await fulfillment(of: [injected], timeout: 2)
        let second = try XCTUnwrap(injector.save)
        let secondOutcome = await second.value
        guard case .failed(_, let recoveryRequired) = secondOutcome else {
            XCTFail("Real B must fail lock contention before publication: \(secondOutcome)"); return
        }
        XCTAssertFalse(recoveryRequired)
        await services.policyBridge.drain()
        await services.awaitPolicyMaintenance()
        XCTAssertTrue(ownedLock.wasAcquired)
        XCTAssertTrue(ownedLock.wasReleasedAtReadBoundary,
            "A must retry validation after B settles rather than drop its saved acknowledgement")
        XCTAssertGreaterThanOrEqual(injector.boundaries, 2)
        XCTAssertFalse(ownedLock.watchdogFired)
        // Cleanup is not authority: the actual actor/disk assertion below still
        // proves B never advanced A, even when the regression fails beforehand.
        ownedLock.release()
        let actual = await settings.acknowledgesPersistedEnvelope(saved)
        XCTAssertTrue(actual)
        XCTAssertTrue(services.policyBridge.isExecutionEnabled)
        XCTAssertEqual(services.policyBridge.acknowledgedEnvelope, saved)
        let retained = try f.readHistory()
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained.first?.results.first?.id, "fixture.recent")
        XCTAssertNil(services.historyPersistenceError)
    }
    func testRecordingBoundsContinuousRealValidationEditsAndReportsUnstoredTerminalResult() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .durable)
        defer { f.remove() }
        let injector = HistoryValidationChurnInjector(maximumEdits: 16)
        let services = await AppExecutionServices.bootstrap(paths: f.paths,
            settings: SettingsStore(url: f.settings), observe: { _ in },
            observeBeforeHistoryAcknowledgement: { revision in
                MainActor.assumeIsolated { injector.issue(revision: revision) }
            })
        await services.awaitPolicyMaintenance()
        // Disposal ends only the monitor observer. It isolates the explicit
        // recording validation below without revoking its real policy owner.
        services.disposeMonitoring()
        injector.services = services
        let baseline = try Data(contentsOf: f.history)
        await services.recordCompletedRun(f.recentReport)
        await services.policyBridge.drain()
        XCTAssertGreaterThan(injector.saves.count, 0)
        XCTAssertLessThan(injector.saves.count, 16,
            "Continuous real edits must exhaust a finite retry budget before becoming stable")
        XCTAssertEqual(try Data(contentsOf: f.history), baseline)
        XCTAssertEqual(try f.readHistory().filter { $0.results.first?.id == "fixture.recorded" }.count, 0)
        let warning = try XCTUnwrap(services.historyPersistenceError)
        XCTAssertTrue(warning.contains("not stored"))
        XCTAssertTrue(warning.contains("settings"))
        await services.awaitPolicyMaintenance()
        XCTAssertEqual(services.historyPersistenceError, warning)
    }
    func testRecordingRetriesPresentationEditStartedInsideAcknowledgementValidation() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .durable)
        defer { f.remove() }
        let io = HistorySaveQueueIO(revisions: [8])
        defer { io.releaseAll() }
        let settings = SettingsStore(url: f.settings, io: io)
        let injected = expectation(description: "Real presentation edit admitted inside validation")
        let injector = HistoryValidationSaveInjector(onInjected: { injected.fulfill() })
        let services = await AppExecutionServices.bootstrap(paths: f.paths, settings: settings,
            observe: { _ in }, observeBeforeHistoryAcknowledgement: { revision in
                MainActor.assumeIsolated { injector.issueOnce(revision: revision) }
            })
        defer { services.disposeMonitoring() }
        await services.awaitPolicyMaintenance()
        injector.services = services
        XCTAssertFalse(services.policyBridge.storageUpdatePending)
        XCTAssertEqual(services.policyBridge.durableSettingsRevision, 7)
        let baseline = try Data(contentsOf: f.history)
        let recording = Task { @MainActor in await services.recordCompletedRun(f.recentReport) }
        do {
            await fulfillment(of: [injected], timeout: 2)
            try await io.waitUntilHeld(revision: 8)
            XCTAssertTrue(injector.didInject)
            XCTAssertTrue(services.policyBridge.storageUpdatePending)
            XCTAssertEqual(try Data(contentsOf: f.history), baseline,
                "No history write may cross an acknowledgement-validation edit")
            recording.cancel()
            io.release(revision: 8)
            let save = try XCTUnwrap(injector.save)
            let outcome = await save.value
            guard case .saved(_, let saved) = outcome else {
                await recording.value; XCTFail("Injected genuine save failed: \(outcome)"); return
            }
            await services.policyBridge.drain()
            await recording.value
            await services.awaitPolicyMaintenance()
            XCTAssertEqual(saved.revision, 8)
            XCTAssertEqual(services.policyBridge.acknowledgedEnvelope, saved)
            XCTAssertTrue(services.policyBridge.isExecutionEnabled)
            XCTAssertFalse(io.watchdogFired)
            let retained = try f.readHistory()
            XCTAssertEqual(retained.count, 2)
            XCTAssertEqual(retained.filter { $0.results.first?.id == "fixture.recorded" }.count, 1,
                "A real edit during validation must cause retry rather than terminal-report loss")
        } catch {
            io.releaseAll(); await services.policyBridge.drain(); await recording.value
            throw error
        }
    }
    func testRealAcknowledgementAppliesAfterBusyPresentationSaveFailsWithoutAdvancingStore() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .legacy)
        defer { f.remove() }
        let io = HistorySaveQueueIO(revisions: [1])
        defer { io.releaseAll() }
        let settings = SettingsStore(url: f.settings, io: io)
        let ownedLock = HistoryOwnedAdvisoryLock()
        defer { ownedLock.release() }
        let services = await AppExecutionServices.bootstrap(paths: f.paths, settings: settings,
            observe: { _ in }, observeBeforeHistoryAcknowledgement: { revision in
                if revision == 1 { ownedLock.releaseAtReadBoundary() }
            })
        defer { services.disposeMonitoring() }
        await services.awaitPolicyMaintenance()
        // This existing synchronous acknowledgement observer executes after
        // A's actor has released its stable lock and before A's bridge task can
        // finish. B awaits that task, so acquisition precedes B's publication.
        let observer = services.configStore.observeAcknowledgedPolicy { revision, _ in
            guard revision == 1 else { return }
            XCTAssertTrue(services.policyBridge.storageUpdatePending)
            XCTAssertTrue(ownedLock.acquire(f.support.appendingPathComponent("config.lock")))
            XCTAssertEqual(try? Data(contentsOf: f.history), f.historyBytes)
        }
        defer { services.configStore.removeAcknowledgedPolicyObserver(observer) }
        do {
            let base = services.configStore.config
            var edited = base; edited.transcriptAgeThresholdDays = 46
            guard case .accepted(_, let first) = services.policyBridge.submit(legacy: .init(
                baseRevision: 0, base: base, edited: edited, compatibilityBase: nil)) else {
                XCTFail("A was not admitted"); return
            }
            try await io.waitUntilHeld(revision: 1)
            guard case .accepted(_, let second) = services.configStore.setGlobalPreference(
                .init(rawValue: "scan.uiBatchesPerSecond"), to: .integer(3)) else {
                io.releaseAll(); await services.policyBridge.drain()
                XCTFail("Presentation B was not admitted"); return
            }
            io.release(revision: 1)
            guard case .saved(_, let firstSaved) = await first.value else {
                await services.policyBridge.drain(); XCTFail("A did not become genuinely durable"); return
            }
            let secondOutcome = await second.value
            guard case .failed(_, let recoveryRequired) = secondOutcome else {
                XCTFail("B should fail real lock contention before publication: \(secondOutcome)"); return
            }
            XCTAssertFalse(recoveryRequired)
            await services.policyBridge.drain()
            await services.awaitPolicyMaintenance()
            XCTAssertTrue(ownedLock.wasAcquired)
            XCTAssertTrue(ownedLock.wasReleasedAtReadBoundary)
            XCTAssertFalse(ownedLock.watchdogFired)
            XCTAssertFalse(io.watchdogFired)
            XCTAssertTrue(services.policyBridge.isExecutionEnabled)
            XCTAssertEqual(services.policyBridge.acknowledgedEnvelope, firstSaved)
            let actual = await settings.acknowledgesPersistedEnvelope(firstSaved)
            XCTAssertTrue(actual, "Busy B must not advance or invalidate actual acknowledged A")
            let retained = try f.readHistory()
            XCTAssertEqual(retained.count, 1)
            XCTAssertEqual(retained.first?.results.first?.id, "fixture.recent")
            XCTAssertNil(services.historyPersistenceError)
        } catch {
            io.releaseAll(); ownedLock.release()
            await services.policyBridge.drain()
            throw error
        }
    }
    func testCancelledOwnerStillRecordsCompletedTerminalReportAfterPendingSaveSettles() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .durable)
        defer { f.remove() }
        let io = HistorySaveQueueIO(revisions: [8])
        defer { io.releaseAll() }
        let settings = SettingsStore(url: f.settings, io: io)
        let services = await AppExecutionServices.bootstrap(paths: f.paths, settings: settings, observe: { _ in })
        defer { services.disposeMonitoring() }
        await services.awaitPolicyMaintenance()
        let baseline = try Data(contentsOf: f.history)
        var recording: Task<Void, Never>?
        do {
            guard case .accepted(_, let save) = services.configStore.setGlobalPreference(
                .init(rawValue: "scan.uiBatchesPerSecond"), to: .integer(3)) else {
                XCTFail("Presentation save was not admitted"); return
            }
            try await io.waitUntilHeld(revision: 8)
            let invoked = expectation(description: "Terminal recording invoked on owned app actor")
            recording = Task { @MainActor in
                invoked.fulfill()
                await services.recordCompletedRun(f.recentReport)
            }
            await fulfillment(of: [invoked], timeout: 2)
            XCTAssertTrue(services.policyBridge.storageUpdatePending)
            XCTAssertEqual(try Data(contentsOf: f.history), baseline)
            recording?.cancel()
            io.release(revision: 8)
            let outcome = await save.value
            guard case .saved(_, let saved) = outcome else {
                await recording?.value
                XCTFail("Genuine presentation save did not succeed: \(outcome)"); return
            }
            await services.policyBridge.drain()
            await recording?.value
            await services.awaitPolicyMaintenance()
            XCTAssertEqual(saved.revision, 8)
            XCTAssertEqual(services.policyBridge.acknowledgedEnvelope, saved)
            XCTAssertTrue(services.policyBridge.isExecutionEnabled)
            XCTAssertFalse(io.watchdogFired)
            let retained = try f.readHistory()
            XCTAssertEqual(retained.count, 2)
            XCTAssertEqual(retained.filter { $0.results.first?.id == "fixture.recorded" }.count, 1,
                "Cancellation of the owned execution call cannot discard its already-produced terminal report")
        } catch {
            io.releaseAll(); await services.policyBridge.drain(); await recording?.value
            throw error
        }
    }
    func testCompletedReportWaitsForPendingPresentationSaveAndIsRecordedExactlyOnce() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .durable)
        defer { f.remove() }
        let io = HistorySaveQueueIO(revisions: [8])
        defer { io.releaseAll() }
        let settings = SettingsStore(url: f.settings, io: io)
        let services = await AppExecutionServices.bootstrap(paths: f.paths, settings: settings, observe: { _ in })
        defer { services.disposeMonitoring() }
        await services.awaitPolicyMaintenance()
        XCTAssertEqual(services.policyBridge.durableSettingsRevision, 7)
        XCTAssertTrue(services.policyBridge.isExecutionEnabled)
        let baseline = try Data(contentsOf: f.history)
        XCTAssertEqual(try f.readHistory().count, 1)
        var recording: Task<Void, Never>?
        do {
            guard case .accepted(_, let save) = services.configStore.setGlobalPreference(
                .init(rawValue: "scan.uiBatchesPerSecond"), to: .integer(3)) else {
                XCTFail("Presentation save was not admitted"); return
            }
            try await io.waitUntilHeld(revision: 8)
            XCTAssertTrue(services.policyBridge.storageUpdatePending)
            XCTAssertTrue(services.policyBridge.isExecutionEnabled)
            let invoked = expectation(description: "Owned record call invoked on app actor")
            recording = Task { @MainActor in
                // Fulfillment does not suspend this app-actor task. The record
                // call reaches its existing synchronous guard (or its future
                // queue wait) before the test resumes on that same actor.
                invoked.fulfill()
                await services.recordCompletedRun(f.recentReport)
            }
            await fulfillment(of: [invoked], timeout: 2)
            XCTAssertTrue(services.policyBridge.storageUpdatePending)
            XCTAssertEqual(try Data(contentsOf: f.history), baseline,
                "A pending presentation save must not authorize a history write")
            io.release(revision: 8)
            let outcome = await save.value
            guard case .saved(_, let saved) = outcome else {
                await recording?.value
                XCTFail("Real presentation save did not succeed: \(outcome)"); return
            }
            XCTAssertEqual(saved.revision, 8)
            await services.policyBridge.drain()
            await recording?.value
            await services.awaitPolicyMaintenance()
            XCTAssertFalse(io.watchdogFired)
            XCTAssertEqual(services.policyBridge.acknowledgedEnvelope, saved)
            let retained = try f.readHistory()
            XCTAssertEqual(retained.count, 2)
            XCTAssertEqual(retained.filter { $0.results.first?.id == "fixture.recorded" }.count, 1,
                "The once-only app-owned recording call must survive queue settlement")
        } catch {
            io.releaseAll()
            await services.policyBridge.drain()
            await recording?.value
            throw error
        }
    }
    func testExternalDurableSupersessionPreservesHistoryInsteadOfApplyingStaleAcknowledgement() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .legacy)
        defer { f.remove() }
        let io = HistorySaveQueueIO()
        defer { io.releaseAll() }
        let settings = SettingsStore(url: f.settings, io: io)
        let reachedHistoryBoundary = expectation(description: "A reached the callback-owned history boundary")
        let services = await AppExecutionServices.bootstrap(paths: f.paths, settings: settings,
            observe: { _ in }, observePolicyMaintenance: { revision in
                if revision == 1 { reachedHistoryBoundary.fulfill() }
            })
        defer { services.disposeMonitoring() }
        await services.awaitPolicyMaintenance()
        var external: Task<SettingsEnvelope, Error>?
        do {
            let base = services.configStore.config
            var edited = base; edited.transcriptAgeThresholdDays = 46
            guard case .accepted(_, let first) = services.policyBridge.submit(legacy: .init(
                baseRevision: 0, base: base, edited: edited, compatibilityBase: nil)) else {
                XCTFail("A was not admitted"); return
            }
            try await io.waitUntilHeld(revision: 1)
            guard case .accepted(_, let second) = services.configStore.setGlobalPreference(
                .init(rawValue: "scan.uiBatchesPerSecond"), to: .integer(3)) else {
                io.releaseAll(); await services.policyBridge.drain()
                XCTFail("Presentation B was not admitted"); return
            }
            // Queue a genuine actor-issued external update while A's actor is
            // held. It runs after A, making B's expected revision stale. C's
            // second bounded I/O hold keeps B pending without faking a policy.
            let enqueued = expectation(description: "External actor update queued")
            external = Task { @MainActor in
                enqueued.fulfill()
                var preferences = PolicyPreferences.project(legacy: edited, saved: nil)
                preferences.global.fields[.init(rawValue: "history.retentionDays")] = .integer(90)
                return try await settings.update(expectedRevision: 1, change: .preferences(preferences))
            }
            await fulfillment(of: [enqueued], timeout: 2)
            io.release(revision: 1)
            guard case .saved(_, let firstSaved) = await first.value else {
                io.releaseAll(); await services.policyBridge.drain(); _ = try? await external?.value
                XCTFail("A did not become genuinely durable"); return
            }
            try await io.waitUntilHeld(revision: 2)
            await fulfillment(of: [reachedHistoryBoundary], timeout: 2)
            XCTAssertEqual(firstSaved.revision, 1)
            XCTAssertTrue(services.policyBridge.storageUpdatePending)
            XCTAssertTrue(services.policyBridge.isExecutionEnabled)
            XCTAssertEqual(try Data(contentsOf: f.history), f.historyBytes,
                "A's retention must remain deferred while B is pending")
            io.release(revision: 2)
            let externalSaved = try await external?.value
            XCTAssertEqual(externalSaved?.revision, 2)
            XCTAssertEqual(externalSaved?.preferences?.global.fields[.init(rawValue: "history.retentionDays")], .integer(90))
            let secondOutcome = await second.value
            guard case .conflict = secondOutcome else {
                XCTFail("B should conflict before writing: \(secondOutcome)"); return
            }
            await services.policyBridge.drain()
            XCTAssertFalse(services.policyBridge.storageUpdatePending)
            XCTAssertFalse(services.policyBridge.policyUpdatePending)
            XCTAssertTrue(services.policyBridge.isExecutionEnabled,
                "A remains acknowledged; presentation conflict does not revoke its authority")
            XCTAssertEqual(services.policyBridge.acknowledgedEnvelope, firstSaved)
            XCTAssertEqual(services.policyBridge.durableSettingsRevision, 1)
            await services.awaitPolicyMaintenance()
            XCTAssertFalse(io.watchdogFired, "Both finite fixture holds must be released explicitly")
            XCTAssertEqual(try Data(contentsOf: f.history), f.historyBytes,
                "The external90-day policy must not be overwritten by stale30-day acknowledgement retention")
            XCTAssertNotNil(services.historyPersistenceError,
                "A real-store mismatch must request acknowledgement refresh without adopting external policy")
        } catch {
            io.releaseAll()
            await services.policyBridge.drain()
            _ = try? await external?.value
            throw error
        }
    }
    func testLegacyHistoryRemainsExactUntilGenuineDurableSaveAcknowledgement() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .legacy)
        defer { f.remove() }
        let services = await AppExecutionServices.bootstrap(paths: f.paths)
        defer { services.disposeMonitoring() }
        XCTAssertEqual(services.settingsLoad.disposition, .migrated)
        XCTAssertEqual(services.configStore.acknowledgedSettingsRevision, 0)
        await services.awaitPolicyMaintenance()
        XCTAssertEqual(try Data(contentsOf: f.history), f.historyBytes)
        XCTAssertEqual(try Data(contentsOf: f.settings), f.settingsBytes)

        services.configStore.installLocalAuthority(nil)
        await services.awaitPolicyMaintenance()
        XCTAssertEqual(try Data(contentsOf: f.history), f.historyBytes)
        let directory = f.support.appendingPathComponent("authority")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let authority = try LocalAuthorityStore(directory: directory,
            installation: LocalInstallationIdentity.verify(directory: directory))
        services.configStore.installLocalAuthority(try await authority.snapshot())
        await services.awaitPolicyMaintenance()
        XCTAssertEqual(try Data(contentsOf: f.history), f.historyBytes)

        await services.recordCompletedRun(f.recentReport)
        XCTAssertEqual(try Data(contentsOf: f.history), f.historyBytes,
            "Recording must not introduce default retention before durable owner acknowledgement")

        // This is the same base-bound compatibility edit used by the real
        // AppConfigStore.config setter. It projects the nondefault legacy
        // cookie field instead of constructing an unrelated empty preference
        // document that the scheduler correctly refuses as mismatched.
        let base = services.configStore.config
        var edited = base
        edited.transcriptAgeThresholdDays = 46
        let submission = services.policyBridge.submit(legacy: .init(
            baseRevision: services.configStore.acknowledgedSettingsRevision,
            base: base, edited: edited,
            compatibilityBase: services.policyBridge.acknowledgedEnvelope?.preferences?.global))
        guard case .accepted(_, let savedTask) = submission else {
            XCTFail("Real settings save was not admitted"); return
        }
        let outcome = await savedTask.value
        guard case .saved(_, let saved) = outcome else {
            XCTFail("Real settings save did not succeed: \(outcome)"); return
        }
        XCTAssertGreaterThan(saved.revision, 0)
        XCTAssertEqual(saved.config.keepCookieDomains, ["fixture.invalid"])
        XCTAssertEqual(saved.config.transcriptAgeThresholdDays, 46)
        XCTAssertEqual(try Data(contentsOf: f.support.appendingPathComponent("config.backup.json")), f.settingsBytes)
        await services.policyBridge.drain()
        await services.awaitPolicyMaintenance()
        XCTAssertEqual(services.policyBridge.durableSettingsRevision, saved.revision)
        XCTAssertEqual(services.policyBridge.acknowledgedEnvelope, saved)
        let retained = try f.readHistory()
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained.first?.results.first?.id, "fixture.recent")
    }

    func testAbsentAndMalformedSettingsPreserveExistingHistoryWithoutFallbackRetention() async throws {
        for kind in [HistoryUpgradeFixture.Settings.absent, .malformed] {
            let f = try HistoryUpgradeFixture.make(settings: kind)
            defer { f.remove() }
            let services = await AppExecutionServices.bootstrap(paths: f.paths)
            defer { services.disposeMonitoring() }
            XCTAssertEqual(services.settingsLoad.disposition,
                kind == .absent ? .newDefaults : .recoveryReadOnly)
            await services.awaitPolicyMaintenance()
            services.configStore.installLocalAuthority(nil)
            await services.awaitPolicyMaintenance()
            await services.recordCompletedRun(f.recentReport)
            XCTAssertEqual(try Data(contentsOf: f.history), f.historyBytes)
            if kind == .absent {
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.settings.path))
            } else {
                XCTAssertEqual(try Data(contentsOf: f.settings), f.settingsBytes)
                XCTAssertNil(services.policyBridge.acknowledgedEnvelope)
            }
        }
    }

    func testLoadedDurableOwnerPolicyRetainsExistingStartupRetention() async throws {
        let f = try HistoryUpgradeFixture.make(settings: .durable)
        defer { f.remove() }
        let services = await AppExecutionServices.bootstrap(paths: f.paths)
        defer { services.disposeMonitoring() }
        XCTAssertEqual(services.settingsLoad.disposition, .loaded)
        XCTAssertEqual(services.policyBridge.durableSettingsRevision, 7)
        await services.awaitPolicyMaintenance()
        let retained = try f.readHistory()
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained.first?.results.first?.id, "fixture.recent")
        XCTAssertEqual(try Data(contentsOf: f.settings), f.settingsBytes)
    }
}

@MainActor
private final class HistoryMaintenanceValidationRaceInjector {
    weak var services: AppExecutionServices?
    private let lock: HistoryOwnedAdvisoryLock
    private let lockPath: URL
    private let history: URL
    private let originalHistory: Data
    private let onInjected: () -> Void
    private(set) var boundaries = 0
    private(set) var save: Task<SettingsIntentOutcome, Never>?
    init(lock: HistoryOwnedAdvisoryLock, lockPath: URL, history: URL,
         originalHistory: Data, onInjected: @escaping () -> Void) {
        self.lock = lock; self.lockPath = lockPath; self.history = history
        self.originalHistory = originalHistory; self.onInjected = onInjected
    }
    func observe(revision: UInt64) {
        guard revision == 1, let services else { return }
        boundaries += 1
        if boundaries == 1 {
            XCTAssertTrue(lock.acquire(lockPath))
            let admission = services.configStore.setGlobalPreference(
                .init(rawValue: "scan.uiBatchesPerSecond"), to: .integer(3))
            guard case .accepted(_, let task) = admission else {
                XCTFail("Real B was not admitted inside validation"); return
            }
            save = task
            XCTAssertTrue(services.policyBridge.storageUpdatePending)
            XCTAssertEqual(try? Data(contentsOf: history), originalHistory)
            onInjected()
        } else {
            XCTAssertFalse(services.policyBridge.storageUpdatePending)
            lock.releaseAtReadBoundary()
        }
    }
}

@MainActor
private final class HistoryValidationChurnInjector {
    weak var services: AppExecutionServices?
    private let maximumEdits: Int
    private(set) var saves: [Task<SettingsIntentOutcome, Never>] = []
    init(maximumEdits: Int) { self.maximumEdits = maximumEdits }
    func issue(revision: UInt64) {
        guard revision >= 7, let services, saves.count < maximumEdits else { return }
        let id = SettingID(rawValue: "scan.uiBatchesPerSecond")
        let current = services.configStore.preferences.global.fields[id]
        let next: SettingValue = current == .integer(3) ? .integer(1) : .integer(3)
        guard case .accepted(_, let task) = services.configStore.setGlobalPreference(id, to: next) else {
            XCTFail("Real churn edit was not admitted"); return
        }
        saves.append(task)
    }
}

@MainActor
private final class HistoryValidationSaveInjector {
    weak var services: AppExecutionServices?
    private(set) var didInject = false
    private(set) var save: Task<SettingsIntentOutcome, Never>?
    private let onInjected: () -> Void
    init(onInjected: @escaping () -> Void) { self.onInjected = onInjected }
    func issueOnce(revision: UInt64) {
        guard revision == 7, !didInject, let services else { return }
        didInject = true
        let admission = services.configStore.setGlobalPreference(
            .init(rawValue: "scan.uiBatchesPerSecond"), to: .integer(3))
        guard case .accepted(_, let task) = admission else {
            XCTFail("Real validation-gap presentation edit was rejected"); return
        }
        save = task
        onInjected()
    }
}

/// An actual advisory lock on one newly-created scratch settings lock file.
/// The read-boundary observation releases only this FD; no policy is supplied.
private final class HistoryOwnedAdvisoryLock: @unchecked Sendable {
    private let state = NSLock()
    private var fd: Int32 = -1
    private var acquired = false
    private var releasedAtBoundary = false
    private var timedOut = false
    private var watchdog: DispatchWorkItem?
    var wasAcquired: Bool { state.lock(); defer { state.unlock() }; return acquired }
    var wasReleasedAtReadBoundary: Bool { state.lock(); defer { state.unlock() }; return releasedAtBoundary }
    var watchdogFired: Bool { state.lock(); defer { state.unlock() }; return timedOut }
    func acquire(_ path: URL) -> Bool {
        state.lock(); defer { state.unlock() }
        guard fd == -1, !acquired else { return false }
        let opened = Darwin.open(path.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard opened >= 0 else { return false }
        var value = stat()
        guard fstat(opened, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              value.st_uid == geteuid(), value.st_mode & 0o777 == 0o600,
              value.st_nlink == 1, flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(opened); return false
        }
        fd = opened; acquired = true
        let work = DispatchWorkItem { [weak self] in self?.release(timedOut: true) }
        watchdog = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: work)
        return true
    }
    func releaseAtReadBoundary() {
        state.lock(); releasedAtBoundary = fd >= 0 || releasedAtBoundary; state.unlock()
        release()
    }
    func release(timedOut: Bool = false) {
        state.lock(); defer { state.unlock() }
        guard fd >= 0 else { return }
        self.timedOut = self.timedOut || timedOut
        watchdog?.cancel(); watchdog = nil
        _ = flock(fd, LOCK_UN); Darwin.close(fd); fd = -1
    }
    deinit { release() }
}

/// Only the owned scratch SettingsStore uses this real-I/O wrapper. It holds
/// each exact candidate revision once and always releases after a finite wait.
private final class HistorySaveQueueIO: JournalPOSIXIO, @unchecked Sendable {
    private let real = DarwinJournalIO()
    private let condition = NSCondition()
    private var entered: Set<UInt64> = []
    private var released: Set<UInt64> = []
    private var timeout = false
    private let revisions: Set<UInt64>
    init(revisions: Set<UInt64> = [1, 2]) {
        precondition(!revisions.isEmpty && revisions.count <= 2)
        self.revisions = revisions
    }
    var watchdogFired: Bool {
        condition.lock(); defer { condition.unlock() }; return timeout
    }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        if offset == 0, let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           object["config"] != nil, let number = object["revision"] as? NSNumber {
            let revision = number.uint64Value
            if revisions.contains(revision) { hold(revision) }
        }
        return try real.write(fd: fd, bytes: bytes, offset: offset)
    }
    private func hold(_ revision: UInt64) {
        condition.lock(); defer { condition.unlock() }
        guard entered.insert(revision).inserted else { return }
        condition.broadcast()
        let deadline = Date().addingTimeInterval(5)
        while !released.contains(revision) {
            if !condition.wait(until: deadline) { timeout = true; released.insert(revision); break }
        }
    }
    private func hasEntered(_ revision: UInt64) -> Bool {
        condition.lock(); defer { condition.unlock() }
        return entered.contains(revision)
    }
    func waitUntilHeld(revision: UInt64) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if hasEntered(revision) { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        releaseAll(); throw POSIXError(.ETIMEDOUT)
    }
    func release(revision: UInt64) {
        condition.lock(); released.insert(revision); condition.broadcast(); condition.unlock()
    }
    func releaseAll() {
        condition.lock(); released.formUnion(revisions); condition.broadcast(); condition.unlock()
    }
    func syncFile(fd: Int32) throws { try real.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try real.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws { try real.syncDirectory(fd: fd) }
}

private struct HistoryUpgradeFixture {
    enum Settings: Equatable { case legacy, absent, malformed, durable }
    let root: URL
    let support: URL
    let settings: URL
    let history: URL
    let historyBytes: Data
    let settingsBytes: Data?
    let recentReport: RunReport
    var paths: AppStoragePaths {
        .init(home: root, settings: settings, journal: support.appendingPathComponent("execution"))
    }
    static func make(settings kind: Settings) throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp/Tidy-HistoryUpgrade-\(UUID().uuidString)")
        let support = root.appendingPathComponent("support")
        for directory in [root, support] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        let settings = support.appendingPathComponent("config.json")
        let settingsBytes: Data?
        switch kind {
        case .legacy:
            settingsBytes = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "hasCompletedOnboarding": true,
                "keepCookieDomains": ["fixture.invalid"], "simulatorsApprovedForDeletion": [],
                "gitRoots": [], "staleNodeModulesThresholdDays": 60,
                "transcriptAgeThresholdDays": 45, "presets": []], options: [.sortedKeys])
        case .absent: settingsBytes = nil
        case .malformed: settingsBytes = Data("not a settings document".utf8)
        case .durable:
            settingsBytes = try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2,
                revision: 7, config: TidyConfig(schemaVersion: 2)))
        }
        if let settingsBytes {
            try settingsBytes.write(to: settings)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        }
        let now = Date()
        func oldFormatLine(_ id: String, finished: Date) throws -> Data {
            let value: [String: Any] = ["tier": "safe",
                "results": [["id": id, "title": "Owned synthetic history", "freedBytes": 0, "succeeded": true]],
                "startedAt": finished.timeIntervalSinceReferenceDate - 1,
                "finishedAt": finished.timeIntervalSinceReferenceDate,
                "freeSpaceBeforeBytes": 1, "freeSpaceAfterBytes": 1]
            var line = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            line.append(0x0A); return line
        }
        var bytes = try oldFormatLine("fixture.old", finished: now.addingTimeInterval(-45 * 86400))
        bytes.append(try oldFormatLine("fixture.recent", finished: now))
        let history = support.appendingPathComponent("runs.jsonl")
        try bytes.write(to: history)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: history.path)
        let report = RunReport(tier: .safe, results: [.init(id: "fixture.recorded", title: "Synthetic completion",
            freedBytes: 0, succeeded: true)], startedAt: now, finishedAt: now,
            freeSpaceBeforeBytes: 1, freeSpaceAfterBytes: 1)
        return Self(root: root, support: support, settings: settings, history: history,
            historyBytes: bytes, settingsBytes: settingsBytes, recentReport: report)
    }
    func readHistory() throws -> [RunReport] {
        try Data(contentsOf: history).split(separator: 0x0A).map { try JSONDecoder().decode(RunReport.self, from: Data($0)) }
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
