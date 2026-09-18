import Foundation

/// Runs every read-only scan concurrently and assembles a `ScanReport`.
/// Nothing here writes to disk.
public enum ScanEngine: Sendable {
    private static let largeFileThreshold: Int64 = 1_073_741_824
    /// Part of every `ScanIndexKey`: bumping this forces every cached aggregate to be
    /// re-measured the next time indexing is enabled, for whenever the home-survey algorithm
    /// itself changes in a way that could change a previously-recorded total.
    static let scannerVersion = 1

    /// Superseded by `ScanEngine.start(environment:registry:sessions:session:)`, which is the
    /// only route that launches discovery, measurement, traversal, or process work. This overload
    /// keeps its row shape for callers not yet moved onto the explicit session path, but returns
    /// a structurally valid, entirely unmeasured report.
    public static func run(environment: CleanEnvironment) async -> ScanReport {
        ScanReport(
            generatedAt: Date(),
            detectedTools: environment.detectedTools,
            diskStats: nil,
            memoryStats: .current(),
            swapStats: SwapStats.current(),
            containerSpace: nil,
            topLevelHomeRanking: [],
            libraryRanking: [],
            filesOver1GB: [],
            localSnapshots: [],
            idleSimulatorRuntimes: [],
            staleNodeModules: [],
            launchAgents: [],
            topMemoryConsumers: [],
            restartOnlyReclaim: RestartReclaimSurvey(components: [], pagedOutBytes: nil,
                pagedOutUnavailableReason: "This route performs no measurement."),
            unclaimedBySize: []
        )
    }
}

public enum CoreOrchestrationError: Error, Equatable, Sendable {
    case schedulerUnavailable
    case policyPaused
    case invalidPolicySnapshot
    case foreignOrFinishedSession
    case stalePolicy
    case invalidScopeAuthorization
}

/// Validated, non-authoritative input for one core scan or planning request. The policy values
/// come only from the bridge's acknowledged scheduler snapshot; callers cannot supply a worker
/// cap, process cap, slice, rate, revision, or generation.
public struct CoreOrchestrationContext: Sendable {
    public let sessionID: UUID
    public let policyRevision: UInt64
    public let generation: UInt64
    public let observationEpoch: UInt64
    public let sliceSeconds: Int
    public let uiBatchesPerSecond: Int
    public let readOnlyProcessLimit: Int
    public let traversalLimits: TraversalLimits

    let sessions: BridgeExplicitSessions
    let session: WorkSession

    private init(sessionID: UUID, policyRevision: UInt64, generation: UInt64,
                 observationEpoch: UInt64, sliceSeconds: Int, uiBatchesPerSecond: Int,
                 readOnlyProcessLimit: Int,
                 limits: TraversalLimits, sessions: BridgeExplicitSessions,
                 session: WorkSession) {
        self.sessionID = sessionID
        self.policyRevision = policyRevision
        self.generation = generation
        self.observationEpoch = observationEpoch
        self.sliceSeconds = sliceSeconds
        self.uiBatchesPerSecond = uiBatchesPerSecond
        self.readOnlyProcessLimit = readOnlyProcessLimit
        traversalLimits = limits
        self.sessions = sessions
        self.session = session
    }

    public static func make(sessions: BridgeExplicitSessions, session: WorkSession,
                            sessionID: UUID,
                            traversalLimits suppliedLimits: TraversalLimits? = nil,
                            allowPaused: Bool = false) async throws -> CoreOrchestrationContext {
        guard await sessions.state(of: session) == .open else {
            throw CoreOrchestrationError.foreignOrFinishedSession
        }
        let snapshot = await sessions.snapshot()
        guard snapshot.availability == .available else {
            throw CoreOrchestrationError.schedulerUnavailable
        }
        guard let revision = snapshot.settingsRevision,
              let slice = snapshot.effectiveSliceSeconds,
              let rate = snapshot.effectiveUIBatchesPerSecond,
              (30...1_800).contains(slice), (1...4).contains(rate),
              (0...2).contains(snapshot.effectiveReadOnlyProcesses) else {
            throw CoreOrchestrationError.invalidPolicySnapshot
        }
        if snapshot.admission == .paused, !allowPaused {
            throw CoreOrchestrationError.policyPaused
        }
        let limits = try suppliedLimits ?? TraversalLimits(sliceSeconds: slice)
        guard limits.sliceSeconds == slice else {
            throw CoreOrchestrationError.invalidPolicySnapshot
        }
        return CoreOrchestrationContext(sessionID: sessionID, policyRevision: revision,
            generation: snapshot.generation, observationEpoch: snapshot.observationEpoch,
            sliceSeconds: slice, uiBatchesPerSecond: rate,
            readOnlyProcessLimit: snapshot.effectiveReadOnlyProcesses,
            limits: limits, sessions: sessions, session: session)
    }

    func replacingSessionID(_ sessionID: UUID) -> CoreOrchestrationContext {
        CoreOrchestrationContext(sessionID: sessionID, policyRevision: policyRevision,
            generation: generation, observationEpoch: observationEpoch,
            sliceSeconds: sliceSeconds, uiBatchesPerSecond: uiBatchesPerSecond,
            readOnlyProcessLimit: readOnlyProcessLimit,
            limits: traversalLimits, sessions: sessions, session: session)
    }

    func checkCurrent(allowPaused: Bool = false,
                      allowLiveObservationChanges: Bool = false) async throws
      -> WorkSchedulerSnapshot {
        guard await sessions.state(of: session) == .open else {
            throw CoreOrchestrationError.foreignOrFinishedSession
        }
        let snapshot = await sessions.snapshot()
        guard snapshot.availability == .available,
              snapshot.settingsRevision == policyRevision,
              snapshot.generation == generation,
              snapshot.effectiveSliceSeconds == sliceSeconds,
              snapshot.effectiveUIBatchesPerSecond == uiBatchesPerSecond else {
            throw CoreOrchestrationError.stalePolicy
        }
        if !allowLiveObservationChanges,
           (snapshot.observationEpoch != observationEpoch
            || snapshot.effectiveReadOnlyProcesses != readOnlyProcessLimit) {
            throw CoreOrchestrationError.stalePolicy
        }
        if snapshot.admission == .paused, !allowPaused {
            throw CoreOrchestrationError.policyPaused
        }
        return snapshot
    }

