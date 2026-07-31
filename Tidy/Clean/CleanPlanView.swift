import SwiftUI
import TidyCore

struct CleanPlanView: View {
    let plan: CleanPlan
    let onConfirm: () -> Void

    @State private var showingConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if plan.nonEmptyItems.isEmpty {
                ContentUnavailableView(
                    "Nothing to Clean",
                    systemImage: "checkmark.circle",
                    description: Text("\(plan.tier.title) found nothing on this machine right now.")
                )
            } else {
                List {
                    Section {
                        HStack {
                            Text("Estimated space to free")
                            Spacer()
                            Text(ByteFormat.human(plan.totalEstimatedBytes))
                                .bold()
                        }
                    }

                    Section("Items (\(plan.nonEmptyItems.count))") {
                        ForEach(plan.nonEmptyItems) { item in
                            PlannedItemRow(item: item)
                        }
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Clean Now") {
                        showingConfirmation = true
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .confirmationDialog(
            "Delete \(plan.nonEmptyItems.count) item(s), freeing about \(ByteFormat.human(plan.totalEstimatedBytes))?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Now", role: .destructive) {
                onConfirm()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct PlannedItemRow: View {
    let item: PlannedItem

    var body: some View {
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
            if let costNote = item.costNote {
                Text(costNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
