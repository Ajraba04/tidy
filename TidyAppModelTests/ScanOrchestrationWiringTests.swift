import Foundation
import Darwin
import Observation
import XCTest
@testable import TidyCore

private actor ScanLifecycleGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private func canonicalScratchBase() throws -> URL {
    var path = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath("/private/tmp", &path) != nil else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return URL(fileURLWithPath: String(cString: path), isDirectory: true)
}

/// Real disposable fixtures, matching `ConfirmationLifecycleTests`'s `AppModelScratch` — no mocks
/// of `AppExecutionServices`/`ScanViewModel`.
private struct ScanWiringScratch {
    let root: URL
    var home: URL { root.appendingPathComponent("home", isDirectory: true) }
    var configURL: URL { root.appendingPathComponent("config.json") }
    var journal: URL { root.appendingPathComponent("journal", isDirectory: true) }
    var documents: URL { home.appendingPathComponent("Documents", isDirectory: true) }
    var cache: URL { home.appendingPathComponent("Library/Caches/typescript", isDirectory: true) }

    init() throws {
        root = try canonicalScratchBase()
            .appendingPathComponent("T085ScanWiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 32_768).write(to: documents.appendingPathComponent("fixture.bin"))
        try Data(repeating: 8, count: 16_384).write(to: cache.appendingPathComponent("cache.bin"))
    }

    /// Installs a real, acknowledged (revision > 0) settings envelope before bootstrapping —
    /// the same pattern `BoundedTraversalTests.TraversalBridgeRig` uses — and awaits the bridge's
    /// pending initial scheduler install before returning. A revision-zero/fresh-install envelope
    /// deliberately leaves the T08.1b scheduler façade unavailable (see `ExecutionPolicyBridge`),
    /// so any fixture that wants a real, working scan must install policy first, exactly as a
    /// real user does the first time they save Settings.
    @MainActor func services(defaultScope: String = "quick", cacheEnabled: Bool = false,
      forceContinuablePartial: Bool = false,
      scanLifecycleHook: (@Sendable (AppScanLifecycleEvent) async -> Void)? = nil)
      async throws -> AppExecutionServices {
        let settings = SettingsStore(url: configURL)
        _ = await settings.load()
        let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
        let scope = SettingID(rawValue: "scan.defaultScope")
        let cache = SettingID(rawValue: "scan.cacheEnabled")
        _ = try await settings.update(expectedRevision: 0,
            change: .preferences(.init(global: .init(fields: [
                rate: .integer(4), scope: .choice(defaultScope), cache: .bool(cacheEnabled)
            ]))))
        let services = await AppExecutionServices.bootstrap(
            paths: AppStoragePaths(home: home, settings: configURL, journal: journal),
            settings: settings, observe: { _ in }, scanLifecycleHook: scanLifecycleHook,
            scanTraversalLimits: forceContinuablePartial
                ? try TraversalLimits(batchEntries: 1).withTestingBatchLimitPerSlice(2) : nil)
        await services.policyBridge.drain()
        return services
    }

    @MainActor func freshDefaultServices() async -> AppExecutionServices {
        let settings = SettingsStore(url: configURL)
        return await AppExecutionServices.bootstrap(
            paths: AppStoragePaths(home: home, settings: configURL, journal: journal),
            settings: settings, observe: { _ in })
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func populateWideFixture(directoryCount: Int = 500, filesPerDirectory: Int = 200) throws {
        for directoryIndex in 0..<directoryCount {
            let directory = cache.appendingPathComponent("bucket-\(directoryIndex)",
                isDirectory: true)
            try FileManager.default.createDirectory(at: directory,
                withIntermediateDirectories: false)
            for fileIndex in 0..<filesPerDirectory {
                let path = directory.appendingPathComponent("entry-\(fileIndex)").path
                let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
                guard descriptor >= 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                guard close(descriptor) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
            }
        }
    }

    func allocatedFixtureBytes() throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in false }) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            let (bytes, overflow) = Int64(info.st_blocks).multipliedReportingOverflow(by: 512)
            let (next, totalOverflow) = total.addingReportingOverflow(bytes)
            guard !overflow, !totalOverflow else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EOVERFLOW))
            }
            total = next
        }
        return total
    }

}

