import SwiftUI
import TidyCore

struct CustomPlanView: View {
    let selection: PlanSelectionModel
    let presets: [CustomPreset]
    let onSavePreset: (CustomPreset) -> Void
    let onConfirm: () -> Void

    @State private var showingConfirmation = false
    @State private var showingSavePreset = false
    @State private var presetName = ""

    init(selection: PlanSelectionModel, presets: [CustomPreset],
         onSavePreset: @escaping (CustomPreset) -> Void,
         onConfirm: @escaping () -> Void) {
        self.selection = selection
        self.presets = presets
        self.onSavePreset = onSavePreset
        self.onConfirm = onConfirm
    }

    private var uncategorizedItems: [PlannedItem] {
        let categorizedIDs = Set(CleanCatalog.categories.flatMap { $0.items.map(\.id) })
        return selection.value.reviewItems.filter { !categorizedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if !presets.isEmpty {
                    Section("Presets") {
                        ForEach(presets) { preset in
                            Button(preset.name) { selection.applyPresetIDs(preset.itemIDs) }
                        }
                    }
                }
                ForEach(CleanCatalog.categories) { category in
                    let ids = Set(category.items.map(\.id))
                    let items = selection.value.reviewItems.filter { ids.contains($0.id) }
                    if !items.isEmpty {
                        Section(category.title) {
                            ForEach(items) { item in
                                PlanReviewRow(item: item, isSelected: binding(for: item.id))
                            }
                        }
                    }
                }
                if !uncategorizedItems.isEmpty {
                    Section("Other") {
                        ForEach(uncategorizedItems) { item in
                            PlanReviewRow(item: item, isSelected: binding(for: item.id))
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Save Selection as Preset…") { showingSavePreset = true }
                    .disabled(selection.value.selectedCount == 0)
                Spacer()
                Text(ByteFormat.human(selection.value.selectedEstimatedBytes))
                    .foregroundStyle(.secondary)
                Button("Clean Selected (\(selection.value.selectedCount))") {
                    showingConfirmation = true
                }
                .disabled(selection.value.selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .confirmationDialog(
            "Delete \(selection.value.selectedCount) selected item(s), freeing about \(ByteFormat.human(selection.value.selectedEstimatedBytes))?",
            isPresented: $showingConfirmation, titleVisibility: .visible
        ) {
            Button("Clean Now", role: .destructive) { onConfirm() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingSavePreset) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save Preset").font(.headline)
                TextField("Preset name", text: $presetName)
                HStack {
                    Spacer()
                    Button("Cancel") { showingSavePreset = false }
                    Button("Save") {
                        onSavePreset(CustomPreset(name: presetName, itemIDs: selection.value.selectedIDs))
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
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { selection.value.selectedIDs.contains(id) }, set: { selection.setSelected($0, id: id) })
    }
}
