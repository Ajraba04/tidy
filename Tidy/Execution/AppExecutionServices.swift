import Foundation
import Observation
import TidyCore

struct AppStoragePaths: Sendable {
    let home: URL
    let settings: URL
    let journal: URL
}

enum AppBootstrapStage: String, Sendable {
    case beforeSettingsLoad, afterSettingsLoad
    case beforeCoordinatorConstruction, afterCoordinatorConstruction
}

/// Thrown by `AppExecutionServices.beginScan` when the T08.1b scheduler façade could not install
/// a valid policy, such as recovery-read-only settings, rather than merely being busy or paused.
enum ScanAvailabilityError: Error, Equatable {
    case policyNotInstalled
}

enum AppScanRequest: Sendable {
    case policyDefault
    case fullHome(FullHomeScanConsent)
}

enum AppScanLifecycleEvent: Equatable, Sendable {
    case startReserved
    case cleanupDetached(UUID)
    case continuationSuspensionStarted
}

private struct AppScanObservationResources: Sendable {
    let id: UUID
    let lease: MonitorLease
    let task: Task<Void, Never>
}

private final class AppScanGenerationResources: @unchecked Sendable {
    let id = UUID()
    let session: WorkSession
    let index: ScanIndexCoordinator?
    var observation: AppScanObservationResources?
    var awaitingManualContinuation = false
    var continuationInvalidated = false
    var suspension: (id: UUID, task: Task<Void, Never>)?
    var cleanupClaimed = false

    init(session: WorkSession, index: ScanIndexCoordinator?,
         observation: AppScanObservationResources) {
        self.session = session
        self.index = index
        self.observation = observation
    }
}

func schedulerLiveObservation(from snapshot: SystemSnapshot) -> SchedulerLiveObservation {
    if snapshot.unavailableReason != nil { return .unknown }
    if snapshot.memoryPressureLevel == .critical || snapshot.thermalState == .critical {
        return .critical
    }
    if snapshot.memoryPressureLevel == .warning { return .constrained }
    if snapshot.thermalState == .serious || snapshot.isLowPowerModeEnabled == true {
        return .signals(lowPower: snapshot.isLowPowerModeEnabled ?? true,
            seriousThermal: snapshot.thermalState.map { $0 == .serious || $0 == .critical } ?? true)
    }
    if snapshot.memoryPressureLevel == .normal, snapshot.thermalState != nil,
       snapshot.isLowPowerModeEnabled == false {
        return .nominal
    }
    return .unknown
}

private struct AppBootstrapWorkerResult: Sendable {
    let load: SettingsLoadResult
    let settingsBootstrap: SettingsSchedulerBootstrap
    let coordinator: ExecutionCoordinator
    let journalAdmission: MutationAdmission
}

private struct AppConfirmedExecution: Sendable {
    let id: UUID
    let binding: ReviewBinding
    let task: Task<RunReport, Error>
    let completion: AppExecutionCompletionLatch
}

private final class AppExecutionCompletionLatch: @unchecked Sendable {
    private struct Waiter {
        let continuation: CheckedContinuation<Bool, Never>
        let timeout: DispatchWorkItem
    }
    private let lock = NSLock()
    private var completed = false
    private var waiters: [UUID: Waiter] = [:]

    func finish() {
        let pending: [Waiter] = lock.withLock {
            guard !completed else { return [] }
            completed = true
            let values = Array(waiters.values)
            waiters.removeAll()
            return values
        }
        for waiter in pending {
            waiter.timeout.cancel()
            waiter.continuation.resume(returning: true)
        }
    }

    func wait(timeout: Duration) async -> Bool {
        let seconds = Self.seconds(timeout)
        return await withCheckedContinuation { continuation in
            let id = UUID()
            let timeoutWork = DispatchWorkItem { [weak self] in self?.timeout(id) }
            let resumeNow = lock.withLock { () -> Bool in
                if completed { return true }
                waiters[id] = Waiter(continuation: continuation, timeout: timeoutWork)
                return false
            }
            if resumeNow {
                continuation.resume(returning: true)
            } else {
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + seconds, execute: timeoutWork)
            }
        }
    }

    private func timeout(_ id: UUID) {
        let waiter = lock.withLock { waiters.removeValue(forKey: id) }
        waiter?.continuation.resume(returning: false)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return max(0, Double(components.seconds)
            + Double(components.attoseconds) / 1e18)
    }
}

enum AppExecutionDrainResult: Equatable, Sendable {
    case noExecution
    case completed
    case durablyUncertain
}

/// Synchronous, Sendable lifetime state shared by the service and its
/// escaping monitor callbacks. Closing it in ordinary `deinit` prevents a
/// still-registered callback from starting new work while main-actor observer
/// removal is queued.
private final class AppMonitoringLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    func dispose() {
        lock.lock(); active = false; lock.unlock()
    }
}

