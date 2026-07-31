import Foundation
import Observation
import TidyCore

@Observable
@MainActor
final class CleanViewModel {
    enum Phase {
        case loadingPlan
        case reviewingPlan(CleanPlan)
        case executing
        case complete(RunReport)
        case failed(String)
    }

    let tier: Tier
    private(set) var phase: Phase = .loadingPlan
    private let engine: CleanEngine
    private let environment: CleanEnvironment

    init(tier: Tier, engine: CleanEngine, environment: CleanEnvironment) {
        self.tier = tier
        self.engine = engine
        self.environment = environment
    }

    func loadPlan() async {
        phase = .loadingPlan
        await DefaultCustomActionExecutors.registerAll(on: engine)
        let plan = await engine.makePlan(items: CleanCatalog.allItems, tier: tier, environment: environment)
        phase = .reviewingPlan(plan)
    }

    /// Only reachable after the plan screen's confirmation dialog — there
    /// is no other path from a plan to a deletion.
    func executeConfirmedPlan(_ plan: CleanPlan) async {
        phase = .executing
        let report = await engine.execute(plan: plan, environment: environment)
        RunLog.append(report)
        phase = .complete(report)
    }
}
