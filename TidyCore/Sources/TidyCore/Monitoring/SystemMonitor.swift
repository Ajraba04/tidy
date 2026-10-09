import Darwin
import Dispatch
import Foundation

/// Everything `SystemMonitor` needs from the OS, isolated behind one
/// protocol so every RED case (API denial, an unsupported signal, a
/// changed boot identity, a nondefault page size) is a plain fixture value
/// instead of a real kernel call. `LiveSystemProbe` is the only production
/// conformance; nothing here ever spawns a process.
public protocol SystemProbing: Sendable {
    func bootIdentity() throws -> BootIdentity
    func diskStats(volumeURL: URL) throws -> DiskStats
    func memoryStats() throws -> MemoryStats
    func swapStats() throws -> SwapStats
    /// Cumulative pages swapped out since boot, and the page size they're
    /// denominated in. Kept separate from `swapStats()` because a fake used
    /// for one RED case (say, API denial on `vm.swapusage`) should not have
    /// to also fake this counter, and vice versa.
    func swapPageOutCounter() throws -> (count: UInt64, pageSizeBytes: UInt64)
    /// `nil` means "unsupported on this host," not "nominal." Never
    /// defaulted to a specific case when the platform call fails.
    func thermalState() -> ProcessInfo.ThermalState?
    func isLowPowerModeEnabled() -> Bool?
}

public struct LiveSystemProbe: SystemProbing {
    public init() {}

    public func bootIdentity() throws -> BootIdentity {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        let result = sysctlbyname("kern.boottime", &boottime, &size, nil, 0)
        guard result == 0 else {
            throw SystemProbeError.denied("kern.boottime")
        }
        return BootIdentity(bootTime: TimeInterval(boottime.tv_sec) + TimeInterval(boottime.tv_usec) / 1_000_000)
    }

    public func diskStats(volumeURL: URL) throws -> DiskStats {
        try DiskStats.current(volumeURL: volumeURL)
    }

    public func memoryStats() throws -> MemoryStats {
        let stats = MemoryStats.current()
        guard stats.usedBytes != nil else {
            throw SystemProbeError.denied(stats.unavailableReason ?? "host_statistics64")
        }
        return stats
    }

    public func swapStats() throws -> SwapStats {
        guard let stats = SwapStats.current() else {
            throw SystemProbeError.denied("vm.swapusage")
        }
        return stats
    }

    public func swapPageOutCounter() throws -> (count: UInt64, pageSizeBytes: UInt64) {
        guard let counters = VMCounterSnapshot.current() else {
            throw SystemProbeError.denied("host_statistics64")
        }
        return (counters.swapOutsCumulative, counters.pageSizeBytes)
    }

    public func thermalState() -> ProcessInfo.ThermalState? {
        ProcessInfo.processInfo.thermalState
    }

    public func isLowPowerModeEnabled() -> Bool? {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

public enum SystemProbeError: Error, Equatable, Sendable {
    case denied(String)
    case unsupported(String)
}

/// A push subscription to memory-pressure events. `cancel()` must be safe
/// to call more than once and safe to never call (e.g. if the monitor is
/// deallocated while a subscription is live).
public protocol MemoryPressureSubscription: Sendable {
    func cancel()
}

public protocol MemoryPressureObserving: Sendable {
    func start(onChange: @escaping @Sendable (MemoryPressureLevel) -> Void) -> MemoryPressureSubscription
}

public struct LiveMemoryPressureObserving: MemoryPressureObserving {
    static let eventMask: DispatchSource.MemoryPressureEvent = [.normal, .warning, .critical]

    public init() {}

    public func start(onChange: @escaping @Sendable (MemoryPressureLevel) -> Void) -> MemoryPressureSubscription {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: Self.eventMask, queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            if event.contains(.critical) { onChange(.critical) }
            else if event.contains(.warning) { onChange(.warning) }
            else { onChange(.normal) }
        }
        source.resume()
        return LiveMemoryPressureSubscription(source: source)
    }
}

private final class LiveMemoryPressureSubscription: MemoryPressureSubscription, @unchecked Sendable {
    private let source: DispatchSourceMemoryPressure
    private let lock = NSLock()
    private var cancelled = false

