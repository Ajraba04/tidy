import CoreServices
import Darwin
import Foundation

/// The contract's own decision table: once a watch has lost reliable history
/// (a wrap, an unavailable log, a dropped-and-reattached stream), a single
/// affected root can no longer be trusted as the invalidation boundary —
/// every approved root must be treated as touched. This is intentionally the
/// only place that decision is made.
public enum InvalidationDecision: Equatable, Sendable {
    case affectedRoot, allApprovedRoots

    public static func decide(historyReliable: Bool) -> Self {
        historyReliable ? .affectedRoot : .allApprovedRoots
    }
}

/// One coalesced filesystem-change notification. `path` is whatever the
/// underlying watch reports as touched — for FSEvents that is a directory,
/// not necessarily the exact descendant that changed, which is why
/// invalidation always widens to the containing approved root rather than
/// trying to diff a single file.
public struct ScanEvent: Equatable, Sendable {
    public let path: String
    public init(path: String) { self.path = path }
}

/// A batch of events plus the watch's own judgment of its history. A source
/// that cannot prove it delivered every event since `resumeCursor` (a wrap, a
/// coalesced drop it detected, an unavailable persisted history) must report
/// `historyReliable == false` on the batch that discovers this — never as a
/// side channel the caller might forget to check.
public struct ScanEventBatch: Sendable {
    public let events: [ScanEvent]
    public let cursor: UInt64
    public let historyReliable: Bool
    /// Separate from retained-history reliability: false means no live delivery channel exists
    /// (for example FSEventStreamCreate/Start failed). A fresh walk cannot make such a watch safe
    /// for later reuse because subsequent mutations would remain invisible.
    public let deliveryAvailable: Bool

    public init(events: [ScanEvent], cursor: UInt64, historyReliable: Bool,
                deliveryAvailable: Bool = true) {
        self.events = events
        self.cursor = cursor
        self.historyReliable = historyReliable
        self.deliveryAvailable = deliveryAvailable
    }
}

/// The injectable seam standing in for FSEvents. Production wires
/// `FSEventsScanEventSource`; tests wire a fully deterministic fake so
/// dropped/coalesced/reordered events, history loss and unmount can be
/// asserted exactly rather than raced against the real OS log.
public protocol ScanEventSource: Sendable {
    /// `persistedDeviceUUID`, when the caller has one on file for the volume being watched, lets
    /// the source detect that the volume was reformatted or swapped while unwatched. It is read
    /// fresh on every call (from `ScanIndexStore`) rather than baked into the source at
    /// construction time, since a source instance can outlive many `start`/`stop` cycles across
    /// different volumes and persisted values.
    func makeStream(roots: [String], resumeCursor: UInt64?,
                    persistedDeviceUUID: String?) async -> any ScanEventStream
}

/// One running scoped watch. `flush` is the event-delivery barrier the
/// generation protocol drains before publication: it must guarantee every
/// event the OS has already accepted becomes visible through `next()` at or
/// before the cursor it returns.
public protocol ScanEventStream: Sendable {
    func initialBatch() async -> ScanEventBatch?
    func next() async -> ScanEventBatch
    func flush() async -> UInt64
    func stop() async
}

public extension ScanEventStream {
    func initialBatch() async -> ScanEventBatch? { nil }
}

public enum ScanInvalidationError: Error, Equatable, Sendable {
    /// The barrier could not confirm the pump had drained to the flushed
    /// watermark within a bounded number of yields. Fails closed: callers
    /// must treat this the same as a generation mismatch, never as fresh.
    case barrierTimedOut
}

struct ScanInvalidationSuspensionCheckpoint: Equatable, Sendable {
    let cursor: UInt64
    let generations: [String: UInt64]
}

