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

/// Thrown by `AppExecutionServices.beginScan` when the T08.1b scheduler façade is genuinely not
/// installed yet (a fresh install that has never saved settings) rather than merely busy/paused.
enum ScanAvailabilityError: Error, Equatable {
    case policyNotInstalled
}

private struct AppBootstrapWorkerResult: Sendable {
    let load: SettingsLoadResult
    let coordinator: ExecutionCoordinator
    let journalAdmission: MutationAdmission
    let detectedTools: Set<ToolchainID>
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
    /// The app's one T10 headroom monitor, constructed once at bootstrap.
    /// Every window that shows disk/memory/swap/thermal/power signals
    /// (menu bar popover, Headroom window) observes this shared instance
    /// rather than owning a probe or a timer of its own.
    let systemMonitor: SystemMonitor
    let detectedTools: Set<ToolchainID>
    private let scanVisibilityID = UUID()
    nonisolated(unsafe) private var signalTask: Task<Void, Never>?


    /// The app's one T08.2 session registry, constructed once at bootstrap. It starts no work;
    /// `beginScan` is the only route that registers and launches a session against it.
    let scanRegistry = ScanSessionRegistry()
    /// The active scan's session ID, if any, kept here (not on a per-window view model) so the
    /// menu-bar/global Cancel affordance survives that window closing.
    private(set) var activeScanSessionID: UUID?
    private var activeScanHandle: CoreScanHandle?
    private var retainedScanHandles: [UUID: CoreScanHandle] = [:]
    private var retainedScanOrder: [UUID] = []
    private var scanStart: Task<CoreScanHandle, Error>?
    private var scanLifetime: Task<Void, Never>?
    nonisolated(unsafe) private var historyTask: Task<Void, Never>?
    private(set) var historyError: String?
    private var scanIndex: ScanIndexCoordinator?

