import Foundation
import XCTest
import TidyCore

/// `TidyUITests` does not exist yet in this project (no such Xcode target
/// is registered in `project.yml`/`project.pbxproj`), so these are
/// UI-*model*-level tests against `HeadroomViewModel` living in
/// `TidyAppModelTests` instead of a real XCUITest target, per the T10 task
/// instructions. They cover the same ownership contract a real UI test
/// would: the view model never starts its own scheduling, only forwards
/// visibility/policy to the shared `SystemMonitor` and republishes what it
/// publishes.
private struct FixedProbe: SystemProbing {
    func bootIdentity() throws -> BootIdentity { BootIdentity(bootTime: 1) }
    func diskStats(volumeURL: URL) throws -> DiskStats {
        DiskStats(totalBytes: 100, availableBytes: 30, availableForImportantUsageBytes: 35)
    }
    func memoryStats() throws -> MemoryStats { MemoryStats(totalBytes: 100, usedBytes: 40) }
    func swapStats() throws -> SwapStats { SwapStats(totalBytes: 10, usedBytes: 2) }
    func swapPageOutCounter() throws -> (count: UInt64, pageSizeBytes: UInt64) { (0, 16_384) }
    func thermalState() -> ProcessInfo.ThermalState? { .nominal }
    func isLowPowerModeEnabled() -> Bool? { false }
}

private struct NoOpPressureObserving: MemoryPressureObserving {
    func start(onChange: @escaping @Sendable (MemoryPressureLevel) -> Void) -> MemoryPressureSubscription {
        NoOpSubscription()
    }
}
private struct NoOpSubscription: MemoryPressureSubscription {
    func cancel() {}
}
private struct ImmediateScheduling: MonitorScheduling {
    func sleep(seconds: Double) async throws { throw CancellationError() }
}

