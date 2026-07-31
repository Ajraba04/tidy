import SwiftUI
import TidyCore

struct MenuBarContentView: View {
    @State private var refresher = StatsRefresher()
    @Environment(\.openWindow) private var openWindow
    @Environment(AppConfigStore.self) private var configStore
    @State private var hasCheckedOnboarding = false

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
                ModeButton(title: "Scan", subtitle: "See what's using space — nothing deleted") {
                    open(WindowID.scan)
                }

                ModeButton(title: "Safe Clean", subtitle: "Regeneratable caches only") {
                    open(WindowID.clean, value: Tier.safe)
                }

                ModeButton(title: "Normal Clean", subtitle: "+ browsers, Trash, build outputs") {
                    open(WindowID.clean, value: Tier.normal)
                }

                ModeButton(title: "Deep Clean", subtitle: "Everything, including re-downloads") {
                    open(WindowID.clean, value: Tier.deep)
                }

                ModeButton(title: "Custom…", subtitle: "Pick individual items, save presets") {
                    open(WindowID.custom)
                }
            }

            Divider()

            HStack {
                Button("Settings…") {
                    open(WindowID.settings)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            refresher.onPopoverAppear()
            checkOnboardingOnce()
        }
        .onDisappear { refresher.onPopoverDisappear() }
    }

    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func open<D: Hashable & Codable>(_ id: String, value: D) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id, value: value)
    }

    private func checkOnboardingOnce() {
        guard !hasCheckedOnboarding else { return }
        hasCheckedOnboarding = true
        guard !configStore.config.hasCompletedOnboarding else { return }
        open(WindowID.onboarding)
    }
}
