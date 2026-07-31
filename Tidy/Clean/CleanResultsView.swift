import SwiftUI
import TidyCore

struct CleanResultsView: View {
    let report: RunReport

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Freed")
                    Spacer()
                    Text(ByteFormat.human(report.totalFreedBytes)).bold()
                }
                HStack {
                    Text("Free space before")
                    Spacer()
                    Text(ByteFormat.human(report.freeSpaceBeforeBytes)).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Free space after")
                    Spacer()
                    Text(ByteFormat.human(report.freeSpaceAfterBytes)).foregroundStyle(.secondary)
                }
                Text("APFS snapshots can delay space showing up in Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Results (\(report.results.count))") {
                ForEach(report.results) { result in
                    HStack {
                        Image(systemName: result.succeeded ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(result.succeeded ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                            if let message = result.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if result.freedBytes > 0 {
                            Text(ByteFormat.human(result.freedBytes))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}
