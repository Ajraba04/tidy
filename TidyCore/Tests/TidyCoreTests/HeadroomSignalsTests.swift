import Foundation
import Testing
@testable import TidyCore

// MARK: - Fixtures

private enum FixtureError: Error, Equatable, Sendable { case denied }

private final class ProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private struct FakeSystemProbing: SystemProbing {
    var bootIdentityResult: Result<BootIdentity, FixtureError> = .success(BootIdentity(bootTime: 1_000))
    var diskStatsResult: Result<DiskStats, FixtureError> = .success(
        DiskStats(totalBytes: 100, availableBytes: 40, availableForImportantUsageBytes: 45))
    var memoryStatsResult: Result<MemoryStats, FixtureError> = .success(MemoryStats(totalBytes: 100, usedBytes: 50))
    var swapStatsResult: Result<SwapStats, FixtureError> = .success(SwapStats(totalBytes: 100, usedBytes: 10))
    var swapPageOutCounterResult: Result<PageOutCounter, FixtureError> = .success(PageOutCounter(count: 0, pageSizeBytes: 16_384))
    var thermal: ProcessInfo.ThermalState?
    var lowPower: Bool?
    var calls: ProbeCounter?

    func bootIdentity() throws -> BootIdentity { calls?.increment(); return try bootIdentityResult.get() }
    func diskStats(volumeURL: URL) throws -> DiskStats { calls?.increment(); return try diskStatsResult.get() }
    func memoryStats() throws -> MemoryStats { calls?.increment(); return try memoryStatsResult.get() }
    func swapStats() throws -> SwapStats { calls?.increment(); return try swapStatsResult.get() }
    func swapPageOutCounter() throws -> (count: UInt64, pageSizeBytes: UInt64) {
        calls?.increment()
        let value = try swapPageOutCounterResult.get()
        return (value.count, value.pageSizeBytes)
    }
    func thermalState() -> ProcessInfo.ThermalState? { calls?.increment(); return thermal }
    func isLowPowerModeEnabled() -> Bool? { calls?.increment(); return lowPower }
}

/// `(count:pageSizeBytes:)` as a concrete Sendable/Equatable value, since
/// bare tuples can't be stored in a `Result`.
private struct PageOutCounter: Sendable, Equatable {
    let count: UInt64
    let pageSizeBytes: UInt64
}

/// A probe whose boot identity and page-out counter are supplied by
/// thread-safe boxed closures, for the reset/negative-delta/
/// nondefault-page-size cases that need control over successive calls
/// rather than one fixed value.
private struct DynamicProbe: SystemProbing {
    let bootIdentityClosure: @Sendable () -> BootIdentity
    let counterClosure: @Sendable () -> PageOutCounter

    init(bootIdentity: @escaping @Sendable () -> BootIdentity,
         counter: @escaping @Sendable () -> PageOutCounter) {
        self.bootIdentityClosure = bootIdentity
        self.counterClosure = counter
    }

    func bootIdentity() throws -> BootIdentity { bootIdentityClosure() }
    func diskStats(volumeURL: URL) throws -> DiskStats {
        DiskStats(totalBytes: 100, availableBytes: 40, availableForImportantUsageBytes: 45)
    }
    func memoryStats() throws -> MemoryStats { MemoryStats(totalBytes: 100, usedBytes: 50) }
    func swapStats() throws -> SwapStats { SwapStats(totalBytes: 100, usedBytes: 10) }
    func swapPageOutCounter() throws -> (count: UInt64, pageSizeBytes: UInt64) {
        let value = counterClosure()
        return (value.count, value.pageSizeBytes)
    }
    func thermalState() -> ProcessInfo.ThermalState? { nil }
    func isLowPowerModeEnabled() -> Bool? { nil }
}

private struct NoOpPressureObserving: MemoryPressureObserving {
    func start(onChange: @escaping @Sendable (MemoryPressureLevel) -> Void) -> MemoryPressureSubscription {
        NoOpSubscription()
    }
}
private struct NoOpSubscription: MemoryPressureSubscription {
    func cancel() {}
}

