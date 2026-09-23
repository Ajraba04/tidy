// Audit-only optional measurement, external worktree only. Production filesystem
// ScanEngine + real store/bridge/registry, no index (matching shipped app).
// Process stage is recording/no-op: this is NOT a full-app timing acceptance run.
// Ambient host VM/disk/kernel probes are read-only. All writes/delete cleanup are
// scoped to one exclusively-created /private/tmp/TidyPerfAudit-<UUID> directory.
// Coordinator: run serialized with other process-global tests. Use external
// /usr/bin/time -l for peak RSS; that is not peak physical footprint.
import Foundation
import Testing
@testable import TidyCore

@Suite("Audit production scan measurements", .serialized)
struct PolicyAuditPerformanceTests {
    @Test("50k and 100k fixture scans, unchanged rerun, then 20 cancel cycles")
    @MainActor
    func measureBoundedProductionScans() async throws {
        for count in [50_000, 100_000] {
            let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("TidyPerfAudit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: root) }
            let home = root.appendingPathComponent("home", isDirectory: true)
            let docs = home.appendingPathComponent("Documents", isDirectory: true)
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            // At most 200 files per leaf, so no fixture directory itself exceeds
            // the production 1024 child-enumeration bound. Queue exhaustion, if
            // encountered, is recorded as partial instead of accepted as full.
            for bucket in 0..<((count + 199) / 200) {
                let dir = docs.appendingPathComponent("b\(bucket)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
                for entry in (bucket * 200)..<min(count, (bucket + 1) * 200) {
                    try Data().write(to: dir.appendingPathComponent("f\(entry)"), options: .withoutOverwriting)
                }
            }
            let witness = root.appendingPathComponent("protected-witness")
            let witnessBytes = Data("must survive every scan and cancellation".utf8)
            try witnessBytes.write(to: witness, options: .withoutOverwriting)
            let settings = SettingsStore(url: root.appendingPathComponent("settings/config.json"))
            _ = await settings.load()
            _ = try await settings.update(expectedRevision: 0, change: .preferences(.init(global: .init(fields: [
                SettingID(rawValue: "scan.uiBatchesPerSecond"): .integer(4)
            ]))))
            let environment = CleanEnvironment(homeDirectory: home.path, detectedTools: [],
                                               gitRoots: [], protectedRoots: [])
            let coordinator = ExecutionCoordinator(environment: environment,
                                                  journalDirectory: root.appendingPathComponent("journal"))
            let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings,
                loaded: await settings.load(), homeDirectory: home.path, detectedTools: [])
            await bridge.drain()
            let sessions = bridge.explicitSessions
            let registry = ScanSessionRegistry()
            let dependencies = CoreScanDependencies(processProbe: { _, _ in .availableEmpty }, testHook: nil)
            for pass in 1...2 {
                let session = try await sessions.beginSession(requirements: SchedulerRequirements(features: [.headroom]))
                let began = ProcessInfo.processInfo.systemUptime
                let handle = try await ScanEngine.start(environment: environment, registry: registry,
                    sessions: sessions, session: session, dependencies: dependencies)
                let subscription = try await registry.subscribe(sessionID: handle.sessionID)
                var usefulSeconds: Double?
                for await event in subscription.stream {
                    if usefulSeconds == nil && !event.snapshot.items.isEmpty {
                        usefulSeconds = ProcessInfo.processInfo.systemUptime - began
                    }
                    if event.terminal != nil { break }
                }
                let seconds = ProcessInfo.processInfo.systemUptime - began
                let state = try await registry.state(sessionID: handle.sessionID)
                let result = try #require(await handle.latestResult())
                await sessions.finish(session: session)
                print("AUDIT_SCAN fixtureFiles=\(count) pass=\(pass) elapsedSeconds=\(seconds) firstUsefulSeconds=\(usefulSeconds.map(String.init(describing:)) ?? "unavailable") processedEntries=\(state.snapshot.processedEntries) complete=\(result.coverage.isComplete) reasons=\(result.coverage.reasons.map(\.rawValue).sorted())")
                #expect(try Data(contentsOf: witness) == witnessBytes)
            }
            let fdBefore = (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count)
            var maximumCancelSeconds: Double = 0
            for _ in 0..<20 {
                let session = try await sessions.beginSession(requirements: SchedulerRequirements(features: [.headroom]))
                let handle = try await ScanEngine.start(environment: environment, registry: registry,
                    sessions: sessions, session: session, dependencies: dependencies)
                let subscription = try await registry.subscribe(sessionID: handle.sessionID)
                let cancelAt = ProcessInfo.processInfo.systemUptime
                try await registry.cancel(sessionID: handle.sessionID)
                for await event in subscription.stream where event.terminal != nil { break }
                maximumCancelSeconds = max(maximumCancelSeconds, ProcessInfo.processInfo.systemUptime - cancelAt)
                await sessions.finish(session: session)
            }
            let registryState = await registry.snapshot()
            let schedulerState = await sessions.snapshot()
            let fdAfter = (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count)
            print("AUDIT_CANCEL fixtureFiles=\(count) cycles=20 maximumAcknowledgementSeconds=\(maximumCancelSeconds) registryActive=\(registryState.activeWork) schedulerActive=\(schedulerState.active) schedulerQueued=\(schedulerState.queued) fdBefore=\(String(describing: fdBefore)) fdAfter=\(String(describing: fdAfter))")
            #expect(registryState.activeWork == 0)
            #expect(schedulerState.active == 0)
            #expect(schedulerState.queued == 0)
            #expect(try Data(contentsOf: witness) == witnessBytes)
        }
    }
}
