import Foundation
import Testing
@testable import TidyCore

@Suite("T08.4 core orchestration", .serialized)
struct CoreOrchestrationTests {
    @Test("legacy scan and planning calls retain rows but cannot launch discovery or measurement")
    func legacyCallsAreSafeNoOpBoundaries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("T084Legacy-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let target = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: target.appendingPathComponent("payload"))
        defer { try? FileManager.default.removeItem(at: root) }

        let environment = CleanEnvironment(homeDirectory: root.path, protectedRoots: [])
        let report = await ScanEngine.run(environment: environment)
        #expect(report.topLevelHomeRanking.isEmpty)
        #expect(report.libraryRanking.isEmpty)
        #expect(report.filesOver1GB.isEmpty)

        let calls = CoreOrchestrationCounter()
        let item = CleanItem(id: "fixture.legacy", title: "Fixture", tier: .safe,
            declaredRoot: { $0.homeDirectory }, locate: { environment in
                calls.increment()
                return [TargetPath(path: environment.homeDirectory + "/cache")]
            }, action: .deletePath)
        let plan = await CleanEngine(sizeScanner: SizeScanner()).makePlan(
            items: [item], tier: .safe, environment: environment)
        let planned = try #require(plan.plannedItems.first)
        #expect(calls.value == 0)
        #expect(planned.targets.isEmpty)
        #expect(planned.estimatedBytes == 0)
        #expect(planned.review.status == .unavailable)
    }

    @Test("explicit planning context uses the acknowledged policy and shared walk permit")
    @MainActor
    func explicitPlanningUsesSharedPolicy() async throws {
        let rig = try await TraversalBridgeRig.make()
        let target = rig.root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 16_384).write(to: target.appendingPathComponent("payload"))

        let context = try await CoreOrchestrationContext.make(
            sessions: rig.sessions, session: rig.session, sessionID: UUID())
        #expect(context.policyRevision == 1)
        #expect(context.sliceSeconds == 300)
        #expect(context.uiBatchesPerSecond == 4)

