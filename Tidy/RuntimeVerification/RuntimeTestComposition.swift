#if TIDY_RUNTIME_TEST_HOST
import Foundation
import Darwin
import SwiftUI
import TidyCore

enum RuntimeTestScenario: String {
    case acknowledged
    case freshDefaults = "fresh-defaults"
    case futureSettings = "future-settings"
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
        return .acknowledged
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
            case .acknowledged:
                try seedAcknowledgedSettings(at: settings)
            case .freshDefaults:
                break
            case .futureSettings:
                try futureSettingsBytes.write(to: settings)
                try fileManager.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: settings.path)
            }
            try seedSyntheticHome(at: home, fileManager: fileManager)
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
        case .acknowledged: settingsState = settingsExists ? "ready" : "missing"
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes: Data = try encoder.encode(envelope)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    private static func seedSyntheticHome(at home: URL, fileManager: FileManager) throws {
        let workspace = home.appendingPathComponent("SyntheticWorkspace", isDirectory: true)
        try createPrivateDirectory(workspace, fileManager: fileManager)
        try witnessBytes.write(to: witnessURL(home: home))

        let payload = Data(repeating: 0x54, count: 4_096)
        for directoryIndex in 0..<80 {
            let directory = workspace.appendingPathComponent(
                String(format: "batch-%02d", directoryIndex), isDirectory: true)
            try createPrivateDirectory(directory, fileManager: fileManager)
            for fileIndex in 0..<64 {
                let file = directory.appendingPathComponent(
                    String(format: "entry-%02d.bin", fileIndex))
                try payload.write(to: file)
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Production runtime verification")
                .font(.title2.bold())
                .accessibilityIdentifier("runtime.control.title")
            Text("This dedicated build uses production scenes and services with disposable storage.")
                .fixedSize(horizontal: false, vertical: true)
            Text(scenario.rawValue)
                .accessibilityLabel("Runtime scenario")
                .accessibilityValue(scenario.rawValue)
                .accessibilityIdentifier("runtime.scenario")

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
            cleanupButton

            Divider()
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
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 540, alignment: .topLeading)
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
                await services.disposeScanResourcesForTesting()
                RuntimeTestComposition.cleanupIfRegistered()
                NSApp.terminate(nil)
            }
        }
        .accessibilityIdentifier("runtime.fixture.cleanupAndQuit")
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
