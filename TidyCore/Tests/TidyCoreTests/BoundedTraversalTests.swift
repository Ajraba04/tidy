import Foundation
import Testing
@testable import TidyCore

private final class LockedTraversalSource: BoundedTraversalSource, @unchecked Sendable {
    struct Node {
        var identity: TraversalSourceIdentity
        var bytes: Int64
        var isDirectory: Bool
        var children: [String]
        var modifiedAt: Date?
        var linkCount: Int
        var terminalReason: TraversalCoverageReason?
        var observedBreadth: Int?
        var readReason: TraversalCoverageReason?
        var contentVersion: UInt64

        init(identity: TraversalSourceIdentity, bytes: Int64, isDirectory: Bool,
             children: [String], modifiedAt: Date? = nil, linkCount: Int = 1,
             terminalReason: TraversalCoverageReason? = nil,
             observedBreadth: Int? = nil,
             readReason: TraversalCoverageReason? = nil,
             contentVersion: UInt64 = 0) {
            self.identity = identity
            self.bytes = bytes
            self.isDirectory = isDirectory
            self.children = children
            self.modifiedAt = modifiedAt
            self.linkCount = linkCount
            self.terminalReason = terminalReason
            self.observedBreadth = observedBreadth
            self.readReason = readReason
            self.contentVersion = contentVersion
        }
    }

    private let lock = NSLock()
    private var nodes: [String: Node]
    private var inspected: [String] = []
    private var mainThreadReads = 0

    init(nodes: [String: Node]) { self.nodes = nodes }

    func rootIdentity(at path: String) -> TraversalRootRead {
        guard let node = nodes[path] else { return .missing }
        return .identity(node.identity)
    }

    func read(_ request: TraversalSourceRequest) -> TraversalSourceRead {
        lock.lock()
        inspected.append(request.path)
        if Thread.isMainThread { mainThreadReads += 1 }
        lock.unlock()

        guard let node = nodes[request.path] else { return .skipped(.missing) }
        if let reason = node.readReason { return .skipped(reason) }
        let children = node.children.compactMap { name -> TraversalSourceChild? in
            let childPath = request.path + "/" + name
            guard let child = nodes[childPath] else { return nil }
            return TraversalSourceChild(name: name, identity: child.identity)
        }
        return .entry(TraversalSourceEntry(
            identity: node.identity,
            bytes: node.bytes,
            kind: node.isDirectory ? .directory : .regularFile,
            modifiedAt: node.modifiedAt,
            linkCount: node.linkCount,
            children: children,
            terminalReason: node.terminalReason,
            observedBreadth: node.observedBreadth ?? children.count,
            openDescriptorHighWater: node.isDirectory ? 1 : 0,
            directoryWatermark: node.isDirectory ? Self.watermark(node) : nil
        ))
    }

    func validateDirectory(at path: String,
                           watermark: TraversalDirectoryWatermark) -> TraversalCoverageReason? {
        lock.lock(); defer { lock.unlock() }
        guard let node = nodes[path], node.isDirectory else { return .churn }
        return Self.watermark(node) == watermark ? nil : .churn
    }

    func replaceIdentity(at path: String, with identity: TraversalSourceIdentity) {
        lock.lock(); defer { lock.unlock() }
        nodes[path]?.identity = identity
    }

    func appendChild(parent: String, name: String, node: Node) {
        lock.lock(); defer { lock.unlock() }
        nodes[parent]?.children.append(name)
        nodes[parent]?.contentVersion += 1
        nodes[parent + "/" + name] = node
    }

    func snapshot() -> (paths: [String], mainThreadReads: Int) {
        lock.lock(); defer { lock.unlock() }
        return (inspected, mainThreadReads)
    }

    private static func watermark(_ node: Node) -> TraversalDirectoryWatermark {
        TraversalDirectoryWatermark(identity: node.identity,
            modifiedSeconds: Int64(bitPattern: node.contentVersion), modifiedNanoseconds: 0,
            changedSeconds: 0, changedNanoseconds: 0, size: Int64(node.children.count),
            linkCount: 1)
    }
}

