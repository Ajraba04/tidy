import SwiftUI
import TidyCore

struct CustomView: View {
    @Environment(AppConfigStore.self) private var configStore
    @State private var model: CustomViewModel
    private let services: AppExecutionServices

    init(services: AppExecutionServices) {
        self.services = services
        _model = State(initialValue: CustomViewModel(services: services))
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
            case .selecting:
                if let selection = model.selection {
                    CustomPlanView(selection: selection,
                                   presets: configStore.config.presets,
                                   onSavePreset: { preset in
                        configStore.config.presets.removeAll { $0.name == preset.name }
                        configStore.config.presets.append(preset)
                    }, onConfirm: {
                        model.confirm()
                    })
                }
            case .executing:
                ProgressView("Cleaning…")
            case .complete(let report):
                CleanResultsView(report: report)
            case .failed(let message):
                ContentUnavailableView("Review Unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
                Button("Review Again") { _ = model.requestLoad() }
                    .disabled(!services.isExecutionEnabled || services.policyUpdatePending)
            }
        }
        .navigationTitle("Custom Clean")
        .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 640)
        .task { await model.loadPlan() }
        .onChange(of: services.policyBridge.updateGeneration) { _, _ in model.policyDidChange() }
        .onDisappear { _ = model.teardown() }
    }

}
