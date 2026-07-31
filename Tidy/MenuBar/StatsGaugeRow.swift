import SwiftUI
import TidyCore

/// One labeled progress bar: "Disk", "Memory", or "Swap", with a used/total
/// fraction and a human-readable detail string.
struct StatsGaugeRow: View {
    let title: String
    let usedBytes: Int64
    let totalBytes: Int64
    let detail: String

    private var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? .red : (fraction > 0.75 ? .yellow : .accentColor))
        }
    }
}