@Observable @MainActor
final class AppExecutionServices {
    let paths: AppStoragePaths
    let settings: SettingsStore
    let settingsLoad: SettingsLoadResult
    let initialJournalAdmission: MutationAdmission
    let coordinator: ExecutionCoordinator
    let policyBridge: ExecutionPolicyBridge
    let configStore: AppConfigStore
    let engine: CleanEngine
    let runLogURL: URL
    let optionalRunHistory: OptionalRunHistoryStore?
    private(set) var historyPersistenceError: String?
    /// The app's one T10 headroom monitor, constructed once at bootstrap.
    /// Every window that shows disk/memory/swap/thermal/power signals
    /// (menu bar popover, Headroom window) observes this shared instance
    /// rather than owning a probe or a timer of its own.
    let systemMonitor: SystemMonitor
    /// These three fields are accessed from ordinary nonisolated `deinit`.
    /// The task and UUID are Sendable; the lifetime is internally locked.
    @ObservationIgnored private let monitoringLifetime = AppMonitoringLifetime()
    @ObservationIgnored nonisolated(unsafe) private var monitorPolicyObserverToken: UUID?
    @ObservationIgnored nonisolated(unsafe) private var monitorVolumeObservationTask:
        Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var executionProgressTask:
        Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var confirmedExecution:
        AppConfirmedExecution?
    private(set) var executionProgress: ExecutionProgressSnapshot?
    private(set) var liveRecoveryAdmission: MutationAdmission
    private(set) var lastRecoveryReport: RecoveryReconciliationReport?

    /// The app's one T08.2 session registry, constructed once at bootstrap. It starts no work;
    /// `beginScan` is the only route that registers and launches a session against it.
    let scanRegistry = ScanSessionRegistry()
    /// Opaque scope grants and expiring full-home consent are shared across every scene.
    @ObservationIgnored private lazy var scanScopeAuthority = ScanScopeAuthority(bridge: policyBridge,
        homeDirectory: paths.home.path)
    @ObservationIgnored private let scanLifecycleHook:
        (@Sendable (AppScanLifecycleEvent) async -> Void)?
    @ObservationIgnored private let scanTraversalLimits: TraversalLimits?
    @ObservationIgnored private var acceptedScanObservationID: UUID?
    @ObservationIgnored private var scanTransition:
        (id: UUID, task: Task<CoreScanHandle, Error>)?
    @ObservationIgnored private var scanCleanup: (id: UUID, task: Task<Void, Never>)?
    private var scanObservationEpoch: UInt64 = 0
    /// The active scan's session ID, if any, kept here (not on a per-window view model) so the
    /// menu-bar/global Cancel affordance survives that window closing.
    private(set) var activeScanSessionID: UUID?
    private var activeScanHandle: CoreScanHandle?
    private var retainedScanHandles: [UUID: CoreScanHandle] = [:]
    private var retainedScanHandleOrder: [UUID] = []
    private var activeScanResources: AppScanGenerationResources?
    private var retainedScanIndex: (cacheMiB: Int64, expiryHours: Int64,
                                    coordinator: ScanIndexCoordinator)?

