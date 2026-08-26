import Foundation
import Observation
import TidyCore

@Observable @MainActor
final class CleanViewModel {
    enum Phase {
        case loadingPlan, reviewingPlan(CleanPlan), executing, complete(RunReport), failed(String)
    }
    let tier: Tier
    private let session: AppReviewSession
    var selection: PlanSelectionModel? { session.selection }
    var registeredReview: RegisteredReview? { session.registeredReview }
    var phase: Phase {
        switch session.phase {
        case .loadingPlan: return .loadingPlan
        case .reviewing(let plan): return .reviewingPlan(plan)
        case .executing: return .executing
        case .complete(let report): return .complete(report)
        case .failed(let message): return .failed(message)
        }
    }
    init(tier: Tier, services: AppExecutionServices) {
        self.tier = tier
        session = AppReviewSession(tier: tier, selectDefaults: true, services: services)
    }
    func requestLoad() -> Task<Void, Never> { session.requestLoad() }
    func loadPlan() async { await requestLoad().value }
    func confirm() { session.confirm() }
    func policyDidChange() { session.policyDidChange() }
    func teardown() -> Task<Void, Never> { session.teardown() }
}
