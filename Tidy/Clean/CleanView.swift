import SwiftUI
import TidyCore

struct CleanView: View {
    @State private var model: CleanViewModel
    private let services: AppExecutionServices

    init(tier: Tier, services: AppExecutionServices) {
        self.services = services
        _model = State(initialValue: CleanViewModel(tier: tier, services: services))
    }

    var body: some View {
        VStack {
            if let message = services.persistenceError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding()
            }
            switch model.phase {
            case .loadingPlan:
                ProgressView("Building plan…")
            case .reviewingPlan:
                if let selection = model.selection {
                    CleanPlanView(selection: selection) {
                        model.confirm()
                    }
                } else {
                    ProgressView("Building plan…")
                }
            case .executing:
                ProgressView("Cleaning…")
            case .complete(let report):
                CleanResultsView(report: report)
            case .failed(let message):
                ContentUnavailableView("Something Went Wrong", systemImage: "exclamationmark.triangle", description: Text(message))
                Button("Review Again") { _ = model.requestLoad() }
                    .disabled(!services.isExecutionEnabled || services.policyUpdatePending)
            }
        }
        .navigationTitle("\(model.tier.title) Clean")
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 640)
        .task { await model.loadPlan() }
        .onChange(of: services.policyBridge.updateGeneration) { _, _ in model.policyDidChange() }
        .onDisappear { _ = model.teardown() }
    }
}