    private init(paths: AppStoragePaths, settings: SettingsStore,
                 worker: AppBootstrapWorkerResult,
                 scanLifecycleHook: (@Sendable (AppScanLifecycleEvent) async -> Void)?,
                 scanTraversalLimits: TraversalLimits? = nil) {
        self.paths = paths
        self.settings = settings
        self.settingsLoad = worker.load
        self.initialJournalAdmission = worker.journalAdmission
        self.liveRecoveryAdmission = worker.journalAdmission
        self.coordinator = worker.coordinator
        self.scanLifecycleHook = scanLifecycleHook
        self.scanTraversalLimits = scanTraversalLimits
        let envelope = worker.load.envelope ?? SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: TidyConfig(schemaVersion: 2))
        self.policyBridge = ExecutionPolicyBridge(coordinator: worker.coordinator,
            settings: settings, bootstrap: worker.settingsBootstrap,
            homeDirectory: paths.home.path,
            detectedTools: [])
        self.configStore = AppConfigStore(loaded: envelope, bridge: policyBridge)
        self.engine = CleanEngine(sizeScanner: SizeScanner())
        let runLogURL = paths.journal.deletingLastPathComponent().appendingPathComponent("runs.jsonl")
        self.runLogURL = runLogURL
        self.optionalRunHistory = try? OptionalRunHistoryStore(
            directory: runLogURL.deletingLastPathComponent())
        #if TIDY_RUNTIME_TEST_HOST
        let monitorInstrumentation: any MonitorInstrumentation =
            RuntimeObservationCoordinator.monitorInstrumentation
        #else
        let monitorInstrumentation: any MonitorInstrumentation = NoOpMonitorInstrumentation()
        #endif
        self.systemMonitor = SystemMonitor(
            configuration: .resolve(self.configStore.effectivePolicy),
            configurationRevision: envelope.revision,
            volumes: [paths.home],
            instrumentation: monitorInstrumentation)
        let monitor = self.systemMonitor
        let configStore = self.configStore
        let optionalRunHistory = self.optionalRunHistory
        let monitoringLifetime = self.monitoringLifetime
        self.monitorPolicyObserverToken = configStore.observeAcknowledgedPolicy { [weak self] revision, policy in
            guard monitoringLifetime.isActive else { return }
            let configuration = SystemMonitor.Configuration.resolve(policy)
            let historyPolicy = OptionalRunHistoryPolicy.resolve(policy)
            Task { @MainActor [weak self] in
                guard monitoringLifetime.isActive else { return }
                let applied = await monitor.applyConfiguration(configuration,
                    acknowledgedRevision: revision)
                guard monitoringLifetime.isActive, applied else { return }
                if let optionalRunHistory {
                    do {
                        _ = try await optionalRunHistory.reconcile(policy: historyPolicy,
                            acknowledgedRevision: revision)
                        guard monitoringLifetime.isActive,
                              self?.configStore.acknowledgedSettingsRevision == revision else { return }
                        self?.historyPersistenceError = nil
                    } catch {
                        guard monitoringLifetime.isActive,
                              self?.configStore.acknowledgedSettingsRevision == revision else { return }
                        self?.historyPersistenceError =
                            "Optional run history could not apply revision \(revision): \(error)"
                    }
                } else if monitoringLifetime.isActive {
                    self?.historyPersistenceError = "Optional run history storage is unavailable."
                }
            }
        }
        self.monitorVolumeObservationTask = Task { @MainActor [weak configStore] in
            let stream = await monitor.subscribe()
            var observationEpoch: UInt64 = 0
            for await snapshot in stream {
                guard monitoringLifetime.isActive, let configStore,
                      !Task.isCancelled else { break }
                let (nextEpoch, overflow) = observationEpoch.addingReportingOverflow(1)
                guard !overflow else { break }
                observationEpoch = nextEpoch
                let disk = snapshot.volumes.first?.disk
                configStore.updateSelectedVolume(identity: disk?.volumeIdentifier,
                    capacityBytes: disk?.totalBytes, observationEpoch: observationEpoch)
            }
        }
        let executionCoordinator = self.coordinator
        self.executionProgressTask = Task { @MainActor [weak self, executionCoordinator] in
            let updates = await executionCoordinator.progressUpdates()
            for await snapshot in updates {
                guard let self, !Task.isCancelled else { break }
                self.executionProgress = snapshot
                self.liveRecoveryAdmission = snapshot.recovery
            }
        }
    }

    deinit {
        // Close callbacks and cancel the Sendable task synchronously. Observer
        // removal must execute on MainActor; capture values only, never `self`.
        monitoringLifetime.dispose()
        monitorVolumeObservationTask?.cancel()
        executionProgressTask?.cancel()
        confirmedExecution?.task.cancel()
        coordinator.cancelCurrentRun()
        guard let token = monitorPolicyObserverToken else { return }
        let configStore = configStore
        Task { @MainActor in
            configStore.removeAcknowledgedPolicyObserver(token)
        }
    }

    /// Ends only the long-lived R08 monitoring bindings owned by this service.
    /// Scan observation and index lifetimes are separate generation resources.
    func disposeMonitoring() {
        monitoringLifetime.dispose()
        monitorVolumeObservationTask?.cancel()
        monitorVolumeObservationTask = nil
        if let token = monitorPolicyObserverToken {
            configStore.removeAcknowledgedPolicyObserver(token)
            monitorPolicyObserverToken = nil
        }
    }

    /// The sole T08.1b bounded explicit-session façade this app consumes. No alternate
    /// scheduler/session authority is created anywhere in the app layer.
    var explicitSessions: BridgeExplicitSessions { policyBridge.explicitSessions }

    /// Begins (or attaches nothing — always a fresh session/generation) one explicit T08.4 scan
    /// against the shared registry and this app's one explicit-session façade. The session this
    /// call opens is released automatically once the registered work reaches a terminal state,
    /// independent of any window's subscription lifetime, so a closed Scan window never strands
    /// (or prematurely finishes) the running scan.
    ///
    /// This call awaits the initial scheduler install. Exact in-memory defaults from a missing
    /// settings file may install read-only explicit-scan policy; recovery, malformed, migrated,
    /// and arbitrary stored revision-zero documents remain unavailable. If installation is still
    /// unavailable, this throws rather than silently starting nothing.
    func issueFullHomeScanConsent(ownerID: UUID) throws -> FullHomeScanConsent {
        try scanScopeAuthority.issueFullHomeConsent(ownerID: ownerID)
    }

    func authorizeProjectScope(ownerID: UUID,
                               localAuthority: LocalAuthoritySnapshot? = nil) throws
        -> AuthorizedScanScope {
        try scanScopeAuthority.authorizeProjects(ownerID: ownerID,
                                                 localAuthority: localAuthority)
    }

    func beginScan(environment: CleanEnvironment, request: AppScanRequest = .policyDefault,
                   ownerID: UUID) async throws -> CoreScanHandle {
        if let scanTransition { return try await resolveScanTransition(scanTransition) }
        if let scanCleanup { await resolveScanCleanup(scanCleanup) }
        if let activeScanSessionID, let activeScanHandle,
           activeScanHandle.sessionID == activeScanSessionID,
           let activeState = try? await scanRegistry.state(sessionID: activeScanSessionID) {
            if activeState.terminal == nil { return activeScanHandle }
            if (await activeScanHandle.latestResult())?.continuationAvailable == true {
                return activeScanHandle
            }
        }
        if let scanCleanup { await resolveScanCleanup(scanCleanup) }
        let transitionID = UUID()
        let task = Task { @MainActor [self] in
            await scanLifecycleHook?(.startReserved)
            return try await beginReservedScan(environment: environment, request: request,
                ownerID: ownerID)
        }
        let transition = (id: transitionID, task: task)
        scanTransition = transition
        return try await resolveScanTransition(transition)
    }

    private func resolveScanTransition(
        _ transition: (id: UUID, task: Task<CoreScanHandle, Error>)
    ) async throws -> CoreScanHandle {
        do {
            let handle = try await transition.task.value
            if scanTransition?.id == transition.id { scanTransition = nil }
            return handle
        } catch {
            if scanTransition?.id == transition.id { scanTransition = nil }
            throw error
        }
    }

    private func beginReservedScan(environment: CleanEnvironment, request: AppScanRequest,
                                   ownerID: UUID) async throws -> CoreScanHandle {
        await explicitSessions.awaitInitialInstall()
        guard await explicitSessions.snapshot().availability == .available else {
            throw ScanAvailabilityError.policyNotInstalled
        }
        let authorization: AuthorizedScanScope
        switch request {
        case .policyDefault:
            authorization = try scanScopeAuthority.authorizePolicyDefault(ownerID: ownerID)
        case .fullHome(let consent):
            authorization = try scanScopeAuthority.authorizeFullHome(
                consent: consent, ownerID: ownerID)
        }
        let session = try await explicitSessions.beginSession(
            requirements: try SchedulerRequirements(features: [.headroom]))
        var observation: AppScanObservationResources?
        var indexCoordinator: ScanIndexCoordinator?
        do {
            observation = await startScanObservation()
            indexCoordinator = try await makeScanIndexCoordinator(
                authorization: authorization)
            let handle = try await ScanEngine.start(environment: environment,
                authorization: authorization, ownerID: ownerID, registry: scanRegistry,
                sessions: explicitSessions, session: session,
                traversalLimits: scanTraversalLimits,
                dormantContinuationSupported: indexCoordinator != nil,
                indexCoordinator: indexCoordinator)
            guard let observation else { throw CoreOrchestrationError.schedulerUnavailable }
            let resources = AppScanGenerationResources(session: session,
                index: indexCoordinator, observation: observation)
            activeScanSessionID = handle.sessionID
            activeScanHandle = handle
            retainScanHandle(handle)
            activeScanResources = resources
            trackScanSessionLifetime(sessionID: handle.sessionID, resources: resources)
            return handle
        } catch {
            await indexCoordinator?.stopWatching()
            if let observation { await stopScanObservation(observation) }
            await explicitSessions.finish(session: session)
            throw error
        }
    }

    /// The latest cumulative result for `sessionID`, if it is still the app's current scan.
    func latestScanResult(sessionID: UUID) async -> CoreScanResult? {
        if let activeScanHandle, activeScanHandle.sessionID == sessionID {
            return await activeScanHandle.latestResult()
        }
        return await retainedScanHandles[sessionID]?.latestResult()
    }

    func continueActiveScan() async throws -> CoreScanHandle {
        if let scanTransition { return try await resolveScanTransition(scanTransition) }
        let transitionID = UUID()
        let task = Task { @MainActor [self] in
            if let scanCleanup { await resolveScanCleanup(scanCleanup) }
            guard let activeScanHandle, let resources = activeScanResources,
                  (await activeScanHandle.latestResult())?.continuationAvailable == true else {
                throw CoreOrchestrationError.invalidScopeAuthorization
            }
            await suspendScanGenerationForManualContinuation(resources)
            if let suspension = resources.suspension {
                await resolveScanSuspension(suspension, resources: resources)
            }
            guard !resources.cleanupClaimed,
                  !resources.continuationInvalidated,
                  (await activeScanHandle.latestResult())?.continuationAvailable == true else {
                if resources.continuationInvalidated {
                    await cleanupScanGeneration(resources,
                        terminalSessionID: activeScanHandle.sessionID,
                        cancelSchedulerSession: true)
                }
                throw CoreOrchestrationError.invalidScopeAuthorization
            }
            do {
                var watchGuard: ScanContinuationWatchGuard?
                if resources.awaitingManualContinuation {
                    guard let index = resources.index,
                          let resumedGuard = await index.resumeWatchingForManualContinuation() else {
                        await activeScanHandle.discardContinuation()
                        throw CoreOrchestrationError.invalidScopeAuthorization
                    }
                    watchGuard = resumedGuard
                    resources.observation = await startScanObservation()
                    resources.awaitingManualContinuation = false
                }
                let handle = try await ScanEngine.continueScan(from: activeScanHandle,
                    registry: scanRegistry, watchGuard: watchGuard)
                guard activeScanResources === resources, !resources.cleanupClaimed else {
                    throw CoreOrchestrationError.foreignOrFinishedSession
                }
                activeScanSessionID = handle.sessionID
                self.activeScanHandle = handle
                retainScanHandle(handle)
                trackScanSessionLifetime(sessionID: handle.sessionID, resources: resources)
                return handle
            } catch {
                await cleanupScanGeneration(resources,
                    terminalSessionID: activeScanHandle.sessionID,
                    cancelSchedulerSession: true)
                throw error
            }
        }
        let transition = (id: transitionID, task: task)
        scanTransition = transition
        return try await resolveScanTransition(transition)
    }

    private func retainScanHandle(_ handle: CoreScanHandle) {
        retainedScanHandles[handle.sessionID] = handle
        retainedScanHandleOrder.append(handle.sessionID)
        while retainedScanHandleOrder.count > 16 {
            retainedScanHandles.removeValue(forKey: retainedScanHandleOrder.removeFirst())
        }
    }

    /// Cancels the active scan by session ID only — this never signals, cancels, or releases a
    /// T04 mutator, and remains reachable from the global/menu owner after every window closes.
    func cancelActiveScan() async {
        guard let sessionID = activeScanSessionID else { return }
        if let state = try? await scanRegistry.state(sessionID: sessionID),
           state.terminal != nil {
            guard let resources = activeScanResources else { return }
            await cleanupScanGeneration(resources, terminalSessionID: sessionID,
                cancelSchedulerSession: true)
        } else {
            try? await scanRegistry.cancel(sessionID: sessionID)
        }
    }

    /// Releases the scheduler-level session exactly once the registered work reaches a terminal
    /// state, independent of any UI subscriber. This is a dedicated internal subscription, not
    /// the one any `ScanViewModel` observes.
    private func trackScanSessionLifetime(sessionID: UUID,
                                          resources: AppScanGenerationResources) {
        let registry = scanRegistry
        Task { [weak self] in
            var terminal: ScanSessionTerminal?
            if let subscription = try? await registry.subscribe(sessionID: sessionID) {
                for await event in subscription.stream where event.terminal != nil {
                    terminal = event.terminal
                    break
                }
            }
            if terminal == .partial, let self,
               self.activeScanResources === resources {
                if self.activeScanSessionID != sessionID { return }
                if (await self.activeScanHandle?.latestResult())?.continuationAvailable == true {
                    await self.suspendScanGenerationForManualContinuation(resources)
                    if resources.continuationInvalidated {
                        await self.cleanupScanGeneration(resources,
                            terminalSessionID: sessionID, cancelSchedulerSession: true)
                    }
                    return
                }
            }
            guard let self else { return }
            await self.cleanupScanGeneration(resources, terminalSessionID: sessionID,
                cancelSchedulerSession: false)
        }
    }

    private func suspendScanGenerationForManualContinuation(
        _ resources: AppScanGenerationResources
    ) async {
        if let suspension = resources.suspension {
            await resolveScanSuspension(suspension, resources: resources)
            return
        }
        guard activeScanResources === resources, !resources.cleanupClaimed else { return }
        if resources.awaitingManualContinuation { return }
        resources.awaitingManualContinuation = true
        let suspensionID = UUID()
        let task = Task { @MainActor [self] in
            await scanLifecycleHook?(.continuationSuspensionStarted)
            let continuationIsSafe = if let index = resources.index {
                await index.suspendWatchingForManualContinuation()
            } else {
                false
            }
            if !continuationIsSafe {
                await activeScanHandle?.discardContinuation()
                resources.continuationInvalidated = true
            }
            if let observation = resources.observation {
                await stopScanObservation(observation)
                resources.observation = nil
            }
        }
        let suspension = (id: suspensionID, task: task)
        resources.suspension = suspension
        await resolveScanSuspension(suspension, resources: resources)
    }

    private func resolveScanSuspension(_ suspension: (id: UUID, task: Task<Void, Never>),
                                       resources: AppScanGenerationResources) async {
        await suspension.task.value
        if resources.suspension?.id == suspension.id { resources.suspension = nil }
    }

    private func cleanupScanGeneration(_ resources: AppScanGenerationResources,
                                       terminalSessionID: UUID,
                                       cancelSchedulerSession: Bool) async {
        if let suspension = resources.suspension {
            await resolveScanSuspension(suspension, resources: resources)
        }
        guard !resources.cleanupClaimed else { return }
        resources.cleanupClaimed = true
        if activeScanResources === resources {
            self.activeScanSessionID = nil
            self.activeScanHandle = nil
            self.activeScanResources = nil
        }
        let cleanupID = UUID()
        let task = Task { @MainActor [self] in
            if cancelSchedulerSession {
                await explicitSessions.cancel(session: resources.session)
            }
            await explicitSessions.finish(session: resources.session)
            await scanLifecycleHook?(.cleanupDetached(terminalSessionID))
            await resources.index?.stopWatching()
            if let observation = resources.observation {
                await stopScanObservation(observation)
                resources.observation = nil
            }
        }
        let cleanup = (id: cleanupID, task: task)
        scanCleanup = cleanup
        await resolveScanCleanup(cleanup)
    }

    private func resolveScanCleanup(_ cleanup: (id: UUID, task: Task<Void, Never>)) async {
        await cleanup.task.value
        if scanCleanup?.id == cleanup.id { scanCleanup = nil }
    }

    private func makeScanIndexCoordinator(authorization: AuthorizedScanScope) async throws
      -> ScanIndexCoordinator? {
        guard !authorization.roots.isEmpty else { return nil }
        let policy = configStore.acknowledgedEffectivePolicy
        guard case .stored(.bool(true))? = policy?.fields[
            SettingID(rawValue: "scan.cacheEnabled")]?.value else {
            await retainedScanIndex?.coordinator.stopWatching()
            retainedScanIndex = nil
            return nil
        }
        guard case .stored(.integer(let cacheMiB))? = policy?.fields[
            SettingID(rawValue: "scan.cacheMiB")]?.value,
              case .stored(.integer(let expiryHours))? = policy?.fields[
                SettingID(rawValue: "scan.cacheExpiryHours")]?.value,
              cacheMiB > 0, expiryHours > 0 else { return nil }
        let identities = authorization.roots.compactMap(ScanRootIdentity.resolve(path:))
        guard identities.count == authorization.roots.count,
              let volumeUUID = identities.first?.volumeUUID,
              identities.allSatisfy({ $0.volumeUUID == volumeUUID }) else { return nil }
        let (capBytes, capOverflow) = cacheMiB.multipliedReportingOverflow(by: 1_048_576)
        let (expirySeconds, expiryOverflow) = expiryHours.multipliedReportingOverflow(by: 3_600)
        guard !capOverflow, !expiryOverflow else { return nil }
        if let retainedScanIndex,
           retainedScanIndex.cacheMiB == cacheMiB,
           retainedScanIndex.expiryHours == expiryHours {
            await retainedScanIndex.coordinator.startWatching(
                approvedRoots: authorization.roots, volumeUUID: volumeUUID)
            return retainedScanIndex.coordinator
        }
        await retainedScanIndex?.coordinator.stopWatching()
        let databaseURL = paths.journal.deletingLastPathComponent()
            .appendingPathComponent("scan-index", isDirectory: true)
            .appendingPathComponent("cache.sqlite")
        let store: ScanIndexStore
        do { store = try ScanIndexStore.openAppOwned(databaseURL: databaseURL) }
        catch ScanIndexError.corrupted {
            store = try ScanIndexStore.recoverAppOwned(databaseURL: databaseURL)
        }
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: FSEventsScanEventSource()),
            capBytes: capBytes, maximumAge: TimeInterval(expirySeconds))
        await coordinator.startWatching(approvedRoots: authorization.roots,
            volumeUUID: volumeUUID)
        retainedScanIndex = (cacheMiB, expiryHours, coordinator)
        return coordinator
    }

    private func startScanObservation() async -> AppScanObservationResources {
        let id = UUID()
        let lease = MonitorLease()
        acceptedScanObservationID = id
        await systemMonitor.acquireExplicitWorkLease(lease)
        let stream = await systemMonitor.subscribe()
        await applyScanObservation(await systemMonitor.requestSnapshot(), sourceID: id)
        let task = Task { @MainActor [weak self] in
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { break }
                await self.applyScanObservation(snapshot, sourceID: id)
            }
        }
        return AppScanObservationResources(id: id, lease: lease, task: task)
    }

    private func stopScanObservation(_ resources: AppScanObservationResources) async {
        resources.task.cancel()
        if acceptedScanObservationID == resources.id { acceptedScanObservationID = nil }
        await systemMonitor.releaseExplicitWorkLease(resources.lease)
    }

    private func applyScanObservation(_ snapshot: SystemSnapshot, sourceID: UUID) async {
        guard acceptedScanObservationID == sourceID else { return }
        let observation = schedulerLiveObservation(from: snapshot)
        let (next, overflow) = scanObservationEpoch.addingReportingOverflow(1)
        guard !overflow else { return }
        scanObservationEpoch = next
        let monotonic = UInt64(max(0, ProcessInfo.processInfo.systemUptime) * 1_000_000_000)
        _ = await explicitSessions.updateLiveObservation(epoch: next,
            monotonicNanoseconds: monotonic, observation: observation)
    }

    func disposeScanResourcesForTesting() async {
        if activeScanSessionID != nil { await cancelActiveScan() }
        if let scanCleanup { await resolveScanCleanup(scanCleanup) }
        await retainedScanIndex?.coordinator.stopWatching()
        retainedScanIndex = nil
        retainedScanHandles.removeAll()
        retainedScanHandleOrder.removeAll()
    }

    func activeScanIndexWatchIsActiveForTesting() async -> Bool {
        await activeScanResources?.index?.isWatchActiveForTesting() ?? false
    }

    static func bootstrap(paths: AppStoragePaths) async -> AppExecutionServices {
        let settings = SettingsStore(url: paths.settings)
        return await bootstrap(paths: paths, settings: settings, observe: { _ in },
            scanLifecycleHook: nil, scanTraversalLimits: nil)
    }

    static func bootstrap(paths: AppStoragePaths, settings: SettingsStore,
                          observe: @escaping @Sendable (AppBootstrapStage) -> Void,
                          scanLifecycleHook:
                            (@Sendable (AppScanLifecycleEvent) async -> Void)? = nil,
                          scanTraversalLimits: TraversalLimits? = nil) async
        -> AppExecutionServices {
        let worker = await Task.detached {
            observe(.beforeSettingsLoad)
            let settingsBootstrap = await settings.loadForSchedulerBootstrap()
            let load = settingsBootstrap.result
            observe(.afterSettingsLoad)
            let config = load.envelope?.config ?? TidyConfig(schemaVersion: 2)
            let environment = config.makePolicyEnvironment(homeDirectory: paths.home.path,
                detectedTools: [])
            observe(.beforeCoordinatorConstruction)
            let coordinator = ExecutionCoordinator(environment: environment,
                journalDirectory: paths.journal)
            observe(.afterCoordinatorConstruction)
            let admission = await coordinator.mutationAdmission()
            return AppBootstrapWorkerResult(load: load, settingsBootstrap: settingsBootstrap,
                coordinator: coordinator, journalAdmission: admission)
        }.value
        let services = AppExecutionServices(paths: paths, settings: settings, worker: worker,
            scanLifecycleHook: scanLifecycleHook, scanTraversalLimits: scanTraversalLimits)
        // Do not publish an editable store while the loaded scheduler policy still owns its
        // admission transition; an immediate settings edit must reach the persistence path.
        await services.explicitSessions.awaitInitialInstall()
        return services
    }

    var isExecutionEnabled: Bool {
        settingsLoad.envelope != nil && liveRecoveryAdmission == .ready
            && policyBridge.isExecutionEnabled
    }
    var policyUpdatePending: Bool { policyBridge.policyUpdatePending }
    var storageUpdatePending: Bool { policyBridge.storageUpdatePending }
    var persistenceError: String? {
        if let error = policyBridge.persistenceError { return error }
        guard liveRecoveryAdmission == .ready else {
            return "Execution records could not be validated. Cleanup remains disabled."
        }
        return nil
    }

    func recordCompletedRun(_ report: RunReport) async {
        let revision = configStore.acknowledgedSettingsRevision
        do {
            guard let optionalRunHistory else {
                historyPersistenceError = "Optional run history storage is unavailable."
                return
            }
            let policy = OptionalRunHistoryPolicy.resolve(configStore.acknowledgedEffectivePolicy)
            let outcome = try await optionalRunHistory.record(report, policy: policy,
                acknowledgedRevision: revision)
            guard configStore.acknowledgedSettingsRevision == revision,
                  outcome != .stalePolicy else { return }
            historyPersistenceError = outcome == .entryExceedsLimit
                ? "The completed run was larger than the optional history limit and was not stored."
                : nil
        } catch {
            guard configStore.acknowledgedSettingsRevision == revision else { return }
            historyPersistenceError = "Optional run history could not be updated: \(error)"
        }
    }

    /// Starts one app-owned confirmed execution or joins the same binding's
    /// existing task. Window/session cancellation never owns this task and
    /// optional history is recorded exactly once inside it.
    func startConfirmedExecution(binding: ReviewBinding) throws -> Task<RunReport, Error> {
        if let confirmedExecution {
            guard confirmedExecution.binding == binding else {
                throw ConfirmationError.busy
            }
            return confirmedExecution.task
        }
        let id = UUID()
        let completion = AppExecutionCompletionLatch()
        let task = Task { @MainActor [self] () throws -> RunReport in
            defer {
                completion.finish()
                if confirmedExecution?.id == id { confirmedExecution = nil }
            }
            try Task.checkCancellation()
            let token = try await coordinator.confirm(binding: binding)
            let revision = await coordinator.currentPolicyRevision()
            let report = await coordinator.execute(token, currentPolicyRevision: revision)
            await recordCompletedRun(report)
            return report
        }
        confirmedExecution = AppConfirmedExecution(id: id, binding: binding,
            task: task, completion: completion)
        return task
    }

    func executeConfirmed(binding: ReviewBinding) async throws -> RunReport {
        try await startConfirmedExecution(binding: binding).value
    }

    var hasActiveConfirmedExecution: Bool { confirmedExecution != nil }

    func awaitActiveConfirmedExecution() async -> RunReport? {
        guard let active = confirmedExecution else { return nil }
        return try? await active.task.value
    }

    func cancelConfirmedExecution() {
        confirmedExecution?.task.cancel()
        coordinator.cancelCurrentRun()
    }

    func reconcileExecutionRecovery() async -> RecoveryReconciliationReport {
        let report = await coordinator.reconcileUnfinishedEffects()
        lastRecoveryReport = report
        liveRecoveryAdmission = await coordinator.mutationAdmission()
        executionProgress = await coordinator.executionProgress()
        return report
    }

    /// Quit may proceed after this bounded drain. A timeout does not claim a
    /// clean cancellation: Core's durable intent remains the recovery truth.
    func cancelAndDrainExecutionForTermination(
        timeout: Duration = .seconds(5)
    ) async -> AppExecutionDrainResult {
        guard let active = confirmedExecution else { return .noExecution }
        active.task.cancel()
        coordinator.cancelCurrentRun()
        return await active.completion.wait(timeout: timeout)
            ? .completed : .durablyUncertain
    }
}

