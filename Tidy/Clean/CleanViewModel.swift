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
    private(set) var selection: PlanSelectionModel?
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
        selection = PlanSelectionModel(plan: plan, selectDefaults: true)
        phase = .reviewingPlan(plan)
    }

    /// Only reachable after the plan screen's confirmation dialog.
    /// There is no other path from a plan to a deletion.
    func executeConfirmedSelection() async {
        guard let selection, selection.value.selectedCount > 0 else { return }
        phase = .executing
        let report = await engine.execute(plan: selection.value.selectedPlan, environment: environment)
        RunLog.append(report)
        phase = .complete(report)
    }
}