    func withPermit<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        _ = try await checkCurrent()
        let value = try await sessions.withPermit(session: session) { probe in
            try await probe.checkCancellation()
            let value = try await operation()
            try await probe.checkCancellation()
            return value
        }
        _ = try await checkCurrent()
        return value
    }

    func withCommand<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        _ = try await checkCurrent()
        try Task.checkCancellation()
        let expected = ProcessPolicyRevision(settings: policyRevision,
            observation: observationEpoch)
        switch await ProcessRunner.applySchedulerObservation(settingsRevision: policyRevision,
            observationEpoch: observationEpoch, resolvedReadOnlyCap: readOnlyProcessLimit) {
        case .applied:
            break
        case .rejectedInvalid:
            throw CoreOrchestrationError.invalidPolicySnapshot
        case .rejectedStale(let current):
            let gate = await ProcessRunner.jobSnapshot()
            guard current == expected, gate.policyRevision == expected,
                  gate.readOnlyCap == readOnlyProcessLimit else {
                throw CoreOrchestrationError.stalePolicy
            }
        }
        let value = try await operation()
        try Task.checkCancellation()
        _ = try await checkCurrent()
        return value
    }
}

public struct CoreScanResult: Sendable {
    public let report: ScanReport
    public let coverage: TraversalCoverage
    /// T08.4 cannot project T08.2's traversal-owned token through the accepted registry schema.
    /// A slice-expired result is therefore truthful partial state with unavailable continuation.
    public let continuationAvailable: Bool
    /// Traversal-source metadata reads performed by this scan generation. Cached aggregate reuse
    /// is zero even though `processedEntries` retains the cached logical count.
    public let metadataVisits: Int
    /// T09 diagnostic-only aggregate/freshness read from the incremental index, when a caller
    /// supplied a `ScanIndexCoordinator` to `ScanEngine.start`. Never a target list and never
    /// consulted to decide what this scan measures — it is purely something the UI may display
    /// alongside the always-authoritative `report`/`coverage` above.
    public let indexStatus: ScanIndexStatus?

    init(report: ScanReport, coverage: TraversalCoverage, continuationAvailable: Bool,
         metadataVisits: Int, indexStatus: ScanIndexStatus? = nil) {
        self.report = report
        self.coverage = coverage
        self.continuationAvailable = continuationAvailable
        self.metadataVisits = metadataVisits
        self.indexStatus = indexStatus
    }
}

public struct CoreScanHandle: Sendable {
    public let sessionID: UUID
    public let policyRevision: UInt64
    public let generation: UInt64
    fileprivate let store: CoreScanResultStore
    fileprivate let continuations: CoreScanContinuationStore

    fileprivate init(sessionID: UUID, policyRevision: UInt64, generation: UInt64,
                     store: CoreScanResultStore,
                     continuations: CoreScanContinuationStore = CoreScanContinuationStore()) {
        self.sessionID = sessionID
        self.policyRevision = policyRevision
        self.generation = generation
        self.store = store
        self.continuations = continuations
    }

    public func latestResult() async -> CoreScanResult? { await store.latest() }
}

internal enum CoreScanTestPoint: Equatable, Sendable {
    case beforeFilesystem
    case beforeProcess
    case beforeTerminal
}

internal struct CoreScanProcessEvidence: Sendable {
    let containerSpace: ContainerSpaceInfo?
    let localSnapshots: [LocalSnapshot]
    let idleSimulatorRuntimes: [SimulatorRuntime]
    let topMemoryConsumers: [ProcessUsage]
    let unavailable: Bool

    static let availableEmpty = CoreScanProcessEvidence(containerSpace: nil,
        localSnapshots: [], idleSimulatorRuntimes: [], topMemoryConsumers: [],
        unavailable: false)
}

internal struct CoreScanDependencies: Sendable {
    let processProbe: @Sendable (CoreOrchestrationContext, CleanEnvironment) async
        -> CoreScanProcessEvidence
    let testHook: (@Sendable (CoreScanTestPoint) async -> Void)?
    let metadataVisit: (@Sendable (String) async -> Void)?

    init(processProbe: @escaping @Sendable (CoreOrchestrationContext, CleanEnvironment) async
            -> CoreScanProcessEvidence,
         testHook: (@Sendable (CoreScanTestPoint) async -> Void)?,
         metadataVisit: (@Sendable (String) async -> Void)? = nil) {
        self.processProbe = processProbe
        self.testHook = testHook
        self.metadataVisit = metadataVisit
    }

    static let live = CoreScanDependencies(processProbe: { context, environment in
        await CoreLiveProcessProbe.run(context: context, environment: environment)
    }, testHook: nil, metadataVisit: nil)
}

private struct CoreMetadataVisitHook: BoundedTraversalTestHook {
    let visit: @Sendable (String) async -> Void
    func receive(_ event: BoundedTraversalTestEvent) async {
        guard case .metadataVisited(let paths) = event else { return }
        for path in paths { await visit(path) }
    }
}

private actor CoreScanResultStore {
    private var value: CoreScanResult?
    func update(_ value: CoreScanResult) { self.value = value }
    func latest() -> CoreScanResult? { value }
}

private struct PendingCoreScanContinuation: Sendable {
    let environment: CleanEnvironment
    let authorization: AuthorizedScanScope
    let context: CoreOrchestrationContext
    let rootIndex: Int
    let traversal: BoundedTraversal
    let cursor: TraversalCursor
    let completedAccumulator: CoreScanAccumulator
    let dependencies: CoreScanDependencies
    let indexCoordinator: ScanIndexCoordinator?
}

private actor CoreScanContinuationStore {
    private var pending: PendingCoreScanContinuation?
    func put(_ value: PendingCoreScanContinuation) { pending = value }
    func take() -> PendingCoreScanContinuation? {
        defer { pending = nil }
        return pending
    }
    func clear() { pending = nil }
    func isAvailable() -> Bool { pending != nil }
}

