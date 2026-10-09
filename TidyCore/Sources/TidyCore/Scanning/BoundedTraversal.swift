import Darwin
import Foundation

public enum TraversalCoverageReason: String, CaseIterable, Hashable, Sendable {
    case missing
    case unreadable
    case protected
    case crossVolume
    case churn
    case arithmeticOverflow
    case stringOverflow
    case queueOverflow
    case hardLinkLimit
    case protectedRootLimit
    case childAggregateLimit
    case resultLimit
    case maxBreadth
    case maxDepth
    case sliceExpired
    case cursorExpired
    case cursorLimit
    case cursorReplay
    case invalidCursor
    case wrongSession
    case rootReplaced
    case generationMismatch
    case policyRevisionMismatch
    case cancelled
}

public struct TraversalCoverage: Equatable, Sendable {
    public let isComplete: Bool
    public let reasons: Set<TraversalCoverageReason>

    public init(isComplete: Bool, reasons: Set<TraversalCoverageReason>) {
        self.isComplete = isComplete
        self.reasons = reasons
    }
}

public struct TraversalLimits: Equatable, Sendable {
    public let batchEntries: Int
    public let queuedPaths: Int
    public let maxDepth: Int
    public let openDescriptors: Int
    public let hardLinkIdentities: Int
    public let childAggregates: Int
    public let resultRecords: Int
    public let topN: Int
    public let maxBreadth: Int
    public let maxPathBytes: Int
    public let cursorCount: Int
    public let cursorTombstones: Int
    public let protectedRoots: Int
    public let sliceSeconds: Int

    public init(batchEntries: Int = 64, queuedPaths: Int = 256, maxDepth: Int = 64,
                openDescriptors: Int = 8, hardLinkIdentities: Int = 4_096,
                childAggregates: Int = 256, resultRecords: Int = 256, topN: Int = 16,
                maxBreadth: Int = 1_024, maxPathBytes: Int = 4_096,
                cursorCount: Int = 64, cursorTombstones: Int = 64,
                protectedRoots: Int = 64,
                sliceSeconds: Int = 300) throws {
        guard (1...256).contains(batchEntries), (1...4_096).contains(queuedPaths),
              (1...128).contains(maxDepth), (1...32).contains(openDescriptors),
              (1...65_536).contains(hardLinkIdentities), (1...4_096).contains(childAggregates),
              (1...4_096).contains(resultRecords), (0...256).contains(topN),
              (1...4_096).contains(maxBreadth), (64...16_384).contains(maxPathBytes),
              (1...64).contains(cursorCount), (0...64).contains(cursorTombstones),
              (0...256).contains(protectedRoots),
              (30...1_800).contains(sliceSeconds) else {
            throw TraversalConfigurationError.invalidLimits
        }
        self.batchEntries = batchEntries
        self.queuedPaths = queuedPaths
        self.maxDepth = maxDepth
        self.openDescriptors = openDescriptors
        self.hardLinkIdentities = hardLinkIdentities
        self.childAggregates = childAggregates
        self.resultRecords = resultRecords
        self.topN = topN
        self.maxBreadth = maxBreadth
        self.maxPathBytes = maxPathBytes
        self.cursorCount = cursorCount
        self.cursorTombstones = cursorTombstones
        self.protectedRoots = protectedRoots
        self.sliceSeconds = sliceSeconds
    }

    internal func replacing(maxDepth: Int? = nil, topN: Int? = nil, sliceSeconds: Int? = nil) -> TraversalLimits {
        TraversalLimits(validatedBatchEntries: batchEntries, queuedPaths: queuedPaths,
            maxDepth: maxDepth ?? self.maxDepth, openDescriptors: openDescriptors,
            hardLinkIdentities: hardLinkIdentities, childAggregates: childAggregates,
            resultRecords: resultRecords, topN: topN ?? self.topN,
            maxBreadth: maxBreadth, maxPathBytes: maxPathBytes, cursorCount: cursorCount,
            cursorTombstones: cursorTombstones, protectedRoots: protectedRoots,
            sliceSeconds: min(self.sliceSeconds, max(30, sliceSeconds ?? self.sliceSeconds)))
    }

    private init(validatedBatchEntries batchEntries: Int, queuedPaths: Int, maxDepth: Int,
                 openDescriptors: Int, hardLinkIdentities: Int, childAggregates: Int,
                 resultRecords: Int, topN: Int, maxBreadth: Int, maxPathBytes: Int,
                 cursorCount: Int, cursorTombstones: Int, protectedRoots: Int,
                 sliceSeconds: Int) {
        self.batchEntries = batchEntries
        self.queuedPaths = queuedPaths
        self.maxDepth = maxDepth
        self.openDescriptors = openDescriptors
        self.hardLinkIdentities = hardLinkIdentities
        self.childAggregates = childAggregates
        self.resultRecords = resultRecords
        self.topN = topN
        self.maxBreadth = maxBreadth
        self.maxPathBytes = maxPathBytes
        self.cursorCount = cursorCount
        self.cursorTombstones = cursorTombstones
        self.protectedRoots = protectedRoots
        self.sliceSeconds = sliceSeconds
    }
}

public enum TraversalConfigurationError: Error, Equatable, Sendable {
    case invalidLimits
}

public enum TraversalRecordSelection: Equatable, Sendable {
    case none
    case all
    case directory(named: String, modifiedBefore: Date)
    case projectMarkers
}

public struct TraversalOptions: Equatable, Sendable {
    public let protectedRoots: [String]
    public let minimumFileBytes: Int64?
    public let collectChildTotals: Bool
    public let recordSelection: TraversalRecordSelection
    public let pruneMatchedDirectories: Bool

    public init(protectedRoots: [String] = [], minimumFileBytes: Int64? = nil,
                collectChildTotals: Bool = false,
                recordSelection: TraversalRecordSelection = .all,
                pruneMatchedDirectories: Bool = false) {
        self.protectedRoots = protectedRoots
        self.minimumFileBytes = minimumFileBytes
        self.collectChildTotals = collectChildTotals
        self.recordSelection = recordSelection
        self.pruneMatchedDirectories = pruneMatchedDirectories
    }
}

public enum TraversalRecordKind: String, Equatable, Sendable {
    case directory
    case regularFile
    case symbolicLink
    case other
}

public struct TraversalRecord: Equatable, Sendable {
    public let path: String
    public let relativePath: String
    public let depth: Int
    public let bytes: Int64
    public let kind: TraversalRecordKind
    public let modifiedAt: Date?
}