    init(source: DispatchSourceMemoryPressure) {
        self.source = source
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true
        source.cancel()
    }
}

/// Test/observability seam over "did a repeating background activity start
/// or stop," independent of actually waiting out a real interval. This is
/// how `HeadroomSignalsTests` proves the hidden+monitoring-disabled case
/// creates zero repeating timers/tasks, rather than trusting the
/// implementation not to regress silently.
public protocol MonitorInstrumentation: Sendable {
    func timerScheduled()
    func timerCancelled()
}

public struct NoOpMonitorInstrumentation: MonitorInstrumentation {
    public init() {}
    public func timerScheduled() {}
    public func timerCancelled() {}
}

/// Injectable sleep, so a repeating loop can be driven deterministically in
/// tests without a real wall-clock wait.
public protocol MonitorScheduling: Sendable {
    func sleep(seconds: Double) async throws
}

public struct SystemClockScheduling: MonitorScheduling {
    public init() {}
    public func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

public struct MonitorLease: Hashable, Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

/// Serializes one scene's visibility messages before they reach `SystemMonitor`. Disposal closes
/// the local producer first, waits for every earlier transition, then asks the monitor to remove
/// both the active lease and its generation entry. This preserves stale-task ordering without a
/// process-lifetime UUID tombstone for every destroyed view model.
public final class MonitorSceneLeaseController: @unchecked Sendable {
    private let lock = NSLock()
    private let monitor: SystemMonitor
    private let lease: MonitorLease
    private var generation: UInt64 = 0
    private var active = true
    private var tail: Task<Void, Never>?

    public init(monitor: SystemMonitor, lease: MonitorLease = MonitorLease()) {
        self.monitor = monitor
        self.lease = lease
    }

    public func setVisible(_ visible: Bool, requestSnapshot: Bool = false) {
        lock.lock()
        guard active else { lock.unlock(); return }
        generation &+= 1
        let generation = generation
        let previous = tail
        let monitor = monitor
        let lease = lease
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await monitor.updateSceneLease(lease, visible: visible, generation: generation)
            if visible, requestSnapshot {
                _ = await monitor.requestSnapshot(forScene: lease, generation: generation)
            }
        }
        tail = task
        lock.unlock()
    }

    public func dispose() {
        lock.lock()
        guard active else { lock.unlock(); return }
        active = false
        generation &+= 1
        let generation = generation
        let previous = tail
        let monitor = monitor
        let lease = lease
        let task = Task {
            await previous?.value
            await monitor.disposeSceneLease(lease, generation: generation)
        }
        tail = task
        lock.unlock()
    }