/// Owns per-root generations and the single running event watch. A scan
/// captures a generation before it starts; any event (or loss of history)
/// touching that root bumps the generation before the scan's commit can
/// observe it as still current.
public actor ScanInvalidation {
    private let source: any ScanEventSource
    private var approvedRoots: [String] = []
    private var generations: [String: UInt64] = [:]
    /// Complete baselines established under the currently running watch. This is separate from
    /// the process-local generation counter: an unreliable restart can legitimately increment a
    /// new actor from zero to the same value persisted by an older process, and equality alone
    /// must never turn that collision into cache trust.
    private var trustedBaselineGenerations: [String: UInt64] = [:]
    private var historyReliable = true
    private var deliveryAvailable = true
    private var appliedCursor: UInt64 = 0
    private var stream: (any ScanEventStream)?
    private var pumpTask: Task<Void, Never>?
    /// True only between a successful `start()` and the next `stop()`/restart. Freshness reads
    /// (`ScanIndexCoordinator.status`/`commitIfCurrent`) must fail closed while this is false —
    /// with no running watch, `currentGeneration` never moves, so a bare "generation unchanged"
    /// check would otherwise report `.cached` forever even though nothing is being invalidated.
    private var watchActive = false

    public init(source: any ScanEventSource) {
        self.source = source
    }

    /// Starts (or restarts) the scoped watch over `roots`. Per contract this
    /// must be called before the baseline traversal begins, with whatever
    /// cursor was durably persisted from the previous run. A nil
    /// `resumeCursor` means no usable history exists yet (first run, or the
    /// index could not read one) and the source itself will normally answer
    /// with `historyReliable == false` on its first batch in that case.
    /// `persistedDeviceUUID`, when known, lets the event source detect a volume that was
    /// reformatted or swapped while unwatched (see `FSEventsScanEventStream`).
    public func start(approvedRoots roots: [String], resumeCursor: UInt64?,
                      persistedDeviceUUID: String? = nil) async {
        await stopCurrentWatch()
        // Canonicalized once here so every other entry point (`currentGeneration`,
        // `invalidateRoot`, and event matching in `apply`) compares against the same form a
        // caller's own canonicalization (e.g. `PathGuard.canonicalize` in `HomeSurvey.walkIndexed`)
        // produces. Without this, a root passed here as `/var/folders/...` would never match
        // generation lookups keyed by its resolved `/private/var/folders/...` form.
        approvedRoots = roots.map(PathGuard.canonicalize)
        for root in approvedRoots where generations[root] == nil {
            generations[root] = 0
        }
        trustedBaselineGenerations.removeAll()
        // A fresh watch has not yet proven anything unreliable; the sticky flag only exists to
        // survive across events *within* one watch's lifetime, never across a restart.
        historyReliable = true
        deliveryAvailable = true
        appliedCursor = resumeCursor ?? 0
        let newStream = await source.makeStream(roots: roots, resumeCursor: resumeCursor,
            persistedDeviceUUID: persistedDeviceUUID)
        stream = newStream
        if let initial = await newStream.initialBatch() { apply(initial) }
        watchActive = deliveryAvailable
        pumpTask = Task { [weak self] in await self?.pump(newStream) }
    }

    public func stop() async {
        await stopCurrentWatch()
    }

    public func isWatchActive() -> Bool { watchActive }

    /// Cancels the pump task, stops the stream (which must resume any waiter parked in the
    /// stream's own `next()` with a neutral, no-op batch — see `FSEventsDeliveryBox.stopDelivery`
    /// / `FakeScanEventStream.stop`), and then actually waits for the pump task to finish. Task
    /// cancellation is cooperative: without both the stream unblocking `next()` and this explicit
    /// `await pumpTask?.value`, a pump parked mid-`await stream.next()` would never notice it was
    /// cancelled and would leak for the lifetime of the process.
    private func stopCurrentWatch() async {
        pumpTask?.cancel()
        await stream?.stop()
        await pumpTask?.value
        pumpTask = nil
        stream = nil
        watchActive = false
    }

    /// The generation a scan of `root` must re-check at commit time. Canonicalizes `root` so a
    /// caller passing either a raw or already-resolved path form lands on the same bucket.
    public func currentGeneration(for root: String) -> UInt64 {
        generations[PathGuard.canonicalize(root), default: 0]
    }

    public func currentCursor() -> UInt64 { appliedCursor }

    /// A persisted generation is usable only while this watch has reliable history, or after a
    /// complete walk under this exact watch established a new trusted baseline. The latter lets a
    /// conservative startup recover useful caching without ever trusting a colliding counter.
    public func isCacheGenerationTrusted(for root: String, generation: UInt64) -> Bool {
        guard watchActive else { return false }
        let canonical = PathGuard.canonicalize(root)
        guard generations[canonical, default: 0] == generation else { return false }
        return historyReliable || trustedBaselineGenerations[canonical] == generation
    }

    /// Marks a freshly completed traversal as the baseline for this watch. A late event cannot
    /// race this into trust: the generation must still match when this actor receives the mark.
    public func establishCompleteBaseline(for root: String, generation: UInt64) {
        guard watchActive else { return }
        let canonical = PathGuard.canonicalize(root)
        guard generations[canonical, default: 0] == generation else { return }
        trustedBaselineGenerations[canonical] = generation
    }

    /// Explicit widening for signals the event stream itself cannot carry:
    /// a moved/replaced root, a changed policy/protected-root set, an
    /// unmounted or swapped volume. All of these invalidate every approved
    /// root, matching `InvalidationDecision.decide(historyReliable: false)`.
    public func invalidateAllApprovedRoots() {
        for root in approvedRoots {
            trustedBaselineGenerations.removeValue(forKey: root)
            generations[root, default: 0] += 1
        }
    }

    public func invalidateRoot(_ root: String) {
        let canonical = PathGuard.canonicalize(root)
        trustedBaselineGenerations.removeValue(forKey: canonical)
        generations[canonical, default: 0] += 1
    }

    /// Drains the event-delivery barrier: forces the stream to flush,
    /// then waits until the pump has applied everything up to that
    /// watermark. Bounded so a stuck pump fails closed instead of hanging
    /// a commit forever.
    public func barrier(maxYields: Int = 10_000) async throws {
        guard let stream else { return }
        let target = await stream.flush()
        var iterations = 0
        while appliedCursor < target {
            guard iterations < maxYields else { throw ScanInvalidationError.barrierTimedOut }
            iterations += 1
            await Task.yield()
        }
    }

    /// Closes event-application admission and captures the continuation checkpoint in one actor
    /// turn. The caller flushes first; after that flush, an event is either already applied and
    /// fails `expectedGenerations`, or remains after `appliedCursor` and is replayed on resume.
    /// There is no suspension point between final validation, invalidation, capture, and pump
    /// cancellation, so an applied event cannot be normalized into the new checkpoint.
    func prepareManualContinuationSuspension(
        expectedGenerations: [String: UInt64]?,
        interleavingBatchForTesting: ScanEventBatch? = nil
    ) -> ScanInvalidationSuspensionCheckpoint? {
        if let interleavingBatchForTesting { apply(interleavingBatchForTesting) }
        guard watchActive, deliveryAvailable else { return nil }
        if let expectedGenerations {
            guard historyReliable else { return nil }
            for (root, generation) in expectedGenerations {
                guard generations[PathGuard.canonicalize(root), default: 0] == generation else {
                    return nil
                }
            }
        }
        invalidateAllApprovedRoots()
        let captured = Dictionary(uniqueKeysWithValues: approvedRoots.map {
            ($0, generations[$0, default: 0])
        })
        let checkpoint = ScanInvalidationSuspensionCheckpoint(cursor: appliedCursor,
            generations: captured)
        watchActive = false
        pumpTask?.cancel()
        return checkpoint
    }

    private func pump(_ stream: any ScanEventStream) async {
        while !Task.isCancelled {
            let batch = await stream.next()
            guard !Task.isCancelled else { break }
            apply(batch)
        }
    }

    private func apply(_ batch: ScanEventBatch) {
        if !batch.deliveryAvailable {
            deliveryAvailable = false
            watchActive = false
        }
        if !batch.historyReliable {
            historyReliable = false
        }
        switch InvalidationDecision.decide(historyReliable: historyReliable) {
        case .allApprovedRoots:
            invalidateAllApprovedRoots()
        case .affectedRoot:
            for event in batch.events {
                // `approvedRoots` is already canonical (set in `start`); the event path is
                // canonicalized here so a raw FSEvents-reported path (or a fixture path with an
                // unresolved `/var`-vs-`/private/var` style symlink) still matches.
                let eventPath = PathGuard.canonicalize(event.path)
                for root in approvedRoots
                where PathGuard.isEqualOrDescendant(eventPath, of: root)
                    || PathGuard.isEqualOrDescendant(root, of: eventPath) {
                    generations[root, default: 0] += 1
                }
            }
        }
        appliedCursor = max(appliedCursor, batch.cursor)
    }

    /// Test/diagnostic-only: whether the watch currently believes its own
    /// history is unbroken. Once false it stays false until `start` is
    /// called again with a fresh watch.
    public func isHistoryReliable() -> Bool { historyReliable }
}