public struct TraversalMetrics: Equatable, Sendable {
    public let processedEntries: Int
    public let batches: Int
    public let maximumQueuedPaths: Int
    public let maximumBatchEntries: Int
    public let maximumDepth: Int
    public let maximumOpenDescriptors: Int
    public let maximumHardLinkIdentities: Int
    public let maximumChildAggregates: Int
    public let maximumResultRecords: Int
    public let maximumTopN: Int

    static let zero = TraversalMetrics(processedEntries: 0, batches: 0,
        maximumQueuedPaths: 0, maximumBatchEntries: 0, maximumDepth: 0,
        maximumOpenDescriptors: 0, maximumHardLinkIdentities: 0,
        maximumChildAggregates: 0, maximumResultRecords: 0, maximumTopN: 0)
}

public struct TraversalCursor: Hashable, Sendable {
    fileprivate let token: UUID
    fileprivate init(token: UUID) { self.token = token }
}

public struct TraversalResult: Sendable {
    public let records: [TraversalRecord]
    public let totalBytes: Int64
    public let topItems: [RankedItem]
    public let childTotals: [RankedItem]
    public let coverage: TraversalCoverage
    public let cursor: TraversalCursor?
    public let metrics: TraversalMetrics
}

/// The result of one bounded scanner-adapter call and the finite cursor store that issued it.
/// Callers use the same traversal to consume `result.cursor`; the adapter never owns scheduler
/// authority and cannot resume through a different permit facade by accident.
public struct BoundedTraversalPage: Sendable {
    public let traversal: BoundedTraversal
    public let result: TraversalResult

    internal init(traversal: BoundedTraversal, result: TraversalResult) {
        self.traversal = traversal
        self.result = result
    }
}

public struct BoundedTraversalStoreSnapshot: Equatable, Sendable {
    public let activeCursors: Int
    public let cursorTombstones: Int
}

internal struct BoundedTraversalClock: Sendable {
    let nowNanoseconds: @Sendable () -> UInt64

    init(nowNanoseconds: @escaping @Sendable () -> UInt64) {
        self.nowNanoseconds = nowNanoseconds
    }

    static let continuous = BoundedTraversalClock {
        DispatchTime.now().uptimeNanoseconds
    }
}

internal struct TraversalSourceIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let generation: UInt64
}

internal struct TraversalDirectoryWatermark: Hashable, Sendable {
    let identity: TraversalSourceIdentity
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
    let size: Int64
    let linkCount: UInt64
}

private struct TraversalDirectoryObservation: Sendable {
    let path: String
    let watermark: TraversalDirectoryWatermark
}

internal enum TraversalRootRead: Sendable {
    case identity(TraversalSourceIdentity)
    case missing
    case unreadable
}

internal struct TraversalSourceChild: Sendable {
    let name: String
    let identity: TraversalSourceIdentity
}

internal struct TraversalSourceEntry: Sendable {
    let identity: TraversalSourceIdentity
    let bytes: Int64
    let kind: TraversalRecordKind
    let modifiedAt: Date?
    let linkCount: Int
    let children: [TraversalSourceChild]
    let terminalReason: TraversalCoverageReason?
    let observedBreadth: Int
    let openDescriptorHighWater: Int
    let directoryWatermark: TraversalDirectoryWatermark?

    init(identity: TraversalSourceIdentity, bytes: Int64, kind: TraversalRecordKind,
         modifiedAt: Date?, linkCount: Int, children: [TraversalSourceChild],
         terminalReason: TraversalCoverageReason?, observedBreadth: Int,
         openDescriptorHighWater: Int,
         directoryWatermark: TraversalDirectoryWatermark? = nil) {
        self.identity = identity
        self.bytes = bytes
        self.kind = kind
        self.modifiedAt = modifiedAt
        self.linkCount = linkCount
        self.children = children
        self.terminalReason = terminalReason
        self.observedBreadth = observedBreadth
        self.openDescriptorHighWater = openDescriptorHighWater
        self.directoryWatermark = directoryWatermark
    }
}

internal struct TraversalSourceRequest: Sendable {
    let path: String
    let relativePath: String
    let depth: Int
    let expectedIdentity: TraversalSourceIdentity?
    let rootIdentity: TraversalSourceIdentity
    let limits: TraversalLimits
}

internal enum TraversalSourceRead: Sendable {
    case entry(TraversalSourceEntry)
    case skipped(TraversalCoverageReason)
}

internal protocol BoundedTraversalSource: Sendable {
    func rootIdentity(at path: String) -> TraversalRootRead
    func read(_ request: TraversalSourceRequest) -> TraversalSourceRead
    func validateDirectory(at path: String,
                           watermark: TraversalDirectoryWatermark) -> TraversalCoverageReason?
}

internal enum BoundedTraversalTestEvent: Equatable, Sendable {
    case batchCompleted(Int, [String])
    case descendantEnqueued(String)
}

internal protocol BoundedTraversalTestHook: Sendable {
    func receive(_ event: BoundedTraversalTestEvent) async
}

internal struct TraversalDescriptorSnapshot: Equatable, Sendable {
    let active: Int
    let maximumActive: Int
}

/// Per-source descriptor accounting keeps resource assertions deterministic even while unrelated
/// package suites launch and reap processes in parallel. Production does not retain this tracker.
internal final class TraversalDescriptorTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maximumActive = 0

    func opened() {
        lock.lock(); defer { lock.unlock() }
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func closed() {
        lock.lock(); defer { lock.unlock() }
        active -= 1
    }

    func snapshot() -> TraversalDescriptorSnapshot {
        lock.lock(); defer { lock.unlock() }
        return TraversalDescriptorSnapshot(active: active, maximumActive: maximumActive)
    }
}