/// Generates a high-cardinality tree on demand so the regression exercises thousands of real
/// traversal entries without retaining a same-sized fixture graph in the test process.
private final class VirtualHighCardinalityTraversalSource: BoundedTraversalSource,
    @unchecked Sendable {
    let root: String
    let directoryCount: Int
    let filesPerDirectory: Int

    private let lock = NSLock()
    private var readCount = 0
    private var maximumChildren = 0

    init(root: String, directoryCount: Int, filesPerDirectory: Int) {
        self.root = root
        self.directoryCount = directoryCount
        self.filesPerDirectory = filesPerDirectory
    }

    func rootIdentity(at path: String) -> TraversalRootRead {
        path == root ? .identity(rootIdentity) : .missing
    }

    func read(_ request: TraversalSourceRequest) -> TraversalSourceRead {
        if request.path == root {
            let children = (0..<directoryCount).map {
                TraversalSourceChild(name: "d\($0)", identity: directoryIdentity($0))
            }
            recordRead(children: children.count)
            return directoryEntry(identity: rootIdentity, children: children)
        }

        let components = request.relativePath.split(separator: "/")
        guard let first = components.first,
              let directory = Self.index(after: "d", in: first) else {
            recordRead(children: 0)
            return .skipped(.missing)
        }
        if components.count == 1, directory < directoryCount {
            let children = (0..<filesPerDirectory).map {
                TraversalSourceChild(name: "f\($0)",
                    identity: fileIdentity(directory: directory, file: $0))
            }
            recordRead(children: children.count)
            return directoryEntry(identity: directoryIdentity(directory), children: children)
        }
        guard components.count == 2,
              let file = Self.index(after: "f", in: components[1]),
              directory < directoryCount, file < filesPerDirectory else {
            recordRead(children: 0)
            return .skipped(.missing)
        }
        let ordinal = directory * filesPerDirectory + file + 1
        recordRead(children: 0)
        return .entry(TraversalSourceEntry(
            identity: fileIdentity(directory: directory, file: file),
            bytes: Int64(ordinal), kind: .regularFile, modifiedAt: nil,
            linkCount: file.isMultiple(of: 8) ? 2 : 1, children: [],
            terminalReason: nil, observedBreadth: 0, openDescriptorHighWater: 0))
    }

    func validateDirectory(at path: String,
                           watermark: TraversalDirectoryWatermark) -> TraversalCoverageReason? {
        let expected: TraversalDirectoryWatermark?
        if path == root {
            expected = directoryWatermark(identity: rootIdentity, children: directoryCount)
        } else {
            let relative = path.dropFirst(root.count + 1)
            if let directory = Self.index(after: "d", in: relative),
               directory < directoryCount {
                expected = directoryWatermark(identity: directoryIdentity(directory),
                                              children: filesPerDirectory)
            } else {
                expected = nil
            }
        }
        return expected == watermark ? nil : .churn
    }

    func snapshot() -> (readCount: Int, maximumChildren: Int) {
        lock.lock(); defer { lock.unlock() }
        return (readCount, maximumChildren)
    }

    private var rootIdentity: TraversalSourceIdentity {
        TraversalSourceIdentity(device: 9, inode: 1, generation: 1)
    }

    private func directoryIdentity(_ directory: Int) -> TraversalSourceIdentity {
        TraversalSourceIdentity(device: 9, inode: UInt64(directory + 2), generation: 1)
    }

    private func fileIdentity(directory: Int, file: Int) -> TraversalSourceIdentity {
        TraversalSourceIdentity(device: 9,
            inode: UInt64(1_000 + directory * filesPerDirectory + file), generation: 1)
    }

    private func directoryEntry(identity: TraversalSourceIdentity,
                                children: [TraversalSourceChild]) -> TraversalSourceRead {
        .entry(TraversalSourceEntry(identity: identity, bytes: 0, kind: .directory,
            modifiedAt: nil, linkCount: 1, children: children, terminalReason: nil,
            observedBreadth: children.count, openDescriptorHighWater: 1,
            directoryWatermark: directoryWatermark(identity: identity,
                                                    children: children.count)))
    }

    private func directoryWatermark(identity: TraversalSourceIdentity,
                                    children: Int) -> TraversalDirectoryWatermark {
        TraversalDirectoryWatermark(identity: identity, modifiedSeconds: 1,
            modifiedNanoseconds: 0, changedSeconds: 1, changedNanoseconds: 0,
            size: Int64(children), linkCount: 1)
    }

    private func recordRead(children: Int) {
        lock.lock(); defer { lock.unlock() }
        readCount += 1
        maximumChildren = max(maximumChildren, children)
    }

    private static func index<S: StringProtocol>(after prefix: Character, in value: S) -> Int? {
        guard value.first == prefix else { return nil }
        return Int(value.dropFirst())
    }
}

private final class ManualTraversalClock: @unchecked Sendable {
    private let lock = NSLock()
    private var nanoseconds: UInt64

    init(seconds: UInt64 = 0) { nanoseconds = seconds * 1_000_000_000 }

    func now() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return nanoseconds
    }

    func advance(seconds: UInt64) {
        lock.lock(); defer { lock.unlock() }
        nanoseconds += seconds * 1_000_000_000
    }

    var traversalClock: BoundedTraversalClock {
        BoundedTraversalClock(nowNanoseconds: { self.now() })
    }
}

private final class DirectoryReplacementRace: @unchecked Sendable {
    private let lock = NSLock()
    private let original: URL
    private let parked: URL
    private let replacement: URL
    private var didRun = false
    private var failure: String?

    init(original: URL, parked: URL, replacement: URL) {
        self.original = original
        self.parked = parked
        self.replacement = replacement
    }

    func replaceBeforeOpen(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        guard !didRun, path == original.path else { return }
        didRun = true
        do {
            try FileManager.default.moveItem(at: original, to: parked)
            try FileManager.default.createSymbolicLink(at: original,
                                                       withDestinationURL: replacement)
        } catch {
            failure = String(describing: error)
        }
    }

    func snapshot() -> (didRun: Bool, failure: String?) {
        lock.lock(); defer { lock.unlock() }
        return (didRun, failure)
    }
}

private actor AdvancingTraversalHook: BoundedTraversalTestHook {
    let clock: ManualTraversalClock
    let secondsPerBatch: UInt64
    private var descendantPaths: [String] = []

    init(clock: ManualTraversalClock, secondsPerBatch: UInt64) {
        self.clock = clock
        self.secondsPerBatch = secondsPerBatch
    }

    func receive(_ event: BoundedTraversalTestEvent) async {
        switch event {
        case .batchCompleted:
            clock.advance(seconds: secondsPerBatch)
        case .descendantEnqueued(let path):
            descendantPaths.append(path)
        }
    }

    func enqueued() -> [String] { descendantPaths }
}

private actor TraversalGateHook: BoundedTraversalTestHook {
    private var batchWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var seenBatches: Set<Int> = []
    private var blockedBatches: Set<Int>
    private var releases: [Int: CheckedContinuation<Void, Never>] = [:]

    init(blockedBatches: Set<Int>) { self.blockedBatches = blockedBatches }

    func receive(_ event: BoundedTraversalTestEvent) async {
        guard case .batchCompleted(let batch, _) = event else { return }
        seenBatches.insert(batch)
        batchWaiters.removeValue(forKey: batch)?.resume()
        if blockedBatches.remove(batch) != nil {
            await withCheckedContinuation { releases[batch] = $0 }
        }
    }

    func waitForBatch(_ batch: Int) async {
        if seenBatches.contains(batch) { return }
        await withCheckedContinuation { batchWaiters[batch] = $0 }
    }

    func releaseBatch(_ batch: Int) { releases.removeValue(forKey: batch)?.resume() }
}