private final class ControlledPressureObserving: MemoryPressureObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@Sendable (MemoryPressureLevel) -> Void] = []
    func start(onChange: @escaping @Sendable (MemoryPressureLevel) -> Void)
        -> MemoryPressureSubscription {
        lock.lock(); callbacks.append(onChange); lock.unlock()
        return NoOpSubscription()
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return callbacks.count }
    func emit(_ level: MemoryPressureLevel, subscription index: Int) {
        lock.lock(); let callback = callbacks[index]; lock.unlock(); callback(level)
    }
}

private struct ImmediateScheduling: MonitorScheduling {
    func sleep(seconds: Double) async throws { throw CancellationError() }
}

private final class CountingInstrumentation: MonitorInstrumentation, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var scheduledCount = 0
    private(set) var cancelledCount = 0

    func timerScheduled() {
        lock.lock(); scheduledCount += 1; lock.unlock()
    }
    func timerCancelled() {
        lock.lock(); cancelledCount += 1; lock.unlock()
    }
}

/// A thread-safe mutable box, so an `@Sendable` fixture closure can advance
/// state across calls without capturing a bare `var` (which the compiler
/// rightly refuses in `@Sendable` closures).
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: Value) { lock.lock(); defer { lock.unlock() }; value = newValue }
}

/// A stepping clock: each call advances by a fixed number of seconds from a
/// fixed origin, so a test can control elapsed time exactly rather than
/// relying on a real wall-clock wait.
private final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let step: TimeInterval

    init(start: Date = Date(timeIntervalSince1970: 0), step: TimeInterval) {
        self.current = start
        self.step = step
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        let value = current
        current = current.addingTimeInterval(step)
        return value
    }
}

@Suite("Headroom signals")
struct HeadroomSignalsTests {

    // MARK: counterRate contract (T10 normative snippet)

    @Test("a reset counter is not read as negative pressure")
    func resetCounterIsNotNegativePressure() {
        #expect(counterRate(before: 10, after: 2, seconds: 5) == nil)
    }

    @Test("zero elapsed time never produces a rate")
    func zeroElapsedProducesNoRate() {
        #expect(counterRate(before: 10, after: 20, seconds: 0) == nil)
    }

    @Test("non-finite elapsed time never produces a rate")
    func nonFiniteElapsedProducesNoRate() {
        #expect(counterRate(before: 10, after: 20, seconds: .infinity) == nil)
        #expect(counterRate(before: 10, after: 20, seconds: .nan) == nil)
    }

    @Test("an unchanged counter is a real, valid zero rate")
    func unchangedCounterIsZeroRate() {
        #expect(counterRate(before: 10, after: 10, seconds: 5) == 0)
    }

    @Test("a positive delta over positive elapsed time produces the expected rate")
    func positiveDeltaProducesExpectedRate() {
        #expect(counterRate(before: 10, after: 30, seconds: 5) == 4)
    }

    // MARK: HeadroomReadiness ("target met," never "buildable")

    @Test("missing target or availability is never presented as met or short")
    func missingInputsAreUnavailable() {
        #expect(HeadroomReadiness.evaluate(targetBytes: nil, availableBytes: 10) == .unavailable)
        #expect(HeadroomReadiness.evaluate(targetBytes: 10, availableBytes: nil) == .unavailable)
    }

    @Test("available at or above target reads as target met, not buildable")
    func availableAboveTargetIsMet() {
        #expect(HeadroomReadiness.evaluate(targetBytes: 10, availableBytes: 10) == .targetMet)
        #expect(HeadroomReadiness.evaluate(targetBytes: 10, availableBytes: 20) == .targetMet)
    }

    @Test("a shortfall reports the exact byte gap")
    func shortfallReportsExactGap() {
        #expect(HeadroomReadiness.evaluate(targetBytes: 20, availableBytes: 5) == .belowTarget(shortfallBytes: 15))
    }

    // MARK: SystemMonitor.Configuration.resolve (T06 inputs this contract consumes)

    @Test("a nil policy resolves to fully disabled, never a guessed default that starts sampling")
    func nilPolicyResolvesDisabled() {
        let configuration = SystemMonitor.Configuration.resolve(nil)
        #expect(configuration.featureEnabled == false)
        #expect(configuration.backgroundEnabled == false)
    }