public actor BoundedTraversal {
    private let sessions: BridgeExplicitSessions
    private let limits: TraversalLimits
    private let clock: BoundedTraversalClock
    private let source: any BoundedTraversalSource
    private let testHook: (any BoundedTraversalTestHook)?
    private var cursors: [UUID: StoredTraversalCursor] = [:]
    private var tombstoneOrder: [UUID] = []
    private var tombstones: Set<UUID> = []

    public init(sessions: BridgeExplicitSessions, limits: TraversalLimits = try! .init()) {
        self.sessions = sessions
        self.limits = limits
        self.clock = .continuous
        self.source = RealFilesystemTraversalSource()
        self.testHook = nil
    }

    internal init(sessions: BridgeExplicitSessions, limits: TraversalLimits,
                  clock: BoundedTraversalClock = .continuous,
                  source: any BoundedTraversalSource,
                  testHook: (any BoundedTraversalTestHook)? = nil) {
        self.sessions = sessions
        self.limits = limits
        self.clock = clock
        self.source = source
        self.testHook = testHook
    }

    public func start(root: String, session: WorkSession, sessionID: UUID,
                      generation: UInt64, options: TraversalOptions = .init()) async -> TraversalResult {
        // Bound caller-controlled storage before canonicalization: Foundation may collapse an
        // overlong, nonexistent path to an empty lexical fallback and hide the original overflow.
        guard root.utf8.count <= limits.maxPathBytes else {
            return .terminal(reason: .stringOverflow)
        }
        guard options.protectedRoots.count <= limits.protectedRoots else {
            return .terminal(reason: .protectedRootLimit)
        }
        guard options.protectedRoots.allSatisfy({ $0.utf8.count <= limits.maxPathBytes }) else {
            return .terminal(reason: .stringOverflow)
        }
        guard options.recordSelection.retainedStringsFit(maxBytes: limits.maxPathBytes) else {
            return .terminal(reason: .stringOverflow)
        }
        let canonicalRoot = PathGuard.canonicalize(root)
        guard canonicalRoot.utf8.count <= limits.maxPathBytes else {
            return .terminal(reason: .stringOverflow)
        }
        guard await sessions.state(of: session) == .open else {
            return .terminal(reason: .cancelled)
        }
        let scheduler = await sessions.snapshot()
        guard scheduler.availability == .available, let revision = scheduler.settingsRevision else {
            return .terminal(reason: .policyRevisionMismatch)
        }
        let normalized = TraversalOptions(
            protectedRoots: options.protectedRoots.map(PathGuard.canonicalize),
            minimumFileBytes: options.minimumFileBytes,
            collectChildTotals: options.collectChildTotals,
            recordSelection: options.recordSelection,
            pruneMatchedDirectories: options.pruneMatchedDirectories)
        if Self.isProtected(canonicalRoot, protectedRoots: normalized.protectedRoots) {
            return .terminal(reason: .protected)
        }
        do {
            return try await sessions.withPermit(session: session) { probe in
                await self.startUnderPermit(root: canonicalRoot, session: session,
                    sessionID: sessionID, schedulerGeneration: scheduler.generation,
                    traversalGeneration: generation, policyRevision: revision,
                    options: normalized, probe: probe)
            }
        } catch is CancellationError {
            return .terminal(reason: .cancelled)
        } catch {
            return .terminal(reason: .unreadable)
        }
    }

    public func `continue`(from cursor: TraversalCursor, session: WorkSession,
                           sessionID: UUID, generation: UInt64) async -> TraversalResult {
        guard let stored = cursors[cursor.token] else {
            return .terminal(reason: tombstones.contains(cursor.token) ? .cursorReplay : .invalidCursor)
        }
        guard stored.state.workSession == session, stored.state.sessionID == sessionID else {
            return .terminal(reason: .wrongSession)
        }
        guard stored.digest == Self.digest(token: cursor.token, state: stored.state,
                                           expiresAt: stored.expiresAt) else {
            consume(cursor.token)
            return .terminal(reason: .invalidCursor)
        }
        if clock.nowNanoseconds() >= stored.expiresAt {
            consume(cursor.token)
            return .terminal(reason: .cursorExpired, metrics: stored.state.metrics)
        }
        guard stored.state.traversalGeneration == generation else {
            consume(cursor.token)
            return .terminal(reason: .generationMismatch, metrics: stored.state.metrics)
        }

        // Reserve the single-use token while the actor is still synchronous. Every subsequent
        // facade call can suspend and permit actor reentrancy; a concurrent Continue must see the
        // tombstone rather than copy the same retained work.
        consume(cursor.token)
        guard await sessions.state(of: session) == .open else {
            return .terminal(reason: .cancelled, metrics: stored.state.metrics)
        }
        let scheduler = await sessions.snapshot()
        guard scheduler.generation == stored.state.schedulerGeneration else {
            return .terminal(reason: .generationMismatch, metrics: stored.state.metrics)
        }
        guard scheduler.settingsRevision == stored.state.policyRevision else {
            return .terminal(reason: .policyRevisionMismatch, metrics: stored.state.metrics)
        }

        do {
            return try await sessions.withPermit(session: session) { probe in
                await self.continueUnderPermit(stored: stored, probe: probe)
            }
        } catch is CancellationError {
            return .terminal(reason: .cancelled, metrics: stored.state.metrics)
        } catch {
            return .terminal(reason: .unreadable, metrics: stored.state.metrics)
        }
    }

    public func invalidate(sessionID: UUID) {
        let tokens = cursors.compactMap { $0.value.state.sessionID == sessionID ? $0.key : nil }
        for token in tokens { consume(token) }
    }

    public func snapshot() -> BoundedTraversalStoreSnapshot {
        purgeExpiredCursors()
        return BoundedTraversalStoreSnapshot(activeCursors: cursors.count,
                                             cursorTombstones: tombstones.count)
    }

    private func startUnderPermit(root: String, session: WorkSession, sessionID: UUID,
                                  schedulerGeneration: UInt64, traversalGeneration: UInt64,
                                  policyRevision: UInt64, options: TraversalOptions,
                                  probe: SchedulerCancellationProbe) async -> TraversalResult {
        let source = self.source
        let rootRead: TraversalRootRead
        do {
            rootRead = try await UtilityTraversalExecutor.shared.run {
                source.rootIdentity(at: root)
            }
        } catch is CancellationError {
            return .terminal(reason: .cancelled)
        } catch {
            return .terminal(reason: .unreadable)
        }
        guard case .identity(let rootIdentity) = rootRead else {
            return .terminal(reason: rootRead.reason)
        }
        var state = TraversalState(root: root, rootIdentity: rootIdentity,
            workSession: session, sessionID: sessionID,
            schedulerGeneration: schedulerGeneration,
            traversalGeneration: traversalGeneration, policyRevision: policyRevision,
            options: options,
            pending: [TraversalPending(path: root, relativePath: "", depth: 0,
                                       expectedIdentity: rootIdentity)],
            totalBytes: 0, topItems: BoundedRankedHeap(limit: limits.topN),
            childBytes: [:], hardLinks: [], directoryObservations: [], reasons: [],
            metrics: .zero.recordingQueue(1))
        return await executeSlice(state: &state, probe: probe)
    }

    private func continueUnderPermit(stored: StoredTraversalCursor,
                                     probe: SchedulerCancellationProbe) async -> TraversalResult {
        guard clock.nowNanoseconds() < stored.expiresAt else {
            return .terminal(reason: .cursorExpired, metrics: stored.state.metrics)
        }
        let scheduler = await sessions.snapshot()
        guard scheduler.generation == stored.state.schedulerGeneration else {
            return .terminal(reason: .generationMismatch, metrics: stored.state.metrics)
        }
        guard scheduler.settingsRevision == stored.state.policyRevision else {
            return .terminal(reason: .policyRevisionMismatch, metrics: stored.state.metrics)
        }
        guard clock.nowNanoseconds() < stored.expiresAt else {
            return .terminal(reason: .cursorExpired, metrics: stored.state.metrics)
        }
        var state = stored.state
        let source = self.source
        let rootPath = state.root
        let current: TraversalRootRead
        do {
            current = try await UtilityTraversalExecutor.shared.run {
                source.rootIdentity(at: rootPath)
            }
        } catch {
            return makeTerminal(state: state, reason: .unreadable, records: [])
        }
        guard case .identity(let identity) = current, identity == state.rootIdentity else {
            return makeTerminal(state: state, reason: .rootReplaced, records: [])
        }
        if let reason = await validateDirectories(in: state) {
            return makeTerminal(state: state, reason: reason, records: [])
        }
        return await executeSlice(state: &state, probe: probe)
    }

    private func executeSlice(state: inout TraversalState,
                              probe: SchedulerCancellationProbe) async -> TraversalResult {
        let sliceStart = clock.nowNanoseconds()
        let sliceNanoseconds = UInt64(limits.sliceSeconds) * 1_000_000_000
        var pageRecords: [TraversalRecord] = []

        while !state.pending.isEmpty {
            if await probe.isCancelled() {
                return makeTerminal(state: state, reason: .cancelled, records: pageRecords)
            }
            if pageRecords.count >= limits.resultRecords {
                return issueCursor(for: state, records: pageRecords, reason: .resultLimit)
            }

            let resultCapacity = limits.resultRecords - pageRecords.count
            let count = min(limits.batchEntries, state.pending.count, max(1, resultCapacity))
            let work = Array(state.pending.prefix(count))
            state.pending.removeFirst(count)
            let source = self.source
            let limits = self.limits
            let protectedRoots = state.options.protectedRoots
            let rootIdentity = state.rootIdentity
            let reads: [TraversalSourceRead]
            do {
                reads = try await UtilityTraversalExecutor.shared.run {
                    work.map { item in
                        if BoundedTraversal.isProtected(item.path, protectedRoots: protectedRoots) {
                            return .skipped(.protected)
                        }
                        return source.read(TraversalSourceRequest(path: item.path,
                            relativePath: item.relativePath, depth: item.depth,
                            expectedIdentity: item.expectedIdentity,
                            rootIdentity: rootIdentity, limits: limits))
                    }
                }
            } catch is CancellationError {
                return makeTerminal(state: state, reason: .cancelled, records: pageRecords)
            } catch {
                return makeTerminal(state: state, reason: .unreadable, records: pageRecords)
            }

            guard let batchMetrics = state.metrics.recordingBatch(count: reads.count,
                queued: state.pending.count + work.count,
                depth: work.map(\.depth).max() ?? 0,
                descriptors: reads.maximumDescriptorHighWater) else {
                return makeTerminal(state: state, reason: .arithmeticOverflow,
                                    records: pageRecords)
            }
            state.metrics = batchMetrics
            await testHook?.receive(.batchCompleted(state.metrics.batches, work.map(\.path)))

            // Cancellation is observed after each finite blocking batch and before any child
            // enters the retained queue. A cancelled batch never launches later enumeration.
            if await probe.isCancelled() {
                return makeTerminal(state: state, reason: .cancelled, records: pageRecords)
            }

            for (workIndex, pair) in zip(work, reads).enumerated() {
                let (item, read) = pair
                guard let processedMetrics = state.metrics.recordingProcessed() else {
                    return makeTerminal(state: state, reason: .arithmeticOverflow,
                                        records: pageRecords)
                }
                state.metrics = processedMetrics
                switch read {
                case .skipped(let reason):
                    state.reasons.insert(reason)
                    continue
                case .entry(let entry):
                    guard entry.identity == item.expectedIdentity else {
                        return makeTerminal(state: state, reason: .churn, records: pageRecords)
                    }
                    if let reason = entry.terminalReason {
                        return makeTerminal(state: state, reason: reason, records: pageRecords)
                    }
                    if entry.observedBreadth > limits.maxBreadth {
                        return makeTerminal(state: state, reason: .maxBreadth, records: pageRecords)
                    }
                    guard entry.openDescriptorHighWater <= limits.openDescriptors else {
                        return makeTerminal(state: state, reason: .unreadable, records: pageRecords)
                    }
                    // All compatibility scanners skip symbolic links before accounting or
                    // selection. Keeping that rule here also prevents traversal escaping a root.
                    if entry.kind == .symbolicLink { continue }

                    if entry.kind == .directory {
                        guard let watermark = entry.directoryWatermark else {
                            return makeTerminal(state: state, reason: .unreadable,
                                                records: pageRecords)
                        }
                        guard state.directoryObservations.count < limits.queuedPaths else {
                            return makeTerminal(state: state, reason: .churn,
                                                records: pageRecords)
                        }
                        state.directoryObservations.append(
                            TraversalDirectoryObservation(path: item.path,
                                                          watermark: watermark))
                    }

                    let duplicateHardLink: Bool
                    if entry.kind != .directory, entry.linkCount > 1 {
                        if state.hardLinks.contains(entry.identity) {
                            duplicateHardLink = true
                        } else if state.hardLinks.count >= limits.hardLinkIdentities {
                            return makeTerminal(state: state, reason: .hardLinkLimit,
                                                records: pageRecords)
                        } else {
                            state.hardLinks.insert(entry.identity)
                            state.metrics = state.metrics.recordingHardLinks(state.hardLinks.count)
                            duplicateHardLink = false
                        }
                    } else {
                        duplicateHardLink = false
                    }
                    if duplicateHardLink { continue }

                    if item.depth == 0 || entry.kind != .directory {
                        guard entry.bytes >= 0 else {
                            return makeTerminal(state: state, reason: .arithmeticOverflow,
                                                records: pageRecords)
                        }
                        let (next, overflow) = state.totalBytes.addingReportingOverflow(entry.bytes)
                        guard !overflow else {
                            return makeTerminal(state: state, reason: .arithmeticOverflow,
                                                records: pageRecords)
                        }
                        state.totalBytes = next
                    }

                    if state.options.collectChildTotals, item.depth > 0,
                       (item.depth == 1 || entry.kind != .directory),
                       let first = item.relativePath.split(separator: "/").first {
                        let childPath = state.root + "/" + String(first)
                        if state.childBytes[childPath] == nil,
                           state.childBytes.count >= limits.childAggregates {
                            return makeTerminal(state: state, reason: .childAggregateLimit,
                                                records: pageRecords)
                        }
                        let (next, overflow) = (state.childBytes[childPath] ?? 0)
                            .addingReportingOverflow(entry.bytes)
                        guard !overflow else {
                            return makeTerminal(state: state, reason: .arithmeticOverflow,
                                                records: pageRecords)
                        }
                        state.childBytes[childPath] = next
                        state.metrics = state.metrics.recordingChildAggregates(state.childBytes.count)
                    }

                    let record = TraversalRecord(path: item.path,
                        relativePath: item.relativePath, depth: item.depth,
                        bytes: entry.bytes, kind: entry.kind, modifiedAt: entry.modifiedAt)
                    let selected = state.options.recordSelection.includes(record)
                    if selected {
                        guard pageRecords.count < limits.resultRecords else {
                            state.pending.insert(item, at: 0)
                            return issueCursor(for: state, records: pageRecords, reason: .resultLimit)
                        }
                        pageRecords.append(record)
                        state.metrics = state.metrics.recordingResultRecords(pageRecords.count)
                    }

                    if entry.kind == .regularFile,
                       let minimum = state.options.minimumFileBytes,
                       entry.bytes >= minimum {
                        state.topItems.insert(RankedItem(path: item.path, bytes: entry.bytes))
                        state.metrics = state.metrics.recordingTopN(state.topItems.count)
                    }

                    if entry.kind == .directory,
                       !(selected && state.options.pruneMatchedDirectories) {
                        guard item.depth < limits.maxDepth || entry.children.isEmpty else {
                            return makeTerminal(state: state, reason: .maxDepth,
                                                records: pageRecords)
                        }
                        guard state.pending.count + entry.children.count <= limits.queuedPaths else {
                            return makeTerminal(state: state, reason: .queueOverflow,
                                                records: pageRecords)
                        }
                        var pendingChildren: [TraversalPending] = []
                        pendingChildren.reserveCapacity(entry.children.count)
                        for child in entry.children.sorted(by: { $0.name < $1.name }) {
                            let childPath = item.path == "/"
                                ? "/" + child.name : item.path + "/" + child.name
                            guard childPath.utf8.count <= limits.maxPathBytes else {
                                return makeTerminal(state: state, reason: .stringOverflow,
                                                    records: pageRecords)
                            }
                            let relative = item.relativePath.isEmpty
                                ? child.name : item.relativePath + "/" + child.name
                            pendingChildren.append(TraversalPending(path: childPath,
                                relativePath: relative, depth: item.depth + 1,
                                expectedIdentity: child.identity))
                        }
                        for (childIndex, pendingChild) in pendingChildren.enumerated() {
                            if await probe.isCancelled() {
                                return makeTerminal(state: state, reason: .cancelled,
                                                    records: pageRecords)
                            }
                            if clock.nowNanoseconds() &- sliceStart >= sliceNanoseconds {
                                let unprocessedWork = work.dropFirst(workIndex + 1)
                                let deferredChildren = pendingChildren.dropFirst(childIndex)
                                guard state.pending.count + unprocessedWork.count
                                    + deferredChildren.count <= limits.queuedPaths else {
                                    return makeTerminal(state: state, reason: .queueOverflow,
                                                        records: pageRecords)
                                }
                                state.pending.append(contentsOf: unprocessedWork)
                                state.pending.append(contentsOf: deferredChildren)
                                state.pending.sort { $0.relativePath < $1.relativePath }
                                state.metrics = state.metrics.recordingQueue(state.pending.count)
                                return issueCursor(for: state, records: pageRecords,
                                                   reason: .sliceExpired)
                            }
                            state.pending.append(pendingChild)
                            state.pending.sort { $0.relativePath < $1.relativePath }
                            state.metrics = state.metrics.recordingQueue(state.pending.count)
                            await testHook?.receive(.descendantEnqueued(pendingChild.path))
                        }
                    }
                }
            }

            let elapsed = clock.nowNanoseconds() &- sliceStart
            if !state.pending.isEmpty, elapsed >= sliceNanoseconds {
                return issueCursor(for: state, records: pageRecords, reason: .sliceExpired)
            }
        }

        if let reason = await validateDirectories(in: state) {
            return makeTerminal(state: state, reason: reason, records: pageRecords)
        }
        return makeResult(state: state, records: pageRecords,
            reasons: state.reasons, isComplete: state.reasons.isEmpty, cursor: nil)
    }

    private func validateDirectories(in state: TraversalState) async -> TraversalCoverageReason? {
        let observations = state.directoryObservations
        guard !observations.isEmpty else { return nil }
        let source = self.source
        do {
            return try await UtilityTraversalExecutor.shared.run {
                for observation in observations {
                    if let reason = source.validateDirectory(at: observation.path,
                                                             watermark: observation.watermark) {
                        return reason
                    }
                }
                return nil
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .unreadable
        }
    }

    private func issueCursor(for state: TraversalState, records: [TraversalRecord],
                             reason: TraversalCoverageReason) -> TraversalResult {
        purgeExpiredCursors()
        guard !state.pending.isEmpty else {
            return makeResult(state: state, records: records,
                reasons: state.reasons, isComplete: state.reasons.isEmpty, cursor: nil)
        }
        guard cursors.count < limits.cursorCount else {
            return makeTerminal(state: state, reason: .cursorLimit, records: records)
        }
        let now = clock.nowNanoseconds()
        let duration = UInt64(limits.sliceSeconds) * 1_000_000_000
        let (expiresAt, overflow) = now.addingReportingOverflow(duration)
        guard !overflow else {
            return makeTerminal(state: state, reason: .arithmeticOverflow, records: records)
        }
        let token = UUID()
        let digest = Self.digest(token: token, state: state, expiresAt: expiresAt)
        cursors[token] = StoredTraversalCursor(state: state, expiresAt: expiresAt, digest: digest)
        var reasons = state.reasons
        reasons.insert(reason)
        return makeResult(state: state, records: records, reasons: reasons,
            isComplete: false, cursor: TraversalCursor(token: token))
    }

    private func makeTerminal(state: TraversalState, reason: TraversalCoverageReason,
                              records: [TraversalRecord]) -> TraversalResult {
        var reasons = state.reasons
        reasons.insert(reason)
        return makeResult(state: state, records: records, reasons: reasons,
                          isComplete: false, cursor: nil)
    }

    private func makeResult(state: TraversalState, records: [TraversalRecord],
                            reasons: Set<TraversalCoverageReason>, isComplete: Bool,
                            cursor: TraversalCursor?) -> TraversalResult {
        let children = state.childBytes.map { RankedItem(path: $0.key, bytes: $0.value) }
            .sorted(by: Self.rankedBefore)
        return TraversalResult(records: records.sorted { $0.path < $1.path },
            totalBytes: state.totalBytes, topItems: state.topItems.sorted(),
            childTotals: children, coverage: TraversalCoverage(isComplete: isComplete,
            reasons: reasons), cursor: cursor, metrics: state.metrics)
    }

    private func consume(_ token: UUID) {
        cursors.removeValue(forKey: token)
        guard limits.cursorTombstones > 0 else { return }
        if tombstones.insert(token).inserted { tombstoneOrder.append(token) }
        while tombstoneOrder.count > limits.cursorTombstones {
            tombstones.remove(tombstoneOrder.removeFirst())
        }
    }

    private func purgeExpiredCursors() {
        let now = clock.nowNanoseconds()
        let expired = cursors.compactMap { $0.value.expiresAt <= now ? $0.key : nil }
        for token in expired { consume(token) }
    }

    private static func digest(token: UUID, state: TraversalState,
                               expiresAt: UInt64) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        func mix(_ string: String) {
            for byte in string.utf8 {
                value ^= UInt64(byte)
                value &*= 1_099_511_628_211
            }
        }
        mix(token.uuidString)
        mix(state.root)
        mix(String(state.rootIdentity.device))
        mix(String(state.rootIdentity.inode))
        mix(String(state.rootIdentity.generation))
        mix(state.sessionID.uuidString)
        mix(String(state.schedulerGeneration))
        mix(String(state.traversalGeneration))
        mix(String(state.policyRevision))
        mix(String(expiresAt))
        for pending in state.pending {
            mix(pending.relativePath)
            mix(String(pending.depth))
            mix(String(pending.expectedIdentity.device))
            mix(String(pending.expectedIdentity.inode))
            mix(String(pending.expectedIdentity.generation))
        }
        for observation in state.directoryObservations {
            mix(observation.path)
            mix(String(observation.watermark.identity.device))
            mix(String(observation.watermark.identity.inode))
            mix(String(observation.watermark.identity.generation))
            mix(String(observation.watermark.modifiedSeconds))
            mix(String(observation.watermark.modifiedNanoseconds))
            mix(String(observation.watermark.changedSeconds))
            mix(String(observation.watermark.changedNanoseconds))
            mix(String(observation.watermark.size))
            mix(String(observation.watermark.linkCount))
        }
        return value
    }

    private static func rankedBefore(_ lhs: RankedItem, _ rhs: RankedItem) -> Bool {
        lhs.bytes != rhs.bytes ? lhs.bytes > rhs.bytes : lhs.path < rhs.path
    }

    fileprivate static func isProtected(_ path: String, protectedRoots: [String]) -> Bool {
        protectedRoots.contains { PathGuard.isEqualOrDescendant(path, of: $0) }
    }
}

