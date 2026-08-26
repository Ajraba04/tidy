import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    @State private var services: AppExecutionServices?

    init() {
        let home = NSHomeDirectory()
        guard let configURL = ConfigStore.defaultURL else {
            _services = State(initialValue: nil)
            return
        }
        let config = ConfigStore.load(from: configURL)
        let support = configURL.deletingLastPathComponent()
        _services = State(initialValue: AppExecutionServices(config: config, configURL: configURL,
            homeDirectory: home, journalDirectory: support.appendingPathComponent("execution", isDirectory: true)))
    }

    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "trash.circle") {
            if let services {
                MenuBarContentView()
                    .environment(services.configStore)
            } else {
                storageUnavailable
            }
        }
        .menuBarExtraStyle(.window)

        Window("Scan Report", id: WindowID.scan) {
            if services != nil { ScanView() }
            else { storageUnavailable }
        }
        .windowResizability(.contentSize)

        WindowGroup(id: WindowID.clean, for: Tier.self) { $tier in
            if let services { CleanView(tier: tier ?? .safe, services: services) }
            else { storageUnavailable }
        }
        .windowResizability(.contentSize)

        Window("Custom Clean", id: WindowID.custom) {
            if let services {
                CustomView(services: services)
                    .environment(services.configStore)
            } else { storageUnavailable }
        }
        .windowResizability(.contentSize)

        Window("Settings", id: WindowID.settings) {
            if let services {
                VStack {
                    if let message = services.persistenceError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding()
                    }
                    SettingsView()
                        .environment(services.configStore)
                }
            } else { storageUnavailable }
        }
        .windowResizability(.contentSize)

        Window("Welcome to Tidy", id: WindowID.onboarding) {
            if let services {
                VStack {
                    if let message = services.persistenceError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding()
                    }
                    OnboardingView()
                        .environment(services.configStore)
                }
            } else { storageUnavailable }
        }
        .windowResizability(.contentSize)
    }

    private var storageUnavailable: some View {
        ContentUnavailableView("Settings Storage Unavailable", systemImage: "exclamationmark.triangle",
            description: Text("Tidy could not locate its application support directory. Cleanup is disabled."))
            .frame(minWidth: 320, minHeight: 200)
    }
}

enum WindowID {
    static let scan = "scan"
    static let clean = "clean"
    static let custom = "custom"
    static let settings = "settings"
    static let onboarding = "onboarding"
}