        let calls = CoreOrchestrationCounter()
        let item = CleanItem(id: "fixture.explicit", title: "Fixture", tier: .safe,
            declaredRoot: { $0.homeDirectory }, locate: { _ in [] },
            action: .deletePath, discover: { environment in
                calls.increment()
                return ActionDiscovery(status: .available,
                    reason: "Explicit fixed fixture path found.",
                    targets: [TargetPath(path: environment.homeDirectory + "/cache")])
            })
        let environment = CleanEnvironment(homeDirectory: rig.root.path, protectedRoots: [])
        let plan = await CleanEngine(sizeScanner: SizeScanner()).makePlan(
            items: [item], tier: .safe, environment: environment,
            orchestration: context)
        let planned = try #require(plan.plannedItems.first)
        #expect(calls.value == 1)
        #expect(planned.targets.map(\.path) == [target.path])
        #expect(planned.estimatedBytes >= 16_384)
        #expect(planned.review.status == .unavailable)
        let scheduler = await rig.sessions.snapshot()
        #expect(scheduler.active == 0)
        #expect(scheduler.queued == 0)
        await rig.cleanup()
    }

    @Test("registered scan publishes useful bounded progress before process probes and one terminal")
    @MainActor
    func registeredScanPublishesBeforeProcessAndTerminatesOnce() async throws {
        let rig = try await TraversalBridgeRig.make()
        let documents = rig.root.appendingPathComponent("Documents", isDirectory: true)
        let library = rig.root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 24_576)
            .write(to: documents.appendingPathComponent("fixture.bin"))
        let oracle = HomeSurvey.walk(root: documents.path, protectedRoots: [],
            largeFileThreshold: 1_073_741_824, breakOutChildren: false)

        let registry = ScanSessionRegistry()
        let checkpoint = CoreScanCheckpoint(blockedAt: .beforeFilesystem)
        let processProbe = CoreScanBlockingProcessProbe()
        let dependencies = CoreScanDependencies(
            processProbe: { _, _ in await processProbe.run() },
            testHook: { point in await checkpoint.receive(point) })
        let handle = try await ScanEngine.start(environment: CleanEnvironment(
            homeDirectory: rig.root.path, detectedTools: [], gitRoots: [], protectedRoots: []),
            registry: registry, sessions: rig.sessions, session: rig.session,
            dependencies: dependencies)
        let subscription = try await registry.subscribe(sessionID: handle.sessionID)
        async let delivered = collectCoreEvents(subscription)

        await checkpoint.waitUntilReached()
        await checkpoint.release()
        await processProbe.waitUntilEntered()
        let inFlight = try await registry.state(sessionID: handle.sessionID)
        #expect(inFlight.policyRevision == handle.policyRevision)
        #expect(inFlight.snapshot.processedEntries > 0)
        #expect(inFlight.terminal == nil)

        await processProbe.release()
        let events = await delivered
        let terminals = events.filter { $0.terminal != nil }
        #expect(events.contains { if case .progress = $0.kind { return true }; return false })
        #expect(terminals.count == 1)
        #expect(terminals.first?.terminal == .complete)
        #expect(events.last?.terminal == .complete)
        #expect(events.allSatisfy { $0.sessionID == handle.sessionID })
        #expect(events.allSatisfy { $0.policyRevision == handle.policyRevision })

        let result = try #require(await handle.latestResult())
        #expect(result.coverage.isComplete)
        #expect(!result.continuationAvailable)
        #expect(result.report.topLevelHomeRanking.contains {
            $0.path == documents.path && $0.bytes == oracle.totalBytes
        })
        await rig.cleanup()
    }

    @Test("catalog build discovery fails closed when its bounded result inventory is exhausted")
    @MainActor
    func boundedCatalogDiscoveryDoesNotPresentTruncatedTargets() async throws {
        let rig = try await TraversalBridgeRig.make()
        let projects = rig.root.appendingPathComponent("Projects", isDirectory: true)
        let project = projects.appendingPathComponent("fixture", isDirectory: true)
        let build = project.appendingPathComponent("build", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data(repeating: 5, count: 4_096).write(to: build.appendingPathComponent("one"))
        try Data(repeating: 6, count: 4_096).write(to: build.appendingPathComponent("two"))

        let limits = try standardLimits(resultRecords: 1)
        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID(), traversalLimits: limits)
        let item = try #require(CleanCatalog.allItems.first {
            $0.id == "normal.extras.build-outputs"
        })
        let environment = CleanEnvironment(homeDirectory: rig.root.path,
            gitRoots: [projects.path], protectedRoots: [])
        let plan = await CleanEngine(sizeScanner: SizeScanner()).makePlan(items: [item],
            tier: .normal, environment: environment, orchestration: context)
        let planned = try #require(plan.plannedItems.first)
        #expect(planned.targets.isEmpty)
        #expect(planned.estimatedBytes == 0)
        #expect(planned.review.status == .unavailable)
        #expect(planned.review.reason.contains("bounded"))
        await rig.cleanup()
    }

    @Test("two registered scans and one planning request share one aggregate walk budget")
    @MainActor
    func scansAndPlanningShareOneWalkBudget() async throws {
        let rig = try await TraversalBridgeRig.make()
        let secondSession = try await rig.makeSession()
        let thirdSession = try await rig.makeSession()
        defer {
            Task {
                await rig.sessions.finish(session: secondSession)
                await rig.sessions.finish(session: thirdSession)
            }
        }
        let cache = rig.root.appendingPathComponent("cache", isDirectory: true)
        let library = rig.root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        for index in 0..<128 {
            try Data(repeating: UInt8(index % 255), count: 1_024)
                .write(to: cache.appendingPathComponent("f\(index)"))
        }

        let planningContext = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        let permitGate = CorePlanningPermitGate()
        let item = CleanItem(id: "fixture.shared-budget", title: "Fixture", tier: .safe,
            declaredRoot: { $0.homeDirectory }, locate: { _ in [] }, action: .deletePath,
            discover: { environment in ActionDiscovery(status: .available,
                reason: "Fixture path.",
                targets: [TargetPath(path: environment.homeDirectory + "/cache")]) })
        let environment = CleanEnvironment(homeDirectory: rig.root.path,
            detectedTools: [], gitRoots: [], protectedRoots: [])
        let engine = CleanEngine(sizeScanner: SizeScanner())
        let planning = Task {
            await engine.makePlan(items: [item], tier: .safe, environment: environment,
                orchestration: planningContext, testHook: { await permitGate.hold() })
        }
        await permitGate.waitUntilEntered()

        let dependencies = CoreScanDependencies(processProbe: { _, _ in .availableEmpty },
            testHook: nil)
        let firstRegistry = ScanSessionRegistry()
        let secondRegistry = ScanSessionRegistry()
        let first = try await ScanEngine.start(environment: environment, registry: firstRegistry,
            sessions: rig.sessions, session: secondSession, dependencies: dependencies)
        let second = try await ScanEngine.start(environment: environment,
            registry: secondRegistry, sessions: rig.sessions, session: thirdSession,
            dependencies: dependencies)
        try await waitForSchedulerQueue(rig.sessions, minimum: 2)
        let pressure = await rig.sessions.snapshot()
        #expect(pressure.effectiveWorkers == 1)
        #expect(pressure.active == 1)
        #expect(pressure.queued >= 2)

        await permitGate.release()
        _ = await planning.value
        try await waitForTerminal(first.sessionID, in: firstRegistry)
        try await waitForTerminal(second.sessionID, in: secondRegistry)
        let final = await rig.sessions.snapshot()
        #expect(final.active == 0)
        #expect(final.queued == 0)
        await rig.cleanup()
    }

    @Test("cancellation at each scan orchestration stage publishes only one cancellation terminal")
    @MainActor
    func cancellationStopsLaterStagesAndPublication() async throws {
        let rig = try await TraversalBridgeRig.make()
        let library = rig.root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let environment = CleanEnvironment(homeDirectory: rig.root.path,
            detectedTools: [], gitRoots: [], protectedRoots: [])

        for (point, expectedProcessCalls) in [
            (CoreScanTestPoint.beforeFilesystem, 0),
            (.beforeProcess, 0),
            (.beforeTerminal, 1)
        ] {
            let workSession = try await rig.makeSession()
            let registry = ScanSessionRegistry()
            let checkpoint = CoreScanCheckpoint(blockedAt: point)
            let probe = CoreScanCountingProcessProbe()
            let dependencies = CoreScanDependencies(
                processProbe: { _, _ in await probe.run() },
                testHook: { reached in await checkpoint.receive(reached) })
            let handle = try await ScanEngine.start(environment: environment,
                registry: registry, sessions: rig.sessions, session: workSession,
                dependencies: dependencies)
            let subscription = try await registry.subscribe(sessionID: handle.sessionID)
            async let delivered = collectCoreEvents(subscription)
            await checkpoint.waitUntilReached()
            try await registry.cancel(sessionID: handle.sessionID)
            await checkpoint.release()

            let events = await delivered
            #expect(events.filter { $0.terminal != nil }.count == 1)
            #expect(events.last?.terminal == .cancelled)
            #expect(await probe.calls() == expectedProcessCalls)
            let state = try await registry.state(sessionID: handle.sessionID)
            #expect(state.terminal == .cancelled)
            #expect(!state.workActive)
            await rig.sessions.finish(session: workSession)
        }
        await rig.cleanup()
    }

    // Exercises the one shared physical ProcessJobGate, whose policy revision
    // and reader counts other suites churn when the whole target runs in one
    // process. The property is only observable without that interference, so
    // this test runs in its own dedicated invocation:
    //   TIDY_ISOLATED_GATE_TESTS=1 swift test --filter CoreOrchestrationTests
    @Test("registered scan process probes stay within the acknowledged shared process cap",
          .enabled(if: ProcessInfo.processInfo.environment["TIDY_ISOLATED_GATE_TESTS"] == "1"))
    @MainActor
    func registeredScanUsesSharedProcessCap() async throws {
        let rig = try await TraversalBridgeRig.make()
        try FileManager.default.createDirectory(
            at: rig.root.appendingPathComponent("Library", isDirectory: true),
            withIntermediateDirectories: true)
        let monitor = CoreActualProcessMonitor()
        let dependencies = CoreScanDependencies(processProbe: { context, _ in
            await monitor.run(context: context)
            return .availableEmpty
        }, testHook: nil)
        let registry = ScanSessionRegistry()
        let handle = try await ScanEngine.start(environment: CleanEnvironment(
            homeDirectory: rig.root.path, detectedTools: [], gitRoots: [], protectedRoots: []),
            registry: registry, sessions: rig.sessions, session: rig.session,
            dependencies: dependencies)
        try await waitForTerminal(handle.sessionID, in: registry)
        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        let peak = await monitor.peak()
        #expect(peak > 0)
        #expect(peak <= context.readOnlyProcessLimit)
        #expect(peak <= 2)
        #expect(await ProcessRunner.jobSnapshot().active == 0)
        await rig.cleanup()
    }

    @Test("process parser or tool failure is partial unavailable evidence, never empty success")
    @MainActor
    func processFailureIsTruthfulPartialEvidence() async throws {
        let rig = try await TraversalBridgeRig.make()
        try FileManager.default.createDirectory(
            at: rig.root.appendingPathComponent("Library", isDirectory: true),
            withIntermediateDirectories: true)
        let registry = ScanSessionRegistry()
        let dependencies = CoreScanDependencies(processProbe: { _, _ in
            CoreScanProcessEvidence(containerSpace: nil, localSnapshots: [],
                idleSimulatorRuntimes: [], topMemoryConsumers: [], unavailable: true)
        }, testHook: nil)
        let handle = try await ScanEngine.start(environment: CleanEnvironment(
            homeDirectory: rig.root.path, detectedTools: [], gitRoots: [], protectedRoots: []),
            registry: registry, sessions: rig.sessions, session: rig.session,
            dependencies: dependencies)
        try await waitForTerminal(handle.sessionID, in: registry)
        let state = try await registry.state(sessionID: handle.sessionID)
        #expect(state.terminal == .partial)
        #expect(state.coverage.reasons.contains(.unreadable))
        let result = try #require(await handle.latestResult())
        #expect(!result.coverage.isComplete)
        #expect(result.coverage.reasons.contains(.unreadable))
        #expect(result.report.localSnapshots.isEmpty)
        await rig.cleanup()
    }

    @Test("bounded build-output discovery finds a real project's output directory")
    @MainActor
    func boundedBuildOutputDiscoveryFindsRealTarget() async throws {
        let rig = try await TraversalBridgeRig.make()
        let projects = rig.root.appendingPathComponent("Projects", isDirectory: true)
        let project = projects.appendingPathComponent("fixture", isDirectory: true)
        let build = project.appendingPathComponent("dist", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 2_048).write(to: build.appendingPathComponent("bundle.js"))

        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        let environment = CleanEnvironment(homeDirectory: rig.root.path,
            gitRoots: [projects.path], protectedRoots: [])
        let discovery = await CleanCatalog.discoverBuildOutputs(environment: environment,
            orchestration: context)
        #expect(discovery.status == .available)
        #expect(discovery.targets.contains { $0.path == build.path })
        await rig.cleanup()
    }

    @Test("bounded stale node_modules discovery finds an aged real directory")
    @MainActor
    func boundedStaleNodeModulesDiscoveryFindsRealTarget() async throws {
        let rig = try await TraversalBridgeRig.make()
        let projects = rig.root.appendingPathComponent("Projects", isDirectory: true)
        let project = projects.appendingPathComponent("fixture", isDirectory: true)
        let nodeModules = project.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        let agedDate = Date().addingTimeInterval(-90 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: agedDate],
            ofItemAtPath: nodeModules.path)

        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        let environment = CleanEnvironment(homeDirectory: rig.root.path,
            gitRoots: [project.path], protectedRoots: [], staleNodeModulesThresholdDays: 60)
        let discovery = await CleanCatalog.discoverStaleNodeModules(environment: environment,
            orchestration: context)
        #expect(discovery.status == .available)
        #expect(discovery.targets.contains { $0.path == nodeModules.path })
        await rig.cleanup()
    }

    @Test("bounded catalog discovery never enters mandatory cloud roots")
    @MainActor
    func catalogDiscoveryProtectsCloudRootsEvenWithAnEmptyCallerList() async throws {
        let rig = try await TraversalBridgeRig.make()
        let cloud = rig.root.appendingPathComponent("Library/CloudStorage")
        let project = cloud.appendingPathComponent("fixture")
        let build = project.appendingPathComponent("dist")
        let modules = project.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90 * 86_400)],
            ofItemAtPath: modules.path)
        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        let environment = CleanEnvironment(homeDirectory: rig.root.path,
            gitRoots: [cloud.path], protectedRoots: [])
        #expect(environment.protectedRoots.contains(cloud.path))
        let outputs = await CleanCatalog.discoverBuildOutputs(environment: environment, orchestration: context)
        let dependencies = await CleanCatalog.discoverStaleNodeModules(environment: environment, orchestration: context)
        #expect(outputs.targets.isEmpty)
        #expect(dependencies.targets.isEmpty)
        await rig.cleanup()
    }

    @Test("Flutter SDK cache discovery fails closed once its session invalidates mid-command")
    @MainActor
    func flutterSDKCacheDiscoveryFailsClosedOnInvalidSession() async throws {
        let rig = try await TraversalBridgeRig.make()
        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        let environment = CleanEnvironment(homeDirectory: rig.root.path, protectedRoots: [])
        await rig.sessions.finish(session: rig.session)
        let discovery = await CleanCatalog.discoverFlutterSDKCache(environment: environment,
            orchestration: context)
        #expect(discovery.status == .unavailable)
        #expect(discovery.reason == "The bounded Flutter tool lookup was unavailable.")
        #expect(discovery.targets.isEmpty)
        try? FileManager.default.removeItem(at: rig.root)
    }

    @Test("local snapshot discovery fails closed once its session invalidates mid-command")
    @MainActor
    func localSnapshotDiscoveryFailsClosedOnInvalidSession() async throws {
        let rig = try await TraversalBridgeRig.make()
        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        await rig.sessions.finish(session: rig.session)
        let discovery = await CleanCatalog.discoverLocalSnapshots(orchestration: context)
        #expect(discovery.status == .unavailable)
        #expect(discovery.reason == "The bounded snapshot command was unavailable or incomplete.")
        #expect(discovery.targets.isEmpty)
        try? FileManager.default.removeItem(at: rig.root)
    }

    @Test("approved simulator discovery fails closed once its session invalidates mid-command")
    @MainActor
    func approvedSimulatorDiscoveryFailsClosedOnInvalidSession() async throws {
        let rig = try await TraversalBridgeRig.make()
        let context = try await CoreOrchestrationContext.make(sessions: rig.sessions,
            session: rig.session, sessionID: UUID())
        let environment = CleanEnvironment(homeDirectory: rig.root.path, protectedRoots: [],
            simulatorsApprovedForDeletion: ["some-udid"])
        await rig.sessions.finish(session: rig.session)
        let discovery = await CleanCatalog.discoverApprovedSimulators(environment: environment,
            orchestration: context)
        #expect(discovery.status == .unavailable)
        #expect(discovery.reason == "The bounded simulator inventory was unavailable or invalid.")
        #expect(discovery.targets.isEmpty)
        try? FileManager.default.removeItem(at: rig.root)
    }

    @Test("owned production routes have no direct fan-out, traversal, or synchronous process escape")
    func productionRouteManifestIsSealed() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sources = tests.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TidyCore")
        let manifest: [String: [String]] = [
            "Engine/ScanEngine.swift": [
                "withTaskGroup(", "HomeSurvey.walk(", "StaleNodeModulesScanner.find(",
                "UnclaimedSpaceScanner.find("
            ],
            "Engine/CleanEngine.swift": ["sizeScanner.scan("],
            "Catalog/CleanCatalog+Extras.swift": [
                "contentsOfDirectory", "StaleNodeModulesScanner.find("
            ],
            "Catalog/CleanCatalog+System.swift": ["hasLocalSnapshotsSync("],
            "Catalog/CleanCatalog+Xcode.swift": ["listDevicesSync("],
            "Catalog/CleanCatalog+DependencyCaches.swift": ["ToolLocator.locate(\"flutter\")"]
        ]

        let routeInventory: [String: (locate: Int, discover: Int, owner: String)] = [
            "CleanCatalog+Android.swift": (1, 0, "T16 Android adapters"),
            "CleanCatalog+Browsers.swift": (4, 0, "T17 browser adapters"),
            "CleanCatalog+DependencyCaches.swift": (1, 0, "T08.4 Flutter async route"),
            "CleanCatalog+Extras.swift": (3, 0, "T08.4 projects; T19 transcripts"),
            "CleanCatalog+Git.swift": (2, 0, "T20 Git adapters"),
            "CleanCatalog+Helpers.swift": (3, 2, "T08.4 pure paths; T12 globs"),
            "CleanCatalog+Memory.swift": (3, 3, "T18 memory requests"),
            "CleanCatalog+SafeCaches.swift": (1, 0, "T15-T16 tool adapters"),
            "CleanCatalog+System.swift": (1, 0, "T08.4 snapshot async route"),
            "CleanCatalog+Xcode.swift": (3, 0, "T08.4 inventory; T15 effects")
        ]
        let catalogDirectory = sources.appendingPathComponent("Catalog")
        let catalogFiles = try FileManager.default.contentsOfDirectory(atPath:
            catalogDirectory.path).filter {
                $0.hasPrefix("CleanCatalog+") && $0.hasSuffix(".swift")
            }
        #expect(Set(catalogFiles) == Set(routeInventory.keys),
            "Every catalog route file must have a named T08.4 or later owner")
        for (file, expected) in routeInventory {
            let source = try String(contentsOf: catalogDirectory.appendingPathComponent(file),
                encoding: .utf8)
            let locateCount = source.components(separatedBy: "locate:").count - 1
            let discoverCount = source.components(separatedBy: "discover:").count - 1
            #expect(locateCount == expected.locate,
                "Uninventoried locate route in \(file); owner: \(expected.owner)")
            #expect(discoverCount == expected.discover,
                "Uninventoried discover route in \(file); owner: \(expected.owner)")
            #expect(!expected.owner.isEmpty)
        }

        for (relative, forbidden) in manifest {
            let source = try String(contentsOf: sources.appendingPathComponent(relative),
                                    encoding: .utf8)
            for token in forbidden {
                #expect(!source.contains(token), "T08.4 escape in \(relative): \(token)")
            }
            for token in ["Process()", "waitUntilExit", "DispatchSemaphore"] {
                #expect(!source.contains(token), "private process escape in \(relative): \(token)")
            }
        }

        let commandRoutedFiles: [String: String] = [
            "Catalog/CleanCatalog+System.swift": "static func discoverLocalSnapshots(",
            "Catalog/CleanCatalog+Xcode.swift": "static func discoverApprovedSimulators("
        ]
        for (relative, discoveryMarker) in commandRoutedFiles {
            let source = try String(contentsOf: sources.appendingPathComponent(relative),
                                    encoding: .utf8)
            guard let markerRange = source.range(of: discoveryMarker) else {
                Issue.record("Expected \(discoveryMarker) in \(relative)")
                continue
            }
            let outsideDiscovery = String(source[source.startIndex..<markerRange.lowerBound])
            for token in ["Process(", "\"tmutil\"", "\"xcrun\"", "\"flutter\""] {
                #expect(!outsideDiscovery.contains(token),
                    "bypass of orchestration.withCommand in \(relative): \(token)")
            }
        }
    }
}

