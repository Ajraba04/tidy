import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    @State private var configStore = AppConfigStore()

    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "trash.circle") {
            MenuBarContentView()
                .environment(configStore)
        }
        .menuBarExtraStyle(.window)

        Window("Scan Report", id: WindowID.scan) {
            ScanView()
        }
        .windowResizability(.contentSize)

        WindowGroup(id: WindowID.clean, for: Tier.self) { $tier in
            CleanView(tier: tier ?? .safe)
        }
        .windowResizability(.contentSize)

        Window("Custom Clean", id: WindowID.custom) {
            CustomView()
                .environment(configStore)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: WindowID.settings) {
            SettingsView()
                .environment(configStore)
        }
        .windowResizability(.contentSize)

        Window("Welcome to Tidy", id: WindowID.onboarding) {
            OnboardingView()
                .environment(configStore)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let scan = "scan"
    static let clean = "clean"
    static let custom = "custom"
    static let settings = "settings"
    static let onboarding = "onboarding"
}
