import SwiftUI
import TidyCore

struct CleanView: View {
    @State private var model: CleanViewModel

    init(tier: Tier) {
        let home = NSHomeDirectory()
        let environment = ConfigStore.load().makeEnvironment(homeDirectory: home)
        let engine = CleanEngine(sizeScanner: SizeScanner())
        _model = State(initialValue: CleanViewModel(tier: tier, engine: engine, environment: environment))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loadingPlan:
                ProgressView("Building plan…")
            case .reviewingPlan(let plan):
                CleanPlanView(plan: plan) {
                    Task { await model.executeConfirmedPlan(plan) }
                }
            case .executing:
                ProgressView("Cleaning…")
            case .complete(let report):
                CleanResultsView(report: report)
            case .failed(let message):
                ContentUnavailableView("Something Went Wrong", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
        .navigationTitle("\(model.tier.title) Clean")
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 640)
        .task { await model.loadPlan() }
    }
}