    public func awaitPendingForTesting() async {
        let pending = lock.withLock { tail }
        await pending?.value
    }
}

/// The optional, timestamped, per-volume/system observation described by
/// the T10 contract. `SystemMonitor` owns the ONE decision of whether a
/// repeating background sample loop may exist at all; every other consumer
/// (the menu bar popover, the Headroom window) asks for an explicit
/// snapshot or observes the published stream, and never starts its own
/// timer.
public actor SystemMonitor {
    public static let featureDisabledReason = "Headroom is disabled in Settings."
    public struct Configuration: Sendable, Equatable {
        /// Mirrors `feature.headroom` from `EffectivePolicy`. When `false`,
        /// no sampling of any kind happens, visible or hidden.
        public var featureEnabled: Bool
        /// Mirrors `monitor.backgroundEnabled` -- an authority setting that
        /// defaults to `false` and requires explicit consent. Only relevant
        /// while the window is hidden; a visible window always samples at
        /// `visibleIntervalSeconds` when the feature is enabled.
        public var backgroundEnabled: Bool
        /// Mirrors `monitor.suppressHiddenSampling`, a restriction that
        /// forces hidden sampling off even if `backgroundEnabled` is true
        /// (e.g. a stricter profile or Battery preset).
        public var suppressHiddenSampling: Bool
        public var visibleIntervalSeconds: Double
        public var hiddenIntervalSeconds: Double
        /// Mirrors `monitor.rawHistoryEnabled`. Opt-in and off by default.
        public var historyEnabled: Bool
        /// Mirrors `monitor.rawHistoryHours`, bounded to 1...24 by policy.
        public var historyHours: Int

        public init(featureEnabled: Bool, backgroundEnabled: Bool, suppressHiddenSampling: Bool,
                    visibleIntervalSeconds: Double, hiddenIntervalSeconds: Double,
                    historyEnabled: Bool, historyHours: Int) {
            self.featureEnabled = featureEnabled
            self.backgroundEnabled = backgroundEnabled
            self.suppressHiddenSampling = suppressHiddenSampling
            self.visibleIntervalSeconds = max(1, visibleIntervalSeconds)
            self.hiddenIntervalSeconds = max(1, hiddenIntervalSeconds)
            self.historyEnabled = historyEnabled
            self.historyHours = max(0, historyHours)
        }

        /// Monitoring off, no history, nothing scheduled: the safe starting
        /// point before any policy has been read.
        public static let disabled = Configuration(featureEnabled: false, backgroundEnabled: false,
            suppressHiddenSampling: true, visibleIntervalSeconds: 5, hiddenIntervalSeconds: 60,
            historyEnabled: false, historyHours: 0)

        /// Reads exactly the T06 settings this contract consumes. A `nil`
        /// policy (no acknowledged settings yet) resolves to `.disabled`,
        /// never to a guessed default that starts sampling.
        public static func resolve(_ policy: EffectivePolicy?) -> Configuration {
            guard let policy else { return .disabled }
            func boolField(_ id: String, default fallback: Bool) -> Bool {
                guard case .stored(.bool(let value))? = policy.fields[SettingID(rawValue: id)]?.value else {
                    return fallback
                }
                return value
            }
            func integerField(_ id: String, default fallback: Int64) -> Int64 {
                guard case .stored(.integer(let value))? = policy.fields[SettingID(rawValue: id)]?.value else {
                    return fallback
                }
                return value
            }
            return Configuration(
                featureEnabled: policy.allowedFeatures.contains("headroom"),
                backgroundEnabled: boolField("monitor.backgroundEnabled", default: false),
                suppressHiddenSampling: boolField("monitor.suppressHiddenSampling", default: false),
                visibleIntervalSeconds: Double(integerField("monitor.visibleIntervalSeconds", default: 5)),
                hiddenIntervalSeconds: Double(integerField("monitor.hiddenIntervalSeconds", default: 60)),
                historyEnabled: boolField("monitor.rawHistoryEnabled", default: false),
                historyHours: Int(integerField("monitor.rawHistoryHours", default: 24)))
        }
    }

    /// One `AsyncStream` per caller of `subscribe()`, keyed by a private id
    /// so each consumer's teardown is independent: closing the Headroom
    /// window must never drop updates for a still-open menu bar popover (or
    /// vice versa), and a leaked subscriber must be individually
    /// removable rather than tearing down every consumer's stream.
    private var subscribers: [UUID: AsyncStream<SystemSnapshot>.Continuation] = [:]

    private var configuration: Configuration
    private var localAuthority: LocalAuthoritySnapshot?
    private var requiresLocalAuthority = false
    private var authorityGeneration: UInt64 = 0
    private var configurationRevision: UInt64
    private var volumes: [URL]
    private let probe: SystemProbing
    private let pressureObserving: MemoryPressureObserving
    private let scheduling: MonitorScheduling
    private let instrumentation: MonitorInstrumentation
    private let clock: @Sendable () -> Date

    private var sceneLeases: Set<MonitorLease> = []
    private var sceneLeaseGenerations: [MonitorLease: UInt64] = [:]
    private var explicitWorkLeases: Set<MonitorLease> = []
    private var timerTask: Task<Void, Never>?
    private var pressureSubscription: MemoryPressureSubscription?
    private var pressureSubscriptionGeneration: UInt64 = 0
    private(set) var history: SignalHistory
    private var lastPageOutCounter: (boot: BootIdentity, count: UInt64, pageSizeBytes: UInt64, at: Date)?
    private var latestPressureLevel: MemoryPressureLevel?
    private var latestSnapshot: SystemSnapshot?
    private var broadcastCount: UInt64 = 0

    public init(configuration: Configuration = .disabled,
                configurationRevision: UInt64 = 0,
                volumes: [URL] = [URL(fileURLWithPath: "/")],
                probe: SystemProbing = LiveSystemProbe(),
                pressureObserving: MemoryPressureObserving = LiveMemoryPressureObserving(),
                scheduling: MonitorScheduling = SystemClockScheduling(),
                instrumentation: MonitorInstrumentation = NoOpMonitorInstrumentation(),
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.configurationRevision = configurationRevision
        self.volumes = volumes
        self.probe = probe
        self.pressureObserving = pressureObserving
        self.scheduling = scheduling
        self.instrumentation = instrumentation
        self.clock = clock
        self.history = SignalHistory(maxEntries: SystemMonitor.historyCapacity(forHours: configuration.historyHours),
            maxAgeSeconds: Double(configuration.historyHours) * 3_600)
        // Arms background sampling immediately when the supplied configuration
        // already calls for it (`featureEnabled && backgroundEnabled &&
        // !suppressHiddenSampling`), rather than leaving the monitor inert
        // until some window happens to open first. `AppExecutionServices`
        // constructs the app's one `SystemMonitor` with the resolved policy
        // at bootstrap specifically so "background monitoring" means what it
        // says: armed at launch, not merely armable. No-op (does not touch
        // `wasRunning`/`timerCancelled`, since nothing was running yet) when
        // the resolved configuration doesn't call for it. Hopped through a
        // task because an initializer is not yet inside this actor's
        // isolation, so it cannot call the isolated method directly.
        Task { await self.reschedule() }
    }

    /// Applies a freshly-resolved `EffectivePolicy` (or `.disabled`). Safe
    /// to call repeatedly, including every time settings change.
    public func applyConfiguration(_ newConfiguration: Configuration) {
        apply(newConfiguration)
    }

    @discardableResult
    public func applyConfiguration(_ newConfiguration: Configuration,
                                   acknowledgedRevision: UInt64) -> Bool {
        guard acknowledgedRevision >= configurationRevision else { return false }
        configurationRevision = acknowledgedRevision
        apply(newConfiguration)
        return true
    }

    /// Separate ordering domain: local consent can change without a settings write.
    /// The live snapshot also denies sampling during the persistence/observer gap.
    public func applyLocalAuthority(_ snapshot: LocalAuthoritySnapshot?, generation: UInt64) {
        guard generation > authorityGeneration else { return }
        authorityGeneration = generation
        requiresLocalAuthority = true
        localAuthority = snapshot?.isCurrent == true ? snapshot : nil
        reschedule()
    }

    private var maySampleInBackground: Bool {
        configuration.backgroundEnabled && !configuration.suppressHiddenSampling &&
            (!requiresLocalAuthority || localAuthority?.permits(.backgroundSignals) == true)
    }

    private func requestScheduledSnapshot() async {
        guard !sceneLeases.isEmpty || !explicitWorkLeases.isEmpty || maySampleInBackground else {
            reschedule()
            return
        }
        _ = await requestSnapshot()
    }

    private func apply(_ newConfiguration: Configuration) {
        let previous = configuration
        configuration = newConfiguration
        if !newConfiguration.featureEnabled {
            let snapshot = featureDisabledSnapshot()
            latestSnapshot = snapshot
            latestPressureLevel = nil
            broadcast(snapshot)
        }
        if !newConfiguration.historyEnabled {
            history = SignalHistory(maxEntries: 0, maxAgeSeconds: 0)
        } else if !previous.historyEnabled || previous.historyHours != newConfiguration.historyHours {
            history = SignalHistory(maxEntries: SystemMonitor.historyCapacity(forHours: newConfiguration.historyHours),
                maxAgeSeconds: Double(newConfiguration.historyHours) * 3_600)
        }
        // Even unchanged settings must recheck independently revocable local authority.
        reschedule()
    }

    public func setVolumes(_ volumes: [URL]) {
        self.volumes = volumes
    }

    public func acquireSceneLease(_ lease: MonitorLease) {
        guard sceneLeases.insert(lease).inserted else { return }
        reschedule()
    }

    public func releaseSceneLease(_ lease: MonitorLease) {
        guard sceneLeases.remove(lease) != nil else { return }
        reschedule()
    }

    public func updateSceneLease(_ lease: MonitorLease, visible: Bool,
                                 generation: UInt64) {
        guard generation >= (sceneLeaseGenerations[lease] ?? 0) else { return }
        sceneLeaseGenerations[lease] = generation
        let changed: Bool
        if visible { changed = sceneLeases.insert(lease).inserted }
        else { changed = sceneLeases.remove(lease) != nil }
        guard changed else { return }
        reschedule()
    }

    /// Terminal counterpart to `updateSceneLease`. Callers must serialize it after their earlier
    /// scene transitions (which `MonitorSceneLeaseController` does); once ordered, the generation
    /// can be removed instead of retained as a tombstone for the process lifetime.
    public func disposeSceneLease(_ lease: MonitorLease, generation: UInt64) {
        guard generation >= (sceneLeaseGenerations[lease] ?? 0) else { return }
        let changed = sceneLeases.remove(lease) != nil
        sceneLeaseGenerations.removeValue(forKey: lease)
        if changed { reschedule() }
    }

    @discardableResult
    public func requestSnapshot(forScene lease: MonitorLease,
                                generation: UInt64) async -> SystemSnapshot? {
        guard sceneLeaseGenerations[lease] == generation,
              sceneLeases.contains(lease) else { return nil }
        return await requestSnapshot()
    }

    public func acquireExplicitWorkLease(_ lease: MonitorLease) {
        guard explicitWorkLeases.insert(lease).inserted else { return }
        reschedule()
    }

    public func releaseExplicitWorkLease(_ lease: MonitorLease) {
        guard explicitWorkLeases.remove(lease) != nil else { return }
        reschedule()
    }

    /// An explicit, one-shot measurement that still honors the master
    /// feature restriction. Opening Headroom is not background consent, and
    /// disabling Headroom makes this return unavailable without probing.
    @discardableResult
    public func requestSnapshot() async -> SystemSnapshot {
        guard configuration.featureEnabled else {
            let snapshot = featureDisabledSnapshot()
            latestSnapshot = snapshot
            broadcast(snapshot)
            return snapshot
        }
        let snapshot = await measure()
        latestSnapshot = snapshot
        broadcast(snapshot)
        return snapshot
    }

    private func featureDisabledSnapshot() -> SystemSnapshot {
        SystemSnapshot(observedAt: clock(), bootIdentity: nil,
            volumes: [], memory: nil, memoryUnavailableReason: Self.featureDisabledReason,
            swap: nil, swapUnavailableReason: Self.featureDisabledReason,
            pageOutRatePerSecond: nil, memoryPressureLevel: nil, thermalState: nil,
            isLowPowerModeEnabled: nil, unavailableReason: Self.featureDisabledReason)
    }

    /// A dedicated stream for ONE consumer. Every caller -- the menu bar
    /// popover, the Headroom window, a future second window -- must call
    /// this separately rather than sharing one stream: a shared stream
    /// with multiple concurrent iterators races over which one drains a
    /// given value out of `.bufferingNewest(1)`, silently starving the
    /// others. Cancelling the `Task` that iterates the returned stream (or
    /// letting it, and everything holding it, go out of scope) is enough to
    /// tear this subscription down -- `onTermination` removes it from
    /// `subscribers` here, so a torn-down consumer can never leak a
    /// permanently-registered continuation.
    public func subscribe() -> AsyncStream<SystemSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SystemSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id) }
        }
        // `subscribe()` and a scene's first explicit snapshot request are launched from separate
        // tasks. If publication wins that race, replay the actor-owned latest value into this
        // subscriber's one-element buffer so the scene cannot remain blank until another timer or
        // external signal happens to publish. This starts no probe, timer, or background work.
        if let latestSnapshot { continuation.yield(latestSnapshot) }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    public func recordedHistory() -> [SystemSnapshot] {
        history.entries
    }

    /// Test-only visibility into whether the repeating loop currently
    /// exists, independent of the instrumentation counters. `public`
    /// (rather than `internal`+`@testable`) so app-layer regression tests
    /// -- e.g. `TidyAppModelTests`, which deliberately consumes only
    /// `TidyCore`'s public surface -- can assert this directly against
    /// real `HeadroomViewModel`/`StatsRefresher` instances.
    public func isTimerRunningForTesting() -> Bool {
        timerTask != nil
    }

    public func activeSceneLeaseCountForTesting() -> Int { sceneLeases.count }
    public func sceneLeaseGenerationCountForTesting() -> Int { sceneLeaseGenerations.count }
    public func activeExplicitWorkLeaseCountForTesting() -> Int { explicitWorkLeases.count }
    public func appliedConfigurationRevisionForTesting() -> UInt64 { configurationRevision }
    public func latestPressureLevelForTesting() -> MemoryPressureLevel? { latestPressureLevel }
    public func latestSnapshotForTesting() -> SystemSnapshot? { latestSnapshot }
    public func broadcastCountForTesting() -> UInt64 { broadcastCount }

    /// Test-only visibility into how many live subscriptions are currently
    /// registered, so a leak (or a successful teardown) is directly
    /// assertable rather than inferred from side effects. `public` for the
    /// same cross-module-regression-test reason as
    /// `isTimerRunningForTesting()`.
    public func subscriberCountForTesting() -> Int {
        subscribers.count
    }

    public func stop() {
        timerTask?.cancel()
        timerTask = nil
        pressureSubscription?.cancel()
        pressureSubscription = nil
        pressureSubscriptionGeneration &+= 1
        latestPressureLevel = nil
        lastPageOutCounter = nil
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
        sceneLeases.removeAll()
        sceneLeaseGenerations.removeAll()
        explicitWorkLeases.removeAll()
    }

    private static func historyCapacity(forHours hours: Int) -> Int {
        // One sample per minute is the densest cadence policy allows
        // (`monitor.hiddenIntervalSeconds` floors at 60); this is a coarse
        // upper bound, not a promise of that exact density.
        max(0, hours) * 60
    }

    /// Starts, restarts, or tears down the repeating loop based on the
    /// current configuration and activity leases. Called after every
    /// configuration or visibility change; safe to call when nothing needs
    /// to change.
    ///
    /// `timerScheduled()`/`timerCancelled()` are NOT called 1:1 by design:
    /// a config change while already running (e.g. the interval changing)
    /// cancels the old `Task` and starts a new one without reporting a
    /// cancel for the old one -- the loop never stopped from the caller's
    /// point of view, only its cadence changed. `timerCancelled()` fires
    /// only on the true off transition (`shouldRun` becoming `false`).
    /// Tests should assert "scheduled at least once" / "cancelled at least
    /// once", not that the two counters stay in lockstep.
    private func reschedule() {
        let foregroundOrExplicit = !sceneLeases.isEmpty || !explicitWorkLeases.isEmpty
        let shouldRun = configuration.featureEnabled &&
            (foregroundOrExplicit ||
             maySampleInBackground)

        timerTask?.cancel()
        let wasRunning = timerTask != nil
        timerTask = nil

        guard shouldRun else {
            if wasRunning {
                instrumentation.timerCancelled()
            }
            pressureSubscription?.cancel()
            pressureSubscription = nil
            pressureSubscriptionGeneration &+= 1
            latestPressureLevel = nil
            lastPageOutCounter = nil
            return
        }

        if pressureSubscription == nil {
            pressureSubscriptionGeneration &+= 1
            let generation = pressureSubscriptionGeneration
            pressureSubscription = pressureObserving.start { [weak self] level in
                guard let self else { return }
                Task { await self.updatePressureLevel(level, generation: generation) }
            }
        }

        let interval = foregroundOrExplicit
            ? configuration.visibleIntervalSeconds : configuration.hiddenIntervalSeconds
        instrumentation.timerScheduled()
        // Sleeps BEFORE the first probe rather than after: `setWindowVisible`/
        // `applyConfiguration` (called from onAppear) already pair with one
        // explicit `requestSnapshot()` from the caller. Probing again here on
        // the very first loop iteration would fire two probes for one
        // window/popover open; sleeping first means the loop's first probe
        // doesn't land until a full interval after the explicit one.
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await self.scheduling.sleep(seconds: interval) }
                catch { break }
                guard !Task.isCancelled else { break }
                await self.requestScheduledSnapshot()
            }
        }
    }

    private func updatePressureLevel(_ level: MemoryPressureLevel, generation: UInt64) {
        guard generation == pressureSubscriptionGeneration,
              pressureSubscription != nil, configuration.featureEnabled,
              !sceneLeases.isEmpty || !explicitWorkLeases.isEmpty || maySampleInBackground
        else { return }
        latestPressureLevel = level
        let snapshot: SystemSnapshot
        if let cached = latestSnapshot {
            snapshot = SystemSnapshot(observedAt: cached.observedAt,
                bootIdentity: cached.bootIdentity, volumes: cached.volumes,
                memory: cached.memory, memoryUnavailableReason: cached.memoryUnavailableReason,
                swap: cached.swap, swapUnavailableReason: cached.swapUnavailableReason,
                pageOutRatePerSecond: cached.pageOutRatePerSecond,
                memoryPressureLevel: level, thermalState: cached.thermalState,
                isLowPowerModeEnabled: cached.isLowPowerModeEnabled,
                unavailableReason: cached.unavailableReason)
        } else {
            snapshot = SystemSnapshot(observedAt: clock(), bootIdentity: nil, volumes: [],
                memory: nil, memoryUnavailableReason: "Awaiting scheduled measurement",
                swap: nil, swapUnavailableReason: "Awaiting scheduled measurement",
                pageOutRatePerSecond: nil, memoryPressureLevel: level, thermalState: nil,
                isLowPowerModeEnabled: nil)
        }
        latestSnapshot = snapshot
        broadcast(snapshot)
    }

    private func broadcast(_ snapshot: SystemSnapshot) {
        broadcastCount &+= 1
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    private func measure() async -> SystemSnapshot {
        let observedAt = clock()
        let boot = try? probe.bootIdentity()

        var volumeObservations: [VolumeObservation] = []
        for url in volumes {
            do {
                let disk = try probe.diskStats(volumeURL: url)
                volumeObservations.append(VolumeObservation(
                    volumeIdentity: disk.volumeIdentifier ?? url.path,
                    displayPath: url.path, disk: disk))
            } catch {
                volumeObservations.append(VolumeObservation(
                    volumeIdentity: url.path, displayPath: url.path, disk: nil,
                    unavailableReason: String(describing: error)))
            }
        }

        var memory: MemoryStats?
        var memoryReason: String?
        do { memory = try probe.memoryStats() } catch { memoryReason = String(describing: error) }

        var swap: SwapStats?
        var swapReason: String?
        do { swap = try probe.swapStats() } catch { swapReason = String(describing: error) }

        let pageOutRate = updatePageOutRate(boot: boot, observedAt: observedAt)

        let snapshot = SystemSnapshot(observedAt: observedAt, bootIdentity: boot, volumes: volumeObservations,
            memory: memory, memoryUnavailableReason: memoryReason, swap: swap, swapUnavailableReason: swapReason,
            pageOutRatePerSecond: pageOutRate, memoryPressureLevel: latestPressureLevel,
            thermalState: probe.thermalState(), isLowPowerModeEnabled: probe.isLowPowerModeEnabled())

        if configuration.historyEnabled {
            history.record(snapshot, now: observedAt)
        }
        return snapshot
    }

    /// The one place `counterRate` is applied to the live swap-out counter.
    /// A changed boot identity between samples is treated exactly like a
    /// reset: no rate this tick, and the new boot/count pair becomes the
    /// baseline for the next one.
    private func updatePageOutRate(boot: BootIdentity?, observedAt: Date) -> Double? {
        guard let boot, let counter = try? probe.swapPageOutCounter() else {
            lastPageOutCounter = nil
            return nil
        }
        defer {
            lastPageOutCounter = (boot: boot, count: counter.count, pageSizeBytes: counter.pageSizeBytes, at: observedAt)
        }
        guard let last = lastPageOutCounter, last.boot == boot else { return nil }
        let elapsed = observedAt.timeIntervalSince(last.at)
        guard let pagesPerSecond = counterRate(before: last.count, after: counter.count, seconds: elapsed) else {
            return nil
        }
        return pagesPerSecond * Double(counter.pageSizeBytes)
    }
}