    private init(paths: AppStoragePaths, settings: SettingsStore,
                 worker: AppBootstrapWorkerResult) {
        self.paths = paths
        self.settings = settings
        self.settingsLoad = worker.load
        self.initialJournalAdmission = worker.journalAdmission
        self.coordinator = worker.coordinator
        self.detectedTools = worker.detectedTools
        let envelope = worker.load.envelope ?? SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: TidyConfig(schemaVersion: 2))
        self.policyBridge = ExecutionPolicyBridge(coordinator: worker.coordinator,
            settings: settings, loaded: worker.load, homeDirectory: paths.home.path,
            detectedTools: worker.detectedTools)
        self.configStore = AppConfigStore(loaded: envelope, bridge: policyBridge)
        self.engine = CleanEngine(sizeScanner: SizeScanner())
        self.runLogURL = paths.journal.deletingLastPathComponent().appendingPathComponent("runs.jsonl")
        self.systemMonitor = SystemMonitor(
            configuration: .resolve(self.configStore.effectivePolicy),
            volumes: [paths.home])
        self.configStore.didAcknowledge = { [weak self] in self?.applyAcknowledgedSettings() }
        let monitor = systemMonitor
        signalTask = Task { [weak self] in
            let stream = await monitor.subscribe()
            for await snapshot in stream {
                guard !Task.isCancelled, let self else { break }
                self.configStore.latestSystemSnapshot = snapshot
                if let disk = snapshot.volumes.first?.disk {
                    self.configStore.selectedVolumeID = disk.volumeIdentifier.flatMap(UUID.init(uuidString:))
                    self.configStore.selectedVolumeCapacity = disk.totalBytes
                } else {
                    self.configStore.selectedVolumeID = nil
                    self.configStore.selectedVolumeCapacity = nil
                }
                await self.policyBridge.updateSystemObservation(snapshot)
            }
        }
        if worker.load.disposition != .recoveryReadOnly { _ = enqueueHistory(nil) }
    }

    deinit { signalTask?.cancel(); historyTask?.cancel() }

    func stopObserving() async {
        signalTask?.cancel()
        await systemMonitor.applyConfiguration(.disabled)
        await cancelActiveScan()
    }

    private func applyAcknowledgedSettings() {
        let configuration = SystemMonitor.Configuration.resolve(configStore.effectivePolicy)
        Task { await systemMonitor.applyConfiguration(configuration) }
        _ = enqueueHistory(nil)
    }

    @discardableResult
    private func enqueueHistory(_ report: RunReport?) -> Task<Void, Never> {
        let previous = historyTask
        let policy = RunHistoryPolicy.resolve(configStore.effectivePolicy)
        let url = runLogURL
        let task = Task { [weak self] in
            await previous?.value
            guard self != nil, !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                Result { try RunLog.update(report, at: url, policy: policy) }
            }.value
            if case .failure = result { self?.historyError = "Optional run history could not be saved or cleared." }
            else { self?.historyError = nil }
        }
        historyTask = task
        return task
    }

    func recordRun(_ report: RunReport) async { await enqueueHistory(report).value }

    private func prepareScanIndex(environment: CleanEnvironment) async -> ScanIndexCoordinator? {
        guard let policy = configStore.effectivePolicy,
              policy.fields[.init(rawValue: "scan.cacheEnabled")]?.value == .stored(.bool(true)),
              let identity = ScanRootIdentity.resolve(path: environment.homeDirectory) else { return nil }
        func integer(_ name: String, _ fallback: Int64) -> Int64 {
            if case .stored(.integer(let value))? = policy.fields[.init(rawValue: name)]?.value { return value }
            return fallback
        }
        let url = paths.settings.deletingLastPathComponent().appendingPathComponent("scan-index/aggregates.sqlite")
        let store = await Task.detached(priority: .utility) { try? ScanIndexStore(databaseURL: url) }.value
        guard let store else { return nil }
        let index = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: FSEventsScanEventSource()),
            capBytes: integer("scan.cacheMiB", 64) * 1_048_576,
            maximumAge: Double(integer("scan.cacheExpiryHours", 24)) * 3_600)
        await index.startWatching(approvedRoots: [environment.homeDirectory,
            environment.homeDirectory + "/Library"], volumeUUID: identity.volumeUUID)
        return index
    }

    /// The sole T08.1b bounded explicit-session façade this app consumes. No alternate
    /// scheduler/session authority is created anywhere in the app layer.
    var explicitSessions: BridgeExplicitSessions { policyBridge.explicitSessions }

    /// Single-flight explicit scan. Simultaneous requests attach to the same session;
    /// the service retains global cancellation after its windows close.
    func beginScan() async throws -> CoreScanHandle {
        if let scanStart { return try await scanStart.value }
        let task = Task<CoreScanHandle, Error> {
            if let activeID = self.activeScanSessionID, let handle = self.activeScanHandle {
                if let state = try? await self.scanRegistry.state(sessionID: activeID), state.terminal == nil {
                    return handle
                }
                await self.scanLifetime?.value
            }
            try Task.checkCancellation()
            return try await self.startScan()
        }
        scanStart = task
        defer { scanStart = nil }
        return try await task.value
    }

    private func startScan() async throws -> CoreScanHandle {
        await configStore.prepareExplicitScan()
        await policyBridge.updateSystemObservation(await systemMonitor.requestSnapshot())
        await explicitSessions.awaitInitialInstall()
        guard await explicitSessions.snapshot().availability == .available else {
            throw ScanAvailabilityError.policyNotInstalled
        }
        let environment = try configStore.scanEnvironment(homeDirectory: paths.home.path, detectedTools: detectedTools)
        let policyRevision = configStore.acknowledgedRevision
        let session = try await explicitSessions.beginSession(
            requirements: try SchedulerRequirements(features: [.headroom]))
        let index = await prepareScanIndex(environment: environment)
        do {
            try Task.checkCancellation()
            guard policyRevision == configStore.acknowledgedRevision else { throw ConfirmationError.stalePolicy }
            let handle = try await ScanEngine.start(environment: environment, registry: scanRegistry,
                sessions: explicitSessions, session: session, indexCoordinator: index)
            scanIndex = index
            await systemMonitor.setWindowVisible(true, consumer: scanVisibilityID)
            activeScanSessionID = handle.sessionID
            activeScanHandle = handle
            retainedScanHandles[handle.sessionID] = handle
            retainedScanOrder.append(handle.sessionID)
            while retainedScanOrder.count > 8 {
                retainedScanHandles.removeValue(forKey: retainedScanOrder.removeFirst())
            }
            trackScanSessionLifetime(sessionID: handle.sessionID, session: session, index: index)
            return handle
        } catch {
            await index?.stopWatching()
            await explicitSessions.finish(session: session)
            throw error
        }
    }

    /// Bounded per-session retention keeps a subsequent scan from stealing terminal results.
    func latestScanResult(sessionID: UUID) async -> CoreScanResult? {
        guard let handle = retainedScanHandles[sessionID] else { return nil }
        return await handle.latestResult()
    }

    /// Cancels the active scan by session ID only — this never signals, cancels, or releases a
    /// T04 mutator, and remains reachable from the global/menu owner after every window closes.
    func cancelActiveScan() async {
        scanStart?.cancel()
        guard let sessionID = activeScanSessionID else { return }
        try? await scanRegistry.cancel(sessionID: sessionID)
    }

    /// Releases the scheduler-level session exactly once the registered work reaches a terminal
    /// state, independent of any UI subscriber. This is a dedicated internal subscription, not
    /// the one any `ScanViewModel` observes.
    private func trackScanSessionLifetime(sessionID: UUID, session: WorkSession, index: ScanIndexCoordinator?) {
        let registry = scanRegistry
        let sessions = explicitSessions
        scanLifetime = Task { [weak self] in
            if let subscription = try? await registry.subscribe(sessionID: sessionID) {
                for await event in subscription.stream where event.terminal != nil { break }
            }
            await index?.stopWatching()
            await sessions.finish(session: session)
            guard let self, self.activeScanSessionID == sessionID else { return }
            self.activeScanSessionID = nil
            self.scanIndex = nil
            await self.systemMonitor.setWindowVisible(false, consumer: self.scanVisibilityID)
        }
    }

    static func bootstrap(paths: AppStoragePaths) async -> AppExecutionServices {
        let settings = SettingsStore(url: paths.settings)
        return await bootstrap(paths: paths, settings: settings, observe: { _ in })
    }

    static func bootstrap(paths: AppStoragePaths, settings: SettingsStore,
                          observe: @escaping @Sendable (AppBootstrapStage) -> Void) async
        -> AppExecutionServices {
        let worker = await Task.detached {
            observe(.beforeSettingsLoad)
            let load = await settings.load()
            observe(.afterSettingsLoad)
            let config = load.envelope?.config ?? TidyConfig(schemaVersion: 2)
            let tools = ToolchainDetector.detect(homeDirectory: paths.home.path)
            let environment = (try? load.envelope?.makePolicyEnvironment(homeDirectory: paths.home.path,
                detectedTools: tools)) ?? config.makePolicyEnvironment(homeDirectory: paths.home.path,
                detectedTools: [])
            observe(.beforeCoordinatorConstruction)
            let coordinator = ExecutionCoordinator(environment: environment,
                journalDirectory: paths.journal)
            observe(.afterCoordinatorConstruction)
            let admission = await coordinator.mutationAdmission()
            return AppBootstrapWorkerResult(load: load, coordinator: coordinator,
                journalAdmission: admission, detectedTools: tools)
        }.value
        return AppExecutionServices(paths: paths, settings: settings, worker: worker)
    }

    var isExecutionEnabled: Bool {
        settingsLoad.envelope != nil && initialJournalAdmission == .ready
            && policyBridge.isExecutionEnabled
    }
    var policyUpdatePending: Bool { policyBridge.policyUpdatePending }
    var storageUpdatePending: Bool { policyBridge.storageUpdatePending }
    var persistenceError: String? {
        if let error = policyBridge.persistenceError { return error }
        guard initialJournalAdmission == .ready else {
            return "Execution records could not be validated. Cleanup remains disabled."
        }
        return nil
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

    func retry(paths: AppStoragePaths) async {
        guard status == .recovery || status == .unavailable else { return }
        status = .loading
        await services?.stopObserving()
        completion = nil
        services = nil
        await start(paths: paths).value
    }

    func storagePathUnavailable() {
        guard completion == nil else { return }
        services = nil
        status = .unavailable
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
        lifetime.invalidate()
        phase = .executing
        _ = lifetime.enqueue { [self] request in
            do {
                let token = try await services.coordinator.confirm(binding: frozen.binding)
                // Policy may change at any await; coordinator validates both actual state and hint.
                let revision = await services.coordinator.currentPolicyRevision()
                let report = await services.coordinator.execute(token, currentPolicyRevision: revision)
                await services.recordRun(report)
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
