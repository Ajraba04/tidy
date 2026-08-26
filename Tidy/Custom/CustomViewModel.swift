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
    private(set) var selection: PlanSelectionModel?
    var selectedIDs: Set<String> { selection?.value.selectedIDs ?? [] }

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
        selection = PlanSelectionModel(plan: plan, selectDefaults: false)
        phase = .selecting(plan)
    }

    func applyPreset(_ preset: CustomPreset) {
        selection?.applyPresetIDs(preset.itemIDs)
    }

    var selectedEstimatedBytes: Int64 {
        selection?.value.selectedEstimatedBytes ?? 0
    }

    var selectedCount: Int { selection?.value.selectedCount ?? 0 }

    func setSelected(_ selected: Bool, id: String) { selection?.setSelected(selected, id: id) }

    /// Only reachable from the confirmation dialog on the selection
    /// screen. There is no other path from a selection to a deletion.
    func executeSelected() async {
        guard case .selecting = phase, let selection, selection.value.selectedCount > 0 else { return }

        phase = .executing
        let report = await engine.execute(plan: selection.value.selectedPlan, environment: environment)
        RunLog.append(report)
        phase = .complete(report)
    }
}