private struct CoreScanAccumulator: Sendable {
    let generatedAt = Date()
    let environment: CleanEnvironment
    var diskStats: DiskStats?
    var containerSpace: ContainerSpaceInfo?
    var topLevelHomeRanking: [RankedItem] = []
    var libraryRanking: [RankedItem] = []
    var filesOver1GB: [RankedItem] = []
    var localSnapshots: [LocalSnapshot] = []
    var idleSimulatorRuntimes: [SimulatorRuntime] = []
    var staleNodeModules: [TargetPath] = []
    var launchAgents: [String] = []
    var topMemoryConsumers: [ProcessUsage] = []
    var restartOnlyReclaim = RestartReclaimSurvey(components: [], pagedOutBytes: nil,
        pagedOutUnavailableReason: "No measurement was recorded.")
    var unclaimedBySize: [RankedItem] = []
    var processedEntries = 0
    var metadataVisits = 0
    var totalBytes: Int64 = 0
    var reasons: Set<TraversalCoverageReason> = []
    var includeItemsInSession = true
    var indexStatus: ScanIndexStatus?

    mutating func absorb(_ result: TraversalResult, optionalMissing: Bool = false) {
        let (entries, entriesOverflow) = processedEntries.addingReportingOverflow(
            result.metrics.processedEntries)
        processedEntries = entriesOverflow ? Int.max : entries
        if entriesOverflow { reasons.insert(.arithmeticOverflow) }
        let (visits, visitsOverflow) = metadataVisits.addingReportingOverflow(
            result.metrics.metadataVisits)
        metadataVisits = visitsOverflow ? Int.max : visits
        if visitsOverflow { reasons.insert(.arithmeticOverflow) }
        let (bytes, bytesOverflow) = totalBytes.addingReportingOverflow(result.totalBytes)
        totalBytes = bytesOverflow ? Int64.max : bytes
        if bytesOverflow { reasons.insert(.arithmeticOverflow) }
        var pageReasons = result.coverage.reasons
        if optionalMissing { pageReasons.remove(.missing) }
        reasons.formUnion(pageReasons)
    }

    mutating func absorbCached(_ record: ScanAggregateRecord, root: String) {
        let (entries, entriesOverflow) = processedEntries.addingReportingOverflow(
            record.processedEntries)
        processedEntries = entriesOverflow ? Int.max : entries
        let (bytes, bytesOverflow) = totalBytes.addingReportingOverflow(record.totalBytes)
        totalBytes = bytesOverflow ? Int64.max : bytes
        if entriesOverflow || bytesOverflow { reasons.insert(.arithmeticOverflow) }
        if record.totalBytes > 0 {
            topLevelHomeRanking.append(RankedItem(path: root, bytes: record.totalBytes))
        }
        indexStatus = .cached(record)
    }

    func report() -> ScanReport {
        ScanReport(generatedAt: generatedAt, detectedTools: environment.detectedTools,
            diskStats: diskStats, memoryStats: .current(), swapStats: SwapStats.current(),
            containerSpace: containerSpace, topLevelHomeRanking: topLevelHomeRanking,
            libraryRanking: libraryRanking, filesOver1GB: filesOver1GB,
            localSnapshots: localSnapshots, idleSimulatorRuntimes: idleSimulatorRuntimes,
            staleNodeModules: staleNodeModules, launchAgents: launchAgents,
            topMemoryConsumers: topMemoryConsumers, restartOnlyReclaim: restartOnlyReclaim,
            unclaimedBySize: unclaimedBySize)
    }

    func sessionSnapshot() -> ScanSessionSnapshot {
        let items = includeItemsInSession
            ? Array((topLevelHomeRanking + libraryRanking + filesOver1GB + unclaimedBySize)
                .prefix(64)) : []
        return ScanSessionSnapshot(processedEntries: processedEntries,
            totalBytes: totalBytes, items: items)
    }
}

private enum CoreLiveProcessProbe {
    private struct DeviceResponse: Decodable { let devices: [String: [SimulatorDevice]] }
    private struct RuntimeResponse: Decodable { let runtimes: [SimulatorRuntime] }

    static func run(context: CoreOrchestrationContext,
                    environment: CleanEnvironment) async -> CoreScanProcessEvidence {
        var unavailable = false
        let container: ContainerSpaceInfo?
        do {
            container = try await context.withCommand {
                guard let path = await ToolLocator.locateAsync("diskutil") else {
                    throw CoreOrchestrationError.schedulerUnavailable
                }
                let output = try await ProcessRunner.runContainerSpace(
                    diskutilURL: URL(fileURLWithPath: path), volumePath: "/")
                guard output.succeeded,
                      let data = output.standardOutput.data(using: .utf8),
                      let plist = try PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil) as? [String: Any],
                      let free = plist["APFSContainerFree"] as? Int,
                      let total = plist["APFSContainerSize"] as? Int else {
                    throw CoreOrchestrationError.schedulerUnavailable
                }
                return ContainerSpaceInfo(totalBytes: Int64(total), freeBytes: Int64(free))
            }
        } catch {
            container = nil
            unavailable = true
        }