@MainActor
final class HeadroomViewModelTests: XCTestCase {
    private func makeMonitor() -> SystemMonitor {
        SystemMonitor(configuration: .init(featureEnabled: true, backgroundEnabled: false,
            suppressHiddenSampling: false, visibleIntervalSeconds: 5,
            hiddenIntervalSeconds: 60, historyEnabled: false, historyHours: 0),
            probe: FixedProbe(),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
    }

    func testCardOrderPreservesAnIntentionallyEmptyPolicySubset() {
        let model = HeadroomViewModel(monitor: makeMonitor(), cardOrder: [])
        XCTAssertEqual(model.cardOrder, [])
    }

    func testCardOrderHonorsAnExplicitOrdering() {
        let custom = ["swap", "disk"]
        let model = HeadroomViewModel(monitor: makeMonitor(), cardOrder: custom)
        XCTAssertEqual(model.cardOrder, custom)
    }

    func testOnAppearPublishesASnapshotWithoutTheViewModelPollingItself() async throws {
        let monitor = makeMonitor()
        let model = HeadroomViewModel(monitor: monitor, cardOrder: [])
        XCTAssertNil(model.snapshot)

        model.onAppear()

        try await waitUntil { model.snapshot != nil }
        XCTAssertNotNil(model.snapshot?.memory)
    }

    func testReadinessReflectsAvailableBytesAgainstTarget() async throws {
        let monitor = makeMonitor()
        let model = HeadroomViewModel(monitor: monitor, cardOrder: [])
        model.onAppear()
        try await waitUntil { model.snapshot != nil }

        // FixedProbe reports 30 strictly-available bytes.
        XCTAssertEqual(model.readiness(targetBytes: nil), .unavailable)
        // 1 GiB is nowhere near the 30 bytes FixedProbe reports as available.
        if case .belowTarget = model.readiness(targetBytes: 1_073_741_824) {
            // expected
        } else {
            XCTFail("expected a shortfall against a 1 GiB target with only 30 bytes available")
        }
    }

    func testOnDisappearIsIdempotentEvenWithoutAPriorOnAppear() async {
        let model = HeadroomViewModel(monitor: makeMonitor(), cardOrder: [])
        model.onDisappear()
        model.onDisappear()
        try? await Task.sleep(nanoseconds: 10_000_000)
        let leaseCount = await model.monitorSceneLeaseCountForTesting()
        XCTAssertEqual(leaseCount, 0)
    }

    func testTwoVisibleModelsReleaseTheirOwnSceneLeasesIndependently() async throws {
        let monitor = makeMonitor()
        let first = HeadroomViewModel(monitor: monitor, cardOrder: [])
        let second = HeadroomViewModel(monitor: monitor, cardOrder: [])
        first.onAppear(); first.onAppear(); second.onAppear()
        try await waitUntil { await monitor.activeSceneLeaseCountForTesting() == 2 }
        first.onDisappear(); first.onDisappear()
        try await waitUntil { await monitor.activeSceneLeaseCountForTesting() == 1 }
        let firstTimerState = await monitor.isTimerRunningForTesting()
        XCTAssertTrue(firstTimerState)
        second.onDisappear()
        try await waitUntil { await monitor.activeSceneLeaseCountForTesting() == 0 }
        let finalTimerState = await monitor.isTimerRunningForTesting()
        XCTAssertFalse(finalTimerState)
    }

    /// The regression test for the "each open/close leaks a subscriber"
    /// blocker: several `HeadroomViewModel`/`StatsRefresher` instances share
    /// ONE `SystemMonitor`, most are discarded, and the survivor must both
    /// (a) not be one of a set of leaked registrations and (b) keep
    /// receiving live updates -- proving discarded consumers actually tore
    /// their subscriptions down rather than merely no longer being
    /// referenced by this test.
    func testDiscardedConsumersDoNotLeakMonitorSubscriptions() async throws {
        let monitor = makeMonitor()
        let initialCount = await monitor.subscriberCountForTesting()
        XCTAssertEqual(initialCount, 0)

        var headroomModels: [HeadroomViewModel]? = (0..<3).map { _ in
            HeadroomViewModel(monitor: monitor, cardOrder: [])
        }
        var refreshers: [StatsRefresher]? = (0..<3).map { _ in
            StatsRefresher(monitor: monitor)
        }
        let survivor = HeadroomViewModel(monitor: monitor, cardOrder: [])

        // Give every subscription's init Task a turn to actually call
        // `subscribe()` before asserting the count -- subscription happens
        // asynchronously (it hops onto the monitor actor).
        try await waitUntil { await monitor.subscriberCountForTesting() == 7 }

        headroomModels = nil
        refreshers = nil
        // `onTermination` also fires asynchronously once each task's
        // subscription is cancelled and the stream notices; poll rather
        // than assert immediately.
        try await waitUntil(timeout: 3) { await monitor.subscriberCountForTesting() == 1 }

        XCTAssertNil(headroomModels)
        XCTAssertNil(refreshers)

        survivor.onAppear()
        try await waitUntil { survivor.snapshot != nil }
        XCTAssertNotNil(survivor.snapshot?.memory)
        let finalCount = await monitor.subscriberCountForTesting()
        XCTAssertEqual(finalCount, 1, "the survivor's own subscription should be the only one left")
    }

    func testResolvedHeadroomTargetBytesIsNilWithoutAPolicy() {
        XCTAssertNil(resolvedHeadroomTargetBytes(nil))
    }

    func testResolvedUICardOrderFallsBackWithoutAPolicy() {
        XCTAssertEqual(resolvedUICardOrder(nil), HeadroomViewModel.defaultCardOrder)
    }

    func testResolvedUICardOrderPreservesExplicitEmptySubset() {
        let id = SettingID(rawValue: "ui.cards")
        let policy = EffectivePolicy(fields: [id: EffectiveField(
            value: .stored(.strings([])), sources: [.layer(.global)], reason: .replaced)],
            allowedFeatures: ["headroom"], walkWorkers: 1, readOnlyProcesses: 1,
            scanAdmission: .userRequestedOnly, manualBatchBytes: 1, manualBatchItems: 1,
            exclusions: [])
        XCTAssertEqual(resolvedUICardOrder(policy), [])
    }

    /// Polls a `@MainActor` condition on a short, bounded schedule instead
    /// of a fixed sleep, so the test is both fast on a healthy run and not
    /// flaky under CI load.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline {
                XCTFail("condition never became true within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