private struct TraversalPending: Sendable {
    let path: String
    let relativePath: String
    let depth: Int
    let expectedIdentity: TraversalSourceIdentity
}

private struct TraversalState: Sendable {
    let root: String
    let rootIdentity: TraversalSourceIdentity
    let workSession: WorkSession
    let sessionID: UUID
    let schedulerGeneration: UInt64
    let traversalGeneration: UInt64
    let policyRevision: UInt64
    let options: TraversalOptions
    var pending: [TraversalPending]
    var totalBytes: Int64
    var topItems: BoundedRankedHeap
    var childBytes: [String: Int64]
    var hardLinks: Set<TraversalSourceIdentity>
    var directoryObservations: [TraversalDirectoryObservation]
    var reasons: Set<TraversalCoverageReason>
    var metrics: TraversalMetrics
}

private struct StoredTraversalCursor: Sendable {
    let state: TraversalState
    let expiresAt: UInt64
    let digest: UInt64
}

private struct BoundedRankedHeap: Sendable {
    let limit: Int
    private(set) var items: [RankedItem] = []
    var count: Int { items.count }

    mutating func insert(_ item: RankedItem) {
        guard limit > 0 else { return }
        if items.count < limit {
            items.append(item)
            siftUp(from: items.count - 1)
        } else if Self.better(item, than: items[0]) {
            items[0] = item
            siftDown(from: 0)
        }
    }

