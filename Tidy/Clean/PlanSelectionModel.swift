import Observation
import TidyCore

@Observable
@MainActor
final class PlanSelectionModel {
    private(set) var value: PlanSelection

    init(plan: CleanPlan, selectDefaults: Bool) {
        value = PlanSelection(plan: plan, selectDefaults: selectDefaults)
    }

    func setSelected(_ selected: Bool, id: String) { value.setSelected(selected, id: id) }
    func applyPresetIDs(_ ids: Set<String>) { value.applyPresetIDs(ids) }
}
