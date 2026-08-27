import SwiftUI

struct ScanView: View {
    @State private var model: ScanViewModel

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
                }
            case .running:
                ProgressView("Scanning…")
                    .padding()
            case .complete(let report):
                ScanReportView(report: report)
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
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 640)
        .toolbar {
            if case .complete = model.phase {
                ToolbarItem {
                    Button("Rescan") {
                        Task { await model.runScan() }
                    }
                }
            }
        }
    }
}
