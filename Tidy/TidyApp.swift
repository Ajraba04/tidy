import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "trash.circle") {
            MenuBarContentView()
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
    }
}

enum WindowID {
    static let scan = "scan"
    static let clean = "clean"
}
