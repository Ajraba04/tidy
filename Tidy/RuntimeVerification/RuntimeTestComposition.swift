#if TIDY_RUNTIME_TEST_HOST
import Foundation
import Darwin
import SwiftUI
import TidyCore

enum RuntimeTestScenario: String {
    case acknowledged
    case cancelQueued = "cancel-queued"
    case freshDefaults = "fresh-defaults"
    case futureSettings = "future-settings"
    case hiddenOff = "hidden-off"
    case hiddenNoAuthority = "hidden-no-authority"
    case performance50k = "performance-50k"
    case activeCancel20 = "active-cancel-20"
}

/// Exists only in the dedicated runtime-verification target. The distributed
/// Tidy target does not compile this declaration or the condition that calls it.
enum RuntimeTestComposition {
    static let controlWindowID = "runtime-verification"
    private static let fixtureDirectoryPrefix = "tidy-production-runtime-"
    private static let witnessRelativePath = "SyntheticWorkspace/runtime-witness.txt"
    private static let witnessBytes = Data("runtime-witness\n".utf8)
    private static let futureSettingsBytes = Data(
        #"{"schemaVersion":999,"revision":0,"config":{}}"#.utf8)
    nonisolated(unsafe) private static var cleanupRoot: URL?

    static func scenario(processArguments: [String]) -> RuntimeTestScenario {
        let arguments = Set(processArguments)
        if arguments.contains("--tidy-runtime-future-settings") { return .futureSettings }
        if arguments.contains("--tidy-runtime-fresh-defaults") { return .freshDefaults }
        if arguments.contains("--tidy-runtime-cancel-queued") { return .cancelQueued }
        if arguments.contains("--tidy-runtime-hidden-off") { return .hiddenOff }
        if arguments.contains("--tidy-runtime-hidden-no-authority") { return .hiddenNoAuthority }
        if arguments.contains("--tidy-runtime-performance-50k") { return .performance50k }
        if arguments.contains("--tidy-runtime-active-cancel-20") { return .activeCancel20 }
        return .acknowledged
    }

    /// Display-only fixture: no native service or accepted effect token exists.
    static func manualServiceCandidate(home: URL) throws -> ManualServiceOperationBinding {
        let root = try LocalRootApproval.verify(directory: home)
        let tool = try LocalExecutableApproval.verify(executable: URL(fileURLWithPath: "/bin/cat"))
        func json<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        }
        let value: [String: Any] = ["schemaVersion": 1, "adapter": "appleSimulatorShutdownV1",
            "object": ["simulator": ["_0": ["udid": "11111111-2222-3333-4444-555555555555",
                "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                "name": "Owned synthetic review candidate", "state": "Booted", "isAvailable": true]]],
            "producer": ["appleSimulator": ["_0": ["resolver": try json(tool), "simctl": try json(tool),
                "developerDirectory": try json(root), "deviceSet": try json(root),
                "xcodeVersion": "27.0", "xcodeBuild": "27A266a", "coreSimulatorVersion": "1171.7"]]]]
        return try JSONDecoder().decode(ManualServiceOperationBinding.self,
            from: JSONSerialization.data(withJSONObject: value))
    }

    static func makePaths(scenario: RuntimeTestScenario = .acknowledged,
                          cleanupOnTermination: Bool = false) -> AppStoragePaths? {
        let fileManager = FileManager.default
        guard let temporary = canonicalTemporaryDirectory() else { return nil }
        guard let root = makeUniqueRoot(in: temporary) else { return nil }
        cleanupRoot = cleanupOnTermination ? root : nil
        let home = root.appendingPathComponent("home", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        let settings = state.appendingPathComponent("config.json")
        let journal = state.appendingPathComponent("execution", isDirectory: true)

        guard root.path.hasPrefix(temporary.path + "/"),
              !root.path.hasPrefix(NSHomeDirectory() + "/") else {
            _ = removeOwnedRoot(root)
            cleanupRoot = nil
            return nil
        }

        do {
            try createPrivateDirectory(home, fileManager: fileManager)
            try createPrivateDirectory(state, fileManager: fileManager)
            try createPrivateDirectory(journal, fileManager: fileManager)
            switch scenario {
            case .acknowledged, .cancelQueued:
                try seedAcknowledgedSettings(at: settings)
            case .performance50k, .activeCancel20:
                try seedPerformanceSettings(at: settings)
            case .hiddenOff:
                try seedObservationSettings(at: settings, headroomEnabled: false)
            case .hiddenNoAuthority:
                try seedObservationSettings(at: settings, headroomEnabled: true)
            case .freshDefaults:
                break
            case .futureSettings:
                try futureSettingsBytes.write(to: settings)
                try fileManager.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: settings.path)
            }
            try seedSyntheticHome(at: home, fileManager: fileManager,
                performance50k: scenario == .performance50k || scenario == .activeCancel20)
            return AppStoragePaths(home: home, settings: settings, journal: journal)
        } catch {
            _ = removeOwnedRoot(root)
            cleanupRoot = nil
            return nil
        }
    }

    static func witnessURL(home: URL) -> URL {
        home.appendingPathComponent(witnessRelativePath)
    }

    static func attestation(for paths: AppStoragePaths,
                            scenario: RuntimeTestScenario) -> String {
        let fileManager = FileManager.default
        var isHomeDirectory = ObjCBool(false)
        var isJournalDirectory = ObjCBool(false)
        let homeReady = fileManager.fileExists(atPath: paths.home.path,
                                                isDirectory: &isHomeDirectory)
            && isHomeDirectory.boolValue
        let settingsExists = fileManager.fileExists(atPath: paths.settings.path)
        let settingsState: String
        switch scenario {
        case .acknowledged, .cancelQueued, .hiddenOff, .hiddenNoAuthority,
             .performance50k, .activeCancel20:
            settingsState = settingsExists ? "ready" : "missing"
        case .freshDefaults: settingsState = settingsExists ? "unexpected" : "absent"
        case .futureSettings:
            settingsState = (try? Data(contentsOf: paths.settings)) == futureSettingsBytes
                ? "preserved" : "changed"
        }
        let journalReady = fileManager.fileExists(atPath: paths.journal.path,
                                                   isDirectory: &isJournalDirectory)
            && isJournalDirectory.boolValue
        let witnessReady = (try? Data(contentsOf: witnessURL(home: paths.home))) == witnessBytes
        return "home:\(homeReady ? "ready" : "missing") "
            + "settings:\(settingsState) "
            + "journal:\(journalReady ? "ready" : "missing") "
            + "witness:\(witnessReady ? "unchanged" : "changed")"
    }

    static func isIsolated(_ paths: AppStoragePaths) -> Bool {
        guard let temporaryDirectory = canonicalTemporaryDirectory() else { return false }
        let temporary = temporaryDirectory.path + "/"
        let realHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).path + "/"
        let root = paths.home.deletingLastPathComponent().path + "/"
        return root.hasPrefix(temporary)
            && paths.home.deletingLastPathComponent().lastPathComponent
                .hasPrefix(fixtureDirectoryPrefix)
            && !root.hasPrefix(realHome)
            && paths.settings.path.hasPrefix(root)
            && paths.journal.path.hasPrefix(root)
    }

    static var authorizationState: String {
        CleanCatalog.allItems.allSatisfy {
            CapabilityRegistry.denialReason(for: $0.action, itemID: $0.id) != nil
        } ? "all-denied" : "authorization-changed"
    }

    static func cleanupIfRegistered() {
        guard let root = cleanupRoot else { return }
        cleanupRoot = nil
        _ = removeOwnedRoot(root)
    }

    private static func removeOwnedRoot(_ root: URL) -> Bool {
        let rootPath = root.path
        let isCanonicalTemporary = rootPath.hasPrefix("/private/var/folders/")
            || rootPath.hasPrefix("/private/tmp/")
        guard root.lastPathComponent.hasPrefix(fixtureDirectoryPrefix),
              isCanonicalTemporary,
              !rootPath.hasPrefix(NSHomeDirectory() + "/") else { return false }
        var info = stat()
        guard lstat(rootPath, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(),
              info.st_mode & 0o777 == 0o700 else { return false }
        do {
            try FileManager.default.removeItem(at: root)
            return !FileManager.default.fileExists(atPath: rootPath)
        } catch {
            return false
        }
    }

    private static func createPrivateDirectory(_ url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
    }

    private static func makeUniqueRoot(in temporary: URL) -> URL? {
        let template = temporary
            .appendingPathComponent(fixtureDirectoryPrefix + "XXXXXX", isDirectory: true).path
        var mutable: [CChar] = Array(template.utf8CString)
        guard mkdtemp(&mutable) != nil else { return nil }
        return URL(fileURLWithPath: String(cString: mutable), isDirectory: true)
    }

    private static func canonicalTemporaryDirectory() -> URL? {
        let raw = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let expanded: String
        if raw == "/var" || raw.hasPrefix("/var/")
            || raw == "/tmp" || raw.hasPrefix("/tmp/") {
            expanded = "/private" + raw
        } else {
            expanded = raw
        }
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(expanded, &path) != nil else { return nil }
        // Do not call standardizedFileURL here: Foundation rewrites the canonical
        // /private/var spelling back to the root /var symlink that the production
        // O_NOFOLLOW settings loader must reject.
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    private static func seedAcknowledgedSettings(at url: URL) throws {
        let config = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true)
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 1, config: config)
        try writeSettings(envelope, to: url)
    }

    private static func seedObservationSettings(at url: URL, headroomEnabled: Bool) throws {
        let config = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true)
        let preferences = PolicyPreferences(global: PolicyValues(fields: [
            SettingID(rawValue: "feature.headroom"): .bool(headroomEnabled),
            SettingID(rawValue: "monitor.suppressHiddenSampling"): .bool(!headroomEnabled),
            SettingID(rawValue: "monitor.hiddenIntervalSeconds"): .integer(60),
        ]))
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 1, config: config,
                                        preferences: preferences)
        try writeSettings(envelope, to: url)
    }