// MARK: - Production event source

/// The real, scoped FSEvents watch. Every OS signal that could mean "an
/// event might have been missed" — a kernel/user drop, a moved or replaced
/// root, a mount/unmount, a device whose FSEvents UUID no longer matches
/// what was persisted for this volume — is coarsened into
/// `historyReliable == false` on the batch that carries it. `ScanInvalidation`
/// already treats that as "invalidate every approved root", which is the one
/// response that stays safe when the log can no longer prove nothing was
/// missed. This class is intentionally not exercised by the deterministic
/// test suite: real FSEvents delivery is inherently nondeterministic, so RED
/// and GREEN coverage for the generation/barrier protocol is written against
/// a fake `ScanEventSource` instead. Callers still get real behavior in
/// production because `ScanIndexCoordinator` accepts any `ScanEventSource`.
public final class FSEventsScanEventSource: ScanEventSource, @unchecked Sendable {
    public init() {}

    /// `persistedDeviceUUID` should be whatever `ScanIndexStore` last saved for this volume (see
    /// `ScanIndexStore.persistedDeviceUUID`). A mismatch against the live value means the
    /// retained event history belongs to a different volume incarnation (reformat, swapped disk).
    public func makeStream(roots: [String], resumeCursor: UInt64?,
                           persistedDeviceUUID: String?) async -> any ScanEventStream {
        FSEventsScanEventStream(roots: roots, resumeCursor: resumeCursor,
            persistedDeviceUUID: persistedDeviceUUID)
    }

