import SwiftUI
import TidyCore

struct CleanResultsView: View {
    let report: RunReport

    var body: some View {
        let presentation = RunReportPresentation(report: report)
        List {
            Section {
                if !presentation.measurementsAvailable {
                    if let message = presentation.admissionMessage {
                        Text(message)
                    }
                    LabeledContent("Disk and memory", value: presentation.memoryText)
                } else {
                    HStack {
                        Text("Removed allocation")
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

                    // The estimate and what the disk actually did are two
                    // different numbers, and showing only the first is how a
                    // cleaner ends up looking like it lied. `measuredDeltaBytes`
                    // existed on RunReport from the start but was displayed
                    // nowhere.
                    HStack {
                        Text("Disk free space rose by")
                        Spacer()
                        Text(ByteFormat.human(report.measuredDeltaBytes))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Memory returned")
                        Spacer()
                        Text(presentation.memoryText)
                            .foregroundStyle(.secondary)
                    }
                    Text("Memory is measured separately from disk and is never added to the freed total.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if report.freedFigureNeedsReconciling {
                        Text("""
                             Removed allocation and observed free space differ. Open files, APFS sharing, \
                             snapshots, and concurrent disk activity can affect these numbers. \
                             Neither figure proves physical space reclaimed by this cleanup.
                             """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("APFS snapshots can delay space showing up in Finder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Results (\(report.results.count))") {
                ForEach(report.results) { result in
                    HStack {
                        Image(systemName: result.succeeded ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(result.succeeded ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                            if let status = result.effectStatus {
                                Text(status.rawValue.capitalized)
                                    .font(.caption)
                                    .accessibilityIdentifier("result.status.\(result.id)")
                            }
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
