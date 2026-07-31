import Foundation
import Observation
import TidyCore

@Observable
@MainActor
final class CustomViewModel {
    enum Phase {
        case loadingPlan
        case selecting(CleanPlan)
        case executing
        case complete(RunReport)
    }

    private(set) var phase: Phase = .loadingPlan
    var selectedIDs: Set<String> = []

    private let engine: CleanEngine
    private let environment: CleanEnvironment

    init(engine: CleanEngine, environment: CleanEnvironment) {
        self.engine = engine
        self.environment = environment
    }

    func loadPlan() async {
        phase = .loadingPlan
        await DefaultCustomActionExecutors.registerAll(on: engine)
        let plan = await engine.makePlan(items: CleanCatalog.allItems, tier: .deep, environment: environment)
        selectedIDs = []
        phase = .selecting(plan)
    }

    func applyPreset(_ preset: CustomPreset) {
        selectedIDs = preset.itemIDs
    }

    var selectedEstimatedBytes: Int64 {
        guard case .selecting(let plan) = phase else { return 0 }
        return plan.plannedItems.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.estimatedBytes }
    }

    /// Only reachable from the confirmation dialog on the selection
    /// screen. There is no other path from a selection to a deletion.
    func executeSelected() async {
        guard case .selecting(let plan) = phase else { return }
        let filteredItems = plan.plannedItems.filter { selectedIDs.contains($0.id) }
        let filteredPlan = CleanPlan(tier: plan.tier, plannedItems: filteredItems)

        phase = .executing
        let report = await engine.execute(plan: filteredPlan, environment: environment)
        RunLog.append(report)
        phase = .complete(report)
    }
}
