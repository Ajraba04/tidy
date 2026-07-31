import SwiftUI

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
    }
}

enum WindowID {
    static let scan = "scan"
}
