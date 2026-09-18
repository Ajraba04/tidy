import Foundation
import CoreServices
import Testing
@testable import TidyCore

/// Fully deterministic stand-in for FSEvents. Real delivery is asynchronous and coalesced by the
/// OS in ways that would make timing-based assertions flaky; this fake instead lets a test push
/// exactly the batch it wants, in the order it wants, and observe the result once `barrier()`
/// (or a direct `next()` drain) has had a chance to run.
actor FakeScanEventSource: ScanEventSource {
    private(set) var makeStreamCallCount = 0
    private(set) var lastResumeCursor: UInt64?
    private(set) var lastPersistedDeviceUUID: String?
    private var streams: [FakeScanEventStream] = []
    private var initialBatches: [ScanEventBatch?]

    init(initialBatches: [ScanEventBatch?] = []) {
        self.initialBatches = initialBatches
    }

    func makeStream(roots: [String], resumeCursor: UInt64?,
                    persistedDeviceUUID: String?) async -> any ScanEventStream {
        makeStreamCallCount += 1
        lastResumeCursor = resumeCursor
        lastPersistedDeviceUUID = persistedDeviceUUID
        let initial = initialBatches.isEmpty ? nil : initialBatches.removeFirst()
        let stream = FakeScanEventStream(resumeCursor: resumeCursor, initialBatch: initial)
        streams.append(stream)
        return stream
    }

    func streamCount() -> Int { streams.count }

    /// Delivers a batch to whichever stream is currently active (the most recently created one).
    func emit(events: [ScanEvent], historyReliable: Bool) async {
        guard let stream = streams.last else { return }
        await stream.enqueue(events: events, historyReliable: historyReliable)
    }

    /// Whether the most recently created stream has been stopped — lets a test assert the pump
    /// actually unwound rather than polling generation state and hoping.
    func lastStreamIsStopped() async -> Bool {
        guard let stream = streams.last else { return true }
        return await stream.stopped
    }

    func streamStopped(at index: Int) async -> Bool {
        guard streams.indices.contains(index) else { return true }
        return await streams[index].stopped
    }
}

actor FakeScanEventStream: ScanEventStream {
    private var pending: [ScanEventBatch] = []
    private var waiter: CheckedContinuation<ScanEventBatch, Never>?
    private var cursor: UInt64
    private var startupBatch: ScanEventBatch?
    private(set) var stopped = false
    private(set) var flushCount = 0

    init(resumeCursor: UInt64?, initialBatch: ScanEventBatch? = nil) {
        cursor = resumeCursor ?? 0
        startupBatch = initialBatch
    }

    func initialBatch() async -> ScanEventBatch? {
        defer { startupBatch = nil }
        return startupBatch
    }

    func enqueue(events: [ScanEvent], historyReliable: Bool) {
        guard !stopped else { return }
        cursor += 1
        let batch = ScanEventBatch(events: events, cursor: cursor, historyReliable: historyReliable)
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: batch)
        } else {
            pending.append(batch)
        }
    }

    func next() async -> ScanEventBatch {
        if stopped { return ScanEventBatch(events: [], cursor: cursor, historyReliable: true) }
        if !pending.isEmpty { return pending.removeFirst() }
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func flush() async -> UInt64 {
        flushCount += 1
        return cursor
    }

    /// Mirrors the production `FSEventsScanEventStream.stop()` contract: resumes any waiter
    /// parked in `next()` with a neutral batch and makes every later `next()` call resolve
    /// immediately, so a pump task blocked on `await stream.next()` is guaranteed to wake up and
    /// observe its own cancellation instead of leaking for the process lifetime.
    func stop() async {
        stopped = true
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: ScanEventBatch(events: [], cursor: cursor, historyReliable: true))
        }
    }
}

