import Foundation
import Testing
@testable import TidyCore

private actor CommandRecorder: CleanupCommandRunning {
    private(set) var calls: [String] = []

    func run(executableName: String, arguments: [String], timeout: TimeInterval) async -> CleanupCommandOutput {
        calls.append(([executableName] + arguments).joined(separator: " "))
        // A malicious/optimistic transport result must never create authority.
        return CleanupCommandOutput(succeeded: true)
    }
}

private actor CustomRecorder {
    private(set) var calls = 0

    func record() -> CustomActionOutcome {
        calls += 1
        return CustomActionOutcome(freedBytes: 999, reclaimedMemoryBytes: 999, succeeded: true)
    }
}

private struct Scratch {
    let root: URL
    let target: URL
    let sentinel: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("T01-\(UUID().uuidString)", isDirectory: true)
        target = root.appendingPathComponent("cache", isDirectory: true)
        sentinel = target.appendingPathComponent("keep.bin")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("preserve this exact payload".utf8).write(to: sentinel)
    }

    var environment: CleanEnvironment {
        CleanEnvironment(homeDirectory: root.path, detectedTools: Set(ToolchainID.allCases), protectedRoots: [])
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func assertIntact() throws {
        #expect(try Data(contentsOf: sentinel) == Data("preserve this exact payload".utf8))
    }
}

@Suite("Legacy quarantine")
struct LegacyQuarantineTests {
    @Test("Every actual catalog action and forged action is denied through raw execute")
    func allCatalogRoutesDeny() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let commands = CommandRecorder()
        let custom = CustomRecorder()
        let engine = CleanEngine(sizeScanner: SizeScanner(), commandRunner: commands)
        await DefaultCustomActionExecutors.registerAll(on: engine, commandRunner: commands)
        for operation in CustomOperationID.allCases {
            await engine.register(operation) { _, _ in await custom.record() }
        }
        var cases = CleanCatalog.allItems.map { ($0.id, $0.action) }
        cases += [
            ("unknown.delete", .deletePath),
            ("unknown.contents", .deleteContents),
            ("safe.cache.swiftpm-cache", .runTool(ToolCommand(.git, ["remote", "prune", "origin"]))),
            ("unknown.tool", .runTool(ToolCommand(.npm, ["cache", "clean", "--force"]))),
            ("unknown.custom", .custom(.restartToReclaimSwap))
        ]
        for (id, action) in cases {
            let targets: [TargetPath]
            switch action {
            case .runTool: targets = []
            case .custom: targets = [TargetPath(path: "fixture-opaque-id", isFilesystemPath: false)]
            case .deletePath, .deleteContents: targets = [TargetPath(path: scratch.target.path)]
            }
            let row = PlannedItem(id: id, title: id, tier: .deep, dangerNote: nil, costNote: nil,
                                  targets: targets, estimatedBytes: 999, action: action,
                                  declaredRoot: scratch.root.path)
            let report = await engine.execute(plan: CleanPlan(tier: .deep, plannedItems: [row]), environment: scratch.environment)
            #expect(report.results.count == 1)
            #expect(report.results.first?.succeeded == false, "\(id) was not denied")
            #expect(report.results.first?.message == CapabilityRegistry.quarantineReason)
            #expect(report.totalFreedBytes == 0)
            #expect(report.totalReclaimedMemoryBytes == 0)
        }
        #expect(await commands.calls.isEmpty)
        #expect(await custom.calls == 0)
        try scratch.assertIntact()
    }

    @Test("All custom IDs are denied even after real default registration")
    func defaultRegistrationsDeny() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let commands = CommandRecorder()
        let engine = CleanEngine(sizeScanner: SizeScanner(), commandRunner: commands)
        await DefaultCustomActionExecutors.registerAll(on: engine, commandRunner: commands)
        for operation in CustomOperationID.allCases {
            let row = PlannedItem(id: "forged.\(operation.rawValue)", title: "Forged", tier: .deep,
                dangerNote: nil, costNote: nil,
                targets: [TargetPath(path: scratch.target.path)], estimatedBytes: 1,
                action: .custom(operation), declaredRoot: scratch.root.path)
            let report = await engine.execute(plan: CleanPlan(tier: .deep, plannedItems: [row]), environment: scratch.environment)
            #expect(report.results.first?.succeeded == false)
            #expect(report.results.first?.message == CapabilityRegistry.quarantineReason)
        }
        #expect(await commands.calls.isEmpty)
        try scratch.assertIntact()
    }

    @Test("Direct command helpers deny without invoking even a successful recorder")
    func directCommandHelpersDeny() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let commands = CommandRecorder()
        let gitDirectory = scratch.target.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        let lock = gitDirectory.appendingPathComponent("index.lock")
        let log = gitDirectory.appendingPathComponent("gc.log")
        try Data("live lock".utf8).write(to: lock)
        try Data("retain log".utf8).write(to: log)
        let conservative = await GitHousekeeper.runConservative(repoPath: scratch.target.path, commandRunner: commands)
        let aggressive = await GitHousekeeper.runAggressiveReflogExpiry(repoPath: scratch.target.path, commandRunner: commands)
        for result in [conservative, aggressive] {
            #expect(!result.succeeded)
            #expect(result.message == CapabilityRegistry.quarantineReason)
        }
        #expect((try? Data(contentsOf: lock)) == Data("live lock".utf8))
        #expect((try? Data(contentsOf: log)) == Data("retain log".utf8))
        #expect(await SimulatorPruner.deleteDevice(udid: "11111111-1111-1111-1111-111111111111", commandRunner: commands) == false)
        let snapshot = LocalSnapshot(identifier: "com.apple.TimeMachine.2026-08-26-120000.local")
        #expect(await SnapshotDeleter.deleteSnapshots([snapshot], commandRunner: commands) == false)
        let purge = await MemoryReclaimer.purgeInactiveMemory(commandRunner: commands)
        let quit = await MemoryReclaimer.quitApplication(named: "Fixture\" & malicious text", commandRunner: commands)
        let restart = await MemoryReclaimer.restartToReclaimSwap(commandRunner: commands)
        for result in [purge, quit, restart] {
            #expect(!result.succeeded)
            #expect(result.reclaimedMemoryBytes == 0)
            #expect(result.message == CapabilityRegistry.quarantineReason)
        }
        #expect(await commands.calls.isEmpty)
        try scratch.assertIntact()
    }

    @Test("Direct browser entry denies before touching DB or backup")
    func directBrowserHelperDenies() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let database = scratch.target.appendingPathComponent("Cookies")
        let backup = scratch.target.appendingPathComponent("Cookies.tidy-backup")
        let payload = Data("not a database; never open for mutation".utf8)
        try payload.write(to: database)
        try Data("older recovery bytes".utf8).write(to: backup)
        let result = ChromiumCookieCleaner.clean(profile: ChromeProfile(name: "Default", path: scratch.target.path),
            keepDomains: ["example.invalid"], homeDirectory: scratch.root.path)
        #expect(result == .failed(reason: CapabilityRegistry.quarantineReason))
        #expect(try Data(contentsOf: database) == payload)
        #expect(try Data(contentsOf: backup) == Data("older recovery bytes".utf8))
        try scratch.assertIntact()
    }
}