    /// The live FSEvents device UUID for the volume containing `path`, so a
    /// caller can persist it and later detect a swapped/reformatted volume.
    public static func currentDeviceUUID(forPathOnVolume path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        guard let cfUUID = FSEventsCopyUUIDForDevice(dev_t(info.st_dev)) else { return nil }
        guard let cfString = CFUUIDCreateString(nil, cfUUID) else { return nil }
        return cfString as String
    }
}

/// Bridges the C callback (no captures allowed) to Swift async consumers.
/// Every mutation is behind a lock because FSEvents calls back on its own
/// dispatch queue while `next()`/`flush()` are called from actor tasks.
final class FSEventsDeliveryBox: @unchecked Sendable {
    static let maximumPendingBatches = 64
    static let maximumEventsPerBatch = 4_096
    static let maximumUTF8BytesPerPath = 4_096
    static let maximumUTF8BytesPerBatch = 1 * 1_024 * 1_024
    static let maximumPendingUTF8Bytes = 8 * 1_024 * 1_024
    private let lock = NSLock()
    private var pending: [ScanEventBatch] = []
    private var pendingUTF8Bytes = 0
    private var overflowMarkerPending = false
    private var waiter: CheckedContinuation<ScanEventBatch, Never>?
    private var lastCursor: UInt64 = 0
    private var stopped = false

