import Foundation
import XCTest
@testable import TidyCore

@MainActor
final class QueuedLegacyGlobalPreferenceTests: XCTestCase {
    func testQueuedGlobalEditUsesProjectedLegacyBaseAfterSchemaOneMigration() async throws {
        try await exerciseQueuedEdit(schemaOne: true, typedPreferences: false)
    }

    func testQueuedGlobalEditUsesProjectedLegacyBaseWithSchemaTwoNilPreferences() async throws {
        try await exerciseQueuedEdit(schemaOne: false, typedPreferences: false)
    }

    func testQueuedGlobalEditKeepsExistingTypedDocument() async throws {
        try await exerciseQueuedEdit(schemaOne: false, typedPreferences: true)
    }

    private func exerciseQueuedEdit(schemaOne: Bool, typedPreferences: Bool) async throws {
        let root = URL(fileURLWithPath: "/private/tmp/TidyQueuedLegacyGlobal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json")
        var legacy = TidyConfig(schemaVersion: schemaOne ? 1 : 2)
        legacy.keepCookieDomains = ["fixture.invalid"]
        legacy.transcriptAgeThresholdDays = 120
        legacy.staleNodeModulesThresholdDays = 90
        var typed = PolicyPreferences.project(legacy: legacy, saved: nil)
        typed.global.fields[.init(rawValue: "ui.units")] = .choice("decimal")
        let seeded: Data
        if schemaOne { seeded = try JSONEncoder().encode(legacy) }
        else {
            seeded = try JSONEncoder().encode(SettingsEnvelope(schemaVersion: 2, revision: 7,
                config: legacy, preferences: typedPreferences ? typed : nil))
        }
        try seeded.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let settings = SettingsStore(url: file)
        let loaded = await settings.load()
        let envelope = try XCTUnwrap(loaded.envelope)
        let coordinator = ExecutionCoordinator(environment: .init(homeDirectory: root.path),
            journalDirectory: root.appendingPathComponent("execution"))
        let gate = FirstQueuedGlobalSaveGate()
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings, loaded: loaded,
            homeDirectory: root.path, detectedTools: [], pendingByteLimit: 32 * 1_048_576,
            schedulerTestHook: nil, testHook: gate)
        await bridge.drain()
        let model = AppConfigStore(loaded: envelope, bridge: bridge)
        let history = SettingID(rawValue: "feature.history")
        let transcript = SettingID(rawValue: "cleanup.transcriptDays")
        do {
            guard case .accepted(_, let first) = model.setGlobalPreference(history, to: .bool(true)) else {
                await gate.release()
        await bridge.drain()
        return XCTFail("First unrelated global edit was rejected")
            }
            try await gate.waitUntilEntered()
            XCTAssertTrue(model.hasPendingSettingsWrites)
            XCTAssertEqual(model.acknowledgedSettingsRevision, envelope.revision)
            XCTAssertEqual(model.config.transcriptAgeThresholdDays, 120)
            // The first save is definitely held before publication. The second
            // edit must use the projected 120 raw base visible in bridge prediction.
            let secondAdmission = model.setGlobalPreference(transcript, to: .integer(121))
            await gate.release()
            let firstOutcome = await first.value
            let timedOut = await gate.didTimeOut()
            XCTAssertFalse(timedOut, "The admission gate watchdog expired")
            guard case .saved = firstOutcome else {
                await bridge.drain()
                return XCTFail("The held first save did not complete")
            }
            guard case .accepted(_, let second) = secondAdmission else {
                await bridge.drain()
                return XCTFail("Optimistic replay supplied nil instead of the projected legacy base")
            }
            guard case .saved(_, let secondEnvelope) = await second.value else {
                await bridge.drain()
                return XCTFail("The queued edit was not durably saved")
            }
            await bridge.drain()
            XCTAssertFalse(model.hasPendingSettingsWrites)
            XCTAssertEqual(model.config.transcriptAgeThresholdDays, 121)
            XCTAssertEqual(model.config.keepCookieDomains, ["fixture.invalid"])
            XCTAssertEqual(model.config.staleNodeModulesThresholdDays, 90)
            XCTAssertEqual(model.acknowledgedSettingsRevision, envelope.revision + 2)
            var expected = typedPreferences ? typed : PolicyPreferences.project(legacy: envelope.config, saved: nil)
            expected.global.fields[history] = .bool(true)
            expected.global.fields[transcript] = .integer(121)
            XCTAssertEqual(secondEnvelope.preferences, expected)
            XCTAssertEqual(bridge.acknowledgedEnvelope, secondEnvelope)
            let reopened = await SettingsStore(url: file).load()
            XCTAssertEqual(reopened.disposition, .loaded)
            XCTAssertEqual(reopened.envelope, secondEnvelope)
        } catch {
            await gate.release()
            await bridge.drain()
            let timedOut = await gate.didTimeOut()
            XCTAssertFalse(timedOut, "The admission gate watchdog expired")
            throw error
        }
    }
}

private actor FirstQueuedGlobalSaveGate: ExecutionPolicyBridgeTestHook {
    private enum GateError: Error { case timedOut }
    private var entered = false
    private var released = false
    private var timedOut = false
    private var entryWaiter: CheckedContinuation<Void, Error>?
    private var blockedSave: CheckedContinuation<Void, Never>?
    private var entryWatchdog: Task<Void, Never>?
    private var holdWatchdog: Task<Void, Never>?

    func receive(_ event: ExecutionPolicyBridgeTestPoint) async {
        switch event {
        case .acceptedAfterBarrierBeforePrepareAndSave, .acceptedAfterPresentationPrepareBeforeSave:
            guard !entered else { return }
            entered = true
            entryWatchdog?.cancel(); entryWatchdog = nil
            entryWaiter?.resume(); entryWaiter = nil
            guard !released else { return }
            holdWatchdog = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                await self?.expire()
            }
            await withCheckedContinuation { blockedSave = $0 }
        default: break
        }
    }
    func waitUntilEntered() async throws {
        if timedOut { throw GateError.timedOut }
        if entered { return }
        entryWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            await self?.expire()
        }
        try await withCheckedThrowingContinuation { entryWaiter = $0 }
    }
    private func expire() {
        timedOut = true
        entryWaiter?.resume(throwing: GateError.timedOut); entryWaiter = nil
        release()
    }
    func release() {
        released = true
        entryWatchdog?.cancel(); entryWatchdog = nil
        holdWatchdog?.cancel(); holdWatchdog = nil
        blockedSave?.resume(); blockedSave = nil
    }
    func didTimeOut() -> Bool { timedOut }
}
