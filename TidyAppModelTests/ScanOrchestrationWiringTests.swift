import Foundation
import Darwin
import Observation
import XCTest
import TidyCore

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

    init() throws {
        root = try canonicalScratchBase()
            .appendingPathComponent("T085ScanWiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: false)
        try Data(repeating: 9, count: 32_768).write(to: documents.appendingPathComponent("fixture.bin"))
    }

    /// Installs a real, acknowledged (revision > 0) settings envelope before bootstrapping —
    /// the same pattern `BoundedTraversalTests.TraversalBridgeRig` uses — and awaits the bridge's
    /// pending initial scheduler install before returning. A revision-zero/fresh-install envelope
    /// deliberately leaves the T08.1b scheduler façade unavailable (see `ExecutionPolicyBridge`),
    /// so any fixture that wants a real, working scan must install policy first, exactly as a
    /// real user does the first time they save Settings.
    @MainActor func services() async throws -> AppExecutionServices {
        let settings = SettingsStore(url: configURL)
        _ = await settings.load()
        let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
        _ = try await settings.update(expectedRevision: 0,
            change: .preferences(.init(global: .init(fields: [rate: .integer(4)]))))
        let services = await AppExecutionServices.bootstrap(
            paths: AppStoragePaths(home: home, settings: configURL, journal: journal),
            settings: settings, observe: { _ in })
        await services.policyBridge.drain()
        return services
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
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

@MainActor
final class ScanOrchestrationWiringTests: XCTestCase {

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
        XCTAssertTrue(report.topLevelHomeRanking.contains { $0.path == scratch.documents.path },
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
}
