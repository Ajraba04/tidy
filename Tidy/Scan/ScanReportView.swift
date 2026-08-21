import SwiftUI
import TidyCore

struct ScanReportView: View {
    let report: ScanReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryRow

                if !report.restartOnlyReclaim.isEmpty {
                    RestartReclaimSection(survey: report.restartOnlyReclaim)
                }

                ReportSection(title: "Big, and not covered by Tidy") {
                    RankedItemsList(
                        items: report.unclaimedBySize,
                        emptyText: "Nothing large sits outside what Tidy's catalog covers."
                    )
                    Text("Tidy has no rule that touches these. Reported so coverage gaps are visible, not offered for deletion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ReportSection(title: "Top level of home") {
                    RankedItemsList(items: report.topLevelHomeRanking, emptyText: "Nothing measured.")
                }

                ReportSection(title: "Inside ~/Library") {
                    RankedItemsList(items: report.libraryRanking, emptyText: "Nothing measured.")
                }

                ReportSection(title: "Files over 1 GB") {
                    RankedItemsList(items: report.filesOver1GB, emptyText: "No single file is over 1 GB.")
                }

                ReportSection(title: "Stale node_modules") {
                    SimpleTextList(
                        lines: report.staleNodeModules.map { PathDisplay.tilde($0.path) },
                        emptyText: "None found under your configured project roots."
                    )
                }

                ReportSection(title: "APFS local snapshots") {
                    SimpleTextList(
                        lines: report.localSnapshots.map(\.dateComponent),
                        emptyText: "No local snapshots are pinning disk space."
                    )
                }

                ReportSection(title: "Idle simulator runtimes") {
                    SimpleTextList(
                        lines: report.idleSimulatorRuntimes.map { "\($0.name): no devices use it" },
                        emptyText: "Every installed runtime is in use."
                    )
                }

                ReportSection(title: "User LaunchAgents (\(report.launchAgents.count))") {
                    SimpleTextList(lines: report.launchAgents, emptyText: "None.")
                }

                ReportSection(title: "Top memory consumers") {
                    ForEach(report.topMemoryConsumers) { usage in
                        HStack {
                            Text(usage.name).font(.callout).lineLimit(1)
                            Spacer()
                            Text(ByteFormat.human(usage.residentBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ReportSection(title: "Detected toolchains") {
                    Text(report.detectedTools.map(\.displayName).sorted().joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("Generated \(report.generatedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let disk = report.diskStats {
                Text("Disk: \(ByteFormat.human(disk.availableForImportantUsageBytes)) free of \(ByteFormat.human(disk.totalBytes))")
            }
            if let container = report.containerSpace {
                Text("Container free space: \(ByteFormat.human(container.freeBytes))")
                    .foregroundStyle(.secondary)
            }
            Text("Memory used: \(ByteFormat.human(report.memoryStats.usedBytes)) of \(ByteFormat.human(report.memoryStats.totalBytes))")
            if let swap = report.swapStats, swap.totalBytes > 0 {
                Text("Swap used: \(ByteFormat.human(swap.usedBytes)) of \(ByteFormat.human(swap.totalBytes))")
            }
        }
        .font(.callout)
    }
}
