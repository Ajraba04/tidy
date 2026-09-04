import Foundation
import Testing
@testable import TidyCore

@Suite("CleanEngine")
struct CleanEngineTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEnvironment(homeDirectory: String) -> CleanEnvironment {
        CleanEnvironment(homeDirectory: homeDirectory, protectedRoots: [])
    }

    // MARK: - makePlan

    @Test("makePlan only includes items matching the requested tier")
    func makePlanFiltersByTier() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let safeItem = CleanItem(
            id: "safe-item", title: "Safe", tier: .safe,
            declaredRoot: { env in env.homeDirectory },
            locate: { _ in [] }, action: .deletePath
        )
        let deepItem = CleanItem(
            id: "deep-item", title: "Deep", tier: .deep,
            declaredRoot: { env in env.homeDirectory },
            locate: { _ in [] }, action: .deletePath
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let plan = await engine.makePlan(items: [safeItem, deepItem], tier: .safe, environment: makeEnvironment(homeDirectory: scratch.path))

        #expect(plan.plannedItems.map(\.id) == ["safe-item"])
    }

    @Test("makePlan is cumulative: Normal includes Safe, Deep includes Safe and Normal")
    func makePlanIsCumulativeAcrossTiers() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        func item(_ id: String, _ tier: Tier) -> CleanItem {
            CleanItem(
                id: id, title: id, tier: tier,
                declaredRoot: { env in env.homeDirectory },
                locate: { _ in [] }, action: .deletePath
            )
        }
        let items = [item("safe", .safe), item("normal", .normal), item("deep", .deep)]
        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = makeEnvironment(homeDirectory: scratch.path)

        let safePlan = await engine.makePlan(items: items, tier: .safe, environment: environment)
        #expect(Set(safePlan.plannedItems.map(\.id)) == ["safe"])

        let normalPlan = await engine.makePlan(items: items, tier: .normal, environment: environment)
        #expect(Set(normalPlan.plannedItems.map(\.id)) == ["safe", "normal"])

        let deepPlan = await engine.makePlan(items: items, tier: .deep, environment: environment)
        #expect(Set(deepPlan.plannedItems.map(\.id)) == ["safe", "normal", "deep"])
    }

    @Test("makePlan launches no measurement and reports zero bytes without deleting anything")
    func makePlanMeasuresWithoutDeleting() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let target = scratch.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 0x1, count: 100_000).write(to: target.appendingPathComponent("f.bin"))

        let item = CleanItem(
            id: "cache-item", title: "Cache", tier: .safe,
            declaredRoot: { env in env.homeDirectory },
            locate: { env in [TargetPath(path: env.homeDirectory + "/cache")] },
            action: .deletePath
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: makeEnvironment(homeDirectory: scratch.path))

        // Superseded by the `orchestration`-taking overload: this legacy overload launches no
        // discovery or measurement, so its estimate is always zero.
        #expect(plan.plannedItems.first?.estimatedBytes == 0)
        #expect(plan.plannedItems.first?.targets.isEmpty == true)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test("makePlan excludes a target that escapes its declared root")
    func makePlanExcludesEscapingTarget() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let outside = scratch.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let item = CleanItem(
            id: "escaping-item", title: "Escaping", tier: .safe,
            declaredRoot: { env in env.homeDirectory + "/allowed" },
            locate: { env in [TargetPath(path: env.homeDirectory + "/outside")] },
            action: .deletePath
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: makeEnvironment(homeDirectory: scratch.path))

        #expect(plan.plannedItems.first?.targets.isEmpty == true)
    }

    // MARK: - execute: deletePath / deleteContents

    @Test("execute denies an unaccepted deletePath and leaves its target intact")
    func executeDeletePathDeniesTarget() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let target = scratch.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let payload = Data(repeating: 0x1, count: 50_000)
        let payloadPath = target.appendingPathComponent("f.bin")
        try payload.write(to: payloadPath)

        let item = CleanItem(
            id: "cache-item", title: "Cache", tier: .safe,
            declaredRoot: { env in env.homeDirectory },
            locate: { env in [TargetPath(path: env.homeDirectory + "/cache")] },
            action: .deletePath
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = makeEnvironment(homeDirectory: scratch.path)
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: environment)
        let report = await engine.execute(plan: plan, environment: environment)

        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(try Data(contentsOf: payloadPath) == payload)
        #expect(report.results.first?.succeeded == false)
        #expect(report.results.first?.message == CapabilityRegistry.quarantineReason)
        #expect(report.totalFreedBytes == 0)
    }

    @Test("execute denies an unaccepted deleteContents and leaves its payload intact")
    func executeDeleteContentsDeniesTarget() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let target = scratch.appendingPathComponent("DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let payload = Data(repeating: 0x1, count: 50_000)
        let payloadPath = target.appendingPathComponent("build.o")
        try payload.write(to: payloadPath)

        let item = CleanItem(
            id: "derived-data", title: "DerivedData", tier: .safe,
            declaredRoot: { env in env.homeDirectory },
            locate: { env in [TargetPath(path: env.homeDirectory + "/DerivedData")] },
            action: .deleteContents
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = makeEnvironment(homeDirectory: scratch.path)
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: environment)
        let report = await engine.execute(plan: plan, environment: environment)

        var isDirectory: ObjCBool = false
        let stillExists = FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        #expect(stillExists && isDirectory.boolValue)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: target.path))?.isEmpty == false)
        #expect(try Data(contentsOf: payloadPath) == payload)
        #expect(report.results.first?.succeeded == false)
        #expect(report.results.first?.message == CapabilityRegistry.quarantineReason)
        #expect(report.totalFreedBytes == 0)
    }

    @Test("execute never deletes anything for a tier with an empty plan")
    func executeNoOpForEmptyPlan() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = makeEnvironment(homeDirectory: scratch.path)
        let plan = await engine.makePlan(items: [], tier: .safe, environment: environment)
        let report = await engine.execute(plan: plan, environment: environment)

        #expect(report.results.isEmpty)
        #expect(report.totalFreedBytes == 0)
    }

    // MARK: - execute: runTool

    @Test("execute denies an unaccepted tool action")
    func executeRunToolDenies() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let item = CleanItem(
            id: "git-version", title: "git --version", tier: .safe,
            declaredRoot: { env in env.homeDirectory },
            locate: { _ in [] },
            action: .runTool(ToolCommand(.git, ["--version"]))
        )

        let commands = CleanEngineCommandRecorder()
        let engine = CleanEngine(sizeScanner: SizeScanner(), commandRunner: commands)
        let environment = makeEnvironment(homeDirectory: scratch.path)
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: environment)
        let report = await engine.execute(plan: plan, environment: environment)

        #expect(report.results.first?.succeeded == false)
        #expect(report.results.first?.message == CapabilityRegistry.quarantineReason)
        #expect(await commands.calls.isEmpty)
    }

    // MARK: - execute: custom

    @Test("execute denies a custom action before its registered executor")
    func executeDeniesCustomActionBeforeExecutor() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let item = CleanItem(
            id: "custom-item", title: "Custom", tier: .safe,
            declaredRoot: { env in env.homeDirectory },
            locate: { env in [
                TargetPath(path: env.homeDirectory + "/a"),
                TargetPath(path: env.homeDirectory + "/b")
            ] },
            action: .custom(.chromeCookies)
        )

        try FileManager.default.createDirectory(atPath: scratch.appendingPathComponent("a").path, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: scratch.appendingPathComponent("b").path, withIntermediateDirectories: true)

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let callCount = LockedCounter()
        await engine.register(.chromeCookies) { target, _ in
            callCount.increment()
            return CustomActionOutcome(freedBytes: 10, succeeded: true, message: target.path)
        }

        let environment = makeEnvironment(homeDirectory: scratch.path)
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: environment)
        let report = await engine.execute(plan: plan, environment: environment)

        #expect(callCount.value == 0)
        #expect(report.results.first?.freedBytes == 0)
        #expect(report.results.first?.succeeded == false)
        #expect(report.results.first?.message == CapabilityRegistry.quarantineReason)
    }

    @Test("execute reports failure for a custom action with no registered executor")
    func executeFailsForUnregisteredCustomAction() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(atPath: scratch.appendingPathComponent("a").path, withIntermediateDirectories: true)

        let item = CleanItem(
            id: "unregistered-custom", title: "Unregistered", tier: .safe,
            declaredRoot: { env in env.homeDirectory },
            locate: { env in [TargetPath(path: env.homeDirectory + "/a")] },
            action: .custom(.gitRepoGC)
        )

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let environment = makeEnvironment(homeDirectory: scratch.path)
        let plan = await engine.makePlan(items: [item], tier: .safe, environment: environment)
        let report = await engine.execute(plan: plan, environment: environment)

        #expect(report.results.first?.succeeded == false)
    }

    // MARK: - defense in depth

    @Test("execute refuses to delete the home directory even if a plan somehow targets it")
    func executeRefusesToDeleteHomeDirectory() async throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Bypasses makePlan's own filtering to simulate a hostile/buggy plan.
        let plannedItem = PlannedItem(
            id: "hostile", title: "Hostile", tier: .safe, dangerNote: nil, costNote: nil,
            targets: [TargetPath(path: scratch.path)],
            estimatedBytes: 0,
            action: .deletePath
        )
        let plan = CleanPlan(tier: .safe, plannedItems: [plannedItem])

        let engine = CleanEngine(sizeScanner: SizeScanner())
        let report = await engine.execute(plan: plan, environment: makeEnvironment(homeDirectory: scratch.path))

        #expect(FileManager.default.fileExists(atPath: scratch.path))
        #expect(report.results.first?.succeeded == false)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() { lock.lock(); _value += 1; lock.unlock() }
}

private actor CleanEngineCommandRecorder: CleanupCommandRunning {
    private(set) var calls: [String] = []

    func run(executableName: String, arguments: [String], timeout: TimeInterval) async -> CleanupCommandOutput {
        calls.append(([executableName] + arguments).joined(separator: " "))
        return CleanupCommandOutput(succeeded: true)
    }
}
