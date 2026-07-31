import SwiftUI

@main
struct TidyApp: App {
    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "trash.circle") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
