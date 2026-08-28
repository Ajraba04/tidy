import Foundation

public struct ScanSessionSnapshot: Equatable, Sendable {
    public let processedEntries: Int
    public let totalBytes: Int64
    public let items: [RankedItem]

    public init(processedEntries: Int = 0, totalBytes: Int64 = 0,
                items: [RankedItem] = []) {
        self.processedEntries = processedEntries
        self.totalBytes = totalBytes
        self.items = items
    }
}

public enum ScanSessionTerminal: String, Equatable, Sendable {
    case complete
    case partial
    case cancelled
    case failed
}

public enum ScanSessionEventKind: Equatable, Sendable {
    case progress
    case terminal(ScanSessionTerminal)
}

public struct ScanSessionEvent: Equatable, Sendable {
    public let sessionID: UUID
    public let sequence: UInt64
    public let policyRevision: UInt64
    public let coverage: TraversalCoverage
    public let snapshot: ScanSessionSnapshot
    public let kind: ScanSessionEventKind

    public var terminal: ScanSessionTerminal? {
        if case .terminal(let terminal) = kind { return terminal }
        return nil
    }
}

public struct ScanSessionCompletion: Equatable, Sendable {
    public let terminal: ScanSessionTerminal
    public let coverage: TraversalCoverage
    public let snapshot: ScanSessionSnapshot

    public init(terminal: ScanSessionTerminal, coverage: TraversalCoverage,
                snapshot: ScanSessionSnapshot) {
        self.terminal = terminal
        self.coverage = coverage
        self.snapshot = snapshot
    }
}

public struct ScanSessionLimits: Equatable, Sendable {
    public let maxSessions: Int
    public let subscribersPerSession: Int
    public let streamBuffer: Int
    public let snapshotItems: Int
    public let snapshotPathBytes: Int

    public init(maxSessions: Int = 32, subscribersPerSession: Int = 8,
                streamBuffer: Int = 8, snapshotItems: Int = 64,
                snapshotPathBytes: Int = 4_096) throws {
        guard (1...64).contains(maxSessions), (1...16).contains(subscribersPerSession),
              (1...32).contains(streamBuffer), (0...256).contains(snapshotItems),
              (64...16_384).contains(snapshotPathBytes) else {
            throw ScanSessionRegistryError.invalidLimits
        }
        self.maxSessions = maxSessions
        self.subscribersPerSession = subscribersPerSession
        self.streamBuffer = streamBuffer
        self.snapshotItems = snapshotItems
        self.snapshotPathBytes = snapshotPathBytes
    }
}

public enum ScanSessionRegistryError: Error, Equatable, Sendable {
    case invalidLimits
    case invalidRate
    case sessionLimit
    case unknownSession
    case subscriberLimit
    case terminalSession
    case workAlreadyStarted
    case snapshotLimit
    case nonCumulativeSnapshot
    case invalidCoverage
    case sequenceOverflow
    case clockMovedBackwards
}

public struct ScanSessionState: Equatable, Sendable {
    public let sessionID: UUID
    public let policyRevision: UInt64
    public let coverage: TraversalCoverage
    public let snapshot: ScanSessionSnapshot
    public let terminal: ScanSessionTerminal?
    public let liveSubscribers: Int
    public let workActive: Bool
}

public struct ScanSessionRegistrySnapshot: Equatable, Sendable {
    public let sessions: Int
    public let activeWork: Int
    public let liveSubscribers: Int
    public let bufferedEvents: Int
    public let maximumBufferedEvents: Int
    public let droppedProgressEvents: Int
    public let retainedTerminalStates: Int
}

public struct ScanSubscription: Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let stream: AsyncStream<ScanSessionEvent>
    private let cancellation: @Sendable () async -> Void

    fileprivate init(id: UUID, sessionID: UUID, stream: AsyncStream<ScanSessionEvent>,
                     cancellation: @escaping @Sendable () async -> Void) {
        self.id = id
        self.sessionID = sessionID
        self.stream = stream
        self.cancellation = cancellation
    }

    public func cancel() async { await cancellation() }
}

public struct ScanSessionReporter: Sendable {
    public let sessionID: UUID
    private let registry: ScanSessionRegistry

    fileprivate init(sessionID: UUID, registry: ScanSessionRegistry) {
        self.sessionID = sessionID
        self.registry = registry
    }

    public func recordBatch(coverage: TraversalCoverage,
                            snapshot: ScanSessionSnapshot) async throws {
        try await registry.recordBatch(sessionID: sessionID, coverage: coverage,
                                       snapshot: snapshot)
    }

