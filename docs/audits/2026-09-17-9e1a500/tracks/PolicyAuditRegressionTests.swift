// Audit-only regression probes. Copy into an isolated TidyCore test target; do not
// change audited production source. Both tests assert the approved behavior and
// are expected to fail at 9e1a500. No real mutator or process probe is invoked.
// The ScanEngine test performs read-only host VM/disk/kernel observations in
// addition to its scratch-home traversal: fake HOME is not full read isolation.
import Foundation
import Testing
@testable import TidyCore

@Suite("Audit policy regressions", .serialized)
struct PolicyAuditRegressionTests {
    @Test("fresh durable-store defaults permit an explicit scan session")
    @MainActor
    func freshInstallAllowsExplicitScan() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyPolicyAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
        let settings = SettingsStore(url: root.appendingPathComponent("settings/config.json"))
        let loaded = await settings.load()
        let coordinator = ExecutionCoordinator(environment: CleanEnvironment(homeDirectory: home.path,
            detectedTools: [], protectedRoots: []), journalDirectory: root.appendingPathComponent("journal"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings, loaded: loaded,
            homeDirectory: home.path, detectedTools: [])
        await bridge.drain()
        #expect(await bridge.explicitSessions.snapshot().availability == .available)
    }

    @Test("selectedProjects with no selected roots does not traverse unrelated Documents")
    @MainActor
    func selectedProjectScopeDoesNotWalkHome() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyPolicyAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let docs = home.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 8192).write(to: docs.appendingPathComponent("witness.bin"))
        let settings = SettingsStore(url: root.appendingPathComponent("settings/config.json"))
        _ = await settings.load()
        _ = try await settings.update(expectedRevision: 0, change: .preferences(.init(global: .init(fields: [
            SettingID(rawValue: "scan.defaultScope"): .choice("selectedProjects")
        ]))))
        let loaded = await settings.load()
        let environment = CleanEnvironment(homeDirectory: home.path, detectedTools: [],
                                           gitRoots: [], protectedRoots: [])
        let coordinator = ExecutionCoordinator(environment: environment,
                                              journalDirectory: root.appendingPathComponent("journal"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings, loaded: loaded,
            homeDirectory: home.path, detectedTools: [])
        await bridge.drain()
        let sessions = bridge.explicitSessions
        let session = try await sessions.beginSession(requirements: SchedulerRequirements(features: [.headroom]))
        let registry = ScanSessionRegistry()
        let handle = try await ScanEngine.start(environment: environment, registry: registry,
            sessions: sessions, session: session,
            dependencies: CoreScanDependencies(processProbe: { _, _ in .availableEmpty }, testHook: nil))
        let subscription = try await registry.subscribe(sessionID: handle.sessionID)
        for await event in subscription.stream where event.terminal != nil { break }
        await sessions.finish(session: session)
        let result = try #require(await handle.latestResult())
        #expect(!result.report.topLevelHomeRanking.contains { $0.path == docs.path })
    }
}
