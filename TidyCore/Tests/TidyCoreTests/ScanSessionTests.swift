import Foundation
import Testing
@testable import TidyCore

private final class SessionManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func now() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func advance(seconds: UInt64) { advance(nanoseconds: seconds * 1_000_000_000) }

    func advance(nanoseconds: UInt64) {
        lock.lock(); defer { lock.unlock() }
        value += nanoseconds
    }

    var traversalClock: BoundedTraversalClock {
        BoundedTraversalClock(nowNanoseconds: { self.now() })
    }
}

private actor SessionWorkGate {
    private var started = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func hold() async {
        started = true
        startedWaiter?.resume(); startedWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }

    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private func snapshot(_ processed: Int, bytes: Int64? = nil,
                      items: [RankedItem] = []) -> ScanSessionSnapshot {
    ScanSessionSnapshot(processedEntries: processed, totalBytes: bytes ?? Int64(processed),
                        items: items)
}

private func collect(_ subscription: ScanSubscription) async -> [ScanSessionEvent] {
    var events: [ScanSessionEvent] = []
    for await event in subscription.stream { events.append(event) }
    return events
}

private func terminalEvent(_ events: [ScanSessionEvent]) -> ScanSessionEvent? {
    events.last { if case .terminal = $0.kind { return true }; return false }
}

@Suite(.serialized)
struct ScanSessionTests {
    @Test("two unique subscribers receive the same cumulative terminal state")
    func subscribersReceiveSameTerminal() async throws {
        let registry = ScanSessionRegistry(limits: try .init(maxSessions: 8,
            subscribersPerSession: 4, streamBuffer: 8, snapshotItems: 8))
        let sessionID = try await registry.begin(policyRevision: 41, batchesPerSecond: 4)
        let first = try await registry.subscribe(sessionID: sessionID)
        let second = try await registry.subscribe(sessionID: sessionID)
        #expect(first.id != second.id)
        async let firstEvents = collect(first)
        async let secondEvents = collect(second)

        try await registry.recordBatch(sessionID: sessionID,
            coverage: .init(isComplete: false, reasons: [.sliceExpired]),
            snapshot: snapshot(1, bytes: 10))
        try await registry.recordBatch(sessionID: sessionID,
            coverage: .init(isComplete: false, reasons: [.sliceExpired]),
            snapshot: snapshot(2, bytes: 20))
        try await registry.complete(sessionID: sessionID, terminal: .complete,
            coverage: .init(isComplete: true, reasons: []),
            snapshot: snapshot(3, bytes: 30,
                items: [RankedItem(path: "/final", bytes: 30)]))

        let a = await firstEvents
        let b = await secondEvents
        let aTerminal = try #require(terminalEvent(a))
        let bTerminal = try #require(terminalEvent(b))
        #expect(aTerminal == bTerminal)
        #expect(aTerminal.sessionID == sessionID)
        #expect(aTerminal.policyRevision == 41)
        #expect(aTerminal.snapshot == snapshot(3, bytes: 30,
            items: [RankedItem(path: "/final", bytes: 30)]))
        #expect(a.map(\.sequence) == a.map(\.sequence).sorted())
        #expect(Set(a.map(\.sequence)).count == a.count)
        let retained = try await registry.state(sessionID: sessionID)
        #expect(retained.terminal == .complete)
        #expect(retained.snapshot == aTerminal.snapshot)
    }

    @Test("cancelling one subscription leaves the other and owned work active")
    func subscriberCancellationDoesNotCancelWork() async throws {
        let registry = ScanSessionRegistry(limits: try .init(maxSessions: 4,
            subscribersPerSession: 4, streamBuffer: 4, snapshotItems: 4))
        let sessionID = try await registry.begin(policyRevision: 7, batchesPerSecond: 4)
        let cancelled = try await registry.subscribe(sessionID: sessionID)
        let survivor = try await registry.subscribe(sessionID: sessionID)
        async let survivorEvents = collect(survivor)
        let gate = SessionWorkGate()

        try await registry.startWork(sessionID: sessionID) { reporter in
            await gate.hold()
            try? await reporter.recordBatch(
                coverage: .init(isComplete: false, reasons: [.sliceExpired]),
                snapshot: snapshot(1))
            return ScanSessionCompletion(terminal: .complete,
                coverage: .init(isComplete: true, reasons: []), snapshot: snapshot(2))
        }
        await gate.waitUntilStarted()
        await cancelled.cancel()
        let active = await registry.snapshot()
        #expect(active.activeWork == 1)
        #expect(active.liveSubscribers == 1)
        #expect(active.sessions == 1)
        await gate.release()

        let events = await survivorEvents
        #expect(terminalEvent(events)?.terminal == .complete)
        let final = await registry.snapshot()
        #expect(final.activeWork == 0)
        #expect(final.maximumBufferedEvents <= 4)
    }

    @Test("slow full subscriber drops bounded progress without corrupting final state")
    func slowSubscriberIsBounded() async throws {
        let clock = SessionManualClock()
        let registry = ScanSessionRegistry(limits: try .init(maxSessions: 4,
            subscribersPerSession: 4, streamBuffer: 1, snapshotItems: 2),
            clock: clock.traversalClock)
        let sessionID = try await registry.begin(policyRevision: 3, batchesPerSecond: 4)
        let slow = try await registry.subscribe(sessionID: sessionID)
        let fast = try await registry.subscribe(sessionID: sessionID)
        async let fastEvents = collect(fast)

        for index in 1...100 {
            clock.advance(seconds: 1)
            try await registry.recordBatch(sessionID: sessionID,
                coverage: .init(isComplete: false, reasons: [.sliceExpired]),
                snapshot: snapshot(index, bytes: Int64(index)))
        }
        let pressure = await registry.snapshot()
        #expect(pressure.maximumBufferedEvents <= 2)
        #expect(pressure.droppedProgressEvents > 0)
        try await registry.complete(sessionID: sessionID, terminal: .partial,
            coverage: .init(isComplete: false, reasons: [.maxBreadth]),
            snapshot: snapshot(101, bytes: 101,
                items: [RankedItem(path: "/kept", bytes: 101)]))

        let fastTerminal = try #require(terminalEvent(await fastEvents))
        let slowEvents = await collect(slow)
        let slowTerminal = try #require(terminalEvent(slowEvents))
        #expect(fastTerminal == slowTerminal)
        #expect(slowTerminal.snapshot.processedEntries == 101)
        #expect(slowTerminal.coverage.reasons == [.maxBreadth])
    }

    @Test("zero subscribers retain no event backlog, only bounded final state")
    func zeroSubscribersHaveNoBacklog() async throws {
        let clock = SessionManualClock()
        let registry = ScanSessionRegistry(limits: try .init(maxSessions: 2,
            subscribersPerSession: 2, streamBuffer: 2, snapshotItems: 2),
            clock: clock.traversalClock)
        let sessionID = try await registry.begin(policyRevision: 1, batchesPerSecond: 4)
        for index in 1...100 {
            clock.advance(seconds: 1)
            try await registry.recordBatch(sessionID: sessionID,
                coverage: .init(isComplete: false, reasons: [.sliceExpired]),
                snapshot: snapshot(index))
        }
        #expect(await registry.snapshot().bufferedEvents == 0)
        try await registry.complete(sessionID: sessionID, terminal: .cancelled,
            coverage: .init(isComplete: false, reasons: [.cancelled]),
            snapshot: snapshot(100))
        let state = try await registry.state(sessionID: sessionID)
        #expect(state.terminal == .cancelled)
        #expect(state.snapshot.processedEntries == 100)
        let final = await registry.snapshot()
        #expect(final.bufferedEvents == 0)
        #expect(final.retainedTerminalStates == 1)
    }

    @Test("injected clock coalesces exactly at configured 1 2 3 and 4 batch rates",
          arguments: [1, 2, 3, 4])
    func exactConfiguredRates(rate: Int) async throws {
        let clock = SessionManualClock()
        let registry = ScanSessionRegistry(limits: try .init(maxSessions: 2,
            subscribersPerSession: 2, streamBuffer: 16, snapshotItems: 2),
            clock: clock.traversalClock)
        let sessionID = try await registry.begin(policyRevision: 1, batchesPerSecond: rate)
        let subscription = try await registry.subscribe(sessionID: sessionID)
        async let events = collect(subscription)
        var processed = 0
        try await registry.recordBatch(sessionID: sessionID,
            coverage: .init(isComplete: false, reasons: [.sliceExpired]),
            snapshot: snapshot(processed))
        let interval = (1_000_000_000 + UInt64(rate) - 1) / UInt64(rate)
        for _ in 0..<rate {
            clock.advance(nanoseconds: interval - 1)
            processed += 1
            try await registry.recordBatch(sessionID: sessionID,
                coverage: .init(isComplete: false, reasons: [.sliceExpired]),
                snapshot: snapshot(processed))
            clock.advance(nanoseconds: 1)
            processed += 1
            try await registry.recordBatch(sessionID: sessionID,
                coverage: .init(isComplete: false, reasons: [.sliceExpired]),
                snapshot: snapshot(processed))
        }
        try await registry.complete(sessionID: sessionID, terminal: .complete,
            coverage: .init(isComplete: true, reasons: []), snapshot: snapshot(processed + 1))

        let emitted = await events
        let progressCount = emitted.filter { if case .progress = $0.kind { return true }; return false }.count
        #expect(progressCount == rate + 1)
        #expect(emitted.last?.terminal == .complete)
    }

    @Test("non-cumulative or oversized snapshots reject without changing shared state")
    func cumulativeAndSnapshotBounds() async throws {
        let registry = ScanSessionRegistry(limits: try .init(maxSessions: 2,
            subscribersPerSession: 2, streamBuffer: 2, snapshotItems: 1,
            snapshotPathBytes: 64))
        let sessionID = try await registry.begin(policyRevision: 1, batchesPerSecond: 1)
        try await registry.recordBatch(sessionID: sessionID,
            coverage: .init(isComplete: false, reasons: [.sliceExpired]), snapshot: snapshot(2))
        await #expect(throws: ScanSessionRegistryError.nonCumulativeSnapshot) {
            try await registry.recordBatch(sessionID: sessionID,
                coverage: .init(isComplete: false, reasons: [.sliceExpired]), snapshot: snapshot(1))
        }
        await #expect(throws: ScanSessionRegistryError.snapshotLimit) {
            try await registry.recordBatch(sessionID: sessionID,
                coverage: .init(isComplete: false, reasons: [.sliceExpired]),
                snapshot: snapshot(3, items: [
                    RankedItem(path: "/a", bytes: 2), RankedItem(path: "/b", bytes: 1)
                ]))
        }
        await #expect(throws: ScanSessionRegistryError.snapshotLimit) {
            try await registry.recordBatch(sessionID: sessionID,
                coverage: .init(isComplete: false, reasons: [.sliceExpired]),
                snapshot: snapshot(3, items: [
                    RankedItem(path: "/" + String(repeating: "x", count: 64), bytes: 3)
                ]))
        }
        #expect(try await registry.state(sessionID: sessionID).snapshot == snapshot(2))
    }

    @Test("terminal kind and coverage cannot contradict one another")
    func terminalCoverageMustBeTruthful() async throws {
        let registry = ScanSessionRegistry()
        let sessionID = try await registry.begin(policyRevision: 1, batchesPerSecond: 1)

        await #expect(throws: ScanSessionRegistryError.invalidCoverage) {
            try await registry.complete(sessionID: sessionID, terminal: .complete,
                coverage: .init(isComplete: false, reasons: [.unreadable]), snapshot: snapshot(1))
        }
        await #expect(throws: ScanSessionRegistryError.invalidCoverage) {
            try await registry.complete(sessionID: sessionID, terminal: .partial,
                coverage: .init(isComplete: true, reasons: []), snapshot: snapshot(1))
        }
        await #expect(throws: ScanSessionRegistryError.invalidCoverage) {
            try await registry.complete(sessionID: sessionID, terminal: .cancelled,
                coverage: .init(isComplete: false, reasons: [.unreadable]), snapshot: snapshot(1))
        }
        #expect(try await registry.state(sessionID: sessionID).terminal == nil)
    }
}