        let snapshots: [LocalSnapshot]
        do {
            snapshots = try await context.withCommand {
                guard let path = await ToolLocator.locateAsync("tmutil") else {
                    throw CoreOrchestrationError.schedulerUnavailable
                }
                let output = try await ProcessRunner.runLocalSnapshots(
                    tmutilURL: URL(fileURLWithPath: path), volumePath: "/")
                guard output.succeeded else { throw CoreOrchestrationError.schedulerUnavailable }
                let parsed = output.standardOutput.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("com.apple.TimeMachine") }
                    .map { LocalSnapshot(identifier: $0) }
                guard parsed.count <= 64 else {
                    throw CoreOrchestrationError.invalidPolicySnapshot
                }
                return parsed
            }
        } catch {
            snapshots = []
            unavailable = true
        }

        let consumers: [ProcessUsage]
        do {
            consumers = try await context.withCommand {
                guard let path = await ToolLocator.locateAsync("ps") else {
                    throw CoreOrchestrationError.schedulerUnavailable
                }
                let output = try await ProcessRunner.runProcessSurvey(
                    psURL: URL(fileURLWithPath: path))
                guard output.succeeded else { throw CoreOrchestrationError.schedulerUnavailable }
                let lines = output.standardOutput.split(separator: "\n")
                guard lines.count > 1 else { throw CoreOrchestrationError.schedulerUnavailable }
                var parsed: [ProcessUsage] = []
                for line in lines.dropFirst() {
                    let parts = line.trimmingCharacters(in: .whitespaces)
                        .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    guard parts.count == 2, let rss = Int64(parts[0]), rss >= 0 else { continue }
                    let (residentBytes, overflow) = rss.multipliedReportingOverflow(by: 1_024)
                    guard !overflow else { continue }
                    parsed.append(ProcessUsage(name: (String(parts[1]) as NSString)
                        .lastPathComponent, residentBytes: residentBytes))
                    if parsed.count == 8 { break }
                }
                guard !parsed.isEmpty else { throw CoreOrchestrationError.schedulerUnavailable }
                return parsed
            }
        } catch {
            consumers = []
            unavailable = true
        }

        var idleRuntimes: [SimulatorRuntime] = []
        if environment.hasTool(.xcode) {
            do {
                idleRuntimes = try await context.withCommand {
                    guard let path = await ToolLocator.locateAsync("xcrun") else {
                        throw CoreOrchestrationError.schedulerUnavailable
                    }
                    let url = URL(fileURLWithPath: path)
                    let devicesOutput = try await ProcessRunner.runSimctlDevices(xcrunURL: url)
                    let runtimesOutput = try await ProcessRunner.runSimctlRuntimes(xcrunURL: url)
                    guard devicesOutput.succeeded, runtimesOutput.succeeded,
                          let deviceData = devicesOutput.standardOutput.data(using: .utf8),
                          let runtimeData = runtimesOutput.standardOutput.data(using: .utf8) else {
                        throw CoreOrchestrationError.schedulerUnavailable
                    }
                    let deviceResponse = try JSONDecoder().decode(DeviceResponse.self,
                        from: deviceData)
                    let runtimeResponse = try JSONDecoder().decode(RuntimeResponse.self,
                        from: runtimeData)
                    guard deviceResponse.devices.values.reduce(0, { $0 + $1.count }) <= 256,
                          runtimeResponse.runtimes.count <= 256 else {
                        throw CoreOrchestrationError.invalidPolicySnapshot
                    }
                    let used = Set(deviceResponse.devices.keys)
                    return runtimeResponse.runtimes.filter { !used.contains($0.identifier) }
                }
            } catch {
                unavailable = true
            }
        }
        return CoreScanProcessEvidence(containerSpace: container,
            localSnapshots: snapshots, idleSimulatorRuntimes: idleRuntimes,
            topMemoryConsumers: consumers, unavailable: unavailable)
    }
}

public extension ScanEngine {
    static func start(environment: CleanEnvironment, authorization: AuthorizedScanScope,
                      ownerID: UUID,
                      registry: ScanSessionRegistry,
                      sessions: BridgeExplicitSessions, session: WorkSession,
                      traversalLimits: TraversalLimits? = nil,
                      indexCoordinator: ScanIndexCoordinator? = nil) async throws -> CoreScanHandle {
        try await start(environment: environment, authorization: authorization,
            ownerID: ownerID,
            registry: registry, sessions: sessions, session: session,
            traversalLimits: traversalLimits, dependencies: .live,
            indexCoordinator: indexCoordinator)
    }

    static func continueScan(from handle: CoreScanHandle,
                             registry: ScanSessionRegistry) async throws -> CoreScanHandle {
        guard let pending = await handle.continuations.take() else {
            throw CoreOrchestrationError.invalidScopeAuthorization
        }
        do {
            let current = try await pending.context.checkCurrent(
                allowLiveObservationChanges: true)
            guard current.settingsRevision == handle.policyRevision else {
                throw CoreOrchestrationError.stalePolicy
            }
            let sessionID = try await registry.begin(policyRevision: handle.policyRevision,
                batchesPerSecond: pending.context.uiBatchesPerSecond,
                initialSnapshot: pending.completedAccumulator.sessionSnapshot())
            let store = CoreScanResultStore()
            let next = CoreScanHandle(sessionID: sessionID,
                policyRevision: handle.policyRevision, generation: handle.generation,
                store: store, continuations: handle.continuations)
            try await registry.startWork(sessionID: sessionID) { reporter in
                await runScopedContinuation(pending: pending, reporter: reporter,
                    store: store, continuations: handle.continuations)
            }
            return next
        } catch {
            await handle.continuations.clear()
            throw error
        }
    }

}

internal extension ScanEngine {
    /// Compatibility seam for `@testable` orchestration/process-cap fixtures. Production callers
    /// must use the public overload that consumes an `AuthorizedScanScope` at the start boundary.
    static func start(environment: CleanEnvironment, registry: ScanSessionRegistry,
                      sessions: BridgeExplicitSessions, session: WorkSession,
                      traversalLimits: TraversalLimits? = nil,
                      indexCoordinator: ScanIndexCoordinator? = nil) async throws -> CoreScanHandle {
        try await start(environment: environment, registry: registry, sessions: sessions,
            session: session, traversalLimits: traversalLimits, dependencies: .live,
            indexCoordinator: indexCoordinator)
    }

    static func start(environment: CleanEnvironment, authorization: AuthorizedScanScope,
                      ownerID: UUID,
                      registry: ScanSessionRegistry,
                      sessions: BridgeExplicitSessions, session: WorkSession,
                      traversalLimits: TraversalLimits? = nil,
                      dependencies: CoreScanDependencies,
                      indexCoordinator: ScanIndexCoordinator? = nil) async throws -> CoreScanHandle {
        try authorization.consumeForStart(ownerID: ownerID, environment: environment)
        let provisional = try await CoreOrchestrationContext.make(sessions: sessions,
            session: session, sessionID: UUID(), traversalLimits: traversalLimits)
        guard authorization.policyRevision == provisional.policyRevision else {
            throw CoreOrchestrationError.invalidScopeAuthorization
        }
        let sessionID = try await registry.begin(policyRevision: provisional.policyRevision,
            batchesPerSecond: provisional.uiBatchesPerSecond)
        let context = provisional.replacingSessionID(sessionID)
        let store = CoreScanResultStore()
        let continuations = CoreScanContinuationStore()
        let handle = CoreScanHandle(sessionID: sessionID,
            policyRevision: context.policyRevision, generation: context.generation, store: store,
            continuations: continuations)
        do {
            try await registry.startWork(sessionID: sessionID) { reporter in
                await runScopedRegistered(environment: environment, authorization: authorization,
                    context: context, reporter: reporter, store: store,
                    dependencies: dependencies, indexCoordinator: indexCoordinator,
                    continuations: continuations)
            }
        } catch {
            try? await registry.complete(sessionID: sessionID, terminal: .failed,
                coverage: TraversalCoverage(isComplete: false, reasons: [.unreadable]),
                snapshot: .init())
            throw error
        }
        return handle
    }