@Suite("T09 ScanInvalidation generation ledger")
struct ScanInvalidationTests {
    @Test func historyDoneMarkerIsNotTreatedAsFilesystemMutation() {
        #expect(!fsEventRepresentsMutation(
            FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)))
        #expect(fsEventRepresentsMutation(FSEventStreamEventFlags(
            kFSEventStreamEventFlagNone)))
    }
    @Test func liveDeliveryQueueIsBoundedAndOverflowFailsClosed() async {
        let box = FSEventsDeliveryBox()
        for cursor in 1...100 {
            box.deliver(ScanEventBatch(events: [ScanEvent(path: "/fixture/\(cursor)")],
                cursor: UInt64(cursor), historyReliable: true))
        }
        #expect(box.pendingBatchCountForTesting() <= 64)
        var sawUnreliable = false
        for _ in 0..<box.pendingBatchCountForTesting() {
            let batch = await box.next()
            if !batch.historyReliable { sawUnreliable = true }
            #expect(batch.events.count <= 4_096)
        }
        #expect(sawUnreliable)

        let oversized = (0..<4_100).map { ScanEvent(path: "/fixture/e\($0)") }
        box.deliver(ScanEventBatch(events: oversized, cursor: 101, historyReliable: true))
        let bounded = await box.next()
        #expect(bounded.events.isEmpty,
            "overflow collapses to a marker without retaining a discarded prefix")
        #expect(!bounded.historyReliable)
    }

    @Test("long callback paths are rejected before Swift bridging and pending bytes stay bounded")
    func longPathStormIsByteBoundedAndFailsClosed() async {
        let oversized = NSString(string: "/fixture/" + String(repeating: "x",
            count: FSEventsDeliveryBox.maximumUTF8BytesPerPath + 1))
        let callbackPaths: NSArray = Array(repeating: oversized, count: 8_192) as NSArray
        let converted = boundedFSEventCallbackPaths(callbackPaths, eventCount: 8_192)
        #expect(converted.events.isEmpty)
        #expect(converted.utf8Bytes == 0)
        #expect(converted.didOverflow)
        #expect(converted.convertedPathCount <= FSEventsDeliveryBox.maximumEventsPerBatch)

        let nearLimit = "/fixture/" + String(repeating: "y",
            count: FSEventsDeliveryBox.maximumUTF8BytesPerPath - 9)
        let batchOverflowBox = FSEventsDeliveryBox()
        let pathsToExceedBatchBytes =
            FSEventsDeliveryBox.maximumUTF8BytesPerBatch / nearLimit.utf8.count + 1
        batchOverflowBox.deliver(ScanEventBatch(
            events: Array(repeating: ScanEvent(path: nearLimit),
                count: pathsToExceedBatchBytes), cursor: 1, historyReliable: true))
        let batchOverflow = await batchOverflowBox.next()
        #expect(batchOverflow.events.isEmpty)
        #expect(!batchOverflow.historyReliable)

        let pendingOverflowBox = FSEventsDeliveryBox()
        let pathsPerRetainedBatch = max(1,
            FSEventsDeliveryBox.maximumUTF8BytesPerBatch / nearLimit.utf8.count / 2)
        let bytesPerRetainedBatch = pathsPerRetainedBatch * nearLimit.utf8.count
        let batchesToExceedPendingBytes =
            FSEventsDeliveryBox.maximumPendingUTF8Bytes / bytesPerRetainedBatch + 1
        for cursor in 1...batchesToExceedPendingBytes {
            pendingOverflowBox.deliver(ScanEventBatch(
                events: Array(repeating: ScanEvent(path: nearLimit),
                    count: pathsPerRetainedBatch),
                cursor: UInt64(cursor), historyReliable: true))
        }
        #expect(pendingOverflowBox.pendingUTF8BytesForTesting()
            <= FSEventsDeliveryBox.maximumPendingUTF8Bytes)
        #expect(pendingOverflowBox.pendingBatchCountForTesting() == 1)
        let overflow = await pendingOverflowBox.next()
        #expect(overflow.events.isEmpty)
        #expect(!overflow.historyReliable)
    }

    @Test("FSEvents startup requires cursor and both matching device identities")
    func startupHistoryTrustRequiresCompleteDeviceProof() {
        #expect(FSEventsStartupHistory.isReliable(resumeCursor: 9,
            persistedDeviceUUID: "device-a", liveDeviceUUID: "device-a", streamStarted: true))
        #expect(!FSEventsStartupHistory.isReliable(resumeCursor: 9,
            persistedDeviceUUID: nil, liveDeviceUUID: "device-a", streamStarted: true))
        #expect(!FSEventsStartupHistory.isReliable(resumeCursor: 9,
            persistedDeviceUUID: "device-a", liveDeviceUUID: nil, streamStarted: true))
        #expect(!FSEventsStartupHistory.isReliable(resumeCursor: 9,
            persistedDeviceUUID: "device-a", liveDeviceUUID: "device-b", streamStarted: true))
        #expect(!FSEventsStartupHistory.isReliable(resumeCursor: nil,
            persistedDeviceUUID: "device-a", liveDeviceUUID: "device-a", streamStarted: true))
    }

    @Test("suspension atomically rejects an event after expected-generation capture")
    func suspensionCheckpointCannotNormalizeInterleavingEvent() async {
        let root = "/fixture/root"
        let invalidation = ScanInvalidation(source: FakeScanEventSource())
        await invalidation.start(approvedRoots: [root], resumeCursor: 0,
            persistedDeviceUUID: "device-a")
        let expected = [root: await invalidation.currentGeneration(for: root)]
        let rejected = await invalidation.prepareManualContinuationSuspension(
            expectedGenerations: expected,
            interleavingBatchForTesting: ScanEventBatch(
                events: [ScanEvent(path: root + "/already-visited")], cursor: 1,
                historyReliable: true))
        #expect(rejected == nil)
        #expect(await invalidation.currentGeneration(for: root) == 1,
            "the event must remain visible, not be folded into a new checkpoint")
        await invalidation.stop()

        let clean = ScanInvalidation(source: FakeScanEventSource())
        await clean.start(approvedRoots: [root], resumeCursor: 0,
            persistedDeviceUUID: "device-a")
        let checkpoint = await clean.prepareManualContinuationSuspension(
            expectedGenerations: [root: 0])
        #expect(checkpoint?.generations[PathGuard.canonicalize(root)] == 1)
        #expect(await clean.isWatchActive() == false)
        await clean.stop()
    }
    @Test("a deeply changed descendant bumps the root's generation even though the root path itself never appears in the event")
    func deeplyChangedDescendantBumpsRootGeneration() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let root = "/tmp/fixture-root"
        await invalidation.start(approvedRoots: [root], resumeCursor: nil)
        #expect(await invalidation.currentGeneration(for: root) == 0)

        await source.emit(events: [ScanEvent(path: root + "/a/b/c/deep-file")], historyReliable: true)
        try await invalidation.barrier()
        #expect(await invalidation.currentGeneration(for: root) == 1)
    }

    @Test("an event on an unrelated path does not bump an unrelated approved root")
    func unrelatedEventDoesNotBumpOtherRoots() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let rootA = "/tmp/fixture-a"
        let rootB = "/tmp/fixture-b"
        await invalidation.start(approvedRoots: [rootA, rootB], resumeCursor: nil)

        await source.emit(events: [ScanEvent(path: rootA + "/child")], historyReliable: true)
        try await invalidation.barrier()
        #expect(await invalidation.currentGeneration(for: rootA) == 1)
        #expect(await invalidation.currentGeneration(for: rootB) == 0)
    }

    @Test("dropped/coalesced events mark history unreliable and invalidate every approved root, not just the reported one")
    func droppedEventsInvalidateEveryApprovedRoot() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let rootA = "/tmp/fixture-a"
        let rootB = "/tmp/fixture-b"
        await invalidation.start(approvedRoots: [rootA, rootB], resumeCursor: nil)

        await source.emit(events: [ScanEvent(path: rootA + "/child")], historyReliable: false)
        try await invalidation.barrier()
        #expect(await invalidation.currentGeneration(for: rootA) == 1)
        #expect(await invalidation.currentGeneration(for: rootB) == 1)
        #expect(await invalidation.isHistoryReliable() == false)
    }

    @Test("once history is unreliable it stays unreliable until a fresh start, so later reliable-looking batches still widen")
    func historyStaysUnreliableUntilRestart() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let rootA = "/tmp/fixture-a"
        let rootB = "/tmp/fixture-b"
        await invalidation.start(approvedRoots: [rootA, rootB], resumeCursor: nil)
        await source.emit(events: [], historyReliable: false)
        try await invalidation.barrier()

        await source.emit(events: [ScanEvent(path: rootA + "/child")], historyReliable: true)
        try await invalidation.barrier()
        #expect(await invalidation.currentGeneration(for: rootB) == 2,
            "rootB was never touched directly but must still widen while history is unreliable")

        await invalidation.start(approvedRoots: [rootA, rootB], resumeCursor: nil)
        #expect(await invalidation.isHistoryReliable() == true)
    }

    @Test("a volume unmount/mount flag is treated the same as a dropped event: invalidate all approved roots")
    func mountUnmountInvalidatesAllApprovedRoots() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let root = "/Volumes/External/Data"
        let other = "/Volumes/External/Other"
        await invalidation.start(approvedRoots: [root, other], resumeCursor: nil)
        // A real mount/unmount flag has no natural translation into a ScanEvent path; the
        // production FSEventsScanEventStream coarsens it into historyReliable == false on the
        // batch instead of trying to name an affected path, which is exactly what is simulated
        // here.
        await source.emit(events: [], historyReliable: false)
        try await invalidation.barrier()
        #expect(await invalidation.currentGeneration(for: root) == 1)
        #expect(await invalidation.currentGeneration(for: other) == 1)
    }

    @Test("explicit invalidateAllApprovedRoots covers root moves and policy/protected-root changes, which the event stream cannot name")
    func explicitInvalidateAllCoversMoveAndPolicyChange() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let root = "/tmp/fixture-root"
        await invalidation.start(approvedRoots: [root], resumeCursor: nil)
        await invalidation.invalidateAllApprovedRoots()
        #expect(await invalidation.currentGeneration(for: root) == 1)
    }

    @Test("resuming start() replays the persisted cursor into the event source")
    func startReplaysPersistedCursor() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        await invalidation.start(approvedRoots: ["/tmp/fixture-root"], resumeCursor: 500)
        #expect(await source.lastResumeCursor == 500)
        #expect(await invalidation.currentCursor() == 500)
    }

    @Test("the barrier drains events already accepted by the stream before returning")
    func barrierDrainsPendingEventsBeforeReturning() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let root = "/tmp/fixture-root"
        await invalidation.start(approvedRoots: [root], resumeCursor: nil)
        // Enqueue several batches back-to-back before ever draining: the pump may not have
        // consumed any of them yet when barrier() is called.
        await source.emit(events: [ScanEvent(path: root + "/x")], historyReliable: true)
        await source.emit(events: [ScanEvent(path: root + "/y")], historyReliable: true)
        await source.emit(events: [ScanEvent(path: root + "/z")], historyReliable: true)
        try await invalidation.barrier()
        #expect(await invalidation.currentGeneration(for: root) == 3)
    }

    @Test("lostHistoryCannotReuseCachedAuthority")
    func lostHistoryCannotReuseCachedAuthority() {
        #expect(InvalidationDecision.decide(historyReliable: false) == .allApprovedRoots)
        #expect(InvalidationDecision.decide(historyReliable: true) == .affectedRoot)
    }

    @Test("stop() deterministically halts the pump before returning: events emitted afterward are never applied")
    func stopHaltsThePump() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let root = "/tmp/fixture-root"
        await invalidation.start(approvedRoots: [root], resumeCursor: nil)
        let generationBeforeStop = await invalidation.currentGeneration(for: root)
        // `stop()` awaits the pump task's own completion (`await pumpTask?.value`) after
        // unblocking it via the stream's `stop()`, so by the time this call returns the pump is
        // guaranteed to have exited — no polling loop needed to make this assertion safe.
        await invalidation.stop()
        #expect(await source.lastStreamIsStopped())
        #expect(await invalidation.currentGeneration(for: root) == generationBeforeStop,
            "the neutral batch used to unblock a cancelled pump must not invalidate roots")
        await invalidation.invalidateRoot(root)
        #expect(await invalidation.currentGeneration(for: root) == generationBeforeStop + 1,
            "the ledger itself still works after stop(); only the event pump is gone")

        await source.emit(events: [ScanEvent(path: root + "/x")], historyReliable: true)
        #expect(await invalidation.currentGeneration(for: root) == generationBeforeStop + 1,
            "an event emitted after stop() has no running pump left to apply it")
    }

    @Test("starting a fresh watch stops the previous pump before the new one begins")
    func startStopsThePreviousPumpDeterministically() async throws {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let root = "/tmp/fixture-root"
        await invalidation.start(approvedRoots: [root], resumeCursor: nil)
        await invalidation.start(approvedRoots: [root], resumeCursor: nil)
        #expect(await source.streamCount() == 2)
        #expect(await source.streamStopped(at: 0),
            "the first stream must be fully stopped before the second start() returns")
        #expect(await source.streamStopped(at: 1) == false)
    }

    // MARK: - T09 review pass: fail-closed with no active watch

    @Test("an invalidation ledger with no active watch reports itself inactive")
    func watchInactiveUntilStarted() async {
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        #expect(await invalidation.isWatchActive() == false)
        await invalidation.start(approvedRoots: ["/tmp/fixture-root"], resumeCursor: nil)
        #expect(await invalidation.isWatchActive() == true)
        await invalidation.stop()
        #expect(await invalidation.isWatchActive() == false)
    }
}