    public func isCancelled() async -> Bool {
        guard let state = try? await registry.state(sessionID: sessionID) else { return true }
        return state.terminal == .cancelled || Task.isCancelled
    }
}

public actor ScanSessionRegistry {
    private struct Subscriber {
        let continuation: AsyncStream<ScanSessionEvent>.Continuation
        var buffered = 0
    }

    private struct Record {
        let id: UUID
        let policyRevision: UInt64
        let batchesPerSecond: Int
        var sequence: UInt64 = 0
        var coverage = TraversalCoverage(isComplete: false, reasons: [])
        var snapshot = ScanSessionSnapshot()
        var terminal: ScanSessionTerminal?
        var terminalEvent: ScanSessionEvent?
        var lastProgressEmission: UInt64?
        var subscribers: [UUID: Subscriber] = [:]
        var task: Task<ScanSessionCompletion, Never>?
        var cancellationRequested = false
    }

    private let limits: ScanSessionLimits
    private let clock: BoundedTraversalClock
    private var records: [UUID: Record] = [:]
    private var order: [UUID] = []
    private var maximumBufferedEvents = 0
    private var droppedProgressEvents = 0

    public init(limits: ScanSessionLimits = try! .init()) {
        self.limits = limits
        self.clock = .continuous
    }

    internal init(limits: ScanSessionLimits, clock: BoundedTraversalClock) {
        self.limits = limits
        self.clock = clock
    }

    public func begin(policyRevision: UInt64, batchesPerSecond: Int,
                      initialSnapshot: ScanSessionSnapshot = .init()) throws -> UUID {
        guard (1...4).contains(batchesPerSecond) else {
            throw ScanSessionRegistryError.invalidRate
        }
        try validate(initialSnapshot, after: nil)
        reapOldestTerminalIfNeeded()
        guard records.count < limits.maxSessions else {
            throw ScanSessionRegistryError.sessionLimit
        }
        let id = UUID()
        var record = Record(id: id, policyRevision: policyRevision,
                            batchesPerSecond: batchesPerSecond)
        record.snapshot = initialSnapshot
        records[id] = record
        order.append(id)
        return id
    }

    public func subscribe(sessionID: UUID) throws -> ScanSubscription {
        guard var record = records[sessionID] else {
            throw ScanSessionRegistryError.unknownSession
        }
        let subscriptionID = UUID()
        let pair = AsyncStream<ScanSessionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(limits.streamBuffer))

        if let terminal = record.terminalEvent {
            pair.continuation.yield(terminal)
            pair.continuation.finish()
            return ScanSubscription(id: subscriptionID, sessionID: sessionID,
                stream: pair.stream, cancellation: {})
        }

        guard record.subscribers.count < limits.subscribersPerSession else {
            pair.continuation.finish()
            throw ScanSessionRegistryError.subscriberLimit
        }
        pair.continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeSubscriber(sessionID: sessionID,
                                                subscriptionID: subscriptionID) }
        }
        record.subscribers[subscriptionID] = Subscriber(continuation: pair.continuation)
        records[sessionID] = record
        let registry = self
        return ScanSubscription(id: subscriptionID, sessionID: sessionID,
            stream: pair.stream, cancellation: {
                await registry.removeSubscriber(sessionID: sessionID,
                                                subscriptionID: subscriptionID)
            })
    }

    public func recordBatch(sessionID: UUID, coverage: TraversalCoverage,
                            snapshot: ScanSessionSnapshot) throws {
        guard var record = records[sessionID] else {
            throw ScanSessionRegistryError.unknownSession
        }
        guard record.terminal == nil else { throw ScanSessionRegistryError.terminalSession }
        try validate(snapshot, after: record.snapshot)
        record.coverage = coverage
        record.snapshot = snapshot
        let now = clock.nowNanoseconds()
        if let last = record.lastProgressEmission, now < last {
            throw ScanSessionRegistryError.clockMovedBackwards
        }
        let interval = (1_000_000_000 + UInt64(record.batchesPerSecond) - 1)
            / UInt64(record.batchesPerSecond)
        let shouldEmit = record.lastProgressEmission.map { now - $0 >= interval } ?? true
        if shouldEmit {
            let event = try nextEvent(record: &record, coverage: coverage,
                snapshot: snapshot, kind: .progress)
            record.lastProgressEmission = now
            emit(event, to: &record)
        }
        records[sessionID] = record
    }

    public func complete(sessionID: UUID, terminal: ScanSessionTerminal,
                         coverage: TraversalCoverage,
                         snapshot: ScanSessionSnapshot) throws {
        guard var record = records[sessionID] else {
            throw ScanSessionRegistryError.unknownSession
        }
        guard record.terminal == nil else { throw ScanSessionRegistryError.terminalSession }
        try validateTerminal(terminal, coverage: coverage)
        try validate(snapshot, after: record.snapshot)
        let event = try nextEvent(record: &record, coverage: coverage,
            snapshot: snapshot, kind: .terminal(terminal))

        // Retain the terminal cumulative state before any stream is finished.
        record.coverage = coverage
        record.snapshot = snapshot
        record.terminal = terminal
        record.terminalEvent = event
        record.task = nil
        records[sessionID] = record

        emit(event, to: &record)
        let continuations = record.subscribers.values.map(\.continuation)
        record.subscribers.removeAll(keepingCapacity: false)
        records[sessionID] = record
        for continuation in continuations { continuation.finish() }
    }

    public func startWork(sessionID: UUID,
        operation: @escaping @Sendable (ScanSessionReporter) async -> ScanSessionCompletion) throws {
        guard var record = records[sessionID] else {
            throw ScanSessionRegistryError.unknownSession
        }
        guard record.terminal == nil else { throw ScanSessionRegistryError.terminalSession }
        guard record.task == nil else { throw ScanSessionRegistryError.workAlreadyStarted }
        let reporter = ScanSessionReporter(sessionID: sessionID, registry: self)
        let registry = self
        let task = Task {
            await operation(reporter)
        }
        record.task = task
        records[sessionID] = record
        Task {
            let completion = await task.value
            await registry.ownedWorkEnded(sessionID: sessionID, completion: completion)
        }
    }

    public func cancel(sessionID: UUID, snapshot: ScanSessionSnapshot? = nil) throws {
        guard var record = records[sessionID] else {
            throw ScanSessionRegistryError.unknownSession
        }
        guard record.terminal == nil else { throw ScanSessionRegistryError.terminalSession }
        if let snapshot {
            try validate(snapshot, after: record.snapshot)
            record.snapshot = snapshot
        }
        record.cancellationRequested = true
        let task = record.task
        records[sessionID] = record

        // Signal owned work first. Its retained task remains the source of truth for active work;
        // the terminal event is emitted only by the completion observer after task.value returns.
        task?.cancel()
        if task == nil {
            try complete(sessionID: sessionID, terminal: .cancelled,
                coverage: TraversalCoverage(isComplete: false, reasons: [.cancelled]),
                snapshot: record.snapshot)
        }
    }

    public func state(sessionID: UUID) throws -> ScanSessionState {
        guard let record = records[sessionID] else {
            throw ScanSessionRegistryError.unknownSession
        }
        return ScanSessionState(sessionID: sessionID, policyRevision: record.policyRevision,
            coverage: record.coverage, snapshot: record.snapshot, terminal: record.terminal,
            liveSubscribers: record.subscribers.count,
            workActive: record.task != nil && record.terminal == nil)
    }

    public func snapshot() -> ScanSessionRegistrySnapshot {
        let activeWork = records.values.filter { $0.task != nil && $0.terminal == nil }.count
        let subscribers = records.values.reduce(0) { $0 + $1.subscribers.count }
        let buffered = records.values.reduce(0) { total, record in
            total + record.subscribers.values.reduce(0) { $0 + $1.buffered }
        }
        return ScanSessionRegistrySnapshot(sessions: records.count, activeWork: activeWork,
            liveSubscribers: subscribers, bufferedEvents: buffered,
            maximumBufferedEvents: maximumBufferedEvents,
            droppedProgressEvents: droppedProgressEvents,
            retainedTerminalStates: records.values.filter { $0.terminal != nil }.count)
    }

    private func nextEvent(record: inout Record, coverage: TraversalCoverage,
                           snapshot: ScanSessionSnapshot,
                           kind: ScanSessionEventKind) throws -> ScanSessionEvent {
        let (next, overflow) = record.sequence.addingReportingOverflow(1)
        guard !overflow else { throw ScanSessionRegistryError.sequenceOverflow }
        record.sequence = next
        return ScanSessionEvent(sessionID: record.id, sequence: next,
            policyRevision: record.policyRevision, coverage: coverage,
            snapshot: snapshot, kind: kind)
    }

    private func emit(_ event: ScanSessionEvent, to record: inout Record) {
        var terminated: [UUID] = []
        for (id, var subscriber) in record.subscribers {
            switch subscriber.continuation.yield(event) {
            case .enqueued(let remainingCapacity):
                subscriber.buffered = max(0, limits.streamBuffer - remainingCapacity)
                record.subscribers[id] = subscriber
            case .dropped(let dropped):
                subscriber.buffered = limits.streamBuffer
                record.subscribers[id] = subscriber
                if case .progress = dropped.kind { droppedProgressEvents += 1 }
            case .terminated:
                terminated.append(id)
            @unknown default:
                terminated.append(id)
            }
        }
        for id in terminated { record.subscribers.removeValue(forKey: id) }
        let otherBuffered = records.reduce(0) { total, element in
            guard element.key != record.id else { return total }
            return total + element.value.subscribers.values.reduce(0) { $0 + $1.buffered }
        }
        let totalBuffered = otherBuffered
            + record.subscribers.values.reduce(0) { $0 + $1.buffered }
        maximumBufferedEvents = max(maximumBufferedEvents, totalBuffered)
    }

    private func removeSubscriber(sessionID: UUID, subscriptionID: UUID) {
        guard var record = records[sessionID],
              let subscriber = record.subscribers.removeValue(forKey: subscriptionID) else { return }
        records[sessionID] = record
        subscriber.continuation.finish()
    }

    private func validate(_ snapshot: ScanSessionSnapshot,
                          after previous: ScanSessionSnapshot?) throws {
        guard snapshot.processedEntries >= 0, snapshot.totalBytes >= 0,
              snapshot.items.count <= limits.snapshotItems,
              snapshot.items.allSatisfy({ $0.path.utf8.count <= limits.snapshotPathBytes }) else {
            throw ScanSessionRegistryError.snapshotLimit
        }
        if let previous,
           (snapshot.processedEntries < previous.processedEntries
            || snapshot.totalBytes < previous.totalBytes) {
            throw ScanSessionRegistryError.nonCumulativeSnapshot
        }
    }

    private func validateTerminal(_ terminal: ScanSessionTerminal,
                                  coverage: TraversalCoverage) throws {
        let structurallyComplete = coverage.reasons.isEmpty
        guard coverage.isComplete == structurallyComplete else {
            throw ScanSessionRegistryError.invalidCoverage
        }
        switch terminal {
        case .complete:
            guard coverage.isComplete else { throw ScanSessionRegistryError.invalidCoverage }
        case .partial, .failed:
            guard !coverage.isComplete else { throw ScanSessionRegistryError.invalidCoverage }
        case .cancelled:
            guard !coverage.isComplete, coverage.reasons.contains(.cancelled) else {
                throw ScanSessionRegistryError.invalidCoverage
            }
        }
    }

    private func reapOldestTerminalIfNeeded() {
        guard records.count >= limits.maxSessions else { return }
        guard let index = order.firstIndex(where: { id in
            guard let record = records[id] else { return true }
            return record.terminal != nil && record.subscribers.isEmpty && record.task == nil
        }) else { return }
        let id = order.remove(at: index)
        records.removeValue(forKey: id)
    }

    private func failOwnedWorkIfNeeded(sessionID: UUID) {
        guard let record = records[sessionID], record.terminal == nil else { return }
        try? complete(sessionID: sessionID, terminal: .failed,
            coverage: TraversalCoverage(isComplete: false, reasons: [.unreadable]),
            snapshot: record.snapshot)
    }

    private func ownedWorkEnded(sessionID: UUID, completion: ScanSessionCompletion) {
        guard let record = records[sessionID], record.terminal == nil else { return }
        if record.cancellationRequested {
            var finalSnapshot = record.snapshot
            do {
                try validate(completion.snapshot, after: record.snapshot)
                finalSnapshot = completion.snapshot
            } catch {
                // A cancelled worker cannot regress the last accepted cumulative snapshot.
            }
            var reasons = record.coverage.reasons
            do {
                try validateTerminal(completion.terminal, coverage: completion.coverage)
                reasons.formUnion(completion.coverage.reasons)
            } catch {
                // Cancellation remains truthful even if a winding-down worker returns a malformed
                // completion that would not be admissible on its own.
            }
            reasons.insert(.cancelled)
            do {
                try complete(sessionID: sessionID, terminal: .cancelled,
                    coverage: TraversalCoverage(isComplete: false, reasons: reasons),
                    snapshot: finalSnapshot)
            } catch {
                failOwnedWorkIfNeeded(sessionID: sessionID)
            }
            return
        }
        do {
            try complete(sessionID: sessionID, terminal: completion.terminal,
                coverage: completion.coverage, snapshot: completion.snapshot)
        } catch {
            failOwnedWorkIfNeeded(sessionID: sessionID)
        }
    }
}
