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
    @State private var auditArrangementStatus = "not arranged"
    @State private var auditArrangementDetail = "not-arranged"

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
            Text("Audit windows: \(auditArrangementStatus)")
                .font(.caption.monospaced())
                .accessibilityLabel("Runtime audit window arrangement")
                .accessibilityValue(auditArrangementDetail)
                .accessibilityIdentifier("runtime.audit.arrangement")
            Button("Arrange audit windows") {
                arrangeAuditWindows()
            }
            .accessibilityIdentifier("runtime.audit.arrange")
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

    private func arrangeAuditWindows() {
        let visibleTitledWindows = NSApp.windows.filter {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        let controls = visibleTitledWindows.filter {
            $0.title == "Tidy Production Runtime Verification"
        }
        guard controls.count == 1 else {
            auditArrangementStatus = "failed (control count)"
            auditArrangementDetail = "failed:expected-one-control found:\(controls.count)"
            return
        }
        let control = controls[0]
        let subjects = visibleTitledWindows.filter { $0 !== control }
        guard subjects.count == 1 else {
            auditArrangementStatus = "failed (subject count)"
            auditArrangementDetail = "failed:expected-one-subject found:\(subjects.count)"
            return
        }
        let subject = subjects[0]
        guard let screen = subject.screen else {
            auditArrangementStatus = "failed (no screen)"
            auditArrangementDetail = "failed:subject-has-no-screen"
            return
        }

        let viewport = screen.visibleFrame
        let gap: CGFloat = 16
        let requiredWidth = control.frame.width + gap + subject.frame.width
        let requiredHeight = max(control.frame.height, subject.frame.height)
        guard requiredWidth <= viewport.width, requiredHeight <= viewport.height else {
            auditArrangementStatus = "failed (no fit)"
            auditArrangementDetail = "failed:no-fit viewport:\(viewport) "
                + "required:\(NSSize(width: requiredWidth, height: requiredHeight))"
            return
        }

        let left = viewport.minX + floor((viewport.width - requiredWidth) / 2)
        let controlFrame = CGRect(
            origin: CGPoint(x: left, y: viewport.maxY - control.frame.height),
            size: control.frame.size)
        let subjectFrame = CGRect(
            origin: CGPoint(x: controlFrame.maxX + gap,
                            y: viewport.maxY - subject.frame.height),
            size: subject.frame.size)
        guard viewport.contains(controlFrame), viewport.contains(subjectFrame) else {
            auditArrangementStatus = "failed (calculation)"
            auditArrangementDetail = "failed:calculated-frame-outside viewport:\(viewport) "
                + "control:\(controlFrame) subject:\(subjectFrame)"
            return
        }

        control.setFrameOrigin(controlFrame.origin)
        subject.setFrameOrigin(subjectFrame.origin)
        let finalControlFrame = control.frame
        let finalSubjectFrame = subject.frame
        let isOnscreen = viewport.contains(finalControlFrame)
            && viewport.contains(finalSubjectFrame)
        let isDisjoint = !finalControlFrame.intersects(finalSubjectFrame)
        guard isOnscreen, isDisjoint,
              finalControlFrame.size == controlFrame.size,
              finalSubjectFrame.size == subjectFrame.size else {
            auditArrangementStatus = "failed (postcondition)"
            auditArrangementDetail = "failed:postcondition viewport:\(viewport) "
                + "control:\(finalControlFrame) subject:\(finalSubjectFrame)"
            return
        }
        auditArrangementStatus = "arranged"
        auditArrangementDetail = "arranged:onscreen viewport:\(viewport) "
            + "control:\(finalControlFrame) subject:\(finalSubjectFrame) "
            + "subject-title:\(subject.title) gap:\(gap)"
    }
}
#endif
