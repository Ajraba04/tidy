import SwiftUI
import TidyCore

struct MenuBarContentView: View {
    @State private var refresher: StatsRefresher
    @Environment(\.openWindow) private var openWindow
    @Environment(AppConfigStore.self) private var configStore

    init(services: AppExecutionServices) {
        _refresher = State(initialValue: StatsRefresher(monitor: services.systemMonitor))
    }

    private var disk: DiskStats? { refresher.snapshot?.volumes.first?.disk }
    private var memory: MemoryStats? { refresher.snapshot?.memory }
    private var swap: SwapStats? { refresher.snapshot?.swap }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tidy")
                .font(.headline)

            if let reason = refresher.snapshot?.unavailableReason {
                Label(reason, systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let disk {
                    StatsGaugeRow(
                        title: "Disk",
                        usedBytes: disk.usedBytes,
                        totalBytes: disk.totalBytes,
                        detail: "\(ByteFormat.human(disk.availableForImportantUsageBytes, units: unitStyle)) free"
                    )
                }

                if let memory, let used = memory.usedBytes {
                    StatsGaugeRow(
                        title: "Memory",
                        usedBytes: used,
                        totalBytes: memory.totalBytes,
                        detail: "\(ByteFormat.human(used, units: unitStyle)) used"
                    )
                } else if refresher.snapshot != nil {
                    // A denied/unsupported read is reported honestly, never as zero used.
                    Text("Memory: unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let swap, swap.totalBytes > 0 {
                    StatsGaugeRow(
                        title: "Swap",
                        usedBytes: swap.usedBytes,
                        totalBytes: swap.totalBytes,
                        detail: "\(ByteFormat.human(swap.usedBytes, units: unitStyle)) used"
                    )
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ModeButton(title: "Scan", subtitle: "See what's using space, nothing deleted") {
                    open(WindowID.scan)
                }

                ModeButton(title: "Headroom", subtitle: "Live disk, memory, swap and pressure signals") {
                    open(WindowID.headroom)
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

            if !configStore.config.hasCompletedOnboarding {
                Button("Set up Tidy…") {
                    open(WindowID.onboarding)
                }
            }

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
        }
        .onDisappear { refresher.onPopoverDisappear() }
    }

    private var unitStyle: ByteUnitStyle {
        resolvedUIUnitStyle(configStore.acknowledgedEffectivePolicy)
    }

    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func open<D: Hashable & Codable>(_ id: String, value: D) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id, value: value)
    }
}