    static func start(environment: CleanEnvironment, registry: ScanSessionRegistry,
                      sessions: BridgeExplicitSessions, session: WorkSession,
                      traversalLimits: TraversalLimits? = nil,
                      dependencies: CoreScanDependencies,
                      indexCoordinator: ScanIndexCoordinator? = nil) async throws -> CoreScanHandle {
        let provisional = try await CoreOrchestrationContext.make(sessions: sessions,
            session: session, sessionID: UUID(), traversalLimits: traversalLimits)
        let sessionID = try await registry.begin(policyRevision: provisional.policyRevision,
            batchesPerSecond: provisional.uiBatchesPerSecond)
        let context = provisional.replacingSessionID(sessionID)
        let store = CoreScanResultStore()
        let handle = CoreScanHandle(sessionID: sessionID,
            policyRevision: context.policyRevision, generation: context.generation, store: store)
        do {
            try await registry.startWork(sessionID: sessionID) { reporter in
                await runRegistered(environment: environment, context: context,
                    reporter: reporter, store: store, dependencies: dependencies,
                    indexCoordinator: indexCoordinator)
            }
        } catch {
            try? await registry.complete(sessionID: sessionID, terminal: .failed,
                coverage: TraversalCoverage(isComplete: false, reasons: [.unreadable]),
                snapshot: .init())
            throw error
        }
        return handle
    }

