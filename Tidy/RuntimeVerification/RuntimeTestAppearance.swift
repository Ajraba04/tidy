#if TIDY_RUNTIME_TEST_HOST
import SwiftUI

/// Fixed presentation inputs for the disposable native host. These never write
/// system preferences and are not compiled into the distributed application.
struct RuntimeTestAppearance: ViewModifier {
    private let arguments = Set(ProcessInfo.processInfo.arguments)

    func body(content: Content) -> some View {
        if arguments.contains("--tidy-runtime-appearance-light") {
            configured(content, scheme: .light)
        } else if arguments.contains("--tidy-runtime-appearance-dark") {
            configured(content, scheme: .dark)
        } else {
            content
        }
    }

    private func configured(_ content: Content, scheme: ColorScheme) -> some View {
        content
            .preferredColorScheme(scheme)
            .environment(\.colorScheme, scheme)
            // The SDK exposes read-only public getters and underscored writable
            // environment keys. Use those keys only in this compiled-out host;
            // the attestation reads the actual public getters seen by scenes.
            .environment(\._colorSchemeContrast,
                arguments.contains("--tidy-runtime-increased-contrast") ? .increased : .standard)
            .environment(\._accessibilityReduceMotion,
                arguments.contains("--tidy-runtime-reduce-motion"))
    }
}

struct RuntimeTestAppearanceAttestation: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var value: String {
        "\(scheme == .dark ? "dark" : "light") "
            + "\(contrast == .increased ? "increased" : "standard") "
            + "motion:\(reduceMotion ? "reduced" : "normal")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption)
                .accessibilityLabel("Runtime presentation environment")
                .accessibilityValue(value)
                .accessibilityIdentifier("runtime.appearance.environment")
            if ProcessInfo.processInfo.arguments.contains("--tidy-runtime-compact") {
                RuntimeCompactWindowGeometry()
            }
        }
    }
}

private struct RuntimeCompactWindowGeometry: View {
    @State private var geometry = "not-open"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(geometry)
                .font(.caption.monospaced())
                .accessibilityLabel("Runtime Settings window geometry")
                .accessibilityValue(geometry)
                .accessibilityIdentifier("runtime.settings.geometry")
            Button("Set compact Settings size") {
                guard let window = NSApp.windows.first(where: { $0.title == "Settings" }) else {
                    return
                }
                window.setContentSize(NSSize(width: 480, height: 520))
                capture(window)
            }
            .accessibilityIdentifier("runtime.settings.compact")
            Button("Hide verification controls") {
                RuntimeAuditControls.hide()
            }
            .accessibilityIdentifier("runtime.audit.hide")
        }
            .onReceive(NotificationCenter.default.publisher(
                for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      window.title == "Settings" else { return }
                capture(window)
            }
    }

    private func capture(_ window: NSWindow) {
        geometry = "frame:\(window.frame.size) min:\(window.minSize) "
            + "contentMin:\(window.contentMinSize) max:\(window.maxSize) "
            + "resizable:\(window.styleMask.contains(.resizable))"
    }
}

@MainActor
enum RuntimeAuditControls {
    private static let controlTitle = "Tidy Production Runtime Verification"

    static func hide() {
        controlWindow?.orderOut(nil)
    }

    static func show() {
        guard let controlWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        controlWindow.makeKeyAndOrderFront(nil)
    }

    private static var controlWindow: NSWindow? {
        let matches = NSApp.windows.filter { $0.title == controlTitle }
        return matches.count == 1 ? matches[0] : nil
    }
}
#endif