    func sorted() -> [RankedItem] {
        items.sorted { Self.better($0, than: $1) }
    }

    private static func better(_ lhs: RankedItem, than rhs: RankedItem) -> Bool {
        lhs.bytes != rhs.bytes ? lhs.bytes > rhs.bytes : lhs.path < rhs.path
    }

    private static func worse(_ lhs: RankedItem, than rhs: RankedItem) -> Bool {
        better(rhs, than: lhs)
    }

    private mutating func siftUp(from start: Int) {
        var index = start
        while index > 0 {
            let parent = (index - 1) / 2
            guard Self.worse(items[index], than: items[parent]) else { return }
            items.swapAt(index, parent)
            index = parent
        }
    }

    private mutating func siftDown(from start: Int) {
        var index = start
        while true {
            let left = index * 2 + 1
            guard left < items.count else { return }
            let right = left + 1
            var worseChild = left
            if right < items.count, Self.worse(items[right], than: items[left]) {
                worseChild = right
            }
            guard Self.worse(items[worseChild], than: items[index]) else { return }
            items.swapAt(index, worseChild)
            index = worseChild
        }
    }
}

private extension TraversalRootRead {
    var reason: TraversalCoverageReason {
        switch self {
        case .identity: return .unreadable
        case .missing: return .missing
        case .unreadable: return .unreadable
        }
    }
}

