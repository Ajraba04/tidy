import Foundation
import Observation
import TidyCore

@Observable @MainActor
final class AppExecutionServices {
    let coordinator: ExecutionCoordinator
    let policyBridge: ExecutionPolicyBridge
    let configStore: AppConfigStore
    let engine: CleanEngine
    let runLogURL: URL

    init(config: TidyConfig, configURL: URL?, homeDirectory: String, journalDirectory: URL) {
        let detectedTools: Set<ToolchainID> = []
        let environment = config.makePolicyEnvironment(homeDirectory: homeDirectory, detectedTools: detectedTools)
        let coordinator = ExecutionCoordinator(environment: environment, journalDirectory: journalDirectory)
        self.coordinator = coordinator
        self.policyBridge = ExecutionPolicyBridge(coordinator: coordinator, configURL: configURL,
                                                 homeDirectory: homeDirectory, detectedTools: detectedTools)
        self.configStore = AppConfigStore(config: config, bridge: policyBridge)
        self.engine = CleanEngine(sizeScanner: SizeScanner())
        self.runLogURL = journalDirectory.deletingLastPathComponent().appendingPathComponent("runs.jsonl")
    }

    var isExecutionEnabled: Bool { policyBridge.isExecutionEnabled }
    var policyUpdatePending: Bool { policyBridge.policyUpdatePending }
    var persistenceError: String? { policyBridge.persistenceError }
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
                    tier: tier, selectDefaults: selectDefaults)
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
