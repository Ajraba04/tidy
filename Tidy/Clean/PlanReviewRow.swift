import SwiftUI
import TidyCore

struct PlanReviewRow: View {
    let item: PlannedItem
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle(isOn: $isSelected) {
                EmptyView()
            }
            .labelsHidden()
            .disabled(!item.review.isSelectable)
            .accessibilityLabel(item.title)
            .accessibilityHint(item.review.reason)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                    Spacer()
                    Text(ByteFormat.human(item.estimatedBytes)).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(item.review.reason).font(.caption).foregroundStyle(.secondary)
                if let dangerNote = item.dangerNote {
                    Label(dangerNote, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if let costNote = item.costNote {
                    Text(costNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