@Observable @MainActor
final class AppBootstrapState {
    enum Status: Equatable { case notStarted, loading, ready, recovery, unavailable }

    private(set) var status: Status = .notStarted
    private(set) var services: AppExecutionServices?
    private var completion: Task<Void, Never>?

    func start(paths: AppStoragePaths) -> Task<Void, Never> {
        start { await AppExecutionServices.bootstrap(paths: paths) }
    }

    func start(paths: AppStoragePaths, settings: SettingsStore,
               observe: @escaping @Sendable (AppBootstrapStage) -> Void) -> Task<Void, Never> {
        start { await AppExecutionServices.bootstrap(paths: paths, settings: settings,
            observe: observe) }
    }

    func storagePathUnavailable() {
        guard completion == nil else { return }
        services = nil
        status = .unavailable
    }

    /// Re-evaluates the already-loaded service after bounded recovery
    /// reconciliation. It never reloads settings, resets storage, or discards
    /// an unresolved record.
    func refreshRecoveryDisposition() {
        guard let services else {
            status = .unavailable
            return
        }
        status = services.isExecutionEnabled ? .ready : .recovery
    }

    private func start(_ operation: @escaping @MainActor () async -> AppExecutionServices)
        -> Task<Void, Never> {
        if let completion { return completion }
        status = .loading
        let task = Task { @MainActor [weak self] in
            let services = await operation()
            guard let self else { return }
            self.services = services
            self.status = services.isExecutionEnabled ? .ready : .recovery
        }
        completion = task
        return task
    }
}

