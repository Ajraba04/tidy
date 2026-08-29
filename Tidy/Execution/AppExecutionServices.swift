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

    /// The app's one T08.2 session registry, constructed once at bootstrap. It starts no work;
    /// `beginScan` is the only route that registers and launches a session against it.
    let scanRegistry = ScanSessionRegistry()
    /// The active scan's session ID, if any, kept here (not on a per-window view model) so the
    /// menu-bar/global Cancel affordance survives that window closing.
    private(set) var activeScanSessionID: UUID?
    private var activeScanHandle: CoreScanHandle?

    private init(paths: AppStoragePaths, settings: SettingsStore,
                 worker: AppBootstrapWorkerResult) {
        self.paths = paths
        self.settings = settings
        self.settingsLoad = worker.load
        self.initialJournalAdmission = worker.journalAdmission
        self.coordinator = worker.coordinator
        let envelope = worker.load.envelope ?? SettingsEnvelope(schemaVersion: 2, revision: 0,
            config: TidyConfig(schemaVersion: 2))
        self.policyBridge = ExecutionPolicyBridge(coordinator: worker.coordinator,
            settings: settings, loaded: worker.load, homeDirectory: paths.home.path,
            detectedTools: [])
        self.configStore = AppConfigStore(loaded: envelope, bridge: policyBridge)
        self.engine = CleanEngine(sizeScanner: SizeScanner())
        self.runLogURL = paths.journal.deletingLastPathComponent().appendingPathComponent("runs.jsonl")
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
    /// A revision-zero/fresh-install envelope deliberately leaves the scheduler façade
    /// `.unavailable` until a real settings save completes (T08.1b) — this call awaits any
    /// pending initial install first, and if the façade is still unavailable afterward, throws
    /// `ScanAvailabilityError.policyNotInstalled` rather than silently starting nothing. Unlike
    /// Clean review, Scan has no honest legacy shape to fall back to (the legacy path only
    /// returns empty rows), so a visible "not available yet" state is the only truthful option.
    func beginScan(environment: CleanEnvironment) async throws -> CoreScanHandle {
        await explicitSessions.awaitInitialInstall()
        guard await explicitSessions.snapshot().availability == .available else {
            throw ScanAvailabilityError.policyNotInstalled
        }
        let session = try await explicitSessions.beginSession(
            requirements: try SchedulerRequirements(features: [.headroom]))
        do {
            let handle = try await ScanEngine.start(environment: environment, registry: scanRegistry,
                sessions: explicitSessions, session: session)
            activeScanSessionID = handle.sessionID
            activeScanHandle = handle
            trackScanSessionLifetime(sessionID: handle.sessionID, session: session)
            return handle
        } catch {
            await explicitSessions.finish(session: session)
            throw error
        }
    }

    /// The latest cumulative result for `sessionID`, if it is still the app's current scan.
    func latestScanResult(sessionID: UUID) async -> CoreScanResult? {
        guard let activeScanHandle, activeScanHandle.sessionID == sessionID else { return nil }
        return await activeScanHandle.latestResult()
    }

    /// Cancels the active scan by session ID only — this never signals, cancels, or releases a
    /// T04 mutator, and remains reachable from the global/menu owner after every window closes.
    func cancelActiveScan() async {
        guard let sessionID = activeScanSessionID else { return }
        try? await scanRegistry.cancel(sessionID: sessionID)
    }

    /// Releases the scheduler-level session exactly once the registered work reaches a terminal
    /// state, independent of any UI subscriber. This is a dedicated internal subscription, not
    /// the one any `ScanViewModel` observes.
    private func trackScanSessionLifetime(sessionID: UUID, session: WorkSession) {
        let registry = scanRegistry
        let sessions = explicitSessions
        Task { [weak self] in
            if let subscription = try? await registry.subscribe(sessionID: sessionID) {
                for await event in subscription.stream where event.terminal != nil { break }
            }
            await sessions.finish(session: session)
            guard let self, self.activeScanSessionID == sessionID else { return }
            self.activeScanSessionID = nil
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
            let environment = config.makePolicyEnvironment(homeDirectory: paths.home.path,
                detectedTools: [])
            observe(.beforeCoordinatorConstruction)
            let coordinator = ExecutionCoordinator(environment: environment,
                journalDirectory: paths.journal)
            observe(.afterCoordinatorConstruction)
            let admission = await coordinator.mutationAdmission()
            return AppBootstrapWorkerResult(load: load, coordinator: coordinator,
                journalAdmission: admission)
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
                RunLog.append(report, to: services.runLogURL)
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
