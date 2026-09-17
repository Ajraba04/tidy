import Foundation
import Testing
@testable import TidyCore

@Suite("Production scan observation handoff", .serialized)
struct ScanObservationTests {
    @Test("critical pause uses monotonic cooldown and stale samples cannot reopen admission")
    @MainActor
    func criticalCooldownAndStaleEpoch() async throws {
        let rig = try await ObservationBridgeRig.make()
        defer { rig.remove() }
        let sessions = rig.bridge.explicitSessions

        #expect(await sessions.updateLiveObservation(epoch: 1, monotonicNanoseconds: 1,
            observation: .critical) == .applied)
        #expect(await sessions.snapshot().effectiveWorkers == 0)

        #expect(await sessions.updateLiveObservation(epoch: 2,
            monotonicNanoseconds: 119_000_000_001, observation: .nominal) == .applied)
        #expect(await sessions.snapshot().effectiveWorkers == 0)

        #expect(await sessions.updateLiveObservation(epoch: 1,
            monotonicNanoseconds: 200_000_000_001, observation: .nominal)
            == .rejectedStale(current: 2))
        #expect(await sessions.snapshot().effectiveWorkers == 0)

        #expect(await sessions.updateLiveObservation(epoch: 3,
            monotonicNanoseconds: 120_000_000_001, observation: .nominal) == .applied)
        #expect(await sessions.snapshot().effectiveWorkers > 0)
    }

    @Test("constrained live observation enforces the one-worker ceiling")
    @MainActor
    func constrainedCeiling() async throws {
        let rig = try await ObservationBridgeRig.make(workers: 4)
        defer { rig.remove() }
        let sessions = rig.bridge.explicitSessions
        #expect(await sessions.updateLiveObservation(epoch: 1, monotonicNanoseconds: 1,
            observation: .constrained) == .applied)
        #expect(await sessions.snapshot().effectiveWorkers == 1)
    }
}

private struct ObservationBridgeRig {
    let root: URL
    let bridge: ExecutionPolicyBridge

    @MainActor
    static func make(workers: Int = 4) async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyR06Observation-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let settings = SettingsStore(url: root.appendingPathComponent("settings/config.json"))
        _ = await settings.load()
        let values = PolicyValues(fields: [
            SettingID(rawValue: "scan.preset"): .choice("custom"),
            SettingID(rawValue: "scan.requestedWorkers"): .integer(Int64(workers)),
            SettingID(rawValue: "scan.resumeAfterCriticalSeconds"): .integer(120)
        ])
        _ = try await settings.update(expectedRevision: 0,
            change: .preferences(.init(global: values)))
        let environment = CleanEnvironment(homeDirectory: home.path, detectedTools: [],
            protectedRoots: CleanEnvironment.defaultProtectedRoots(homeDirectory: home.path))
        let coordinator = ExecutionCoordinator(environment: environment,
            journalDirectory: root.appendingPathComponent("journal"))
        let bridge = ExecutionPolicyBridge(coordinator: coordinator, settings: settings,
            loaded: await settings.load(), homeDirectory: home.path, detectedTools: [])
        await bridge.drain()
        return Self(root: root, bridge: bridge)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
