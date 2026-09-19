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
        Text(value)
            .font(.caption)
            .accessibilityLabel("Runtime presentation environment")
            .accessibilityValue(value)
            .accessibilityIdentifier("runtime.appearance.environment")
    }
}
#endif
