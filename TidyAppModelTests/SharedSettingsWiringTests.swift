import Foundation
import Darwin
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
    enum Fault { case none, configReplace, configDirectorySync }
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
            try real.replace(directoryFD: fault == .configReplace ? -1 : directoryFD,
                temporary: temporary, destination: destination)
        } catch { record(error); throw error }
        lock.lock(); awaitingConfigSync = true; lock.unlock()
        probe.hit("config.done.\(number)")
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock(); let fail = awaitingConfigSync && fault == .configDirectorySync
        awaitingConfigSync = false; lock.unlock()
        probe.hit("syncDirectory")
        do { try real.syncDirectory(fd: fail ? -1 : fd) }
        catch { record(error); throw error }
    }
}

@MainActor
final class SharedSettingsWiringTests: XCTestCase {
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

    func testPresentationSuccessCannotHealAcceptedInvalidatingConflict() async throws {
        try await run { _, services, _ in
            let bridge = services.policyBridge
            let review = try await self.noOpReview(services)
            let invalidatingID = SettingID(rawValue: "cleanup.requestedBatchGiB")
            let conflicting = GlobalPreferenceDelta(baseRevision: 0, id: invalidatingID,
                baseValue: .integer(99), editedValue: .integer(12))
            guard case .accepted(_, let invalidatingCompletion) = bridge.submit(global: conflicting) else {
                return XCTFail("Valid-shape conflicting invalidating edit was not admitted")
            }
            _ = await invalidatingCompletion.value
            XCTAssertFalse(bridge.isExecutionEnabled)
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            let blockingMessage = try XCTUnwrap(bridge.persistenceError)
            do {
                _ = try await services.coordinator.confirm(binding: review.binding)
                XCTFail("Old confirmation survived invalidating conflict")
            } catch let error as ConfirmationError {
                XCTAssertEqual(error, .stalePolicy)
            }

            let units = SettingID(rawValue: "ui.units")
            let presentation = GlobalPreferenceDelta(baseRevision: 0, id: units,
                baseValue: nil, editedValue: .choice("decimal"))
            guard case .accepted(_, let presentationCompletion) = bridge.submit(global: presentation) else {
                return XCTFail("Presentation edit was not admitted")
            }
            guard case .saved = await presentationCompletion.value else {
                return XCTFail("Presentation edit did not persist")
            }
            XCTAssertFalse(bridge.isExecutionEnabled)
            XCTAssertEqual(bridge.persistenceError, blockingMessage)
            XCTAssertEqual(services.coordinator.policyAdmission(), .updating(revision: 2))
            let saved = await services.settings.load()
            XCTAssertEqual(saved.envelope?.preferences?.global.fields[units], .choice("decimal"))
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

    func testUnavailableProductionPathStateCreatesNoServices() {
        let state = AppBootstrapState()
        state.storagePathUnavailable()
        XCTAssertEqual(state.status, .unavailable)
        XCTAssertNil(state.services)
    }
}