private actor PermitHoldGate {
    private var started = 0
    private var startWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        started += 1
        let ready = startWaiters.filter { started >= $0.target }
        startWaiters.removeAll { started >= $0.target }
        for waiter in ready { waiter.continuation.resume() }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted(_ target: Int) async {
        if started >= target { return }
        await withCheckedContinuation { startWaiters.append((target, $0)) }
    }

    func releaseAll() {
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}

struct TraversalBridgeRig {
    let root: URL
    let bridge: ExecutionPolicyBridge
    let sessions: BridgeExplicitSessions
    let session: WorkSession

    @MainActor
    static func make() async throws -> TraversalBridgeRig {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("BoundedTraversalBridge-\(UUID().uuidString)", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: false)
        let environment = CleanEnvironment(homeDirectory: root.path, protectedRoots: [])
        let coordinator = ExecutionCoordinator(environment: environment, journalDirectory: journal)
        let settingsURL = root.appendingPathComponent("settings/config.json")
        let settings = SettingsStore(url: settingsURL)
        _ = await settings.load()
        let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
        _ = try await settings.update(expectedRevision: 0,
            change: .preferences(.init(global: .init(fields: [rate: .integer(4)]))))
        let loaded = await settings.load()
        let bridge = ExecutionPolicyBridge(
            coordinator: coordinator,
            settings: settings,
            loaded: loaded,
            homeDirectory: root.path,
            detectedTools: []
        )
        await bridge.drain()
        let sessions = bridge.explicitSessions
        let session = try await sessions.beginSession(
            requirements: SchedulerRequirements(features: [.projects])
        )
        return TraversalBridgeRig(root: root, bridge: bridge, sessions: sessions,
                                  session: session)
    }

    func cleanup() async {
        await sessions.finish(session: session)
        try? FileManager.default.removeItem(at: root)
    }

    func makeSession() async throws -> WorkSession {
        try await sessions.beginSession(requirements: SchedulerRequirements(features: [.projects]))
    }
}

func standardLimits(batchEntries: Int = 2, queuedPaths: Int = 64,
                    maxDepth: Int = 16, hardLinks: Int = 64,
                    resultRecords: Int = 64, topN: Int = 8,
                    maxBreadth: Int = 64, protectedRoots: Int = 32,
                    sliceSeconds: Int = 300) throws -> TraversalLimits {
    try TraversalLimits(batchEntries: batchEntries, queuedPaths: queuedPaths, maxDepth: maxDepth,
                        openDescriptors: 2, hardLinkIdentities: hardLinks,
                        childAggregates: 32, resultRecords: resultRecords, topN: topN,
                        maxBreadth: maxBreadth, maxPathBytes: 1_024,
                        cursorCount: 16, cursorTombstones: 16,
                        protectedRoots: protectedRoots,
                        sliceSeconds: sliceSeconds)
}

private func syntheticFlatTree(root: String, count: Int) -> [String: LockedTraversalSource.Node] {
    var nodes: [String: LockedTraversalSource.Node] = [
        root: .init(identity: .init(device: 1, inode: 1, generation: 1), bytes: 0,
                    isDirectory: true, children: (0..<count).map { "f\($0)" })
    ]
    for index in 0..<count {
        nodes[root + "/f\(index)"] = .init(
            identity: .init(device: 1, inode: UInt64(index + 2), generation: 1),
            bytes: Int64((index * 37) % 11), isDirectory: false, children: [])
    }
    return nodes
}

private func occupyAllTraversalPermits(_ sessions: BridgeExplicitSessions,
                                       session: WorkSession,
                                       gate: PermitHoldGate) async -> [Task<Void, Never>] {
    let workers = await sessions.snapshot().effectiveWorkers
    let tasks = (0..<workers).map { _ in
        Task<Void, Never> {
            do {
                try await sessions.withPermit(session: session) { _ in await gate.hold() }
            } catch {
                return
            }
        }
    }
    await gate.waitUntilStarted(workers)
    return tasks
}

private func waitForTraversalQueue(_ sessions: BridgeExplicitSessions,
                                   atLeast minimum: Int) async -> Bool {
    for _ in 0..<10_000 {
        if await sessions.snapshot().queued >= minimum { return true }
    }
    return false
}

@Suite(.serialized)
struct BoundedTraversalTests {
    @Test("blocking enumeration is off-main and cancellation stops before descendant enqueue")
    @MainActor
    func cancellationStopsAtBatchBoundary() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }

        let root = "/synthetic"
        let source = LockedTraversalSource(nodes: [
            root: .init(identity: .init(device: 1, inode: 1, generation: 1), bytes: 0,
                        isDirectory: true, children: ["a", "b"]),
            root + "/a": .init(identity: .init(device: 1, inode: 2, generation: 1), bytes: 10,
                               isDirectory: false, children: []),
            root + "/b": .init(identity: .init(device: 1, inode: 3, generation: 1), bytes: 20,
                               isDirectory: false, children: [])
        ])
        let hook = TraversalGateHook(blockedBatches: [1])
        let limits = try TraversalLimits(batchEntries: 2, queuedPaths: 8, maxDepth: 8,
                                         openDescriptors: 2, hardLinkIdentities: 8,
                                         childAggregates: 8, resultRecords: 8, topN: 4,
                                         maxBreadth: 8, maxPathBytes: 1_024,
                                         cursorCount: 8, cursorTombstones: 8,
                                         sliceSeconds: 300)
        let traversal = BoundedTraversal(sessions: rig.sessions, limits: limits,
                                         source: source, testHook: hook)
        let task = Task {
            await traversal.start(root: root, session: rig.session, sessionID: UUID(),
                                  generation: 1, options: .init())
        }

        await hook.waitForBatch(1)
        await rig.sessions.cancel(session: rig.session)
        await hook.releaseBatch(1)
        let result = await task.value
        let sourceSnapshot = source.snapshot()

        #expect(sourceSnapshot.mainThreadReads == 0)
        #expect(sourceSnapshot.paths == [root])
        #expect(result.coverage.reasons == [.cancelled])
        #expect(result.cursor == nil)
        #expect(result.metrics.maximumBatchEntries == 1)
        #expect(result.metrics.maximumQueuedPaths == 1)
    }

    @Test("virtual high-cardinality traversal processes thousands within every retained bound")
    @MainActor
    func syntheticHighCardinalityIsBounded() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/virtual-high-cardinality"
        let source = VirtualHighCardinalityTraversalSource(
            root: root, directoryCount: 16, filesPerDirectory: 256)
        let limits = try standardLimits(batchEntries: 64, queuedPaths: 4_096, maxDepth: 8,
                                        hardLinks: 512, resultRecords: 64, topN: 8,
                                        maxBreadth: 256)
        let traversal = BoundedTraversal(sessions: rig.sessions, limits: limits, source: source)
        let logicalID = UUID()
        let result = await traversal.start(root: root, session: rig.session, sessionID: logicalID,
                                           generation: 1, options: .init(
                                            minimumFileBytes: 0,
                                            collectChildTotals: true,
                                            recordSelection: .all))

        var page = result
        var recordCount = page.records.count
        while let cursor = page.cursor {
            page = await traversal.continue(from: cursor, session: rig.session,
                                            sessionID: logicalID, generation: 1)
            recordCount += page.records.count
        }
        let sourceSnapshot = source.snapshot()

        #expect(page.coverage.isComplete)
        #expect(recordCount == 4_113)
        #expect(sourceSnapshot.readCount == 4_113)
        #expect(sourceSnapshot.maximumChildren == 256)
        #expect(page.totalBytes == 8_390_656)
        #expect(page.childTotals.count == 16)
        #expect(page.topItems.count == 8)
        #expect(page.metrics.maximumQueuedPaths == limits.queuedPaths)
        #expect(page.metrics.maximumBatchEntries <= limits.batchEntries)
        #expect(page.metrics.maximumDepth <= limits.maxDepth)
        #expect(page.metrics.maximumOpenDescriptors <= limits.openDescriptors)
        #expect(page.metrics.maximumHardLinkIdentities == limits.hardLinkIdentities)
        #expect(page.metrics.maximumChildAggregates <= limits.childAggregates)
        #expect(page.metrics.maximumResultRecords == limits.resultRecords)
        #expect(page.metrics.maximumTopN == limits.topN)
    }

    @Test("bounded top-N equals a complete bytes-descending path-ascending sort")
    @MainActor
    func boundedHeapMatchesOracle() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/heap"
        let source = LockedTraversalSource(nodes: syntheticFlatTree(root: root, count: 60))
        let limits = try standardLimits(batchEntries: 7, queuedPaths: 64, resultRecords: 8,
                                        topN: 8, maxBreadth: 64)
        let traversal = BoundedTraversal(sessions: rig.sessions, limits: limits, source: source)
        let result = await traversal.start(root: root, session: rig.session, sessionID: UUID(),
                                           generation: 1,
                                           options: .init(minimumFileBytes: 0,
                                                          recordSelection: .none))
        var oracle: [RankedItem] = []
        for index in 0..<60 {
            let path = root + "/f" + String(index)
            let bytes = Int64((index * 37) % 11)
            oracle.append(RankedItem(path: path, bytes: bytes))
        }
        oracle.sort {
            $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path
        }

        #expect(result.coverage.isComplete)
        #expect(result.topItems == Array(oracle.prefix(8)))
        #expect(result.metrics.maximumTopN == 8)
    }

    @Test("partial Continue has no duplicate or missing records and cursors reject replay and wrong session")
    @MainActor
    func continuationIsFiniteSingleUseAndSessionBound() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let otherSession = try await rig.makeSession()
        defer { Task { await rig.sessions.finish(session: otherSession) } }
        let root = "/pages"
        let source = LockedTraversalSource(nodes: syntheticFlatTree(root: root, count: 7))
        let clock = ManualTraversalClock()
        let hook = AdvancingTraversalHook(clock: clock, secondsPerBatch: 30)
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 2, resultRecords: 2, sliceSeconds: 30),
            clock: clock.traversalClock, source: source, testHook: hook)
        let logicalID = UUID()
        var page = await traversal.start(root: root, session: rig.session, sessionID: logicalID,
                                         generation: 7, options: .init(recordSelection: .all))
        let firstCursor = try #require(page.cursor)
        let wrong = await traversal.continue(from: firstCursor, session: otherSession,
                                             sessionID: logicalID, generation: 7)
        #expect(wrong.coverage.reasons == [.wrongSession])

        var paths = page.records.map(\.path)
        page = await traversal.continue(from: firstCursor, session: rig.session,
                                        sessionID: logicalID, generation: 7)
        let replay = await traversal.continue(from: firstCursor, session: rig.session,
                                              sessionID: logicalID, generation: 7)
        #expect(replay.coverage.reasons == [.cursorReplay])
        paths.append(contentsOf: page.records.map(\.path))
        while let cursor = page.cursor {
            page = await traversal.continue(from: cursor, session: rig.session,
                                            sessionID: logicalID, generation: 7)
            paths.append(contentsOf: page.records.map(\.path))
        }

        let expected = [root] + (0..<7).map { root + "/f\($0)" }
        #expect(paths.sorted() == expected.sorted())
        #expect(Set(paths).count == expected.count)
        #expect(page.coverage.isComplete)
        let store = await traversal.snapshot()
        #expect(store.activeCursors == 0)
        #expect(store.cursorTombstones <= 16)
    }

    @Test("concurrent Continue calls reserve one cursor exactly once before suspension")
    @MainActor
    func concurrentCursorReservationIsSingleUse() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/concurrent-cursor"
        let source = LockedTraversalSource(nodes: syntheticFlatTree(root: root, count: 4))
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 1, resultRecords: 1), source: source)
        let logicalID = UUID()
        let first = await traversal.start(root: root, session: rig.session,
            sessionID: logicalID, generation: 1, options: .init(recordSelection: .all))
        let cursor = try #require(first.cursor)

        let results = await withTaskGroup(of: TraversalResult.self,
                                          returning: [TraversalResult].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await traversal.continue(from: cursor, session: rig.session,
                        sessionID: logicalID, generation: 1)
                }
            }
            var values: [TraversalResult] = []
            for await value in group { values.append(value) }
            return values
        }

        let accepted = results.filter { !$0.coverage.reasons.contains(.cursorReplay) }
        let replayed = results.filter { $0.coverage.reasons == [.cursorReplay] }
        #expect(accepted.count == 1)
        #expect(replayed.count == 7)
        #expect(replayed.allSatisfy { $0.cursor == nil && !$0.coverage.isComplete })
        await traversal.invalidate(sessionID: logicalID)
        #expect(await traversal.snapshot().activeCursors == 0)
    }

    @Test("a cursor expiring while queued for a permit terminalizes before resumed work")
    @MainActor
    func queuedCursorRevalidatesExpiryAfterPermit() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/queued-expiry"
        let source = LockedTraversalSource(nodes: syntheticFlatTree(root: root, count: 3))
        let clock = ManualTraversalClock()
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 1, resultRecords: 1, sliceSeconds: 30),
            clock: clock.traversalClock, source: source)
        let logicalID = UUID()
        let first = await traversal.start(root: root, session: rig.session,
            sessionID: logicalID, generation: 1, options: .init(recordSelection: .all))
        let cursor = try #require(first.cursor)
        #expect(source.snapshot().paths == [root])

        let gate = PermitHoldGate()
        let holders = await occupyAllTraversalPermits(rig.sessions, session: rig.session, gate: gate)
        let continuation = Task {
            await traversal.continue(from: cursor, session: rig.session,
                sessionID: logicalID, generation: 1)
        }
        let queued = await waitForTraversalQueue(rig.sessions, atLeast: 1)
        #expect(queued)
        clock.advance(seconds: 30)
        await gate.releaseAll()
        for holder in holders { await holder.value }

        let result = await continuation.value
        #expect(result.coverage.reasons == [.cursorExpired])
        #expect(result.cursor == nil)
        #expect(source.snapshot().paths == [root])
        let replay = await traversal.continue(from: cursor, session: rig.session,
            sessionID: logicalID, generation: 1)
        #expect(replay.coverage.reasons == [.cursorReplay])
    }

    @Test("a queued cursor revalidates its policy revision after permit admission")
    @MainActor
    func queuedCursorRevalidatesPolicyAfterPermit() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/queued-policy"
        let source = LockedTraversalSource(nodes: syntheticFlatTree(root: root, count: 3))
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 1, resultRecords: 1), source: source)
        let logicalID = UUID()
        let first = await traversal.start(root: root, session: rig.session,
            sessionID: logicalID, generation: 1, options: .init(recordSelection: .all))
        let cursor = try #require(first.cursor)

        let gate = PermitHoldGate()
        let holders = await occupyAllTraversalPermits(rig.sessions, session: rig.session, gate: gate)
        let continuation = Task {
            await traversal.continue(from: cursor, session: rig.session,
                sessionID: logicalID, generation: 1)
        }
        #expect(await waitForTraversalQueue(rig.sessions, atLeast: 1))

        let rate = SettingID(rawValue: "scan.uiBatchesPerSecond")
        let admission = rig.bridge.submit(global: .init(baseRevision: 1, id: rate,
            baseValue: .integer(4), editedValue: .integer(1)))
        guard case .accepted(_, let completion) = admission else {
            await gate.releaseAll()
            for holder in holders { await holder.value }
            Issue.record("rate-only revision update was rejected: \(String(describing: admission))")
            return
        }
        let outcome = await completion.value
        guard case .saved(_, let saved) = outcome else {
            await gate.releaseAll()
            for holder in holders { await holder.value }
            Issue.record("rate-only revision update failed: \(String(describing: outcome))")
            return
        }
        #expect(saved.revision == 2)
        #expect(await rig.sessions.snapshot().settingsRevision == 2)
        await gate.releaseAll()
        for holder in holders { await holder.value }

        let result = await continuation.value
        #expect(result.coverage.reasons == [.policyRevisionMismatch])
        #expect(result.cursor == nil)
        #expect(source.snapshot().paths == [root])
        let replay = await traversal.continue(from: cursor, session: rig.session,
            sessionID: logicalID, generation: 1)
        #expect(replay.coverage.reasons == [.cursorReplay])
    }

    @Test("an opened directory handle cannot be swapped to enumerate outside the checked root")
    @MainActor
    func directoryHandleBindsCheckedIdentity() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let fixture = rig.root.appendingPathComponent("checked-directory", isDirectory: true)
        let parked = rig.root.appendingPathComponent("parked-directory", isDirectory: true)
        let outside = rig.root.appendingPathComponent("outside-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data([1]).write(to: fixture.appendingPathComponent("inside"))
        try Data([2]).write(to: outside.appendingPathComponent("outside-secret"))
        let race = DirectoryReplacementRace(original: fixture, parked: parked,
                                            replacement: outside)
        let source = RealFilesystemTraversalSource(
            beforeDirectoryOpen: { path in race.replaceBeforeOpen(path) })
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 4), source: source)

        let result = await traversal.start(root: fixture.path, session: rig.session,
            sessionID: UUID(), generation: 1, options: .init(recordSelection: .all))
        let raceState = race.snapshot()

        #expect(raceState.didRun)
        #expect(raceState.failure == nil)
        #expect(result.coverage.reasons == [.churn])
        #expect(!result.coverage.isComplete)
        #expect(result.cursor == nil)
        #expect(result.records.allSatisfy { !$0.path.contains("outside-secret") })
    }

    @Test("Continue cannot claim complete after an enumerated directory gains a child")
    @MainActor
    func continuationDetectsDirectoryContentChurn() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/directory-watermark"
        let source = LockedTraversalSource(nodes: syntheticFlatTree(root: root, count: 1))
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 1, resultRecords: 1), source: source)
        let logicalID = UUID()
        let first = await traversal.start(root: root, session: rig.session,
            sessionID: logicalID, generation: 1, options: .init(recordSelection: .all))
        let cursor = try #require(first.cursor)
        source.appendChild(parent: root, name: "late", node: .init(
            identity: .init(device: 1, inode: 999, generation: 1), bytes: 99,
            isDirectory: false, children: []))

        let resumed = await traversal.continue(from: cursor, session: rig.session,
            sessionID: logicalID, generation: 1)

        #expect(resumed.coverage.reasons == [.churn])
        #expect(!resumed.coverage.isComplete)
        #expect(resumed.cursor == nil)
        #expect(resumed.records.isEmpty)
        #expect(!source.snapshot().paths.contains(root + "/late"))
    }

    @Test("allocated-size metadata failure is unreadable, never zero-byte complete coverage")
    @MainActor
    func metadataFailureIsTruthful() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let file = rig.root.appendingPathComponent("metadata-failure.bin")
        try Data(repeating: 7, count: 8_192).write(to: file)
        let source = RealFilesystemTraversalSource(allocatedBytes: { _ in nil })
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(), source: source)

        let result = await traversal.start(root: file.path, session: rig.session,
            sessionID: UUID(), generation: 1, options: .init(recordSelection: .all))

        #expect(result.coverage.reasons == [.unreadable])
        #expect(!result.coverage.isComplete)
        #expect(result.totalBytes == 0)
        #expect(result.records.isEmpty)
        #expect(result.cursor == nil)
    }

    @Test("caller-controlled selection names are bounded before cursor state can retain them")
    @MainActor
    func selectionStringIsBounded() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/selection-string"
        let source = LockedTraversalSource(nodes: [
            root: .init(identity: .init(device: 1, inode: 1, generation: 1), bytes: 0,
                        isDirectory: true, children: [])
        ])
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(), source: source)
        let overlong = String(repeating: "n", count: 1_025)

        let result = await traversal.start(root: root, session: rig.session,
            sessionID: UUID(), generation: 1,
            options: .init(recordSelection: .directory(named: overlong,
                                                       modifiedBefore: Date())))

        #expect(result.coverage.reasons == [.stringOverflow])
        #expect(!result.coverage.isComplete)
        #expect(result.cursor == nil)
        #expect(source.snapshot().paths.isEmpty)
    }

    @Test("cursor expiry generation root replacement churn breadth and depth fail truthfully")
    @MainActor
    func cursorInvalidationAndStructuralBoundsAreTruthful() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }

        func partial(_ root: String, source: LockedTraversalSource,
                     clock: ManualTraversalClock) async throws -> (BoundedTraversal, TraversalCursor, UUID) {
            let hook = AdvancingTraversalHook(clock: clock, secondsPerBatch: 30)
            let traversal = BoundedTraversal(sessions: rig.sessions,
                limits: try standardLimits(batchEntries: 1, resultRecords: 1, sliceSeconds: 30),
                clock: clock.traversalClock, source: source, testHook: hook)
            let logical = UUID()
            let result = await traversal.start(root: root, session: rig.session,
                                               sessionID: logical, generation: 3,
                                               options: .init(recordSelection: .all))
            return (traversal, try #require(result.cursor), logical)
        }

        let expiryRoot = "/expiry"
        let expirySource = LockedTraversalSource(nodes: syntheticFlatTree(root: expiryRoot, count: 2))
        let expiryClock = ManualTraversalClock()
        let (expiryTraversal, expiryCursor, expiryID) = try await partial(
            expiryRoot, source: expirySource, clock: expiryClock)
        expiryClock.advance(seconds: 30)
        let expired = await expiryTraversal.continue(from: expiryCursor, session: rig.session,
                                                     sessionID: expiryID, generation: 3)
        #expect(expired.coverage.reasons == [.cursorExpired])

        let generationRoot = "/generation"
        let generationSource = LockedTraversalSource(nodes: syntheticFlatTree(root: generationRoot, count: 2))
        let (generationTraversal, generationCursor, generationID) = try await partial(
            generationRoot, source: generationSource, clock: ManualTraversalClock())
        let generation = await generationTraversal.continue(from: generationCursor,
            session: rig.session, sessionID: generationID, generation: 4)
        #expect(generation.coverage.reasons == [.generationMismatch])

        let replacementRoot = "/replacement"
        let replacementSource = LockedTraversalSource(nodes: syntheticFlatTree(root: replacementRoot, count: 2))
        let (replacementTraversal, replacementCursor, replacementID) = try await partial(
            replacementRoot, source: replacementSource, clock: ManualTraversalClock())
        replacementSource.replaceIdentity(at: replacementRoot,
            with: .init(device: 1, inode: 999, generation: 1))
        let replaced = await replacementTraversal.continue(from: replacementCursor,
            session: rig.session, sessionID: replacementID, generation: 3)
        #expect(replaced.coverage.reasons == [.rootReplaced])

        let churnRoot = "/churn"
        let churnSource = LockedTraversalSource(nodes: syntheticFlatTree(root: churnRoot, count: 2))
        let (churnTraversal, churnCursor, churnID) = try await partial(
            churnRoot, source: churnSource, clock: ManualTraversalClock())
        churnSource.replaceIdentity(at: churnRoot + "/f0",
            with: .init(device: 1, inode: 888, generation: 2))
        let churned = await churnTraversal.continue(from: churnCursor,
            session: rig.session, sessionID: churnID, generation: 3)
        #expect(churned.coverage.reasons == [.churn])

        let breadthRoot = "/breadth"
        let breadthSource = LockedTraversalSource(nodes: syntheticFlatTree(root: breadthRoot, count: 4))
        let breadth = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(queuedPaths: 2, maxBreadth: 2), source: breadthSource)
            .start(root: breadthRoot, session: rig.session, sessionID: UUID(), generation: 1)
        #expect(breadth.coverage.reasons.contains(.queueOverflow)
                || breadth.coverage.reasons.contains(.maxBreadth))
        #expect(breadth.cursor == nil)

        let depthRoot = "/depth"
        let depthSource = LockedTraversalSource(nodes: [
            depthRoot: .init(identity: .init(device: 1, inode: 1, generation: 1), bytes: 0,
                             isDirectory: true, children: ["a"]),
            depthRoot + "/a": .init(identity: .init(device: 1, inode: 2, generation: 1), bytes: 0,
                                    isDirectory: true, children: ["b"]),
            depthRoot + "/a/b": .init(identity: .init(device: 1, inode: 3, generation: 1), bytes: 1,
                                      isDirectory: false, children: [])
        ])
        let depth = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(maxDepth: 1), source: depthSource)
            .start(root: depthRoot, session: rig.session, sessionID: UUID(), generation: 1)
        #expect(depth.coverage.reasons == [.maxDepth])
        #expect(depth.cursor == nil)
    }

    @Test("coverage preserves protected cross-volume unreadable hard-link and arithmetic failures")
    @MainActor
    func incompleteCoverageNeverClaimsSuccess() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/coverage"
        let source = LockedTraversalSource(nodes: [
            root: .init(identity: .init(device: 1, inode: 1, generation: 1), bytes: 0,
                        isDirectory: true, children: ["protected", "cross", "unreadable"]),
            root + "/protected": .init(identity: .init(device: 1, inode: 2, generation: 1), bytes: 1,
                                       isDirectory: false, children: [], readReason: .protected),
            root + "/cross": .init(identity: .init(device: 2, inode: 3, generation: 1), bytes: 1,
                                   isDirectory: false, children: [], readReason: .crossVolume),
            root + "/unreadable": .init(identity: .init(device: 1, inode: 4, generation: 1), bytes: 1,
                                        isDirectory: false, children: [], readReason: .unreadable)
        ])
        let result = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(), source: source)
            .start(root: root, session: rig.session, sessionID: UUID(), generation: 1)
        #expect(!result.coverage.isComplete)
        #expect(result.coverage.reasons == [.protected, .crossVolume, .unreadable])

        let hardRoot = "/hardlinks"
        let hardSource = LockedTraversalSource(nodes: [
            hardRoot: .init(identity: .init(device: 1, inode: 1, generation: 1), bytes: 0,
                            isDirectory: true, children: ["a", "b"]),
            hardRoot + "/a": .init(identity: .init(device: 1, inode: 2, generation: 1), bytes: 4,
                                   isDirectory: false, children: [], linkCount: 2),
            hardRoot + "/b": .init(identity: .init(device: 1, inode: 3, generation: 1), bytes: 5,
                                   isDirectory: false, children: [], linkCount: 2)
        ])
        let hard = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(hardLinks: 1), source: hardSource)
            .start(root: hardRoot, session: rig.session, sessionID: UUID(), generation: 1)
        #expect(hard.coverage.reasons == [.hardLinkLimit])
        #expect(hard.cursor == nil)

        let missing = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(), source: LockedTraversalSource(nodes: [:]))
            .start(root: "/missing", session: rig.session, sessionID: UUID(), generation: 1)
        #expect(missing.coverage.reasons == [.missing])
        #expect(missing.cursor == nil)

        let overflowRoot = "/overflow"
        let overflowSource = LockedTraversalSource(nodes: [
            overflowRoot: .init(identity: .init(device: 1, inode: 1, generation: 1),
                                bytes: Int64.max, isDirectory: true, children: ["one-more"]),
            overflowRoot + "/one-more": .init(
                identity: .init(device: 1, inode: 2, generation: 1), bytes: 1,
                isDirectory: false, children: [])
        ])
        let overflow = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(), source: overflowSource)
            .start(root: overflowRoot, session: rig.session, sessionID: UUID(), generation: 1)
        #expect(overflow.coverage.reasons == [.arithmeticOverflow])
        #expect(overflow.cursor == nil)

        let longRoot = "/" + String(repeating: "x", count: 1_100)
        let stringOverflow = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(), source: LockedTraversalSource(nodes: [:]))
            .start(root: longRoot, session: rig.session, sessionID: UUID(), generation: 1)
        #expect(stringOverflow.coverage.reasons == [.stringOverflow])
        #expect(stringOverflow.cursor == nil)

        let optionRoot = "/bounded-options"
        let optionSource = LockedTraversalSource(nodes: [
            optionRoot: .init(identity: .init(device: 1, inode: 1, generation: 1),
                              bytes: 0, isDirectory: true, children: [])
        ])
        let optionOverflow = await BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(protectedRoots: 1), source: optionSource)
            .start(root: optionRoot, session: rig.session, sessionID: UUID(), generation: 1,
                   options: .init(protectedRoots: ["/one", "/two"]))
        #expect(optionOverflow.coverage.reasons == [.protectedRootLimit])
        #expect(optionOverflow.cursor == nil)
    }

    @Test("small real filesystem fixture preserves allocated-byte and deterministic top-N behavior")
    @MainActor
    func realFilesystemParity() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let fixture = rig.root.appendingPathComponent("fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture.appendingPathComponent("nested"),
                                                withIntermediateDirectories: true)
        try Data(repeating: 1, count: 80_000).write(to: fixture.appendingPathComponent("a.bin"))
        try Data(repeating: 2, count: 160_000).write(to: fixture.appendingPathComponent("nested/b.bin"))
        let traversal = BoundedTraversal(sessions: rig.sessions,
                                         limits: try standardLimits(batchEntries: 8))
        let result = await traversal.start(root: fixture.path, session: rig.session,
            sessionID: UUID(), generation: 1,
            options: .init(minimumFileBytes: 0, collectChildTotals: true,
                           recordSelection: .none))
        let oracle = SizeScanner.diskUsage(ofPath: fixture.path, protectedRoots: [])

        #expect(result.coverage.isComplete)
        #expect(result.totalBytes == oracle)
        #expect(result.topItems.map(\.path) == [
            PathGuard.canonicalize(fixture.appendingPathComponent("nested/b.bin").path),
            PathGuard.canonicalize(fixture.appendingPathComponent("a.bin").path)
        ])
        #expect(result.metrics.maximumOpenDescriptors <= 2)
    }

    @Test("injected clock expires exact configured scan slices",
          arguments: [30, 300, 1_800])
    @MainActor
    func exactSliceExpiry(seconds: Int) async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let root = "/slice-\(seconds)"
        let source = LockedTraversalSource(nodes: syntheticFlatTree(root: root, count: 2))
        let clock = ManualTraversalClock()
        let hook = AdvancingTraversalHook(clock: clock, secondsPerBatch: UInt64(seconds))
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 1, resultRecords: 8,
                                       sliceSeconds: seconds),
            clock: clock.traversalClock, source: source, testHook: hook)
        let logicalID = UUID()
        let result = await traversal.start(root: root, session: rig.session,
            sessionID: logicalID, generation: 1, options: .init(recordSelection: .all))

        #expect(result.coverage.reasons == [.sliceExpired])
        #expect(result.cursor != nil)
        #expect(result.metrics.batches == 1)
        #expect(await hook.enqueued().isEmpty)

        var paths = result.records.map(\.path)
        var page = result
        while let cursor = page.cursor {
            page = await traversal.continue(from: cursor, session: rig.session,
                                            sessionID: logicalID, generation: 1)
            paths.append(contentsOf: page.records.map(\.path))
        }
        #expect(page.coverage.isComplete)
        #expect(paths.sorted() == [root, root + "/f0", root + "/f1"].sorted())
    }

    @Test("twenty Continue cycles restore cursor descriptors and scheduler leases to baseline")
    @MainActor
    func twentyContinueCyclesRestoreResources() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let fixture = rig.root.appendingPathComponent("twenty-cycles", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        for index in 0..<20 {
            try Data(repeating: UInt8(index), count: 128)
                .write(to: fixture.appendingPathComponent("f\(index)"))
        }
        let baselineScheduler = await rig.sessions.snapshot()
        let descriptorTracker = TraversalDescriptorTracker()
        let clock = ManualTraversalClock()
        let hook = AdvancingTraversalHook(clock: clock, secondsPerBatch: 30)
        let traversal = BoundedTraversal(sessions: rig.sessions,
            limits: try standardLimits(batchEntries: 1, resultRecords: 1,
                                       sliceSeconds: 30),
            clock: clock.traversalClock,
            source: RealFilesystemTraversalSource(descriptorTracker: descriptorTracker),
            testHook: hook)
        let logicalID = UUID()
        var page = await traversal.start(root: fixture.path, session: rig.session,
            sessionID: logicalID, generation: 1, options: .init(recordSelection: .all))
        var continues = 0
        while let cursor = page.cursor {
            continues += 1
            page = await traversal.continue(from: cursor, session: rig.session,
                sessionID: logicalID, generation: 1)
        }
        let finalScheduler = await rig.sessions.snapshot()
        let store = await traversal.snapshot()
        let descriptors = descriptorTracker.snapshot()

        #expect(continues == 20)
        #expect(page.coverage.isComplete)
        #expect(store.activeCursors == 0)
        #expect(descriptors.active == 0)
        #expect(descriptors.maximumActive <= 1)
        #expect(finalScheduler.active == baselineScheduler.active)
        #expect(finalScheduler.queued == baselineScheduler.queued)
        #expect(finalScheduler.liveSessions == baselineScheduler.liveSessions)
    }

    @Test("twenty cancellation cycles restore descriptors and scheduler leases to baseline")
    @MainActor
    func twentyCancellationCyclesRestoreResources() async throws {
        let rig = try await TraversalBridgeRig.make()
        defer { Task { await rig.cleanup() } }
        let fixture = rig.root.appendingPathComponent("twenty-cancellations", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        for index in 0..<8 {
            try Data(repeating: UInt8(index), count: 128)
                .write(to: fixture.appendingPathComponent("f\(index)"))
        }
        let baselineScheduler = await rig.sessions.snapshot()
        let descriptorTracker = TraversalDescriptorTracker()

        for cycle in 0..<20 {
            let session = try await rig.makeSession()
            let hook = TraversalGateHook(blockedBatches: [1])
            let traversal = BoundedTraversal(sessions: rig.sessions,
                limits: try standardLimits(batchEntries: 1),
                source: RealFilesystemTraversalSource(descriptorTracker: descriptorTracker),
                testHook: hook)
            let task = Task {
                await traversal.start(root: fixture.path, session: session,
                    sessionID: UUID(), generation: UInt64(cycle),
                    options: .init(recordSelection: .all))
            }
            await hook.waitForBatch(1)
            await rig.sessions.cancel(session: session)
            await hook.releaseBatch(1)
            let result = await task.value
            await rig.sessions.finish(session: session)

            #expect(result.coverage.reasons == [.cancelled])
            #expect(result.cursor == nil)
        }

        let finalScheduler = await rig.sessions.snapshot()
        let descriptors = descriptorTracker.snapshot()
        #expect(descriptors.active == 0)
        #expect(descriptors.maximumActive <= 1)
        #expect(finalScheduler.active == baselineScheduler.active)
        #expect(finalScheduler.queued == baselineScheduler.queued)
        #expect(finalScheduler.liveSessions == baselineScheduler.liveSessions)
    }
}