    // MARK: RED -- API denial

    @Test("a denied disk read is reported as unavailable with a reason, never a fabricated zero")
    func deniedDiskReadIsUnavailable() async {
        let probe = FakeSystemProbing(diskStatsResult: .failure(.denied))
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration, probe: probe,
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        let snapshot = await monitor.requestSnapshot()
        #expect(snapshot.volumes.first?.disk == nil)
        #expect(snapshot.volumes.first?.unavailableReason != nil)
    }

    @Test("a denied memory read is reported as unavailable, never shown as zero used")
    func deniedMemoryReadIsUnavailable() async {
        let probe = FakeSystemProbing(memoryStatsResult: .failure(.denied))
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration, probe: probe,
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        let snapshot = await monitor.requestSnapshot()
        #expect(snapshot.memory == nil)
        #expect(snapshot.memoryUnavailableReason != nil)
    }

    // MARK: RED -- unsupported signal

    @Test("an unsupported thermal signal is reported nil, never defaulted to nominal")
    func unsupportedThermalSignalIsNil() async {
        let probe = FakeSystemProbing(thermal: nil)
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration, probe: probe,
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        let snapshot = await monitor.requestSnapshot()
        #expect(snapshot.thermalState == nil)
    }

    @Test("an unsupported power signal is reported nil, never defaulted to false")
    func unsupportedPowerSignalIsNil() async {
        let probe = FakeSystemProbing(lowPower: nil)
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration, probe: probe,
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        let snapshot = await monitor.requestSnapshot()
        #expect(snapshot.isLowPowerModeEnabled == nil)
    }

    // MARK: RED -- wake/reboot resets cumulative counters

    @Test("a changed boot identity between samples yields no rate, even though the raw counts rose")
    func changedBootIdentityYieldsNoRate() async {
        let firstBoot = BootIdentity(bootTime: 1_000)
        let secondBoot = BootIdentity(bootTime: 2_000)
        let clock = SteppingClock(step: 10)
        let callCount = Box(0)
        let monitor = SystemMonitor(
            configuration: enabledVisibleConfiguration,
            probe: DynamicProbe(
                bootIdentity: {
                    let n = callCount.get() + 1
                    callCount.set(n)
                    return n == 1 ? firstBoot : secondBoot
                },
                counter: { PageOutCounter(count: UInt64(callCount.get()) * 100, pageSizeBytes: 4_096) }),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling(),
            clock: clock.now)

        _ = await monitor.requestSnapshot() // establishes baseline under firstBoot
        let second = await monitor.requestSnapshot() // reports under secondBoot: reset, not a huge rate
        #expect(second.pageOutRatePerSecond == nil)
    }

    @Test("consistent boot identity across two samples produces a real page-out rate using the real page size")
    func consistentBootIdentityProducesRate() async {
        let boot = BootIdentity(bootTime: 1_000)
        let clock = SteppingClock(step: 10)
        let counts: [UInt64] = [0, 100]
        let index = Box(0)
        let monitor = SystemMonitor(
            configuration: enabledVisibleConfiguration,
            probe: DynamicProbe(
                bootIdentity: { boot },
                counter: {
                    let i = index.get()
                    index.set(min(i + 1, counts.count - 1))
                    return PageOutCounter(count: counts[i], pageSizeBytes: 16_384)
                }),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling(),
            clock: clock.now)

        _ = await monitor.requestSnapshot()
        let second = await monitor.requestSnapshot()
        // (100 - 0) pages / 10 seconds * 16384 bytes/page (a nondefault page size, not the
        // hardcoded 4 KiB many tools assume) = 163840 bytes/sec.
        #expect(second.pageOutRatePerSecond == 163_840)
    }