    private static func seedPerformanceSettings(at url: URL) throws {
        let config = TidyConfig(schemaVersion: 2, hasCompletedOnboarding: true)
        let preferences = PolicyPreferences(global: PolicyValues(fields: [
            SettingID(rawValue: "scan.cacheEnabled"): .bool(false),
        ]))
        let envelope = SettingsEnvelope(schemaVersion: 2, revision: 1, config: config,
                                        preferences: preferences)
        try writeSettings(envelope, to: url)
    }

    private static func writeSettings(_ envelope: SettingsEnvelope, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes: Data = try encoder.encode(envelope)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    private static func seedSyntheticHome(at home: URL, fileManager: FileManager,
                                          performance50k: Bool) throws {
        let workspace = home.appendingPathComponent("SyntheticWorkspace", isDirectory: true)
        try createPrivateDirectory(workspace, fileManager: fileManager)
        try witnessBytes.write(to: witnessURL(home: home))

        let payload = Data(repeating: 0x54, count: 4_096)
        if performance50k { try requirePerformanceHeadroom(at: home) }
        let directoryCount = performance50k ? 500 : 80
        let filesPerDirectory = performance50k ? 100 : 64
        for directoryIndex in 0..<directoryCount {
            let directory = workspace.appendingPathComponent(
                String(format: "batch-%03d", directoryIndex), isDirectory: true)
            try createPrivateDirectory(directory, fileManager: fileManager)
            for fileIndex in 0..<filesPerDirectory {
                let file = directory.appendingPathComponent(
                    String(format: "entry-%03d.bin", fileIndex))
                if performance50k {
                    try createEmptyFile(file)
                } else {
                    try payload.write(to: file)
                }
            }
        }

        var quickRoot = home
        for component in ["Library", "Caches", "typescript", "RuntimeFreshFixture"] {
            quickRoot.appendPathComponent(component, isDirectory: true)
            try createPrivateDirectory(quickRoot, fileManager: fileManager)
        }
        for fileIndex in 0..<32 {
            try payload.write(to: quickRoot.appendingPathComponent(
                String(format: "quick-%02d.bin", fileIndex)))
        }
    }

    private static func requirePerformanceHeadroom(at url: URL) throws {
        var info = statfs()
        guard statfs(url.path, &info) == 0, info.f_bavail >= 0, info.f_bsize > 0 else {
            throw POSIXError(.EIO)
        }
        let (available, overflow) = UInt64(info.f_bavail)
            .multipliedReportingOverflow(by: UInt64(info.f_bsize))
        guard !overflow, available >= 2_147_483_648 else { throw POSIXError(.ENOSPC) }
    }

    private static func createEmptyFile(_ url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                              0o600)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard close(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

private actor RuntimeTestPermitHoldGate {
    private let target: Int
    private var entered = 0
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(target: Int) { self.target = target }

    func hold() async {
        entered += 1
        if entered >= target {
            let waiters = entryWaiters
            entryWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilAllEntered() async {
        if entered >= target { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let enteredWaiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in enteredWaiters { waiter.resume() }
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

@MainActor
private final class RuntimeTestQueuedCancellationBlocker {
    private let services: AppExecutionServices
    private let sessions: BridgeExplicitSessions
    private var blockerSession: WorkSession?
    private var gate: RuntimeTestPermitHoldGate?
    private var tasks: [Task<Void, Never>] = []
    private var released = false

    init(services: AppExecutionServices) {
        self.services = services
        sessions = services.explicitSessions
    }

    func start() async -> String {
        guard blockerSession == nil, gate == nil, tasks.isEmpty else {
            return "failed duplicate-start"
        }
        await sessions.awaitInitialInstall()
        let initial = await sessions.snapshot()
        guard initial.availability == .available, initial.effectiveWorkers > 0,
              initial.active == 0, initial.queued == 0 else {
            return "failed scheduler-not-idle"
        }
        do {
            let session = try await sessions.beginSession(
                requirements: try SchedulerRequirements(features: [.headroom]))
            let gate = RuntimeTestPermitHoldGate(target: initial.effectiveWorkers)
            blockerSession = session
            self.gate = gate
            tasks = (0..<initial.effectiveWorkers).map { _ in
                Task {
                    try? await sessions.withPermit(session: session) { _ in
                        await gate.hold()
                    }
                }
            }
            await gate.waitUntilAllEntered()
            let occupied = await sessions.snapshot()
            guard occupied.active == initial.effectiveWorkers, occupied.queued == 0 else {
                return "failed permits-not-occupied"
            }
            return "ready permits:\(initial.effectiveWorkers) active:\(occupied.active)"
        } catch {
            return "failed \(String(describing: error))"
        }
    }

    func releaseAndAttest() async -> String {
        if !released {
            released = true
            if let blockerSession { await sessions.cancel(session: blockerSession) }
            await gate?.release()
            for task in tasks { await task.value }
            if let blockerSession { await sessions.finish(session: blockerSession) }
            tasks.removeAll()
            blockerSession = nil
            gate = nil
        }
        var scheduler = await sessions.snapshot()
        var registry = await services.scanRegistry.snapshot()
        var leases = await services.systemMonitor.activeExplicitWorkLeaseCountForTesting()
        var watchActive = await services.activeScanIndexWatchIsActiveForTesting()
        var settled = services.activeScanSessionID == nil && registry.activeWork == 0
            && scheduler.active == 0 && scheduler.queued == 0 && scheduler.liveSessions == 0
            && leases == 0 && !watchActive
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !settled, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(10))
            scheduler = await sessions.snapshot()
            registry = await services.scanRegistry.snapshot()
            leases = await services.systemMonitor.activeExplicitWorkLeaseCountForTesting()
            watchActive = await services.activeScanIndexWatchIsActiveForTesting()
            settled = services.activeScanSessionID == nil && registry.activeWork == 0
                && scheduler.active == 0 && scheduler.queued == 0
                && scheduler.liveSessions == 0 && leases == 0 && !watchActive
        }
        let witnessUnchanged = (try? Data(contentsOf: RuntimeTestComposition.witnessURL(
            home: services.paths.home))) == Data("runtime-witness\n".utf8)
        return "\(settled ? "released" : "failed natural-settle") "
            + "serviceActive:\(services.activeScanSessionID != nil) "
            + "registry:\(registry.sessions)/\(registry.activeWork)/"
            + "\(registry.retainedTerminalStates) "
            + "scheduler:\(scheduler.active)/\(scheduler.queued)/\(scheduler.liveSessions) "
            + "leases:\(leases) watch:\(watchActive) "
            + "witness:\(witnessUnchanged ? "unchanged" : "changed")"
    }
}

final class RuntimeTestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        RuntimeTestComposition.cleanupIfRegistered()
    }
}

@MainActor
struct RuntimeTestControlView: View {
    let services: AppExecutionServices
    let scenario: RuntimeTestScenario
    var manualServices: ManualServiceReviewModel? = nil
    @Environment(\.openWindow) private var openWindow
    @State private var queuedCancellationBlocker: RuntimeTestQueuedCancellationBlocker?
    @State private var queuedCancellationState = "not-required"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Production runtime verification")
                .font(.title2.bold())
                .accessibilityIdentifier("runtime.control.title")
            RuntimeTestAppearanceAttestation()
            if scenario == .hiddenOff || scenario == .hiddenNoAuthority {
                RuntimeObservationControl(services: services, scenario: scenario)
            }
            if scenario == .performance50k || scenario == .activeCancel20 {
                RuntimePerformanceControl(services: services, scenario: scenario)
            }
            Text("This dedicated build uses production scenes and services with disposable storage.")
                .fixedSize(horizontal: false, vertical: true)
            Text(scenario.rawValue)
                .accessibilityLabel("Runtime scenario")
                .accessibilityValue(scenario.rawValue)
                .accessibilityIdentifier("runtime.scenario")
            if scenario == .cancelQueued {
                Text(queuedCancellationState)
                    .font(.caption)
                    .accessibilityLabel("Queued cancellation fixture")
                    .accessibilityValue(queuedCancellationState)
                    .accessibilityIdentifier("runtime.cancel.blocker")
                Button("Release cancellation blocker") {
                    Task { @MainActor in await releaseQueuedCancellationBlocker() }
                }
                .disabled(queuedCancellationBlocker == nil)
                .accessibilityIdentifier("runtime.cancel.release")
            }
            cleanupButton
            Button("Inspect Manual Review Fixture") {
                guard let manualServices,
                      let binding = try? RuntimeTestComposition.manualServiceCandidate(home: services.paths.home) else { return }
                manualServices.inspect(binding)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.developer)
            }
            .disabled(manualServices == nil)
            .accessibilityIdentifier("runtime.open.manual.fixture")
            HStack {
                openButton("Open Scan", id: WindowID.scan,
                           identifier: "runtime.open.scan")
                openButton("Open Settings", id: WindowID.settings,
                           identifier: "runtime.open.settings")
                Button("Open Safe Clean") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: WindowID.clean, value: Tier.safe)
                }
                .accessibilityIdentifier("runtime.open.clean.safe")
                openButton("Open Headroom", id: WindowID.headroom,
                           identifier: "runtime.open.headroom")
            }
            Divider()

            pathRow("Synthetic home", value: services.paths.home.path,
                    identifier: "runtime.synthetic.home")
            pathRow("Synthetic settings", value: services.paths.settings.path,
                    identifier: "runtime.synthetic.settings")
            pathRow("Synthetic journal", value: services.paths.journal.path,
                    identifier: "runtime.synthetic.journal")
            pathRow("Synthetic witness",
                    value: RuntimeTestComposition.witnessURL(home: services.paths.home).path,
                    identifier: "runtime.synthetic.witness")

            Text(RuntimeTestComposition.attestation(for: services.paths,
                                                     scenario: scenario))
                .accessibilityLabel("Synthetic storage attestation")
                .accessibilityValue(RuntimeTestComposition.attestation(for: services.paths,
                                                                        scenario: scenario))
                .accessibilityIdentifier("runtime.synthetic.attestation")
            Text(RuntimeTestComposition.isIsolated(services.paths) ? "isolated" : "unsafe")
                .accessibilityLabel("Synthetic storage isolation")
                .accessibilityValue(RuntimeTestComposition.isIsolated(services.paths)
                    ? "isolated" : "unsafe")
                .accessibilityIdentifier("runtime.synthetic.isolation")
            Text(RuntimeTestComposition.authorizationState)
                .accessibilityLabel("Mutation authorization")
                .accessibilityValue(RuntimeTestComposition.authorizationState)
                .accessibilityIdentifier("runtime.authorization")
            Text("\(ProcessInfo.processInfo.processIdentifier)")
                .accessibilityLabel("Runtime host process identifier")
                .accessibilityValue("\(ProcessInfo.processInfo.processIdentifier)")
                .accessibilityIdentifier("runtime.process.pid")
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 540, alignment: .topLeading)
        .task { await startQueuedCancellationBlockerIfNeeded() }
    }

    private func pathRow(_ label: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.bold())
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityLabel(label)
                .accessibilityValue(value)
                .accessibilityIdentifier(identifier)
        }
    }

    private func openButton(_ title: String, id: String, identifier: String) -> some View {
        Button(title) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: id)
        }
        .accessibilityIdentifier(identifier)
    }

    private var cleanupButton: some View {
        Button("Clean up fixture and quit") {
            services.disposeMonitoring()
            Task { @MainActor in
                await RuntimeObservationCoordinator.stopIfActive()
                await RuntimePerformanceCoordinator.stopIfActive()
                _ = await queuedCancellationBlocker?.releaseAndAttest()
                await services.disposeScanResourcesForTesting()
                RuntimeTestComposition.cleanupIfRegistered()
                NSApp.terminate(nil)
            }
        }
        .accessibilityIdentifier("runtime.fixture.cleanupAndQuit")
    }

    private func startQueuedCancellationBlockerIfNeeded() async {
        guard scenario == .cancelQueued, queuedCancellationBlocker == nil else { return }
        let blocker = RuntimeTestQueuedCancellationBlocker(services: services)
        queuedCancellationBlocker = blocker
        queuedCancellationState = await blocker.start()
    }

    private func releaseQueuedCancellationBlocker() async {
        guard let queuedCancellationBlocker else { return }
        queuedCancellationState = await queuedCancellationBlocker.releaseAndAttest()
    }
}