/// Per-window review lifecycle; authority remains exclusively in the shared coordinator.
@Observable @MainActor
final class AppReviewSession {
    enum Phase {
        case loadingPlan, reviewing(CleanPlan), executing, complete(RunReport), failed(String)
    }
    private let tier: Tier
    private let selectDefaults: Bool
    private(set) var phase: Phase = .loadingPlan
    private(set) var selection: PlanSelectionModel?
    private(set) var registeredReview: RegisteredReview?
    private let services: AppExecutionServices
    private let lifetime = ReviewRequestLifetime()
    init(tier: Tier, selectDefaults: Bool, services: AppExecutionServices) {
        self.tier = tier
        self.selectDefaults = selectDefaults
        self.services = services
    }

    func requestLoad() -> Task<Void, Never> {
        selection?.invalidate(policyEnabled: false)
        selection = nil
        return lifetime.enqueue { [self] request in
            if services.hasActiveConfirmedExecution {
                phase = .executing
                if let report = await services.awaitActiveConfirmedExecution(),
                   lifetime.isCurrent(request) {
                    phase = .complete(report)
                }
                return
            }
            phase = .loadingPlan
            if let old = registeredReview {
                registeredReview = nil
                await services.coordinator.discardReview(planID: old.binding.planID)
                guard lifetime.isCurrent(request) else { return }
            }
            guard services.isExecutionEnabled, !services.policyUpdatePending else {
                phase = .failed(services.persistenceError ?? "Settings are still being saved. Review again after saving completes.")
                return
            }
            do {
                let review = try await services.coordinator.prepareReview(engine: services.engine,
                    tier: tier, selectDefaults: selectDefaults, sessions: services.explicitSessions)
                guard lifetime.isCurrent(request) else {
                    await services.coordinator.discardReview(planID: review.binding.planID)
                    return
                }
                guard services.coordinator.policyAdmission() == .ready(revision: review.binding.policyRevision) else {
                    await services.coordinator.discardReview(planID: review.binding.planID)
                    guard lifetime.isCurrent(request) else { return }
                    phase = .failed(confirmationFailureMessage(ConfirmationError.stalePolicy))
                    return
                }
                registeredReview = review
                let model = PlanSelectionModel(review: review) { [weak self] ids in self?.requestSelection(ids) }
                model.invalidate(policyEnabled: true)
                selection = model
                phase = .reviewing(review.plan)
            } catch {
                guard lifetime.isCurrent(request) else { return }
                phase = .failed(confirmationFailureMessage(error))
            }
        }
    }
    func loadPlan() async { await requestLoad().value }

