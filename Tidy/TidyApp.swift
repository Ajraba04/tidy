import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    @State private var bootstrap: AppBootstrapState
    private let productionPaths: AppStoragePaths?

    init() {
        _bootstrap = State(initialValue: AppBootstrapState())
        productionPaths = Self.resolveProductionPaths()
    }

    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "trash.circle") {
            withServices { services in
                VStack(alignment: .leading, spacing: 0) {
                    MenuBarContentView()
                        .environment(services.configStore)
                    if services.activeScanSessionID != nil {
                        Divider()
                        Button("Cancel Scan") {
                            Task { await services.cancelActiveScan() }
                        }
                        .accessibilityIdentifier("menuBar.cancelScan")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Scan Report", id: WindowID.scan) {
            withServices { services in
                ScanView(services: services)
            }
        }
        .windowResizability(.contentSize)

        WindowGroup(id: WindowID.clean, for: Tier.self) { $tier in
            withServices { services in
                CleanView(tier: tier ?? .safe, services: services)
            }
        }
        .windowResizability(.contentSize)

        Window("Custom Clean", id: WindowID.custom) {
            withServices { services in
                CustomView(services: services)
                    .environment(services.configStore)
            }
        }
        .windowResizability(.contentSize)

        Window("Settings", id: WindowID.settings) {
            withServices { services in
                VStack {
                    if let message = services.persistenceError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding()
                    }
                    SettingsView()
                        .environment(services.configStore)
                }
            }
        }
        .windowResizability(.contentSize)

        Window("Welcome to Tidy", id: WindowID.onboarding) {
            withServices { services in
                VStack {
                    if let message = services.persistenceError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding()
                    }
                    OnboardingView()
                        .environment(services.configStore)
                }
            }
        }
        .windowResizability(.contentSize)
    }

    @ViewBuilder
    private func withServices<Content: View>(
        @ViewBuilder content: (AppExecutionServices) -> Content
    ) -> some View {
        Group {
            switch bootstrap.status {
            case .notStarted, .loading:
                ProgressView("Loading settings…")
                    .frame(minWidth: 320, minHeight: 200)
            case .ready:
                if let services = bootstrap.services {
                    content(services)
                } else {
                    recoveryUnavailable
                }
            case .recovery:
                recoveryUnavailable
            case .unavailable:
                storageUnavailable
            }
        }
        .task { await startBootstrap() }
    }

    @MainActor
    private func startBootstrap() async {
        guard bootstrap.status == .notStarted || bootstrap.status == .loading else { return }
        guard let productionPaths else {
            bootstrap.storagePathUnavailable()
            return
        }
        await bootstrap.start(paths: productionPaths).value
    }

    private var recoveryUnavailable: some View {
        ContentUnavailableView("Settings Recovery Required", systemImage: "exclamationmark.triangle",
            description: Text(bootstrap.services?.persistenceError
                ?? "Tidy could not validate its settings or execution records. Cleanup and settings changes remain disabled."))
            .frame(minWidth: 320, minHeight: 200)
    }

    private var storageUnavailable: some View {
        ContentUnavailableView("Settings Storage Unavailable", systemImage: "exclamationmark.triangle",
            description: Text("Tidy could not locate its application support directory. Cleanup is disabled."))
            .frame(minWidth: 320, minHeight: 200)
    }

    private static func resolveProductionPaths() -> AppStoragePaths? {
        let homePath = NSHomeDirectory()
        guard homePath.hasPrefix("/"), !homePath.utf8.contains(0),
              let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let home = URL(fileURLWithPath: homePath, isDirectory: true).standardizedFileURL
        let base = support.standardizedFileURL.appendingPathComponent("Tidy", isDirectory: true)
        guard home.isFileURL, support.isFileURL, home.path.hasPrefix("/"),
              support.path.hasPrefix("/") else { return nil }
        return AppStoragePaths(home: home,
            settings: base.appendingPathComponent("config.json"),
            journal: base.appendingPathComponent("execution", isDirectory: true))
    }
}

enum WindowID {
    static let scan = "scan"
    static let clean = "clean"
    static let custom = "custom"
    static let settings = "settings"
    static let onboarding = "onboarding"
}