private extension Array where Element == TraversalSourceRead {
    var maximumDescriptorHighWater: Int {
        reduce(0) { current, read in
            guard case .entry(let entry) = read else { return current }
            return Swift.max(current, entry.openDescriptorHighWater)
        }
    }
}

private extension TraversalMetrics {
    func recordingBatch(count: Int, queued: Int, depth: Int,
                        descriptors: Int) -> TraversalMetrics? {
        let (nextBatches, overflow) = batches.addingReportingOverflow(1)
        guard !overflow else { return nil }
        return TraversalMetrics(processedEntries: processedEntries, batches: nextBatches,
            maximumQueuedPaths: max(maximumQueuedPaths, queued),
            maximumBatchEntries: max(maximumBatchEntries, count),
            maximumDepth: max(maximumDepth, depth),
            maximumOpenDescriptors: max(maximumOpenDescriptors, descriptors),
            maximumHardLinkIdentities: maximumHardLinkIdentities,
            maximumChildAggregates: maximumChildAggregates,
            maximumResultRecords: maximumResultRecords,
            maximumTopN: maximumTopN)
    }

    func recordingProcessed() -> TraversalMetrics? {
        let (next, overflow) = processedEntries.addingReportingOverflow(1)
        guard !overflow else { return nil }
        return replacing(processedEntries: next)
    }
    func recordingQueue(_ value: Int) -> TraversalMetrics {
        replacing(maximumQueuedPaths: max(maximumQueuedPaths, value))
    }
    func recordingHardLinks(_ value: Int) -> TraversalMetrics {
        replacing(maximumHardLinkIdentities: max(maximumHardLinkIdentities, value))
    }
    func recordingChildAggregates(_ value: Int) -> TraversalMetrics {
        replacing(maximumChildAggregates: max(maximumChildAggregates, value))
    }
    func recordingResultRecords(_ value: Int) -> TraversalMetrics {
        replacing(maximumResultRecords: max(maximumResultRecords, value))
    }
    func recordingTopN(_ value: Int) -> TraversalMetrics {
        replacing(maximumTopN: max(maximumTopN, value))
    }

