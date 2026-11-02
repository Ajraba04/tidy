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

final class BuildPrepVolumeSelectionTests: XCTestCase {
    private let homeID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let externalID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    func testUnselectedTargetDefaultsToHomeIdentityRatherThanFirstAvailableVolume() {
        let selection = BuildPrepVolumeSelection()
        XCTAssertEqual(selection.resolvedID(homeVolumeID: homeID,
            availableVolumeIDs: [externalID, homeID]), homeID)
    }

    func testExplicitTargetKeepsItsIdentityWhenAvailableVolumeOrderChanges() {
        var selection = BuildPrepVolumeSelection()
        selection.select(externalID)
        XCTAssertEqual(selection.resolvedID(homeVolumeID: homeID,
            availableVolumeIDs: [homeID, externalID]), externalID)
        XCTAssertEqual(selection.resolvedID(homeVolumeID: homeID,
            availableVolumeIDs: [externalID, homeID]), externalID)
    }

    func testMissingSelectedTargetDoesNotFallBackToHomeOrAnotherVolume() {
        var selection = BuildPrepVolumeSelection()
        selection.select(externalID)
        XCTAssertNil(selection.resolvedID(homeVolumeID: homeID,
            availableVolumeIDs: [homeID]))
        XCTAssertEqual(selection.selectedID, externalID)
        XCTAssertEqual(selection.resolvedID(homeVolumeID: homeID,
            availableVolumeIDs: [externalID, homeID]), externalID)
    }

    func testMissingHomeIdentityCannotUseAnUnrelatedMeasurementAsDefault() {
        let selection = BuildPrepVolumeSelection()
        XCTAssertNil(selection.resolvedID(homeVolumeID: nil,
            availableVolumeIDs: [externalID]))
        XCTAssertNil(selection.resolvedID(homeVolumeID: homeID,
            availableVolumeIDs: [externalID]))
    }
}

@MainActor
final class BuildPrepCapacityTests: XCTestCase {
    private struct Fixture: Sendable {
        let directory: URL
        let target: BuildPrepVolumeTarget
        let authority: LocalAuthorityStore
        let snapshot: LocalAuthoritySnapshot
        let disk: DiskStats
    }

    private func fixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildPrepCapacity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let ledger = directory.appendingPathComponent("authority")
        let approved = directory.appendingPathComponent("approved")
        for url in [ledger, approved] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        let root = try LocalRootApproval.verify(directory: approved)
        let authority = try LocalAuthorityStore(directory: ledger,
            installation: LocalInstallationIdentity.verify(directory: ledger))
        let owner = LocalAuthorityOwner()
        let scope = LocalAuthorityScope.localRoot(root)
        let token = try await authority.beginReview(scope: scope, owner: owner,
            nowMonotonicNanoseconds: 1)
        let snapshot = try await authority.confirm(token, owner: owner,
            nowMonotonicNanoseconds: 2)
        return Fixture(directory: directory, target: BuildPrepVolumeTarget(root: root, scope: scope),
            authority: authority, snapshot: snapshot,
            disk: DiskStats(totalBytes: 1_000, availableBytes: 100,
                availableForImportantUsageBytes: 200, volumeIdentifier: root.volumeID.uuidString))
    }

    func testApprovedTargetMeasuresOnlyItsExactPathAndPreservesStrictCapacity() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.target, disk = fixture.disk
        let measured = try await target.measure(authority: fixture.snapshot) { url in
            XCTAssertEqual(url.path, target.root.canonicalPath)
            return disk
        }
        XCTAssertEqual(measured.volumeIdentifier, target.id.uuidString)
        XCTAssertEqual(measured.availableBytes, 100)
        XCTAssertEqual(measured.availableForImportantUsageBytes, 200)
    }

    func testUnapprovedTargetNeverInvokesCapacityProbe() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        do {
            _ = try await fixture.target.measure(authority: nil) { _ in
                XCTFail("Capacity probe ran without the matching local authority")
                return fixture.disk
            }
            XCTFail("Unapproved volume was accepted")
        } catch BuildPrepVolumeTarget.Error.authorityChanged {}
    }

    func testRevocationDuringCapacityProbeRejectsLateResult() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let authority = fixture.authority, target = fixture.target, disk = fixture.disk
        do {
            _ = try await target.measure(authority: fixture.snapshot) { _ in
                _ = try await authority.revoke(.localRoot(target.root))
                return disk
            }
            XCTFail("Revoked volume measurement was accepted")
        } catch BuildPrepVolumeTarget.Error.authorityChanged {}
    }

    func testProbeCannotSubstituteAnotherVolumeIdentity() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        do {
            _ = try await fixture.target.measure(authority: fixture.snapshot) { _ in
                DiskStats(totalBytes: 1_000, availableBytes: 900,
                    availableForImportantUsageBytes: 900, volumeIdentifier: UUID().uuidString)
            }
            XCTFail("Another volume's capacity was accepted")
        } catch BuildPrepVolumeTarget.Error.measurementUnavailable {}
    }

    func testReplacedApprovedRootDuringProbeRejectsLateResult() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.target, disk = fixture.disk
        let displaced = fixture.directory.appendingPathComponent("displaced")
        do {
            _ = try await target.measure(authority: fixture.snapshot) { url in
                try FileManager.default.moveItem(at: url, to: displaced)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
                return disk
            }
            XCTFail("Replaced root measurement was accepted")
        } catch BuildPrepVolumeTarget.Error.identityChanged {}
    }
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

    func testDestroyingManySceneModelsReturnsLeaseGenerationBookkeepingToBaseline() async throws {
        let monitor = makeMonitor()
        let baselineLeases = await monitor.activeSceneLeaseCountForTesting()
        let baselineGenerations = await monitor.sceneLeaseGenerationCountForTesting()
        let expectedAddedScenes = 200

        var headroomModels: [HeadroomViewModel]? = (0..<100).map { _ in
            HeadroomViewModel(monitor: monitor, cardOrder: [])
        }
        var menuModels: [StatsRefresher]? = (0..<100).map { _ in
            StatsRefresher(monitor: monitor)
        }
        headroomModels?.forEach { $0.onAppear() }
        menuModels?.forEach { $0.onPopoverAppear() }

        // Establish that every queued visibility update reached the actor before
        // testing deinit cleanup. Without this barrier the baseline could match
        // transiently before the visibility tasks ran, then rise after the test
        // had already accepted the baseline as its cleanup result.
        try await waitUntil(timeout: 5) {
            let leases = await monitor.activeSceneLeaseCountForTesting()
            let generations = await monitor.sceneLeaseGenerationCountForTesting()
            return leases == baselineLeases + expectedAddedScenes &&
                generations == baselineGenerations + expectedAddedScenes
        }
        let activeLeases = await monitor.activeSceneLeaseCountForTesting()
        let activeGenerations = await monitor.sceneLeaseGenerationCountForTesting()
        XCTAssertEqual(activeLeases, baselineLeases + expectedAddedScenes)
        XCTAssertEqual(activeGenerations, baselineGenerations + expectedAddedScenes)

        headroomModels = nil
        menuModels = nil

        try await waitUntil(timeout: 5) {
            let leases = await monitor.activeSceneLeaseCountForTesting()
            let generations = await monitor.sceneLeaseGenerationCountForTesting()
            return leases == baselineLeases && generations == baselineGenerations
        }
        let finalLeases = await monitor.activeSceneLeaseCountForTesting()
        let finalGenerations = await monitor.sceneLeaseGenerationCountForTesting()
        XCTAssertEqual(finalLeases, baselineLeases)
        XCTAssertEqual(finalGenerations, baselineGenerations)
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