    @Test("a counter that appears to go backwards under the same boot never becomes a rate")
    func negativeDeltaUnderSameBootNeverBecomesRate() async {
        let boot = BootIdentity(bootTime: 1_000)
        let clock = SteppingClock(step: 10)
        let counts: [UInt64] = [50, 10]
        let index = Box(0)
        let monitor = SystemMonitor(
            configuration: enabledVisibleConfiguration,
            probe: DynamicProbe(bootIdentity: { boot }, counter: {
                let i = index.get()
                index.set(min(i + 1, counts.count - 1))
                return PageOutCounter(count: counts[i], pageSizeBytes: 4_096)
            }),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling(),
            clock: clock.now)

        _ = await monitor.requestSnapshot()
        let second = await monitor.requestSnapshot()
        #expect(second.pageOutRatePerSecond == nil)
    }

    @Test("local consent revocation stops hidden monitoring independently of settings revision")
    func localConsentRevocationStopsHiddenMonitoring() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tidy-monitor-authority-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = try LocalAuthorityStore(directory: scratch,
            installation: LocalInstallationIdentity.verify(directory: scratch))
        let owner = LocalAuthorityOwner()
        let review = try await store.beginReview(scope: .backgroundSignals, owner: owner,
            nowMonotonicNanoseconds: 1)
        let approved = try await store.confirm(review, owner: owner, nowMonotonicNanoseconds: 2)
        let monitor = SystemMonitor(configuration: .disabled,
            probe: FakeSystemProbing(), pressureObserving: NoOpPressureObserving(),
            scheduling: ImmediateScheduling())
        await monitor.applyLocalAuthority(approved, generation: 1)
        var configuration = enabledVisibleConfiguration
        configuration.backgroundEnabled = true
        _ = await monitor.applyConfiguration(configuration, acknowledgedRevision: 7)
        #expect(await monitor.isTimerRunningForTesting())
        _ = try await store.revoke(.backgroundSignals)
        // Even a stale observer/configuration cannot revive the invalidated snapshot.
        _ = await monitor.applyConfiguration(configuration, acknowledgedRevision: 7)
        #expect(!(await monitor.isTimerRunningForTesting()))
        await monitor.applyLocalAuthority(nil, generation: 2)
        await monitor.applyLocalAuthority(approved, generation: 1)
        #expect(!(await monitor.isTimerRunningForTesting()))
        #expect(await monitor.appliedConfigurationRevisionForTesting() == 7)
    }

    // MARK: Visibility and explicit-work leases

    @Test("hidden and disabled produces no repeating timer at all")
    func hiddenAndDisabledProducesNoTimer() async {
        let instrumentation = CountingInstrumentation()
        let monitor = SystemMonitor(configuration: .disabled, probe: FakeSystemProbing(),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling(),
            instrumentation: instrumentation)
        await monitor.applyConfiguration(.disabled)
        #expect(instrumentation.scheduledCount == 0)
        #expect(await monitor.isTimerRunningForTesting() == false)
    }

    @Test("scene leases are independent and duplicate acquire/release is idempotent")
    func sceneLeasesAreIndependentAndIdempotent() async {
        let instrumentation = CountingInstrumentation()
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            probe: FakeSystemProbing(), pressureObserving: NoOpPressureObserving(),
            scheduling: ImmediateScheduling(), instrumentation: instrumentation)
        let headroom = MonitorLease()
        let popover = MonitorLease()

        await monitor.acquireSceneLease(headroom)
        await monitor.acquireSceneLease(headroom)
        await monitor.acquireSceneLease(popover)
        #expect(await monitor.activeSceneLeaseCountForTesting() == 2)
        #expect(await monitor.isTimerRunningForTesting())

        await monitor.releaseSceneLease(headroom)
        await monitor.releaseSceneLease(headroom)
        #expect(await monitor.activeSceneLeaseCountForTesting() == 1)
        #expect(await monitor.isTimerRunningForTesting())

        await monitor.releaseSceneLease(popover)
        #expect(await monitor.activeSceneLeaseCountForTesting() == 0)
        #expect(await monitor.isTimerRunningForTesting() == false)
    }

    @Test("stale out-of-order scene transitions cannot resurrect a hidden lease")
    func staleSceneTransitionsCannotResurrectLease() async {
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            probe: FakeSystemProbing(), pressureObserving: NoOpPressureObserving(),
            scheduling: ImmediateScheduling())
        let scene = MonitorLease()
        await monitor.updateSceneLease(scene, visible: false, generation: 2)
        await monitor.updateSceneLease(scene, visible: true, generation: 1)
        #expect(await monitor.activeSceneLeaseCountForTesting() == 0)
        #expect(await monitor.isTimerRunningForTesting() == false)
        await monitor.updateSceneLease(scene, visible: true, generation: 3)
        #expect(await monitor.activeSceneLeaseCountForTesting() == 1)
    }

    @Test("stale acknowledged policy delivery cannot overwrite a newer feature disable")
    func stalePolicyDeliveryCannotOverwriteDisable() async {
        let calls = ProbeCounter()
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            configurationRevision: 1, probe: FakeSystemProbing(calls: calls),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        await monitor.applyConfiguration(.disabled, acknowledgedRevision: 3)
        await monitor.applyConfiguration(enabledVisibleConfiguration, acknowledgedRevision: 2)
        let snapshot = await monitor.requestSnapshot()
        #expect(snapshot.unavailableReason == SystemMonitor.featureDisabledReason)
        #expect(calls.count == 0)
        #expect(await monitor.appliedConfigurationRevisionForTesting() == 3)
    }

    @Test("an acknowledged feature disable immediately publishes unavailable without probing")
    func acknowledgedDisablePublishesUnavailableWithoutProbe() async {
        let calls = ProbeCounter()
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            configurationRevision: 1, probe: FakeSystemProbing(calls: calls),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        _ = await monitor.requestSnapshot()
        let probeCount = calls.count
        let broadcasts = await monitor.broadcastCountForTesting()

        let applied = await monitor.applyConfiguration(.disabled, acknowledgedRevision: 2)
        let snapshot = await monitor.latestSnapshotForTesting()

        #expect(applied)
        #expect(snapshot?.unavailableReason == SystemMonitor.featureDisabledReason)
        #expect(snapshot?.volumes.isEmpty == true && snapshot?.memory == nil)
        #expect(await monitor.broadcastCountForTesting() == broadcasts + 1)
        #expect(calls.count == probeCount)
    }

    @Test("memory-pressure events publish immediately without waiting for a timer or probing")
    func pressureEventsPublishImmediatelyWithoutProbing() async throws {
        let calls = ProbeCounter()
        let pressure = ControlledPressureObserving()
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            probe: FakeSystemProbing(calls: calls), pressureObserving: pressure,
            scheduling: ImmediateScheduling())
        await monitor.acquireSceneLease(MonitorLease())
        _ = await monitor.requestSnapshot()
        let probeCount = calls.count
        let broadcasts = await monitor.broadcastCountForTesting()
        #expect(pressure.count == 1)

        pressure.emit(.critical, subscription: 0)
        for _ in 0..<200 {
            if await monitor.broadcastCountForTesting() > broadcasts { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(await monitor.broadcastCountForTesting() == broadcasts + 1)
        #expect(await monitor.latestPressureLevelForTesting() == .critical)
        #expect(calls.count == probeCount)
    }

    @Test("a subscriber registering after publication replays the latest snapshot")
    func lateSubscriberReceivesLatestSnapshot() async throws {
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            probe: FakeSystemProbing(), pressureObserving: NoOpPressureObserving(),
            scheduling: ImmediateScheduling())
        let published = await monitor.requestSnapshot()
        let receipt = Box<SystemSnapshot?>(nil)
        let stream = await monitor.subscribe()
        let task = Task {
            for await snapshot in stream {
                receipt.set(snapshot)
                break
            }
        }
        for _ in 0..<200 {
            if receipt.get() != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let received = receipt.get()
        #expect(received?.observedAt == published.observedAt)
        #expect(received?.volumes.first?.disk?.availableBytes
            == published.volumes.first?.disk?.availableBytes)
        task.cancel()
    }

    @Test("production pressure observation subscribes to nominal recovery")
    func productionPressureMaskIncludesRecovery() {
        #expect(LiveMemoryPressureObserving.eventMask.contains(.normal))
        #expect(LiveMemoryPressureObserving.eventMask.contains(.warning))
        #expect(LiveMemoryPressureObserving.eventMask.contains(.critical))
    }

    @Test("the current pressure subscription publishes nominal recovery after critical")
    func currentPressureSubscriptionPublishesRecovery() async throws {
        let calls = ProbeCounter()
        let pressure = ControlledPressureObserving()
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            probe: FakeSystemProbing(calls: calls), pressureObserving: pressure,
            scheduling: ImmediateScheduling())
        await monitor.acquireSceneLease(MonitorLease())
        _ = await monitor.requestSnapshot()
        let probeCount = calls.count

        pressure.emit(.critical, subscription: 0)
        for _ in 0..<200 {
            if await monitor.latestPressureLevelForTesting() == .critical { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        pressure.emit(.normal, subscription: 0)
        for _ in 0..<200 {
            if await monitor.latestPressureLevelForTesting() == .normal { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        #expect(await monitor.latestPressureLevelForTesting() == .normal)
        #expect(calls.count == probeCount)
    }

    @Test("callbacks from a replaced pressure subscription cannot clear a current critical event")
    func stalePressureCallbackCannotOverwriteCurrentEvent() async throws {
        let pressure = ControlledPressureObserving()
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            configurationRevision: 1, probe: FakeSystemProbing(),
            pressureObserving: pressure, scheduling: ImmediateScheduling())
        await monitor.acquireSceneLease(MonitorLease())
        #expect(pressure.count == 1)
        await monitor.applyConfiguration(.disabled, acknowledgedRevision: 2)
        await monitor.applyConfiguration(enabledVisibleConfiguration, acknowledgedRevision: 3)
        #expect(pressure.count == 2)

        pressure.emit(.critical, subscription: 1)
        for _ in 0..<200 {
            if await monitor.latestPressureLevelForTesting() == .critical { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        pressure.emit(.normal, subscription: 0)
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await monitor.latestPressureLevelForTesting() == .critical)
    }

    @Test("an explicit-work lease keeps observations alive while every scene is hidden")
    func explicitWorkLeaseKeepsObservationAliveWhenHidden() async {
        let monitor = SystemMonitor(configuration: enabledVisibleConfiguration,
            probe: FakeSystemProbing(), pressureObserving: NoOpPressureObserving(),
            scheduling: ImmediateScheduling())
        let scan = MonitorLease()
        await monitor.acquireExplicitWorkLease(scan)
        await monitor.acquireExplicitWorkLease(scan)
        #expect(await monitor.activeExplicitWorkLeaseCountForTesting() == 1)
        #expect(await monitor.isTimerRunningForTesting())
        await monitor.releaseExplicitWorkLease(scan)
        await monitor.releaseExplicitWorkLease(scan)
        #expect(await monitor.activeExplicitWorkLeaseCountForTesting() == 0)
        #expect(await monitor.isTimerRunningForTesting() == false)
    }

    @Test("background disabled and window hidden after being visible tears the timer down, not just slows it")
    func backgroundDisabledHiddenTearsDownTimer() async {
        let instrumentation = CountingInstrumentation()
        let monitor = SystemMonitor(configuration: .disabled, probe: FakeSystemProbing(),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling(),
            instrumentation: instrumentation)
        var configuration = enabledVisibleConfiguration
        configuration.backgroundEnabled = false
        await monitor.applyConfiguration(configuration)
        let scene = MonitorLease()
        await monitor.acquireSceneLease(scene)
        #expect(instrumentation.scheduledCount >= 1)
        #expect(await monitor.isTimerRunningForTesting())

        await monitor.releaseSceneLease(scene)
        #expect(instrumentation.cancelledCount >= 1)
        #expect(await monitor.isTimerRunningForTesting() == false)
    }

    @Test("feature disabled overrides an explicit background-enabled setting")
    func featureDisabledOverridesBackgroundEnabled() async {
        let instrumentation = CountingInstrumentation()
        let monitor = SystemMonitor(configuration: .disabled, probe: FakeSystemProbing(),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling(),
            instrumentation: instrumentation)
        let configuration = SystemMonitor.Configuration(featureEnabled: false, backgroundEnabled: true,
            suppressHiddenSampling: false, visibleIntervalSeconds: 5, hiddenIntervalSeconds: 60,
            historyEnabled: false, historyHours: 0)
        await monitor.applyConfiguration(configuration)
        #expect(instrumentation.scheduledCount == 0)
    }

    @Test("suppressHiddenSampling forces the hidden loop off even with background enabled")
    func suppressHiddenSamplingForcesOff() async {
        let instrumentation = CountingInstrumentation()
        let monitor = SystemMonitor(configuration: .disabled, probe: FakeSystemProbing(),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling(),
            instrumentation: instrumentation)
        let configuration = SystemMonitor.Configuration(featureEnabled: true, backgroundEnabled: true,
            suppressHiddenSampling: true, visibleIntervalSeconds: 5, hiddenIntervalSeconds: 60,
            historyEnabled: false, historyHours: 0)
        await monitor.applyConfiguration(configuration)
        #expect(instrumentation.scheduledCount == 0)
    }

    // MARK: History -- opt-in and bounded, never stores process data

    @Test("history stays empty when disabled, even after explicit snapshots")
    func historyStaysEmptyWhenDisabled() async {
        var configuration = enabledVisibleConfiguration
        configuration.historyEnabled = false
        let monitor = SystemMonitor(configuration: configuration, probe: FakeSystemProbing(),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        _ = await monitor.requestSnapshot()
        _ = await monitor.requestSnapshot()
        #expect(await monitor.recordedHistory().isEmpty)
    }

    @Test("history records when enabled and stays bounded by its configured window")
    func historyRecordsWhenEnabledAndStaysBounded() {
        var history = SignalHistory(maxEntries: 2, maxAgeSeconds: 1_000)
        let base = Date(timeIntervalSince1970: 0)
        func snapshot(at offset: TimeInterval) -> SystemSnapshot {
            SystemSnapshot(observedAt: base.addingTimeInterval(offset), bootIdentity: nil, volumes: [],
                memory: nil, memoryUnavailableReason: nil, swap: nil, swapUnavailableReason: nil,
                pageOutRatePerSecond: nil, memoryPressureLevel: nil, thermalState: nil,
                isLowPowerModeEnabled: nil)
        }
        history.record(snapshot(at: 0), now: base)
        history.record(snapshot(at: 1), now: base.addingTimeInterval(1))
        history.record(snapshot(at: 2), now: base.addingTimeInterval(2))
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.observedAt == base.addingTimeInterval(1))
    }

    @Test("history ages entries out past its configured window")
    func historyAgesEntriesOut() {
        var history = SignalHistory(maxEntries: 100, maxAgeSeconds: 5)
        let base = Date(timeIntervalSince1970: 0)
        func snapshot(at offset: TimeInterval) -> SystemSnapshot {
            SystemSnapshot(observedAt: base.addingTimeInterval(offset), bootIdentity: nil, volumes: [],
                memory: nil, memoryUnavailableReason: nil, swap: nil, swapUnavailableReason: nil,
                pageOutRatePerSecond: nil, memoryPressureLevel: nil, thermalState: nil,
                isLowPowerModeEnabled: nil)
        }
        history.record(snapshot(at: 0), now: base)
        history.prune(now: base.addingTimeInterval(10))
        #expect(history.entries.isEmpty)
    }

    // MARK: Feature restriction applies at the one-shot probe boundary

    @Test("an explicit request while disabled invokes zero probes and reports exact unavailability")
    func explicitSnapshotIsUnavailableWithoutProbingWhileDisabled() async {
        let calls = ProbeCounter()
        let monitor = SystemMonitor(configuration: .disabled,
            probe: FakeSystemProbing(calls: calls),
            pressureObserving: NoOpPressureObserving(), scheduling: ImmediateScheduling())
        let snapshot = await monitor.requestSnapshot()
        #expect(calls.count == 0)
        #expect(snapshot.unavailableReason == SystemMonitor.featureDisabledReason)
        #expect(snapshot.memory == nil && snapshot.volumes.isEmpty)
    }

    private var enabledVisibleConfiguration: SystemMonitor.Configuration {
        SystemMonitor.Configuration(featureEnabled: true, backgroundEnabled: false,
            suppressHiddenSampling: false, visibleIntervalSeconds: 5, hiddenIntervalSeconds: 60,
            historyEnabled: true, historyHours: 1)
    }
}