    private static func runRegistered(environment: CleanEnvironment,
                                      context: CoreOrchestrationContext,
                                      reporter: ScanSessionReporter,
                                      store: CoreScanResultStore,
                                      dependencies: CoreScanDependencies,
                                      indexCoordinator: ScanIndexCoordinator? = nil) async
      -> ScanSessionCompletion {
        var accumulator = CoreScanAccumulator(environment: environment)
        await dependencies.testHook?(.beforeFilesystem)
        if await reporter.isCancelled() {
            return await cancelledCompletion(accumulator, store: store)
        }

        // Captured before each root's baseline walk starts, per the T09 generation protocol: any
        // event touching that root from here until its commit below invalidates the capture, and
        // the commit is then rejected in favor of retaining whatever was already cached.
        let homeRoot = PathGuard.canonicalize(environment.homeDirectory)
        let homeIndexContext = await indexRootContext(root: homeRoot,
            coordinator: indexCoordinator, context: context)
        var homeCacheHit: ScanAggregateRecord?
        if let homeIndexContext, let indexCoordinator,
           case .cached(let record) = await indexCoordinator.status(for: homeIndexContext.key,
               root: homeRoot), record.isComplete {
            homeCacheHit = record
        }

        var homeIndexStatus: ScanIndexStatus?
        if let record = homeCacheHit {
            // The whole point of the index: nothing is walked for this root at all. Per-child
            // ranking and individual large files are never persisted (T09 forbids caching
            // anything resembling a path list), so both stay empty this round — a display-only
            // degradation the contract explicitly allows ("aggregates and freshness only"); it
            // never changes coverage, and `homeIndexStatus` below tells a caller exactly why.
            homeIndexStatus = .cached(record)
        } else {
            let home = await HomeSurvey.walkBounded(sessions: context.sessions,
                session: context.session, sessionID: context.sessionID,
                generation: context.generation, root: environment.homeDirectory,
                protectedRoots: environment.protectedRoots,
                largeFileThreshold: largeFileThreshold, breakOutChildren: true,
                limits: context.traversalLimits)
            accumulator.absorb(home.result)
            accumulator.topLevelHomeRanking = Array(home.result.childTotals
                .filter { LargestItemsScanner.matchesHomeTopLevelPattern(
                    URL(fileURLWithPath: $0.path).lastPathComponent) }
                .sorted(by: rankedBefore).prefix(8))
            accumulator.filesOver1GB = Array(home.result.topItems
                .sorted(by: rankedBefore).prefix(8))
            if home.result.cursor != nil {
                await home.traversal.invalidate(sessionID: context.sessionID)
                _ = await publishProgress(accumulator: &accumulator, context: context,
                    reporter: reporter, store: store)
                return await partialCompletion(accumulator, store: store)
            }
            homeIndexStatus = await commitRootResult(home.result, root: homeRoot,
                indexContext: homeIndexContext, coordinator: indexCoordinator)
        }
        guard await publishProgress(accumulator: &accumulator, context: context,
                                    reporter: reporter, store: store) else {
            return await cancelledCompletion(accumulator, store: store)
        }

        let libraryRoot = PathGuard.canonicalize(environment.homeDirectory + "/Library")
        let libraryIndexContext = await indexRootContext(root: libraryRoot,
            coordinator: indexCoordinator, context: context)
        var libraryCacheHit: ScanAggregateRecord?
        if let libraryIndexContext, let indexCoordinator,
           case .cached(let record) = await indexCoordinator.status(for: libraryIndexContext.key,
               root: libraryRoot), record.isComplete {
            libraryCacheHit = record
        }

        if libraryCacheHit == nil {
            let library = await HomeSurvey.walkBounded(sessions: context.sessions,
                session: context.session, sessionID: context.sessionID,
                generation: context.generation, root: environment.homeDirectory + "/Library",
                protectedRoots: environment.protectedRoots, largeFileThreshold: 0,
                breakOutChildren: true, limits: context.traversalLimits)
            accumulator.absorb(library.result, optionalMissing: true)
            accumulator.libraryRanking = Array(library.result.childTotals
                .sorted(by: rankedBefore).prefix(6))
            if library.result.cursor != nil {
                await library.traversal.invalidate(sessionID: context.sessionID)
                return await partialCompletion(accumulator, store: store)
            }
            _ = await commitRootResult(library.result, root: libraryRoot,
                indexContext: libraryIndexContext, coordinator: indexCoordinator)
        }

        if environment.gitRoots.count > 64 {
            accumulator.reasons.insert(.resultLimit)
        } else {
            for root in environment.gitRoots {
                guard let page = await StaleNodeModulesScanner.findBounded(root: root,
                    olderThanDays: environment.staleNodeModulesThresholdDays,
                    sessions: context.sessions, session: context.session,
                    sessionID: context.sessionID, generation: context.generation,
                    limits: context.traversalLimits) else { continue }
                accumulator.absorb(page.result, optionalMissing: true)
                let remaining = max(0, context.traversalLimits.resultRecords
                    - accumulator.staleNodeModules.count)
                accumulator.staleNodeModules.append(contentsOf: page.result.records.prefix(remaining).map {
                    TargetPath(path: $0.path, label: $0.path)
                })
                if page.result.records.count > remaining {
                    accumulator.reasons.insert(.resultLimit)
                }
                if page.result.cursor != nil {
                    await page.traversal.invalidate(sessionID: context.sessionID)
                    return await partialCompletion(accumulator, store: store)
                }
            }
        }

        let launchAgents = await boundedDirectory(environment.homeDirectory
            + "/Library/LaunchAgents", context: context, optionalMissing: true)
        accumulator.absorb(launchAgents.result, optionalMissing: true)
        let launchAgentNames = launchAgents.result.records.filter { $0.depth == 1 }
            .map { URL(fileURLWithPath: $0.path).lastPathComponent }.sorted()
        accumulator.launchAgents = Array(launchAgentNames.prefix(256))
        if launchAgentNames.count > 256 { accumulator.reasons.insert(.resultLimit) }
        if launchAgents.result.cursor != nil {
            await launchAgents.traversal.invalidate(sessionID: context.sessionID)
            return await partialCompletion(accumulator, store: store)
        }

        var reclaimBuckets: [String: (bytes: Int64, count: Int)] = [:]
        for directory in RestartReclaimSurvey.vmDirectories {
            let page = await boundedDirectory(directory, context: context, optionalMissing: true)
            accumulator.absorb(page.result, optionalMissing: true)
            for record in page.result.records where record.depth == 1
                && record.kind == .regularFile {
                let label = RestartReclaimSurvey.label(
                    forFileNamed: URL(fileURLWithPath: record.path).lastPathComponent)
                var bucket = reclaimBuckets[label] ?? (0, 0)
                bucket.bytes += record.bytes
                bucket.count += 1
                reclaimBuckets[label] = bucket
            }
            if page.result.cursor != nil {
                await page.traversal.invalidate(sessionID: context.sessionID)
                return await partialCompletion(accumulator, store: store)
            }
        }
        let swap = SwapStats.current()
        accumulator.restartOnlyReclaim = RestartReclaimSurvey(components: reclaimBuckets.map {
            .init(label: $0.key, bytes: $0.value.bytes, fileCount: $0.value.count)
        }.sorted { $0.bytes > $1.bytes }, pagedOutBytes: swap?.usedBytes,
            pagedOutUnavailableReason: swap == nil
                ? "The swap usage reading was unavailable." : nil)

        if accumulator.topLevelHomeRanking.contains(where: {
            $0.bytes >= UnclaimedSpaceScanner.defaultThresholdBytes
        }) {
            // Without an accepted bounded claim inventory, suppress candidates and mark the
            // evidence unavailable instead of presenting an empty successful discovery.
            accumulator.reasons.insert(.unreadable)
        }
        do {
            accumulator.diskStats = try await context.withPermit { try DiskStats.current() }
        } catch {
            accumulator.reasons.insert(.unreadable)
        }

        guard await publishProgress(accumulator: &accumulator, context: context,
                                    reporter: reporter, store: store) else {
            return await cancelledCompletion(accumulator, store: store)
        }
        await dependencies.testHook?(.beforeProcess)
        if await reporter.isCancelled() {
            return await cancelledCompletion(accumulator, store: store)
        }
        let process = await dependencies.processProbe(context, environment)
        accumulator.containerSpace = process.containerSpace
        accumulator.localSnapshots = process.localSnapshots
        accumulator.idleSimulatorRuntimes = process.idleSimulatorRuntimes
        accumulator.topMemoryConsumers = process.topMemoryConsumers
        if process.unavailable { accumulator.reasons.insert(.unreadable) }

        do { _ = try await context.checkCurrent() }
        catch {
            if await reporter.isCancelled() {
                return await cancelledCompletion(accumulator, store: store)
            }
            accumulator.reasons.insert(.policyRevisionMismatch)
        }
        await dependencies.testHook?(.beforeTerminal)
        if await reporter.isCancelled() {
            return await cancelledCompletion(accumulator, store: store)
        }

        let coverage = TraversalCoverage(isComplete: accumulator.reasons.isEmpty,
            reasons: accumulator.reasons)
        // `homeIndexStatus` was already resolved above — either a cache hit that made the home
        // walk unnecessary, or the outcome of committing what the home walk actually measured.
        // Nothing here re-derives it from `accumulator`'s scan-wide totals, which mix in
        // library/stale-node_modules/launch-agents/restart-reclaim bytes that have nothing to do
        // with the home root's own aggregate.
        await store.update(CoreScanResult(report: accumulator.report(), coverage: coverage,
            continuationAvailable: false, metadataVisits: accumulator.metadataVisits,
            indexStatus: homeIndexStatus))
        return ScanSessionCompletion(terminal: coverage.isComplete ? .complete : .partial,
            coverage: coverage, snapshot: accumulator.sessionSnapshot())
    }