    private func replacing(processedEntries: Int? = nil, maximumQueuedPaths: Int? = nil,
                           maximumHardLinkIdentities: Int? = nil,
                           maximumChildAggregates: Int? = nil,
                           maximumResultRecords: Int? = nil,
                           maximumTopN: Int? = nil) -> TraversalMetrics {
        TraversalMetrics(processedEntries: processedEntries ?? self.processedEntries,
            batches: batches, maximumQueuedPaths: maximumQueuedPaths ?? self.maximumQueuedPaths,
            maximumBatchEntries: maximumBatchEntries, maximumDepth: maximumDepth,
            maximumOpenDescriptors: maximumOpenDescriptors,
            maximumHardLinkIdentities: maximumHardLinkIdentities ?? self.maximumHardLinkIdentities,
            maximumChildAggregates: maximumChildAggregates ?? self.maximumChildAggregates,
            maximumResultRecords: maximumResultRecords ?? self.maximumResultRecords,
            maximumTopN: maximumTopN ?? self.maximumTopN)
    }
}

private extension TraversalRecordSelection {
    func retainedStringsFit(maxBytes: Int) -> Bool {
        switch self {
        case .none, .all, .projectMarkers: return true
        case .directory(let name, _): return name.utf8.count <= maxBytes
        }
    }

    func includes(_ record: TraversalRecord) -> Bool {
        switch self {
        case .none: return false
        case .all: return true
        case .projectMarkers: return ProjectInventory.selects(record)
        case .directory(let name, let modifiedBefore):
            return record.kind == .directory
                && (record.path as NSString).lastPathComponent == name
                && record.modifiedAt.map { $0 < modifiedBefore } == true
        }
    }
}

private extension TraversalResult {
    static func terminal(reason: TraversalCoverageReason,
                         metrics: TraversalMetrics = .zero) -> TraversalResult {
        TraversalResult(records: [], totalBytes: 0, topItems: [], childTotals: [],
            coverage: TraversalCoverage(isComplete: false, reasons: [reason]),
            cursor: nil, metrics: metrics)
    }
}

/// A single bounded execution context for blocking directory APIs. Scheduler permits remain the
/// sole admission authority; this queue only keeps those admitted calls off Swift's cooperative
/// executor and the main thread.
private final class UtilityTraversalExecutor: @unchecked Sendable {
    static let shared = UtilityTraversalExecutor()
    private let queue: OperationQueue

    private init() {
        queue = OperationQueue()
        queue.name = "TidyCore.BoundedTraversal.utility"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 4
    }

