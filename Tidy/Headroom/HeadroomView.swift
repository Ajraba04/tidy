import SwiftUI
import TidyCore

/// Optional, timestamped disk/memory/swap/thermal/power signals for one
/// window -- deliberately not a combined score. Every card shows its own
/// "unavailable" state when the underlying probe was denied or the signal
/// is unsupported on this Mac, rather than folding that into a number that
/// would hide it.
struct HeadroomView: View {
    @State private var model: HeadroomViewModel
    @Environment(AppConfigStore.self) private var configStore

    init(services: AppExecutionServices) {
        _model = State(initialValue: HeadroomViewModel(
            monitor: services.systemMonitor,
            cardOrder: resolvedUICardOrder(services.configStore.effectivePolicy)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                ForEach(model.cardOrder, id: \.self) { card in
                    cardView(for: card)
                }

                readinessSection

                if let observedAt = model.snapshot?.observedAt {
                    Text("Measured \(observedAt.formatted(date: .omitted, time: .standard)). Every figure here changes constantly.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 380, minHeight: 440)
        .onAppear { model.onAppear(policy: configStore.effectivePolicy) }
        .onDisappear { model.onDisappear() }
        .onChange(of: configStore.effectivePolicy) { _, policy in model.applyPolicy(policy) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Headroom")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh") { model.refreshNow() }
                    .accessibilityIdentifier("headroom.refresh")
            }
            Text("Independent, timestamped readings -- not a combined health score.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func cardView(for card: String) -> some View {
        switch card {
        case "disk": diskCard
        case "memoryPressure": memoryPressureCard
        case "swap": swapCard
        case "thermal": thermalCard
        case "power": powerCard
        default: EmptyView()
        }
    }

    private var diskCard: some View {
        ReportSection(title: "Disk") {
            if let volumes = model.snapshot?.volumes, !volumes.isEmpty {
                ForEach(volumes) { volume in
                    if let disk = volume.disk {
                        StatsGaugeRow(
                            title: PathDisplay.tilde(volume.displayPath),
                            usedBytes: disk.usedBytes,
                            totalBytes: disk.totalBytes,
                            detail: "\(ByteFormat.human(disk.availableForImportantUsageBytes)) free"
                        )
                        Text("Strictly available: \(ByteFormat.human(disk.availableBytes))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        unavailableRow(title: PathDisplay.tilde(volume.displayPath), reason: volume.unavailableReason)
                    }
                }
            } else {
                unavailableRow(title: "Disk", reason: "No measurement yet")
            }
        }
    }

    private var memoryPressureCard: some View {
        ReportSection(title: "Memory pressure") {
            if let memory = model.snapshot?.memory, let used = memory.usedBytes {
                StatsGaugeRow(title: "Memory", usedBytes: used, totalBytes: memory.totalBytes,
                    detail: "\(ByteFormat.human(used)) used")
            } else {
                unavailableRow(title: "Memory", reason: model.snapshot?.memoryUnavailableReason)
            }
            Text("Kernel pressure level: \(pressureLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pressureLabel: String {
        switch model.snapshot?.memoryPressureLevel {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case nil: return "Not reported yet"
        }
    }

    private var swapCard: some View {
        ReportSection(title: "Swap") {
            if let swap = model.snapshot?.swap {
                StatsGaugeRow(title: "Swap", usedBytes: swap.usedBytes, totalBytes: max(swap.totalBytes, 1),
                    detail: "\(ByteFormat.human(swap.usedBytes)) used")
            } else {
                unavailableRow(title: "Swap", reason: model.snapshot?.swapUnavailableReason)
            }
            if let rate = model.snapshot?.pageOutRatePerSecond {
                Text("Paging out ~\(ByteFormat.human(Int64(rate)))/s -- a pressure indicator, not a measurement of disk writes and not proof swap will be cleared.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No page-out rate yet -- needs two samples on the same boot.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var thermalCard: some View {
        ReportSection(title: "Thermal") {
            Text(thermalLabel)
                .font(.callout)
        }
    }

    private var thermalLabel: String {
        switch model.snapshot?.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        case nil: return "Not available on this Mac"
        @unknown default: return "Unrecognized state"
        }
    }

    private var powerCard: some View {
        ReportSection(title: "Power") {
            switch model.snapshot?.isLowPowerModeEnabled {
            case .some(true): Text("Low Power Mode is on")
            case .some(false): Text("Low Power Mode is off")
            case nil: Text("Not available")
            }
        }
    }

    private var readinessSection: some View {
        let targetBytes = resolvedHeadroomTargetBytes(configStore.effectivePolicy)
        let readiness = model.readiness(targetBytes: targetBytes)
        return ReportSection(title: "Build headroom") {
            switch readiness {
            case .targetMet:
                Text("Target met on \(model.primaryVolume.map { PathDisplay.tilde($0.displayPath) } ?? "this volume").")
                    .font(.callout)
                Text("This means free space currently covers the configured target -- it is not a guarantee a specific build will still fit when it runs.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            case .belowTarget(let shortfall):
                Text("\(ByteFormat.human(shortfall)) short of target.")
                    .font(.callout)
            case .unavailable:
                Text(targetBytes == nil ? "Headroom target is unavailable until the volume and its capacity can be resolved." : "Available space could not be measured.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func unavailableRow(title: String, reason: String?) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(reason ?? "Unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