    fileprivate static func runScopedRegistered(environment: CleanEnvironment,
                                             authorization: AuthorizedScanScope,
                                             context: CoreOrchestrationContext,
                                             reporter: ScanSessionReporter,
                                             store: CoreScanResultStore,
                                             dependencies: CoreScanDependencies,
                                             indexCoordinator: ScanIndexCoordinator?,
                                             continuations: CoreScanContinuationStore) async
      -> ScanSessionCompletion {
        let accumulator = CoreScanAccumulator(environment: environment)
        await dependencies.testHook?(.beforeFilesystem)
        if await reporter.isCancelled() {
            return await cancelledCompletion(accumulator, store: store)
        }
        return await runScopedPages(environment: environment, authorization: authorization,
            context: context, rootIndex: 0, current: nil,
            completedAccumulator: accumulator, reporter: reporter, store: store,
            dependencies: dependencies, indexCoordinator: indexCoordinator,
            continuations: continuations)
    }

    fileprivate static func runScopedContinuation(pending: PendingCoreScanContinuation,
                                              reporter: ScanSessionReporter,
                                              store: CoreScanResultStore,
                                              continuations: CoreScanContinuationStore) async
      -> ScanSessionCompletion {
        await runScopedPages(environment: pending.environment,
            authorization: pending.authorization, context: pending.context,
            rootIndex: pending.rootIndex,
            current: (pending.traversal, pending.cursor),
            completedAccumulator: pending.completedAccumulator,
            reporter: reporter, store: store, dependencies: pending.dependencies,
            indexCoordinator: pending.indexCoordinator, continuations: continuations)
    }

    fileprivate static func runScopedPages(environment: CleanEnvironment,
                                       authorization: AuthorizedScanScope,
                                       context: CoreOrchestrationContext,
                                       rootIndex: Int,
                                       current: (BoundedTraversal, TraversalCursor)?,
                                       completedAccumulator: CoreScanAccumulator,
                                       reporter: ScanSessionReporter,
                                       store: CoreScanResultStore,
                                       dependencies: CoreScanDependencies,
                                       indexCoordinator: ScanIndexCoordinator?,
                                       continuations: CoreScanContinuationStore) async
      -> ScanSessionCompletion {
        var completed = completedAccumulator
        let protected = Array(Set(environment.protectedRoots + authorization.excludedRoots))
        let visitHook = dependencies.metadataVisit.map(CoreMetadataVisitHook.init(visit:))
        for index in rootIndex..<authorization.roots.count {
            let root = authorization.roots[index]
            if await reporter.isCancelled() {
                await continuations.clear()
                return await cancelledCompletion(completed, store: store)
            }
            let traversal: BoundedTraversal
            let result: TraversalResult
            let indexContext: IndexRootContext?
            if current == nil || index != rootIndex {
                indexContext = await indexRootContext(root: root,
                    coordinator: indexCoordinator, context: context)
            } else {
                indexContext = nil
            }
            if let indexContext, let indexCoordinator,
               case .cached(let record) = await indexCoordinator.status(
                    for: indexContext.key, root: root), record.isComplete {
                completed.absorbCached(record, root: root)
                completed.topLevelHomeRanking = Array(completed.topLevelHomeRanking
                    .sorted(by: rankedBefore).prefix(8))
                guard await publishProgress(accumulator: &completed, context: context,
                                            reporter: reporter, store: store,
                                            allowLiveObservationChanges: true) else {
                    await continuations.clear()
                    return await cancelledCompletion(completed, store: store)
                }
                continue
            }
            if index == rootIndex, let current {
                traversal = current.0
                result = await traversal.continue(from: current.1,
                    session: context.session, sessionID: context.sessionID,
                    generation: context.generation)
            } else if let visitHook {
                traversal = BoundedTraversal(sessions: context.sessions,
                    limits: context.traversalLimits, testHook: visitHook)
                result = await traversal.start(root: root, session: context.session,
                    sessionID: context.sessionID, generation: context.generation,
                    options: TraversalOptions(protectedRoots: protected,
                        minimumFileBytes: largeFileThreshold, collectChildTotals: false,
                        recordSelection: .none))
            } else {
                traversal = BoundedTraversal(sessions: context.sessions,
                    limits: context.traversalLimits)
                result = await traversal.start(root: root, session: context.session,
                    sessionID: context.sessionID, generation: context.generation,
                    options: TraversalOptions(protectedRoots: protected,
                        minimumFileBytes: largeFileThreshold, collectChildTotals: false,
                        recordSelection: .none))
            }
            var displayed = completed
            displayed.absorb(result, optionalMissing: true)
            if result.totalBytes > 0 {
                displayed.topLevelHomeRanking.append(
                    RankedItem(path: root, bytes: result.totalBytes))
            }
            displayed.filesOver1GB.append(contentsOf: result.topItems)
            displayed.topLevelHomeRanking = Array(displayed.topLevelHomeRanking
                .sorted(by: rankedBefore).prefix(8))
            displayed.filesOver1GB = Array(displayed.filesOver1GB
                .sorted(by: rankedBefore).prefix(8))
            if let cursor = result.cursor {
                await continuations.put(PendingCoreScanContinuation(
                    environment: environment, authorization: authorization,
                    context: context, rootIndex: index, traversal: traversal,
                    cursor: cursor, completedAccumulator: completed,
                    dependencies: dependencies, indexCoordinator: indexCoordinator))
                return await continuablePartialCompletion(displayed, store: store)
            }
            if let indexContext {
                displayed.indexStatus = await commitRootResult(result, root: root,
                    indexContext: indexContext, coordinator: indexCoordinator)
            }
            completed = displayed
            guard await publishProgress(accumulator: &completed, context: context,
                                        reporter: reporter, store: store,
                                        allowLiveObservationChanges: true) else {
                await continuations.clear()
                return await cancelledCompletion(completed, store: store)
            }
        }
        do { _ = try await context.checkCurrent(allowLiveObservationChanges: true) }
        catch { completed.reasons.insert(.policyRevisionMismatch) }
        await continuations.clear()
        let coverage = TraversalCoverage(isComplete: completed.reasons.isEmpty,
            reasons: completed.reasons)
        await store.update(CoreScanResult(report: completed.report(), coverage: coverage,
            continuationAvailable: false, metadataVisits: completed.metadataVisits,
            indexStatus: completed.indexStatus))
        return ScanSessionCompletion(terminal: coverage.isComplete ? .complete : .partial,
            coverage: coverage, snapshot: completed.sessionSnapshot())
    }