    func deliver(_ batch: ScanEventBatch) {
        let bounded = Self.bound(batch)
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        lastCursor = max(lastCursor, bounded.batch.cursor)
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: bounded.batch)
        } else {
            let (nextBytes, bytesOverflow) = pendingUTF8Bytes.addingReportingOverflow(
                bounded.utf8Bytes)
            if overflowMarkerPending || bounded.didOverflow
                || pending.count >= Self.maximumPendingBatches || bytesOverflow
                || nextBytes > Self.maximumPendingUTF8Bytes {
                collapseToOverflowMarker()
            } else {
                pending.append(bounded.batch)
                pendingUTF8Bytes = nextBytes
            }
            lock.unlock()
        }
    }

    private static func bound(_ batch: ScanEventBatch)
      -> (batch: ScanEventBatch, utf8Bytes: Int, didOverflow: Bool) {
        guard batch.events.count <= maximumEventsPerBatch else {
            return (ScanEventBatch(events: [], cursor: batch.cursor, historyReliable: false,
                deliveryAvailable: batch.deliveryAvailable), 0, true)
        }
        var bytes = 0
        for event in batch.events {
            let pathBytes = event.path.utf8.count
            guard pathBytes <= maximumUTF8BytesPerPath else {
                return (ScanEventBatch(events: [], cursor: batch.cursor,
                    historyReliable: false, deliveryAvailable: batch.deliveryAvailable), 0, true)
            }
            let (next, overflow) = bytes.addingReportingOverflow(pathBytes)
            guard !overflow, next <= maximumUTF8BytesPerBatch else {
                return (ScanEventBatch(events: [], cursor: batch.cursor,
                    historyReliable: false, deliveryAvailable: batch.deliveryAvailable), 0, true)
            }
            bytes = next
        }
        return (batch, bytes, false)
    }

    private func collapseToOverflowMarker() {
        pending = [ScanEventBatch(events: [], cursor: lastCursor, historyReliable: false)]
        pendingUTF8Bytes = 0
        overflowMarkerPending = true
    }

    /// One locked section decides everything: either a batch is already pending and the
    /// continuation resumes immediately, or none is and it is parked as `waiter` for `deliver`
    /// to resume later. There is deliberately no separate synchronous fast-path in front of this
    /// — an earlier version checked-then-unlocked-then-relocked, which held the lock correctly
    /// but left the "am I about to wait or not" decision split across two independent critical
    /// sections for no benefit.
    func next() async -> ScanEventBatch {
        await withCheckedContinuation { continuation in
            lock.lock()
            if stopped {
                let cursor = lastCursor
                lock.unlock()
                continuation.resume(returning: ScanEventBatch(events: [], cursor: cursor,
                    historyReliable: true))
            } else if !pending.isEmpty {
                let batch = pending.removeFirst()
                if overflowMarkerPending {
                    overflowMarkerPending = false
                } else {
                    pendingUTF8Bytes = max(0, pendingUTF8Bytes
                        - batch.events.reduce(0) { $0 + $1.path.utf8.count })
                }
                lock.unlock()
                continuation.resume(returning: batch)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    func snapshotCursor() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return lastCursor
    }

    func pendingBatchCountForTesting() -> Int {
        lock.lock(); defer { lock.unlock() }
        return pending.count
    }

    func pendingUTF8BytesForTesting() -> Int {
        lock.lock(); defer { lock.unlock() }
        return pendingUTF8Bytes
    }

    /// Unblocks a pump parked in `next()` and makes every subsequent `next()` call resolve
    /// immediately with a neutral (no events, reliable) batch instead of parking forever. Task
    /// cancellation alone cannot do this — cancelling `pumpTask` only sets a flag the pump checks
    /// *between* iterations, and a pump suspended inside this box's continuation would otherwise
    /// never wake up to observe it.
    func stopDelivery() {
        lock.lock()
        stopped = true
        let toResume = waiter
        waiter = nil
        let cursor = lastCursor
        lock.unlock()
        toResume?.resume(returning: ScanEventBatch(events: [], cursor: cursor, historyReliable: true))
    }
}

struct BoundedFSEventCallbackPaths {
    let events: [ScanEvent]
    let utf8Bytes: Int
    let didOverflow: Bool
    let convertedPathCount: Int
}

/// Reads at most the accepted callback prefix and checks the NSString byte length before creating
/// any Swift String. This avoids the old `NSArray as? [String]` bridge, which converted every
/// callback path before the event-count cap was applied.
func boundedFSEventCallbackPaths(_ paths: NSArray, eventCount: Int)
  -> BoundedFSEventCallbackPaths {
    guard eventCount >= 0 else {
        return .init(events: [], utf8Bytes: 0, didOverflow: true, convertedPathCount: 0)
    }
    let limit = min(eventCount, FSEventsDeliveryBox.maximumEventsPerBatch)
    var events: [ScanEvent] = []
    events.reserveCapacity(limit)
    var bytes = 0
    var converted = 0
    var overflow = eventCount > limit || paths.count < limit
    guard !overflow else {
        return .init(events: [], utf8Bytes: 0, didOverflow: true, convertedPathCount: 0)
    }
    for index in 0..<limit {
        guard let path = paths.object(at: index) as? NSString else {
            overflow = true
            break
        }
        let pathBytes = path.lengthOfBytes(using: String.Encoding.utf8.rawValue)
        guard pathBytes <= FSEventsDeliveryBox.maximumUTF8BytesPerPath else {
            overflow = true
            break
        }
        let (next, byteOverflow) = bytes.addingReportingOverflow(pathBytes)
        guard !byteOverflow, next <= FSEventsDeliveryBox.maximumUTF8BytesPerBatch else {
            overflow = true
            break
        }
        events.append(ScanEvent(path: path as String))
        converted += 1
        bytes = next
    }
    if overflow {
        return .init(events: [], utf8Bytes: 0, didOverflow: true,
            convertedPathCount: converted)
    }
    return .init(events: events, utf8Bytes: bytes, didOverflow: false,
        convertedPathCount: converted)
}

enum FSEventsStartupHistory {
    static func isReliable(resumeCursor: UInt64?, persistedDeviceUUID: String?,
                           liveDeviceUUID: String?, streamStarted: Bool) -> Bool {
        guard resumeCursor != nil, streamStarted,
              let persistedDeviceUUID, let liveDeviceUUID else { return false }
        return persistedDeviceUUID == liveDeviceUUID
    }
}

private final class FSEventsScanEventStream: ScanEventStream, @unchecked Sendable {
    private let box = FSEventsDeliveryBox()
    private let queue = DispatchQueue(label: "com.tidy.scanindex.fsevents")
    private let flushQueue = DispatchQueue(label: "com.tidy.scanindex.fsevents.flush")
    private let streamLock = NSLock()
    private var streamRef: FSEventStreamRef?
    private var initial: ScanEventBatch?

    init(roots: [String], resumeCursor: UInt64?, persistedDeviceUUID: String?) {
        let liveDeviceUUID = roots.first.flatMap(
            FSEventsScanEventSource.currentDeviceUUID(forPathOnVolume:))

        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let sinceWhen: FSEventStreamEventId = resumeCursor.map { FSEventStreamEventId($0) }
            ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        // `UseCFTypes` is required for `eventPaths` to arrive as a `CFArray` of `CFString`
        // (bridged to `NSArray` in the callback below) rather than a raw `char**`.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagNoDefer)
        let created = FSEventStreamCreate(nil, fsEventsScanCallback, &context,
            roots as CFArray, sinceWhen, 0.2, flags)
        streamRef = created
        var streamStarted = false
        if let created {
            FSEventStreamSetDispatchQueue(created, queue)
            streamStarted = FSEventStreamStart(created)
        }
        let reliable = FSEventsStartupHistory.isReliable(resumeCursor: resumeCursor,
            persistedDeviceUUID: persistedDeviceUUID, liveDeviceUUID: liveDeviceUUID,
            streamStarted: streamStarted)
        // The pump's very first read reports the resolved reliability so a
        // caller that never sees a real event before its barrier still
        // learns the truth.
        initial = ScanEventBatch(events: [],
            cursor: resumeCursor ?? UInt64(FSEventsGetCurrentEventId()),
            historyReliable: reliable, deliveryAvailable: streamStarted)
    }

    func initialBatch() async -> ScanEventBatch? {
        defer { initial = nil }
        return initial
    }

    func next() async -> ScanEventBatch { await box.next() }

    func flush() async -> UInt64 {
        // `FSEventStreamFlushSync` blocks its calling thread until the OS has delivered every
        // buffered event; running it directly on whatever cooperative-pool thread `flush()`
        // resumed on could starve that pool. It also must not run on the stream's callback queue:
        // when events are pending, FlushSync waits for callbacks that need that queue and would
        // deadlock. A separate serial queue confines the block while delivery remains runnable.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            flushQueue.async { [self] in
                streamLock.lock()
                if let streamRef { FSEventStreamFlushSync(streamRef) }
                streamLock.unlock()
                continuation.resume()
            }
        }
        return box.snapshotCursor()
    }

    func stop() async {
        // Unblock the pump first: `stopDelivery()` is safe to call even if nothing is parked.
        box.stopDelivery()
        let stoppedStream = streamLock.withLock { () -> FSEventStreamRef? in
            defer { streamRef = nil }
            return streamRef
        }
        guard let streamRef = stoppedStream else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
    }
}

