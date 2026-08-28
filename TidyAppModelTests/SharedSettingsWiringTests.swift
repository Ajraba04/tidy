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
