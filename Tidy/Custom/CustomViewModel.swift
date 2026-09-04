import Foundation
import Observation
import TidyCore

@Observable @MainActor
final class CustomViewModel {
    enum Phase {
        case loadingPlan, selecting(CleanPlan), executing, complete(RunReport), failed(String)
    }
    private let session: AppReviewSession
    var selection: PlanSelectionModel? { session.selection }
    var registeredReview: RegisteredReview? { session.registeredReview }
    var phase: Phase {
        switch session.phase {
        case .loadingPlan: return .loadingPlan
        case .reviewing(let plan): return .selecting(plan)
        case .executing: return .executing
        case .complete(let report): return .complete(report)
        case .failed(let message): return .failed(message)
        }
    }
    init(services: AppExecutionServices) {
        session = AppReviewSession(tier: .deep, selectDefaults: false, services: services)
    }
    func requestLoad() -> Task<Void, Never> { session.requestLoad() }
    func loadPlan() async { await requestLoad().value }
    func confirm() { session.confirm() }
    func policyDidChange() { session.policyDidChange() }
    func teardown() -> Task<Void, Never> { session.teardown() }
}