private final class CoreOrchestrationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

private func collectCoreEvents(_ subscription: ScanSubscription) async -> [ScanSessionEvent] {
    var events: [ScanSessionEvent] = []
    for await event in subscription.stream { events.append(event) }
    return events
}

private actor CoreScanCheckpoint {
    private let blockedAt: CoreScanTestPoint
    private var reached = false
    private var reachedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(blockedAt: CoreScanTestPoint) { self.blockedAt = blockedAt }

    func receive(_ point: CoreScanTestPoint) async {
        guard point == blockedAt else { return }
        reached = true
        reachedWaiter?.resume()
        reachedWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilReached() async {
        if reached { return }
        await withCheckedContinuation { reachedWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor CoreScanBlockingProcessProbe {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func run() async -> CoreScanProcessEvidence {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return .availableEmpty
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor CoreScanCountingProcessProbe {
    private var count = 0
    func run() -> CoreScanProcessEvidence {
        count += 1
        return .availableEmpty
    }
    func calls() -> Int { count }
}

private actor CoreActualProcessMonitor {
    private var highWater = 0

    func run(context: CoreOrchestrationContext) async {
        let first = Task {
            try? await context.withCommand {
                try await ProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["0.10"])
            }
        }
        let second = Task {
            try? await context.withCommand {
                try await ProcessRunner.run(executableURL: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["0.10"])
            }
        }
        for _ in 0..<100 {
            highWater = max(highWater, await ProcessRunner.jobSnapshot().activeReaders)
            try? await Task.sleep(for: .milliseconds(2))
        }
        _ = await first.value
        _ = await second.value
        highWater = max(highWater, await ProcessRunner.jobSnapshot().activeReaders)
    }

    func peak() -> Int { highWater }
}

private enum CoreOrchestrationTestError: Error { case timedOut }

private actor CorePlanningPermitGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private func waitForSchedulerQueue(_ sessions: BridgeExplicitSessions,
                                   minimum: Int) async throws {
    for _ in 0..<500 {
        if await sessions.snapshot().queued >= minimum { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    throw CoreOrchestrationTestError.timedOut
}

private func waitForTerminal(_ sessionID: UUID, in registry: ScanSessionRegistry) async throws {
    for _ in 0..<1_000 {
        if try await registry.state(sessionID: sessionID).terminal != nil { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    throw CoreOrchestrationTestError.timedOut
}
