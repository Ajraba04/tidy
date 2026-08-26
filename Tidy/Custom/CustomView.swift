import SwiftUI
import TidyCore

struct CustomView: View {
    @Environment(AppConfigStore.self) private var configStore
    @State private var model: CustomViewModel

    init(tier: Tier = .deep) {
        let home = NSHomeDirectory()
        let config = ConfigStore.load()
        let environment = config.makeEnvironment(homeDirectory: home)
        let engine = CleanEngine(sizeScanner: SizeScanner())
        _model = State(initialValue: CustomViewModel(engine: engine, environment: environment))
    }

    var body: some View {
        Group {
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
                        Task { await model.executeSelected() }
                    })
                }
            case .executing:
                ProgressView("Cleaning…")
            case .complete(let report):
                CleanResultsView(report: report)
            }
        }
        .navigationTitle("Custom Clean")
        .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 640)
        .task { await model.loadPlan() }
    }

}
