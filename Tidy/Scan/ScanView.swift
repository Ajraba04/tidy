import SwiftUI
import TidyCore

struct ScanView: View {
    @State private var model: ScanViewModel
    @State private var confirmsFullHome = false

    init(services: AppExecutionServices) {
        _model = State(initialValue: ScanViewModel(services: services))
    }

    var body: some View {
        VStack {
            switch model.phase {
            case .idle:
                ContentUnavailableView {
                    Label("Scan this Mac", systemImage: "magnifyingglass")
                } description: {
                    Text("Read-only. Nothing is deleted or modified.")
                } actions: {
                    Button("Run Scan") {
                        Task { await model.runScan() }
                    }
                    Button("Full Home Scan…") { confirmsFullHome = true }
                }
                .accessibilityIdentifier("scan.phase.idle")
            case .running:
                VStack(spacing: 12) {
                    ProgressView("Scanning…")
                    Button("Cancel") {
                        Task { await model.cancelScan() }
                    }
                }
                .padding()
                .accessibilityIdentifier("scan.phase.running")
            case .runningPartial(let result):
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        ProgressView()
                        Text("Scanning within the authorized scope…")
                        Spacer()
                        Button("Cancel") { Task { await model.cancelScan() } }
                    }
                    .padding(8)
                    ScanReportView(report: result.report)
                }
                .accessibilityIdentifier("scan.phase.runningPartial")
            case .partial(let result):
                VStack(alignment: .leading, spacing: 0) {
                    partialBanner(result)
                    if result.continuationAvailable {
                        HStack {
                            Button("Continue") { Task { await model.continueScan() } }
                            Button("Cancel") { Task { await model.cancelScan() } }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    ScanReportView(report: result.report)
                }
                .accessibilityIdentifier("scan.phase.partial")
            case .paused:
                ContentUnavailableView {
                    Label("Scan Paused", systemImage: "pause.circle")
                } description: {
                    Text("System conditions are constrained right now. Try again shortly.")
                } actions: {
                    Button("Try Again") {
                        Task { await model.runScan() }
                    }
                }
                .accessibilityIdentifier("scan.phase.paused")
            case .cancelled:
                ContentUnavailableView {
                    Label("Scan Cancelled", systemImage: "xmark.circle")
                } description: {
                    Text("The scan was cancelled before it finished.")
                } actions: {
                    Button("Scan Again") {
                        Task { await model.runScan() }
                    }
                }
                .accessibilityIdentifier("scan.phase.cancelled")
            case .complete(let report):
                ScanReportView(report: report)
                    .accessibilityIdentifier("scan.phase.complete")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Scan Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task { await model.runScan() }
                    }
                }
                .accessibilityIdentifier("scan.phase.failed")
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 640)
        .toolbar {
            if isRescannable {
                ToolbarItem {
                    Button("Rescan") {
                        Task { await model.runScan() }
                    }
                }
            }
        }
        .task { model.attachToActiveScanIfNeeded() }
        .onDisappear { model.detachSubscription() }
        .confirmationDialog("Scan your full home folder once?", isPresented: $confirmsFullHome) {
            Button("Scan Full Home") { Task { await model.runFullHomeScan() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This one-run permission expires and is not reused by another window or scan.")
        }
    }

    private var isRescannable: Bool {
        switch model.phase {
        case .complete, .cancelled, .failed: return true
        case .partial: return false
        case .idle, .running, .runningPartial, .paused: return false
        }
    }

    @ViewBuilder
    private func partialBanner(_ result: CoreScanResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(result.continuationAvailable
                ? "Partial results. More can still be scanned."
                : "Partial results. Continuing this scan is not available.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(result.continuationAvailable
            ? "scan.partial.continueAvailable" : "scan.partial.continueUnavailable")
    }
}
