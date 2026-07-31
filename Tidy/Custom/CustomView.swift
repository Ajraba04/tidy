import SwiftUI
import TidyCore

struct CustomView: View {
    @Environment(AppConfigStore.self) private var configStore
    @State private var model: CustomViewModel
    @State private var showingConfirmation = false
    @State private var showingSavePreset = false
    @State private var presetName = ""

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
            case .selecting(let plan):
                selectionView(plan: plan)
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

    private func selectionView(plan: CleanPlan) -> some View {
        VStack(spacing: 0) {
            List {
                if !configStore.config.presets.isEmpty {
                    Section("Presets") {
                        ForEach(configStore.config.presets) { preset in
                            Button(preset.name) { model.applyPreset(preset) }
                        }
                    }
                }

                ForEach(CleanCatalog.categories) { category in
                    let items = plan.plannedItems.filter { item in category.items.contains { $0.id == item.id } }
                    if !items.isEmpty {
                        Section(category.title) {
                            ForEach(items) { item in
                                CustomItemRow(item: item, isSelected: selectionBinding(for: item.id))
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Save Selection as Preset…") { showingSavePreset = true }
                    .disabled(model.selectedIDs.isEmpty)
                Spacer()
                Text(ByteFormat.human(model.selectedEstimatedBytes))
                    .foregroundStyle(.secondary)
                Button("Clean Selected (\(model.selectedIDs.count))") { showingConfirmation = true }
                    .disabled(model.selectedIDs.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .confirmationDialog(
            "Delete \(model.selectedIDs.count) selected item(s)?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Now", role: .destructive) {
                Task { await model.executeSelected() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingSavePreset) {
            savePresetSheet
        }
    }

    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Preset").font(.headline)
            TextField("Preset name", text: $presetName)
            HStack {
                Spacer()
                Button("Cancel") { showingSavePreset = false }
                Button("Save") {
                    let preset = CustomPreset(name: presetName, itemIDs: model.selectedIDs)
                    configStore.config.presets.removeAll { $0.name == preset.name }
                    configStore.config.presets.append(preset)
                    presetName = ""
                    showingSavePreset = false
                }
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedIDs.contains(id) },
            set: { isOn in
                if isOn { model.selectedIDs.insert(id) } else { model.selectedIDs.remove(id) }
            }
        )
    }
}

private struct CustomItemRow: View {
    let item: PlannedItem
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title)
                    Spacer()
                    Text(ByteFormat.human(item.estimatedBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let dangerNote = item.dangerNote {
                    Label(dangerNote, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