    func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.addOperation {
                do { continuation.resume(returning: try operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

internal struct RealFilesystemTraversalSource: BoundedTraversalSource {
    private let descriptorTracker: TraversalDescriptorTracker?
    private let beforeDirectoryOpen: @Sendable (String) -> Void
    private let allocatedBytes: @Sendable (stat) -> Int64?

    init(descriptorTracker: TraversalDescriptorTracker? = nil,
         beforeDirectoryOpen: @escaping @Sendable (String) -> Void = { _ in },
         allocatedBytes: @escaping @Sendable (stat) -> Int64? = { metadata in
             RealFilesystemTraversalSource.checkedAllocatedBytes(metadata)
         }) {
        self.descriptorTracker = descriptorTracker
        self.beforeDirectoryOpen = beforeDirectoryOpen
        self.allocatedBytes = allocatedBytes
    }

    func rootIdentity(at path: String) -> TraversalRootRead {
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable
        }
        return .identity(Self.identity(metadata))
    }

    func validateDirectory(at path: String,
                           watermark: TraversalDirectoryWatermark) -> TraversalCoverageReason? {
        beforeDirectoryOpen(path)
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            return errno == ENOENT || errno == ENOTDIR || errno == ELOOP ? .churn : .unreadable
        }
        descriptorTracker?.opened()
        defer {
            close(descriptor)
            descriptorTracker?.closed()
        }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { return .unreadable }
        guard metadata.st_mode & S_IFMT == S_IFDIR,
              Self.identity(metadata) == watermark.identity else { return .churn }
        return Self.watermark(metadata) == watermark ? nil : .churn
    }

    func read(_ request: TraversalSourceRequest) -> TraversalSourceRead {
        var metadata = stat()
        guard lstat(request.path, &metadata) == 0 else {
            return .skipped(request.expectedIdentity == nil ? .missing : .churn)
        }
        let identity = Self.identity(metadata)
        guard identity == request.expectedIdentity else { return .skipped(.churn) }
        guard identity.device == request.rootIdentity.device else { return .skipped(.crossVolume) }

        let fileType = metadata.st_mode & S_IFMT
        if fileType == S_IFLNK {
            return .entry(TraversalSourceEntry(identity: identity, bytes: 0, kind: .symbolicLink,
                modifiedAt: Self.modifiedAt(metadata), linkCount: Int(metadata.st_nlink),
                children: [], terminalReason: nil, observedBreadth: 0,
                openDescriptorHighWater: 0))
        }
        let kind: TraversalRecordKind = fileType == S_IFDIR ? .directory
            : (fileType == S_IFREG ? .regularFile : .other)
        guard kind == .directory else {
            guard let bytes = allocatedBytes(metadata) else { return .skipped(.unreadable) }
            return .entry(TraversalSourceEntry(identity: identity, bytes: bytes, kind: kind,
                modifiedAt: Self.modifiedAt(metadata), linkCount: Int(metadata.st_nlink),
                children: [], terminalReason: nil, observedBreadth: 0,
                openDescriptorHighWater: 0))
        }

        beforeDirectoryOpen(request.path)
        let descriptor = open(request.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            return .skipped(errno == ENOENT || errno == ENOTDIR || errno == ELOOP
                ? .churn : .unreadable)
        }
        descriptorTracker?.opened()
        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0 else {
            close(descriptor)
            descriptorTracker?.closed()
            return .skipped(.unreadable)
        }
        let openedIdentity = Self.identity(openedMetadata)
        guard openedIdentity == request.expectedIdentity,
              openedIdentity.device == request.rootIdentity.device,
              openedMetadata.st_mode & S_IFMT == S_IFDIR else {
            close(descriptor)
            descriptorTracker?.closed()
            return .skipped(.churn)
        }
        guard let bytes = allocatedBytes(openedMetadata) else {
            close(descriptor)
            descriptorTracker?.closed()
            return .skipped(.unreadable)
        }
        guard let directory = fdopendir(descriptor) else {
            close(descriptor)
            descriptorTracker?.closed()
            return .skipped(.unreadable)
        }
        defer {
            closedir(directory)
            descriptorTracker?.closed()
        }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            if names.count >= request.limits.maxBreadth {
                return .entry(TraversalSourceEntry(identity: identity, bytes: bytes,
                    kind: .directory, modifiedAt: Self.modifiedAt(metadata),
                    linkCount: Int(metadata.st_nlink), children: [], terminalReason: .maxBreadth,
                    observedBreadth: names.count + 1, openDescriptorHighWater: 1))
            }
            names.append(name)
        }

        names.sort()
        var children: [TraversalSourceChild] = []
        children.reserveCapacity(names.count)
        for name in names {
            let childPath = request.path == "/"
                ? "/" + name : request.path + "/" + name
            guard childPath.utf8.count <= request.limits.maxPathBytes else {
                return .entry(TraversalSourceEntry(identity: identity, bytes: bytes,
                    kind: .directory, modifiedAt: Self.modifiedAt(metadata),
                    linkCount: Int(metadata.st_nlink), children: [], terminalReason: .stringOverflow,
                    observedBreadth: names.count, openDescriptorHighWater: 1))
            }
            var childMetadata = stat()
            guard fstatat(dirfd(directory), name, &childMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
                return .entry(TraversalSourceEntry(identity: identity, bytes: bytes,
                    kind: .directory, modifiedAt: Self.modifiedAt(metadata),
                    linkCount: Int(metadata.st_nlink), children: [], terminalReason: .churn,
                    observedBreadth: names.count, openDescriptorHighWater: 1))
            }
            children.append(TraversalSourceChild(name: name,
                                                  identity: Self.identity(childMetadata)))
        }
        var finalMetadata = stat()
        guard fstat(dirfd(directory), &finalMetadata) == 0 else {
            return .entry(TraversalSourceEntry(identity: openedIdentity, bytes: bytes,
                kind: .directory, modifiedAt: Self.modifiedAt(openedMetadata),
                linkCount: Int(openedMetadata.st_nlink), children: [],
                terminalReason: .unreadable, observedBreadth: names.count,
                openDescriptorHighWater: 1))
        }
        let openedWatermark = Self.watermark(openedMetadata)
        let finalWatermark = Self.watermark(finalMetadata)
        guard openedWatermark == finalWatermark else {
            return .entry(TraversalSourceEntry(identity: openedIdentity, bytes: bytes,
                kind: .directory, modifiedAt: Self.modifiedAt(openedMetadata),
                linkCount: Int(openedMetadata.st_nlink), children: [], terminalReason: .churn,
                observedBreadth: names.count, openDescriptorHighWater: 1))
        }
        return .entry(TraversalSourceEntry(identity: openedIdentity, bytes: bytes,
            kind: .directory, modifiedAt: Self.modifiedAt(openedMetadata),
            linkCount: Int(openedMetadata.st_nlink), children: children, terminalReason: nil,
            observedBreadth: names.count, openDescriptorHighWater: 1,
            directoryWatermark: finalWatermark))
    }

    private static func identity(_ metadata: stat) -> TraversalSourceIdentity {
        TraversalSourceIdentity(device: UInt64(truncatingIfNeeded: metadata.st_dev),
            inode: UInt64(truncatingIfNeeded: metadata.st_ino),
            generation: UInt64(truncatingIfNeeded: metadata.st_gen))
    }

    private static func modifiedAt(_ metadata: stat) -> Date {
        Date(timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec)
             + TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    private static func watermark(_ metadata: stat) -> TraversalDirectoryWatermark {
        TraversalDirectoryWatermark(identity: identity(metadata),
            modifiedSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
            changedSeconds: Int64(metadata.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(metadata.st_ctimespec.tv_nsec),
            size: Int64(metadata.st_size), linkCount: UInt64(metadata.st_nlink))
    }

    private static func checkedAllocatedBytes(_ metadata: stat) -> Int64? {
        let blocks = Int64(metadata.st_blocks)
        guard blocks >= 0 else { return nil }
        let (bytes, overflow) = blocks.multipliedReportingOverflow(by: 512)
        return overflow ? nil : bytes
    }
}