@MainActor
struct RuntimeTestRecoveryAttestationView: View {
    let services: AppExecutionServices
    let scenario: RuntimeTestScenario

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scenario.rawValue)
                .accessibilityLabel("Runtime scenario")
                .accessibilityValue(scenario.rawValue)
                .accessibilityIdentifier("runtime.scenario")
            Text(services.paths.settings.path)
                .accessibilityLabel("Synthetic settings")
                .accessibilityValue(services.paths.settings.path)
                .accessibilityIdentifier("runtime.synthetic.settings")
            Text(services.paths.home.path)
                .accessibilityLabel("Synthetic home")
                .accessibilityValue(services.paths.home.path)
                .accessibilityIdentifier("runtime.synthetic.home")
            Text(RuntimeTestComposition.attestation(for: services.paths,
                                                     scenario: scenario))
                .accessibilityLabel("Synthetic storage attestation")
                .accessibilityValue(RuntimeTestComposition.attestation(for: services.paths,
                                                                        scenario: scenario))
                .accessibilityIdentifier("runtime.synthetic.attestation")
            Text(RuntimeTestComposition.authorizationState)
                .accessibilityLabel("Mutation authorization")
                .accessibilityValue(RuntimeTestComposition.authorizationState)
                .accessibilityIdentifier("runtime.authorization")
            Button("Clean up fixture and quit") {
                services.disposeMonitoring()
                Task { @MainActor in
                    await RuntimeObservationCoordinator.stopIfActive()
                    await RuntimePerformanceCoordinator.stopIfActive()
                    await services.disposeScanResourcesForTesting()
                    RuntimeTestComposition.cleanupIfRegistered()
                    NSApp.terminate(nil)
                }
            }
            .accessibilityIdentifier("runtime.fixture.cleanupAndQuit")
        }
    }
}
#endif
