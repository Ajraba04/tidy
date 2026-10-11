import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    private static let runtimeVerificationBundleIdentifier =
        "io.github.ajraba04.Tidy.ProductionRuntimeVerification"
#if TIDY_RUNTIME_TEST_HOST
    @NSApplicationDelegateAdaptor(RuntimeTestAppDelegate.self)
    private var runtimeTestAppDelegate
#else
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self)
    private var appTerminationDelegate
#endif
    @State private var features: AppFeatureModels?
    @State private var bootstrap: AppBootstrapState
    private let productionPaths: AppStoragePaths?
#if TIDY_RUNTIME_TEST_HOST
    private let runtimeScenario: RuntimeTestScenario
#endif

    init() {
        _bootstrap = State(initialValue: AppBootstrapState())
#if TIDY_RUNTIME_TEST_HOST
        NSWindow.allowsAutomaticWindowTabbing = false
        let arguments = ProcessInfo.processInfo.arguments
        let scenario = RuntimeTestComposition.scenario(processArguments: arguments)
        runtimeScenario = scenario
        if Bundle.main.bundleIdentifier == Self.runtimeVerificationBundleIdentifier {
            productionPaths = RuntimeTestComposition.makePaths(scenario: scenario,
                cleanupOnTermination: arguments.contains(
                    "--tidy-runtime-cleanup-on-termination"))
        } else {
            productionPaths = nil
        }
#else
        productionPaths = Bundle.main.bundleIdentifier
            == Self.runtimeVerificationBundleIdentifier ? nil : Self.resolveProductionPaths()
#endif
    }

    var body: some Scene {
#if TIDY_RUNTIME_TEST_HOST
        WindowGroup("Tidy Production Runtime Verification",
                    id: RuntimeTestComposition.controlWindowID) {
            withServices(accessibilityLabel: "Runtime verification controls") { services in
                RuntimeTestControlView(services: services, scenario: runtimeScenario,
                    manualServices: features?.manualServices)
            }
        }
        .defaultSize(width: 620, height: 540)
        .commands {
            CommandMenu("Runtime Verification") {
                Button("Show Verification Controls") {
                    RuntimeAuditControls.show()
                }
                Button("Hide Verification Controls") {
                    RuntimeAuditControls.hide()
                }
            }
        }
#endif

        MenuBarExtra {
            withServices(accessibilityLabel: "Tidy menu") { services in
                VStack(alignment: .leading, spacing: 0) {
                    MenuBarContentView(services: services)
                        .environment(services.configStore)
                    if services.hasActiveConfirmedExecution {
                        Divider()
                        if let progress = services.executionProgress {
                            Text("Cleanup: \(progress.completedEffects) of \(progress.scheduledEffects)")
                                .font(.caption).padding(.horizontal, 16)
                        }
                        Button("Cancel Cleanup") { services.cancelConfirmedExecution() }
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    if services.liveRecoveryAdmission != .ready {
                        Button("Reconcile Cleanup Recovery") {
                            Task { await services.reconcileExecutionRecovery() }
                        }.padding(.horizontal, 16)
                    }
                    if features?.developer.isScanning == true {
                        Button("Cancel Developer Inventory") { features?.developer.cancel() }
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
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
        } label: {
            Image(systemName: "trash.circle")
                .accessibilityLabel("Tidy")
                .modifier(AssistanceNavigationHost(model: features?.assistance))
                .task { await startBootstrap() }
        }
        .menuBarExtraStyle(.window)

        Window("Scan Report", id: WindowID.scan) {
            withServices(accessibilityLabel: "Scan report") { services in
                ScanView(services: services)
            }
        }
        .windowResizability(.contentSize)

        Window("Headroom", id: WindowID.headroom) {
            withServices(accessibilityLabel: "Headroom") { services in
                HeadroomView(services: services)
                    .environment(services.configStore)
            }
        }
        .windowResizability(.contentSize)

        WindowGroup(id: WindowID.clean, for: Tier.self) { $tier in
            withServices(accessibilityLabel: "Cleanup review") { services in
                CleanView(tier: tier ?? .safe, services: services)
            }
        }
        .windowResizability(.contentSize)

        Window("Developer Workspace", id: WindowID.developer) {
            withServices(accessibilityLabel: "Developer workspace") { services in
                if let features {
                    DeveloperWorkspaceView(model: features.developer, manualServices: features.manualServices,
                        localAuthority: services.configStore.localAuthoritySnapshot,
                        policy: services.configStore.acknowledgedEffectivePolicy)
                }
            }
        }

        Window("Assistance and Local Consent", id: WindowID.assistance) {
            withServices(accessibilityLabel: "Assistance and local consent") { _ in
                if let features { AssistanceView(model: features.assistance) }
            }
        }

        Window("Custom Clean", id: WindowID.custom) {
            withServices(accessibilityLabel: "Custom cleanup") { services in
                CustomView(services: services)
                    .environment(services.configStore)
            }
        }
        .windowResizability(.contentSize)

        Window("Settings", id: WindowID.settings) {
            withServices(accessibilityLabel: "Settings") { services in
                VStack {
                    if let message = services.persistenceError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .padding()
                    }
                    if let message = services.historyPersistenceError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                    }
                    SettingsView(optionalDataControls: AnyView(OptionalDataControls(services: services)))
                        .environment(services.configStore)
                }
            }
        }
        .windowResizability(.contentSize)

        Window("Welcome to Tidy", id: WindowID.onboarding) {
            withServices(accessibilityLabel: "Welcome to Tidy") { services in
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
        accessibilityLabel: String,
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
        .background(SceneContentAccessibilityLabel(label: accessibilityLabel)
            .frame(width: 0, height: 0))
        .task { await startBootstrap() }
#if TIDY_RUNTIME_TEST_HOST
        .modifier(RuntimeTestAppearance())
#endif
    }

    @MainActor
    private func startBootstrap() async {
        guard bootstrap.status == .notStarted || bootstrap.status == .loading else { return }
        guard let productionPaths else {
            bootstrap.storagePathUnavailable()
            return
        }
        await bootstrap.start(paths: productionPaths).value
        if let services = bootstrap.services {
            if features == nil { features = AppFeatureModels(services: services) }
#if !TIDY_RUNTIME_TEST_HOST
            appTerminationDelegate.bind(services: services)
#endif
        }
    }

    private var recoveryUnavailable: some View {
        VStack {
            ContentUnavailableView("Settings Recovery Required", systemImage: "exclamationmark.triangle",
                description: Text(bootstrap.services?.persistenceError
                    ?? "Tidy could not validate its settings or execution records. Cleanup and settings changes remain disabled."))
            if let services = bootstrap.services, services.liveRecoveryAdmission != .ready {
                Button("Retry Cleanup Verification") {
                    Task {
                        _ = await services.reconcileExecutionRecovery()
                        bootstrap.refreshRecoveryDisposition()
                    }
                }
                if let report = services.lastRecoveryReport {
                    Text("\(report.reconciledEffects) of \(report.inspectedEffects) effects reconciled. \(report.disposition.rawValue)")
                        .font(.caption)
                }
            }
#if TIDY_RUNTIME_TEST_HOST
            if let services = bootstrap.services {
                Text("load:\(String(describing: services.settingsLoad.disposition)) "
                     + "recovery:\(String(describing: services.settingsLoad.recoveryReason)) "
                     + "journal:\(String(describing: services.initialJournalAdmission)) "
                     + "settings:\(services.paths.settings.path)")
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("runtime.bootstrap.diagnostic")
                RuntimeTestRecoveryAttestationView(services: services,
                    scenario: runtimeScenario)
            }
#endif
        }
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

/// The menu-bar label remains mounted while its menu and every review window
/// are closed. It supplies the app's sole navigation owner with a scene-aware
/// window opener; destination views only render selected state.
private struct AssistanceNavigationHost: ViewModifier {
    let model: AssistanceModel?
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: model.map { ObjectIdentifier($0) }, initial: true) { _, _ in
            let opener = openWindow
            model?.bindNavigationHandler { navigation in
                switch navigation {
                case .headroomReview:
                    opener(id: WindowID.headroom)
                case .budgetReview:
                    opener(id: WindowID.assistance)
                case .maintenance(.reviewCache):
                    opener(id: WindowID.developer)
                }
            }
        }
    }
}

/// SwiftUI's macOS hosting container is a separate accessibility group from its
/// declarative children. Label that public AppKit container without combining or
/// hiding any of the scene's independently accessible controls.
private struct SceneContentAccessibilityLabel: NSViewRepresentable {
    let label: String

    func makeNSView(context: Context) -> LabelView {
        let view = LabelView(frame: .zero)
        view.setAccessibilityElement(false)
        view.label = label
        return view
    }

    func updateNSView(_ view: LabelView, context: Context) {
        view.label = label
        view.applyLabel()
    }

    final class LabelView: NSView {
        var label = ""

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyLabel()
        }

        func applyLabel() {
            window?.contentView?.setAccessibilityLabel(label)
        }
    }
}

enum WindowID {
    static let scan = "scan"
    static let headroom = "headroom"
    static let clean = "clean"
    static let custom = "custom"
    static let settings = "settings"
    static let onboarding = "onboarding"
    static let developer = "developer"
    static let assistance = "assistance"
}