    private struct IndexRootContext: Sendable {
        let key: ScanIndexKey
        let volumeUUID: String
        let generation: UInt64
    }

    /// Resolves the cache key and captures the generation a walk of `root` must recheck at
    /// commit time. Returns nil whenever there is nothing to cache against — no coordinator was
    /// supplied, or the root's volume/file identity can't be resolved right now — in which case
    /// the caller always falls through to a real walk with no index involvement at all.
    private static func indexRootContext(root: String, coordinator: ScanIndexCoordinator?,
                                         context: CoreOrchestrationContext) async
      -> IndexRootContext? {
        guard let coordinator, let identity = ScanRootIdentity.resolve(path: root) else {
            return nil
        }
        let key = ScanIndexKey(volumeUUID: identity.volumeUUID, rootIdentity: identity.fileIdentity,
            scannerVersion: ScanEngine.scannerVersion,
            policyFingerprint: String(context.policyRevision))
        let generation = await coordinator.beginScan(root: root)
        return IndexRootContext(key: key, volumeUUID: identity.volumeUUID, generation: generation)
    }

    /// Best-effort only: a failure here never changes `coverage`, `report`, or anything about the
    /// walk that already happened — the returned status exists purely for display. Publishing to
    /// the index can never gate, filter, or otherwise influence what a scan measures or reports.
    private static func commitRootResult(_ result: TraversalResult, root: String,
                                         indexContext: IndexRootContext?,
                                         coordinator: ScanIndexCoordinator?) async
      -> ScanIndexStatus? {
        guard let coordinator, let indexContext else { return nil }
        let reasons = Set(result.coverage.reasons.map(\.rawValue))
        let outcome = await coordinator.commitIfCurrent(key: indexContext.key, root: root,
            volumeUUID: indexContext.volumeUUID, capturedGeneration: indexContext.generation,
            totalBytes: result.totalBytes, processedEntries: result.metrics.processedEntries,
            isComplete: result.coverage.isComplete, reasons: reasons)
        switch outcome {
        case .committed(let record):
            return .cached(record)
        case .staleGeneration, .rejectedPartialOverComplete, .unavailable:
            return await coordinator.status(for: indexContext.key, root: root)
        }
    }

    private static func boundedDirectory(_ path: String, context: CoreOrchestrationContext,
                                         optionalMissing: Bool) async -> BoundedTraversalPage {
        let limits = context.traversalLimits.replacing(maxDepth: 1, topN: 0)
        let traversal = BoundedTraversal(sessions: context.sessions, limits: limits)
        let result = await traversal.start(root: path, session: context.session,
            sessionID: context.sessionID, generation: context.generation,
            options: TraversalOptions(recordSelection: .all))
        return BoundedTraversalPage(traversal: traversal, result: result)
    }

    private static func publishProgress(accumulator: inout CoreScanAccumulator,
                                        context: CoreOrchestrationContext,
                                        reporter: ScanSessionReporter,
                                        store: CoreScanResultStore,
                                        allowLiveObservationChanges: Bool = false) async -> Bool {
        if await reporter.isCancelled() { return false }
        do { _ = try await context.checkCurrent(
            allowLiveObservationChanges: allowLiveObservationChanges) }
        catch { return false }
        var progressReasons = accumulator.reasons
        progressReasons.insert(.sliceExpired)
        let coverage = TraversalCoverage(isComplete: false, reasons: progressReasons)
        var snapshot = accumulator.sessionSnapshot()
        do {
            try await reporter.recordBatch(coverage: coverage, snapshot: snapshot)
        } catch ScanSessionRegistryError.snapshotLimit {
            accumulator.includeItemsInSession = false
            snapshot = accumulator.sessionSnapshot()
            do { try await reporter.recordBatch(coverage: coverage, snapshot: snapshot) }
            catch { return false }
        } catch {
            return false
        }
        await store.update(CoreScanResult(report: accumulator.report(), coverage: coverage,
            continuationAvailable: false, metadataVisits: accumulator.metadataVisits))
        return true
    }

    private static func cancelledCompletion(_ accumulator: CoreScanAccumulator,
                                            store: CoreScanResultStore) async
      -> ScanSessionCompletion {
        var reasons = accumulator.reasons
        reasons.insert(.cancelled)
        let coverage = TraversalCoverage(isComplete: false, reasons: reasons)
        await store.update(CoreScanResult(report: accumulator.report(), coverage: coverage,
            continuationAvailable: false, metadataVisits: accumulator.metadataVisits))
        return ScanSessionCompletion(terminal: .cancelled,
            coverage: coverage,
            snapshot: accumulator.sessionSnapshot())
    }

    private static func partialCompletion(_ accumulator: CoreScanAccumulator,
                                          store: CoreScanResultStore) async
      -> ScanSessionCompletion {
        var reasons = accumulator.reasons
        if reasons.isEmpty { reasons.insert(.sliceExpired) }
        let coverage = TraversalCoverage(isComplete: false, reasons: reasons)
        await store.update(CoreScanResult(report: accumulator.report(), coverage: coverage,
            continuationAvailable: false, metadataVisits: accumulator.metadataVisits))
        return ScanSessionCompletion(terminal: .partial,
            coverage: coverage,
            snapshot: accumulator.sessionSnapshot())
    }

    private static func continuablePartialCompletion(_ accumulator: CoreScanAccumulator,
                                                      store: CoreScanResultStore) async
      -> ScanSessionCompletion {
        var reasons = accumulator.reasons
        reasons.insert(.sliceExpired)
        let coverage = TraversalCoverage(isComplete: false, reasons: reasons)
        await store.update(CoreScanResult(report: accumulator.report(), coverage: coverage,
            continuationAvailable: true, metadataVisits: accumulator.metadataVisits,
            indexStatus: accumulator.indexStatus))
        return ScanSessionCompletion(terminal: .partial, coverage: coverage,
            snapshot: accumulator.sessionSnapshot())
    }

    private static func rankedBefore(_ lhs: RankedItem, _ rhs: RankedItem) -> Bool {
        lhs.bytes != rhs.bytes ? lhs.bytes > rhs.bytes : lhs.path < rhs.path
    }
}
