import SwiftUI
import TidyCore

struct MenuBarContentView: View {
    @State private var refresher = StatsRefresher()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tidy")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                if let disk = refresher.disk {
                    StatsGaugeRow(
                        title: "Disk",
                        usedBytes: disk.usedBytes,
                        totalBytes: disk.totalBytes,
                        detail: "\(ByteFormat.human(disk.availableForImportantUsageBytes)) free"
                    )
                }

                StatsGaugeRow(
                    title: "Memory",
                    usedBytes: refresher.memory.usedBytes,
                    totalBytes: refresher.memory.totalBytes,
                    detail: "\(ByteFormat.human(refresher.memory.usedBytes)) used"
                )

                if let swap = refresher.swap, swap.totalBytes > 0 {
                    StatsGaugeRow(
                        title: "Swap",
                        usedBytes: swap.usedBytes,
                        totalBytes: swap.totalBytes,
                        detail: "\(ByteFormat.human(swap.usedBytes)) used"
                    )
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ModeButton(title: "Scan", subtitle: "See what's using space — nothing deleted") {}
                ModeButton(title: "Safe Clean", subtitle: "Regeneratable caches only") {}
                ModeButton(title: "Normal Clean", subtitle: "+ browsers, Trash, build outputs") {}
                ModeButton(title: "Deep Clean", subtitle: "Everything, including re-downloads") {}
            }
            .disabled(true)
            .opacity(0.5)

            Divider()

            HStack {
                Button("Settings…") {}
                    .disabled(true)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { refresher.onPopoverAppear() }
        .onDisappear { refresher.onPopoverDisappear() }
    }
}