/// The FSEvents C callback. No Swift captures are allowed here — everything
/// it needs travels through `clientCallBackInfo`.
private func fsEventsScanCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let box = Unmanaged<FSEventsDeliveryBox>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self)
    let unreliableMask = FSEventStreamEventFlags(
        kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagUserDropped
        | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount
        | kFSEventStreamEventFlagUnmount | kFSEventStreamEventFlagMustScanSubDirs
        | kFSEventStreamEventFlagEventIdsWrapped)
    let eventLimit = min(numEvents, 4_096)
    let converted = boundedFSEventCallbackPaths(paths, eventCount: numEvents)
    var events: [ScanEvent] = []
    events.reserveCapacity(converted.events.count)
    var reliable = !converted.didOverflow
    let maxID = numEvents > 0 ? UInt64(eventIds[numEvents - 1]) : 0
    for index in 0..<eventLimit {
        let flag = eventFlags[index]
        if flag & unreliableMask != 0 { reliable = false }
        // Catch-up completion names the watched root but is not a filesystem mutation.
        // Invalidating it makes every restarted real stream reject an unchanged cache record.
        if !fsEventRepresentsMutation(flag) { continue }
        if converted.events.indices.contains(index) { events.append(converted.events[index]) }
    }
    if converted.didOverflow { events.removeAll(keepingCapacity: false) }
    box.deliver(ScanEventBatch(events: events, cursor: maxID, historyReliable: reliable))
}

internal func fsEventRepresentsMutation(_ flags: FSEventStreamEventFlags) -> Bool {
    flags & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) == 0
}