private func waitUntil(timeoutSeconds: TimeInterval = 4.0,
                       _ condition: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while true {
        if await condition() { return }
        if Date() > deadline { return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

private func freeBytes(at path: String) throws -> UInt64 {
    var info = statfs()
    guard statfs(path, &info) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return UInt64(info.f_bavail) * UInt64(info.f_bsize)
}

@MainActor
private func runAppScanToCompletion(services: AppExecutionServices,
                                    environment: CleanEnvironment) async throws -> CoreScanResult {
    var handle = try await services.beginScan(environment: environment, ownerID: UUID())
    while true {
        try await waitUntil(timeoutSeconds: 600) {
            (try? await services.scanRegistry.state(sessionID: handle.sessionID))?.terminal != nil
        }
        guard let state = try? await services.scanRegistry.state(sessionID: handle.sessionID),
              state.terminal != nil,
              let result = await handle.latestResult() else {
            throw NSError(domain: "TidyR07ScanFixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "scan did not reach a retained terminal result"])
        }
        if result.continuationAvailable {
            handle = try await services.continueActiveScan()
        } else {
            return result
        }
    }
}

@MainActor
final class ScanOrchestrationWiringTests: XCTestCase {

    func testFreshInstallExplicitScanUsesDefaultsWithoutWritingSettingsOrStartingBackgroundWork()
      async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = await scratch.freshDefaultServices()
        XCTAssertEqual(services.settingsLoad.disposition, .newDefaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.configURL.path))
        let beforeRegistry = await services.scanRegistry.snapshot()
        let beforeLeaseCount = await services.systemMonitor.activeExplicitWorkLeaseCountForTesting()
        let beforeTimer = await services.systemMonitor.isTimerRunningForTesting()
        let beforeIndexWatch = await services.activeScanIndexWatchIsActiveForTesting()
        XCTAssertEqual(beforeRegistry.sessions, 0)
        XCTAssertEqual(beforeRegistry.activeWork, 0)
        XCTAssertEqual(beforeLeaseCount, 0)
        XCTAssertFalse(beforeTimer)
        XCTAssertFalse(beforeIndexWatch)

        let model = ScanViewModel(services: services)
        await model.runScan()
        try await waitUntil { if case .complete = model.phase { return true }; return false }

        guard case .complete(let report) = model.phase else {
            return XCTFail("Fresh defaults did not admit the explicit scan: \(model.phase)")
        }
        XCTAssertTrue(report.topLevelHomeRanking.contains { $0.path == scratch.cache.path })
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.configURL.path),
            "Read-only scan admission must not persist defaults as a side effect")
        try await waitUntil { services.activeScanSessionID == nil }
        let afterLeaseCount = await services.systemMonitor.activeExplicitWorkLeaseCountForTesting()
        let afterTimer = await services.systemMonitor.isTimerRunningForTesting()
        XCTAssertEqual(afterLeaseCount, 0)
        XCTAssertFalse(afterTimer)
        await services.disposeScanResourcesForTesting()
    }

    func testMissingLiveSignalCannotReopenNominalSchedulerAdmission() {
        let partial = SystemSnapshot(observedAt: Date(), bootIdentity: nil, volumes: [],
            memory: nil, memoryUnavailableReason: "missing", swap: nil,
            swapUnavailableReason: nil, pageOutRatePerSecond: nil,
            memoryPressureLevel: nil, thermalState: .nominal,
            isLowPowerModeEnabled: false)
        XCTAssertEqual(schedulerLiveObservation(from: partial), .unknown)
        let critical = SystemSnapshot(observedAt: Date(), bootIdentity: nil, volumes: [],
            memory: nil, memoryUnavailableReason: nil, swap: nil,
            swapUnavailableReason: nil, pageOutRatePerSecond: nil,
            memoryPressureLevel: .critical, thermalState: nil,
            isLowPowerModeEnabled: nil)
        XCTAssertEqual(schedulerLiveObservation(from: critical), .critical)
    }

    func testSimultaneousWindowsShareTheReservedStart() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let gate = ScanLifecycleGate()
        let services = try await scratch.services(scanLifecycleHook: { event in
            if event == .startReserved { await gate.pause() }
        })
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        let first = Task { @MainActor in
            try await services.beginScan(environment: environment, ownerID: UUID())
        }
        await gate.waitUntilEntered()
        let second = Task { @MainActor in
            try await services.beginScan(environment: environment, ownerID: UUID())
        }
        await Task.yield()
        await gate.release()

        let firstHandle = try await first.value
        let secondHandle = try await second.value
        XCTAssertEqual(firstHandle.sessionID, secondHandle.sessionID)
        XCTAssertEqual(firstHandle.generation, secondHandle.generation)
        let snapshot = await services.scanRegistry.snapshot()
        XCTAssertEqual(snapshot.sessions, 1,
            "overlapping windows must not create a second registry generation")
    }

    func testReplacementStartWaitsForDetachedOldCleanupThenCompletes() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let cleanupGate = ScanLifecycleGate()
        let services = try await scratch.services(cacheEnabled: true,
            scanLifecycleHook: { event in
                if case .cleanupDetached = event { await cleanupGate.pause() }
            })
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        let first = try await services.beginScan(environment: environment, ownerID: UUID())
        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: first.sessionID))?.terminal != nil
        }
        await cleanupGate.waitUntilEntered()

        let replacementTask = Task { @MainActor in
            try await services.beginScan(environment: environment, ownerID: UUID())
        }
        await Task.yield()
        let whileCleanupPaused = await services.scanRegistry.snapshot()
        XCTAssertEqual(whileCleanupPaused.sessions, 1,
            "replacement start must wait for the retained teardown barrier")
        await cleanupGate.release()
        let replacement = try await replacementTask.value
        XCTAssertNotEqual(first.sessionID, replacement.sessionID)
        XCTAssertEqual(services.activeScanSessionID, replacement.sessionID)

        try await waitUntil(timeoutSeconds: 20) {
            (try? await services.scanRegistry.state(sessionID: replacement.sessionID))?.terminal != nil
        }
        let state = try await services.scanRegistry.state(sessionID: replacement.sessionID)
        let result = await replacement.latestResult()
        let scheduler = await services.explicitSessions.snapshot()
        let registry = await services.scanRegistry.snapshot()
        XCTAssertEqual(state.terminal, .complete,
            "scheduler=\(scheduler) registry=\(registry) result=\(String(describing: result))")
        XCTAssertEqual(result?.coverage.isComplete, true,
            "scheduler=\(scheduler) registry=\(registry)")
        await services.disposeScanResourcesForTesting()
    }

    // 1. `runScan()` never calls the legacy `ScanEngine.run(environment:)` no-op path — that path
    // always returns empty ranking arrays, so a non-empty result here can only have come from the
    // explicit `ScanEngine.start` orchestration route this view model now calls.
    func testRunScanUsesExplicitSessionNotLegacyRun() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        let model = ScanViewModel(services: services)
        await model.runScan()
        try await waitUntil { if case .complete = model.phase { return true }; return false }
        guard case .complete(let report) = model.phase else {
            XCTFail("Expected a completed scan, got \(model.phase)"); return
        }
        XCTAssertTrue(report.topLevelHomeRanking.contains { $0.path == scratch.cache.path },
            "The legacy no-op path cannot ever produce a non-empty ranking.")
    }

    // 2. Two windows sharing the same `AppExecutionServices` and session converge on identical
    // terminal state, with only one walk performed.
    func testTwoWindowsShareOneSessionAndConvergeOnIdenticalTerminalState() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        let first = ScanViewModel(services: services)
        await first.runScan()
        guard services.activeScanSessionID != nil else {
            XCTFail("Expected an active scan session after runScan()"); return
        }
        let second = ScanViewModel(services: services)
        second.attachToActiveScanIfNeeded()

        try await waitUntil {
            if case .complete = first.phase, case .complete = second.phase { return true }
            return false
        }
        guard case .complete(let firstReport) = first.phase,
              case .complete(let secondReport) = second.phase else {
            XCTFail("Expected both windows to converge on completion"); return
        }
        XCTAssertEqual(firstReport.topLevelHomeRanking.map(\.path),
                       secondReport.topLevelHomeRanking.map(\.path))
        XCTAssertEqual(firstReport.topLevelHomeRanking.map(\.bytes),
                       secondReport.topLevelHomeRanking.map(\.bytes))
    }

    // 3. Closing/deinit-ing one window's view model while another subscriber remains live leaves
    // the session alive and the second subscriber still receives the terminal event.
    func testWindowCloseDetachesSubscriptionOnlySessionSurvives() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        var first: ScanViewModel? = ScanViewModel(services: services)
        await first!.runScan()
        guard let sessionID = services.activeScanSessionID else {
            XCTFail("Expected an active scan session"); return
        }
        let second = ScanViewModel(services: services)
        second.attachToActiveScanIfNeeded()

        // Simulate the first window closing: detach only, never cancel.
        first!.detachSubscription()
        first = nil

        try await waitUntil { if case .complete = second.phase { return true }; return false }
        guard case .complete = second.phase else {
            XCTFail("Expected the surviving subscriber to still receive the terminal event"); return
        }
        let state = try await services.scanRegistry.state(sessionID: sessionID)
        XCTAssertEqual(state.terminal, .complete, "Closing one window must never cancel the session.")
    }

    // 4. The menu-bar/global Cancel affordance targets the active session by ID and remains
    // reachable after the window that started the scan has closed.
    func testMenuBarCancelTargetsActiveSessionAfterWindowCloses() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        var model: ScanViewModel? = ScanViewModel(services: services)
        await model!.runScan()
        guard let sessionID = services.activeScanSessionID else {
            XCTFail("Expected an active scan session"); return
        }

        // Simulate the window closing before cancellation is requested.
        model!.detachSubscription()
        model = nil

        // This is exactly the call the menu-bar/global owner makes; it needs no window.
        await services.cancelActiveScan()

        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: sessionID))?.terminal != nil
        }
        let state = try await services.scanRegistry.state(sessionID: sessionID)
        XCTAssertEqual(state.terminal, .cancelled)
    }

    // 5. Rescanning after a terminal state creates a new session/generation; the old session's
    // subscription is already torn down by the time the new one starts, so a late event tagged
    // with the superseded session cannot reach the current view model.
    func testRescanAfterTerminalCreatesNewGenerationAndIgnoresStaleEvents() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        let model = ScanViewModel(services: services)

        await model.runScan()
        guard let firstSessionID = services.activeScanSessionID else {
            XCTFail("Expected an active scan session"); return
        }
        try await waitUntil { if case .complete = model.phase { return true }; return false }
        guard case .complete = model.phase else { XCTFail("Expected first scan to complete"); return }

        await model.runScan()
        guard let secondSessionID = services.activeScanSessionID else {
            XCTFail("Expected a new active scan session on rescan"); return
        }
        XCTAssertNotEqual(firstSessionID, secondSessionID, "Rescan must open a new session, not reuse the old one.")

        try await waitUntil { if case .complete = model.phase { return true }; return false }
        guard case .complete = model.phase else { XCTFail("Expected rescan to complete"); return }

        // The superseded session reached its own, independent, unaffected terminal state.
        let firstState = try await services.scanRegistry.state(sessionID: firstSessionID)
        XCTAssertEqual(firstState.terminal, .complete)
        let secondState = try await services.scanRegistry.state(sessionID: secondSessionID)
        XCTAssertEqual(secondState.terminal, .complete)
    }

    // 6. Bootstrap, reading Settings-surfaced state, and constructing a view model perform no
    // scan/session/process work until an explicit Run.
    func testBootstrapAndSettingsOpenLaunchNoScanOrProcess() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        let model = ScanViewModel(services: services)
        _ = services.configStore.config
        _ = services.persistenceError
        _ = services.isExecutionEnabled
        model.attachToActiveScanIfNeeded() // no-op: nothing is active yet

        try await Task.sleep(nanoseconds: 50_000_000)
        let snapshot = await services.scanRegistry.snapshot()
        XCTAssertEqual(snapshot.sessions, 0)
        XCTAssertEqual(snapshot.activeWork, 0)
        XCTAssertNil(services.activeScanSessionID)
        guard case .idle = model.phase else {
            XCTFail("Expected idle phase before any explicit Run, got \(model.phase)"); return
        }
    }

    // 7. Partial, cancelled, and complete are distinct, exhaustively-handled `Phase` cases (no
    // default arm exists in `ScanViewModel.apply`, so every `ScanSessionTerminal`/progress case
    // maps to its own accessible state by construction). `.paused` requires a critical-observation
    // fixture and `.partial` a slice-expiry fixture; both are only reachable through TidyCore's
    // internal test hooks (see `CoreOrchestrationTests`), which this app-model target cannot reach
    // through the public `TidyCore` surface — they are exercised at that layer instead.
    func testCancelledAndCompleteAreDistinctAccessibleStates() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()

        let cancelModel = ScanViewModel(services: services)
        await cancelModel.runScan()
        await cancelModel.cancelScan()
        try await waitUntil {
            switch cancelModel.phase {
            case .cancelled, .complete: return true
            default: return false
            }
        }
        switch cancelModel.phase {
        case .cancelled, .complete: break
        default: XCTFail("Expected a terminal phase after cancel, got \(cancelModel.phase)")
        }

        let completeModel = ScanViewModel(services: services)
        await completeModel.runScan()
        try await waitUntil { if case .complete = completeModel.phase { return true }; return false }
        guard case .complete = completeModel.phase else {
            XCTFail("Expected an uninterrupted scan to complete"); return
        }
    }

    // 8. Twenty attach/detach/cancel cycles through the app-model layer restore the registry's
    // active-work and live-subscriber baseline (mirrors T08.1a's 20-cycle gate at this layer).
    func test20AttachDetachCancelCyclesRestoreBaseline() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        let baseline = await services.scanRegistry.snapshot()

        for _ in 0..<20 {
            let model = ScanViewModel(services: services)
            await model.runScan()
            guard let sessionID = services.activeScanSessionID else {
                XCTFail("Expected an active session"); continue
            }
            model.detachSubscription()
            try? await services.scanRegistry.cancel(sessionID: sessionID)
            try await waitUntil {
                (try? await services.scanRegistry.state(sessionID: sessionID))?.terminal != nil
            }
        }

        let final = await services.scanRegistry.snapshot()
        XCTAssertEqual(final.activeWork, baseline.activeWork)
        XCTAssertEqual(final.liveSubscribers, baseline.liveSubscribers)
        XCTAssertEqual(final.bufferedEvents, baseline.bufferedEvents)
    }

    func testContinuableTerminalPartialReleasesIdleResourcesAndGapChangeFailsClosed()
      async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        try Data(repeating: 1, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("a-visited.bin"))
        try Data(repeating: 2, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("z-pending.bin"))
        let services = try await scratch.services(cacheEnabled: true,
            forceContinuablePartial: true)
        try await waitUntil { await services.systemMonitor.subscriberCountForTesting() >= 1 }
        let baselineSubscribers = await services.systemMonitor.subscriberCountForTesting()
        let model = ScanViewModel(services: services)
        await model.runScan()
        guard let sessionID = services.activeScanSessionID else {
            XCTFail("Expected active scan"); return
        }
        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: sessionID))?.terminal == .partial
        }
        guard let partial = await services.latestScanResult(sessionID: sessionID) else {
            XCTFail("Expected retained partial result"); return
        }
        XCTAssertTrue(partial.continuationAvailable)
        XCTAssertGreaterThanOrEqual(partial.metadataVisits, 2,
            "the fixture must retain totals from at least one visited child before idling")
        model.detachSubscription()

        try await waitUntil {
            let scheduler = await services.explicitSessions.snapshot()
            let registry = await services.scanRegistry.snapshot()
            let leaseCount = await services.systemMonitor.activeExplicitWorkLeaseCountForTesting()
            let subscribers = await services.systemMonitor.subscriberCountForTesting()
            let timerRunning = await services.systemMonitor.isTimerRunningForTesting()
            let watchActive = await services.activeScanIndexWatchIsActiveForTesting()
            return scheduler.active == 0 && scheduler.queued == 0
                && registry.activeWork == 0 && registry.liveSubscribers == 0
                && leaseCount == 0 && subscribers == baselineSubscribers
                && timerRunning == false && watchActive == false
        }

        // Change bytes that were already accumulated before the terminal partial. Continue must
        // either restart fresh or reject the dormant cursor; it may never publish the old total.
        try Data(repeating: 7, count: 32_768).write(
            to: scratch.cache.appendingPathComponent("a-visited.bin"))
        do {
            let resumed = try await services.continueActiveScan()
            try await waitUntil {
                (try? await services.scanRegistry.state(sessionID: resumed.sessionID))?.terminal != nil
            }
            let result = await resumed.latestResult()
            XCTAssertNotEqual(result?.coverage.isComplete, true,
                "changed already-visited bytes must not survive the unwatched gap as complete")
        } catch CoreOrchestrationError.invalidScopeAuthorization {
            // Expected fail-closed path when catch-up sees the gap mutation or cannot prove
            // device/history continuity.
        }

        try await waitUntil {
            let scheduler = await services.explicitSessions.snapshot()
            let leaseCount = await services.systemMonitor.activeExplicitWorkLeaseCountForTesting()
            let watchActive = await services.activeScanIndexWatchIsActiveForTesting()
            return scheduler.active == 0 && scheduler.queued == 0
                && scheduler.liveSessions == 0
                && leaseCount == 0 && watchActive == false
        }
        await services.disposeScanResourcesForTesting()
    }

    func testFirstIndexedPartialContinueWaitsForSuspensionAndUsesLiveDeviceCheckpoint()
      async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        try Data(repeating: 1, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("a-visited.bin"))
        try Data(repeating: 2, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("z-pending.bin"))
        let gate = ScanLifecycleGate()
        let services = try await scratch.services(cacheEnabled: true,
            forceContinuablePartial: true, scanLifecycleHook: { event in
                if event == .continuationSuspensionStarted { await gate.pause() }
            })
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        let first = try await services.beginScan(environment: environment, ownerID: UUID())
        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: first.sessionID))?.terminal == .partial
        }
        await gate.waitUntilEntered()
        let immediate = Task { @MainActor in try await services.continueActiveScan() }
        await Task.yield()
        let leaseCountWhilePaused = await services.systemMonitor
            .activeExplicitWorkLeaseCountForTesting()
        XCTAssertEqual(leaseCountWhilePaused, 1,
            "Continue must wait behind suspension instead of racing a second observation lease")
        await gate.release()
        let continued = try await immediate.value
        XCTAssertNotEqual(continued.sessionID, first.sessionID)
        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: continued.sessionID))?.terminal
                == .partial
        }
        await services.cancelActiveScan()
        let scheduler = await services.explicitSessions.snapshot()
        XCTAssertEqual(scheduler.active, 0)
        XCTAssertEqual(scheduler.queued, 0)
        XCTAssertEqual(scheduler.liveSessions, 0)
        let finalLeaseCount = await services.systemMonitor.activeExplicitWorkLeaseCountForTesting()
        let finalWatchActive = await services.activeScanIndexWatchIsActiveForTesting()
        XCTAssertEqual(finalLeaseCount, 0)
        XCTAssertFalse(finalWatchActive)
        await services.disposeScanResourcesForTesting()
    }

    func testSimultaneousContinueCallersShareOneReservedContinuationTransition() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        try Data(repeating: 1, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("a-visited.bin"))
        try Data(repeating: 2, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("z-pending.bin"))
        let gate = ScanLifecycleGate()
        let services = try await scratch.services(cacheEnabled: true,
            forceContinuablePartial: true, scanLifecycleHook: { event in
                if event == .continuationSuspensionStarted { await gate.pause() }
            })
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        let first = try await services.beginScan(environment: environment, ownerID: UUID())
        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: first.sessionID))?.terminal == .partial
        }
        await gate.waitUntilEntered()

        let firstContinue = Task { @MainActor in try await services.continueActiveScan() }
        let secondContinue = Task { @MainActor in try await services.continueActiveScan() }
        await Task.yield()
        await gate.release()
        let firstHandle = try await firstContinue.value
        let secondHandle = try await secondContinue.value
        XCTAssertEqual(firstHandle.sessionID, secondHandle.sessionID)
        XCTAssertEqual(firstHandle.generation, secondHandle.generation)
        let afterContinue = await services.scanRegistry.snapshot()
        XCTAssertEqual(afterContinue.sessions, 2,
            "one initial partial plus exactly one shared continuation session")
        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: firstHandle.sessionID))?.terminal
                == .partial
        }
        await services.cancelActiveScan()
        await services.disposeScanResourcesForTesting()
        let scheduler = await services.explicitSessions.snapshot()
        XCTAssertEqual(scheduler.active, 0)
        XCTAssertEqual(scheduler.queued, 0)
        XCTAssertEqual(scheduler.liveSessions, 0)
    }

    func testIndexDisabledTerminalPartialDoesNotAdvertiseContinueAndReleasesSession() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        try Data(repeating: 1, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("a-visited.bin"))
        try Data(repeating: 2, count: 4_096).write(
            to: scratch.cache.appendingPathComponent("z-pending.bin"))
        let services = try await scratch.services(cacheEnabled: false,
            forceContinuablePartial: true)
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        let first = try await services.beginScan(environment: environment, ownerID: UUID())
        try await waitUntil {
            (try? await services.scanRegistry.state(sessionID: first.sessionID))?.terminal == .partial
        }
        let latest = await first.latestResult()
        let result = try XCTUnwrap(latest)
        XCTAssertFalse(result.continuationAvailable)
        try await waitUntil { services.activeScanSessionID == nil }
        do {
            _ = try await services.continueActiveScan()
            XCTFail("Index-disabled partial must not expose a dormant continuation")
        } catch CoreOrchestrationError.invalidScopeAuthorization {
            // The UI-visible result already reported continuation unavailable.
        }
        let scheduler = await services.explicitSessions.snapshot()
        XCTAssertEqual(scheduler.active, 0)
        XCTAssertEqual(scheduler.queued, 0)
        XCTAssertEqual(scheduler.liveSessions, 0)
    }

    // 9. Wiring regression: the legacy no-op boundaries are never called by the rewired app. This
    // is the same guarantee `CoreOrchestrationTests.legacyCallsAreSafeNoOpBoundaries` proves at
    // the core layer; here it is proven by observation instead of by source inspection: a real
    // scan against a real fixture, run only through `ScanViewModel`/`AppExecutionServices`,
    // produces non-empty measured results, which `ScanEngine.run(environment:)` structurally
    // cannot produce.
    func testAppNeverProducesLegacyNoOpEmptyResults() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services()
        let model = ScanViewModel(services: services)
        await model.runScan()
        try await waitUntil { if case .complete = model.phase { return true }; return false }
        guard case .complete(let report) = model.phase else {
            XCTFail("Expected completion"); return
        }
        XCTAssertFalse(report.topLevelHomeRanking.isEmpty)
    }

    func testSelectedProjectsWithoutRootsDoesNotTraverseDocuments() async throws {
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        let services = try await scratch.services(defaultScope: "selectedProjects")
        let model = ScanViewModel(services: services)
        await model.runScan()
        try await waitUntil { if case .complete = model.phase { return true }; return false }
        guard case .complete(let report) = model.phase else {
            XCTFail("Expected empty selected-project scan to complete"); return
        }
        XCTAssertFalse(report.topLevelHomeRanking.contains {
            $0.path == scratch.documents.path || $0.path == scratch.cache.path
        })
    }

    func testRealFSEventsHundredThousandUnchangedScanMatchesFreshAndReducesMetadataVisits()
      async throws {
        XCTAssertEqual(ProcessInfo.processInfo.environment["TIDY_RUN_R07_100K"], "1",
            "The TidyAppModelTests scheme must run the bounded R07 acceptance fixture.")
        let fiveGiB = UInt64(5) * 1_024 * 1_024 * 1_024
        let freeBefore = try freeBytes(at: "/private/tmp")
        XCTAssertGreaterThan(freeBefore, fiveGiB,
            "The fixture must not start below the 5 GiB host safety floor.")
        let scratch = try ScanWiringScratch(); defer { scratch.remove() }
        try scratch.populateWideFixture()
        let allocatedBytes = try scratch.allocatedFixtureBytes()
        XCTAssertLessThanOrEqual(allocatedBytes, Int64(512) * 1_024 * 1_024)
        let freeAfterCreation = try freeBytes(at: "/private/tmp")
        XCTAssertGreaterThan(freeAfterCreation, fiveGiB,
            "The fixture must remain above the 5 GiB host safety floor.")

        let services = try await scratch.services(cacheEnabled: true)
        let environment = services.configStore.config.makePolicyEnvironment(
            homeDirectory: services.paths.home.path, detectedTools: [])
        var fresh = try await runAppScanToCompletion(services: services, environment: environment)
        XCTAssertTrue(fresh.coverage.isComplete)
        XCTAssertGreaterThanOrEqual(fresh.metadataVisits, 100_502)
        var unchanged: CoreScanResult?
        var freshPasses = 1
        // APFS may publish fixture-creation events after the first baseline watch begins. That
        // must conservatively force another full pass; once catch-up is quiet, the next unchanged
        // pass must reuse the committed aggregate. Bound the retry instead of masking live loss.
        for _ in 0..<3 {
            try await waitUntil(timeoutSeconds: 30) { services.activeScanSessionID == nil }
            XCTAssertNil(services.activeScanSessionID)
            let candidate = try await runAppScanToCompletion(
                services: services, environment: environment)
            XCTAssertTrue(candidate.coverage.isComplete)
            if candidate.metadataVisits * 5 <= fresh.metadataVisits,
               case .cached? = candidate.indexStatus {
                unchanged = candidate
                break
            }
            fresh = candidate
            freshPasses += 1
        }
        await services.disposeScanResourcesForTesting()
        let cachedResult = try XCTUnwrap(unchanged,
            "Real FSEvents catch-up never reached bounded unchanged cache reuse.")
        XCTAssertEqual(cachedResult.report.topLevelHomeRanking.map(\.path),
            fresh.report.topLevelHomeRanking.map(\.path))
        XCTAssertEqual(cachedResult.report.topLevelHomeRanking.map(\.bytes),
            fresh.report.topLevelHomeRanking.map(\.bytes))
        let reduction = 1.0 - (Double(cachedResult.metadataVisits) / Double(fresh.metadataVisits))
        XCTAssertGreaterThanOrEqual(reduction, 0.8)
        print("R07_REAL_FSEVENTS_100K fixtureDirectories=500 fixtureFiles=100000 "
            + "allocatedBytes=\(allocatedBytes) "
            + "freeBefore=\(freeBefore) freeAfterCreation=\(freeAfterCreation) "
            + "catchUpFreshRetries=\(freshPasses - 1) freshMetadataVisits=\(fresh.metadataVisits) "
            + "cachedMetadataVisits=\(cachedResult.metadataVisits) reduction=\(reduction) "
            + "freshComplete=\(fresh.coverage.isComplete) "
            + "unchangedComplete=\(cachedResult.coverage.isComplete) parity=true")
    }
}
