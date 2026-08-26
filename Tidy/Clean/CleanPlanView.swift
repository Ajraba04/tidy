import SwiftUI
import TidyCore

struct CleanPlanView: View {
    @Bindable var selection: PlanSelectionModel
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if selection.value.reviewItems.isEmpty {
                ContentUnavailableView(
                    "Nothing to Clean",
                    systemImage: "checkmark.circle",
                    description: Text("\(selection.value.plan.tier.title) found nothing on this machine right now.")
                )
            } else {
                List {
                    Section {
                        HStack {
                            Text("Estimated space to free")
                            Spacer()
                            Text(ByteFormat.human(selection.value.selectedEstimatedBytes))
                                .bold()
                        }
                    }

                    Section("Items (\(selection.value.reviewItems.count))") {
                        ForEach(selection.value.reviewItems) { item in
                            PlanReviewRow(item: item, isSelected: selectionBinding(for: item.id))
                        }
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Clean Now") {
                        selection.beginConfirmation()
                    }
                    .disabled(!selection.canConfirm)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .confirmationDialog(
            "Delete \(selection.frozenPresentation?.selectedCount ?? 0) item(s), estimated at \(ByteFormat.human(selection.frozenPresentation?.estimatedBytes ?? 0))?",
            isPresented: $selection.showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Now", role: .destructive) {
                onConfirm()
            }
            .disabled(!selection.canConfirm)
            Button("Cancel", role: .cancel) { selection.cancelConfirmation() }
        }
    }

    private func selectionBinding(for id: String) -> Binding<Bool> {
        Binding(get: { selection.value.selectedIDs.contains(id) }, set: { selection.setSelected($0, id: id) })
    }
}