    private func requestSelection(_ ids: Set<String>) {
        guard let held = registeredReview else { return }
        _ = lifetime.enqueue { [self] request in
            do {
                let review = try await services.coordinator.setSelection(planID: held.binding.planID, selectedIDs: ids)
                guard lifetime.isCurrent(request) else { return }
                guard services.coordinator.policyAdmission() == .ready(revision: review.binding.policyRevision),
                      services.isExecutionEnabled, !services.policyUpdatePending else {
                    policyDidChange()
                    return
                }
                registeredReview = review
                selection?.replace(review: review)
            } catch {
                guard lifetime.isCurrent(request) else { return }
                if let registeredReview { selection?.replace(review: registeredReview) }
                selection?.invalidate(policyEnabled: false)
                phase = .failed(confirmationFailureMessage(error))
            }
        }
    }

    /// Capture the exact dialog value synchronously, before scheduling any actor work.
    func confirm() {
        guard services.isExecutionEnabled, !services.policyUpdatePending,
              let candidate = selection?.frozenPresentation,
              services.coordinator.policyAdmission() == .ready(revision: candidate.binding.policyRevision),
              let frozen = selection?.takeConfirmation() else {
            selection?.cancelConfirmation()
            return
        }
        let executionTask: Task<RunReport, Error>
        do {
            executionTask = try services.startConfirmedExecution(binding: frozen.binding)
        } catch {
            phase = .failed(confirmationFailureMessage(error))
            return
        }
        lifetime.invalidate()
        phase = .executing
        _ = lifetime.enqueue { [self] request in
            do {
                let report = try await executionTask.value
                guard lifetime.isCurrent(request) else { return }
                phase = .complete(report)
            } catch {
                guard lifetime.isCurrent(request) else { return }
                phase = .failed(confirmationFailureMessage(error))
            }
        }
    }

    func policyDidChange() {
        lifetime.invalidate()
        selection?.invalidate(policyEnabled: false)
        phase = .failed(services.persistenceError ?? "Settings changed. Review the items again before confirming.")
    }

    func teardown() -> Task<Void, Never> {
        selection?.invalidate(policyEnabled: false)
        selection = nil
        return lifetime.teardown { [self] in
            if let old = registeredReview {
                registeredReview = nil
                await services.coordinator.discardReview(planID: old.binding.planID)
            }
        }
    }
}
