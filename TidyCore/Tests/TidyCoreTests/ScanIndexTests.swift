import Foundation
import Darwin
import Testing
@testable import TidyCore

/// A test-only device: two files with a supplied byte count, so a `ScanIndexKey` and a total can
/// be constructed without ever touching a real home directory.
private func makeFixtureRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanIndexTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(repeating: 7, count: 4_096).write(to: root.appendingPathComponent("a"))
    return root
}

private func makeStore() throws -> (URL, ScanIndexStore) {
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScanIndexTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("index.sqlite")
    return (dbURL, try ScanIndexStore(databaseURL: dbURL))
}

private func makeKey(root: URL) -> ScanIndexKey {
    guard let identity = ScanRootIdentity.resolve(path: root.path) else {
        fatalError("fixture root must resolve an identity")
    }
    return ScanIndexKey(volumeUUID: identity.volumeUUID, rootIdentity: identity.fileIdentity,
        scannerVersion: 1, policyFingerprint: "fp-1")
}

private func makeRecord(key: ScanIndexKey, totalBytes: Int64 = 4_096, isComplete: Bool = true,
                        generation: UInt64 = 0, cursor: UInt64 = 0) -> ScanAggregateRecord {
    ScanAggregateRecord(key: key, totalBytes: totalBytes, processedEntries: 1,
        isComplete: isComplete, reasons: [], generation: generation, cursor: cursor,
        updatedAt: Date())
}

private actor CatchupOnFlushSource: ScanEventSource {
    let stream: CatchupOnFlushStream
    init(changedPath: String, cursor: UInt64) {
        stream = CatchupOnFlushStream(changedPath: changedPath, cursor: cursor)
    }
    func makeStream(roots: [String], resumeCursor: UInt64?, persistedDeviceUUID: String?) async
      -> any ScanEventStream { stream }
}

private actor CatchupOnFlushStream: ScanEventStream {
    let changedPath: String
    let cursor: UInt64
    var waiter: CheckedContinuation<ScanEventBatch, Never>?
    var delivered = false
    var pendingDelivery = false
    var stopped = false

    init(changedPath: String, cursor: UInt64) {
        self.changedPath = changedPath
        self.cursor = cursor
    }

    func next() async -> ScanEventBatch {
        if stopped {
            return ScanEventBatch(events: [], cursor: cursor, historyReliable: true)
        }
        if pendingDelivery {
            pendingDelivery = false
            return ScanEventBatch(events: [ScanEvent(path: changedPath)], cursor: cursor,
                historyReliable: true)
        }
        return await withCheckedContinuation { waiter = $0 }
    }

    func flush() async -> UInt64 {
        guard !delivered else { return cursor }
        delivered = true
        let pending = waiter
        waiter = nil
        if let pending {
            pending.resume(returning: ScanEventBatch(
                events: [ScanEvent(path: changedPath)], cursor: cursor, historyReliable: true))
        } else {
            pendingDelivery = true
        }
        return cursor
    }

    func stop() async {
        stopped = true
        let pending = waiter
        waiter = nil
        pending?.resume(returning: ScanEventBatch(events: [], cursor: cursor,
            historyReliable: true))
    }
}

@Suite("T09 ScanIndex durable aggregate cache")
struct ScanIndexTests {
    @Test("app-owned cache rejects links for every SQLite family file without touching the witness",
          arguments: ["", "-wal", "-shm", "-journal"], [false, true])
    func appOwnedCacheRejectsLinkedDatabaseFamilyWithoutTouchingOutsideWitness(
        suffix: String, hardLink: Bool
    ) throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyR07IndexSafety-\(UUID().uuidString)", isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("scan-index", isDirectory: true)
        let database = cacheDirectory.appendingPathComponent("cache.sqlite")
        let linkedArtifact = URL(fileURLWithPath: database.path + suffix)
        let outside = root.appendingPathComponent("outside-witness")
        let witness = Data("must remain byte-identical".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: cacheDirectory,
            withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try witness.write(to: outside)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = hardLink
            ? link(outside.path, linkedArtifact.path)
            : symlink(outside.path, linkedArtifact.path)
        #expect(result == 0)
        #expect(throws: ScanIndexError.unsafeLocation) {
            _ = try ScanIndexStore.openAppOwned(databaseURL: database)
        }
        #expect(throws: ScanIndexError.unsafeLocation) {
            _ = try ScanIndexStore.recoverAppOwned(databaseURL: database)
        }
        #expect(try Data(contentsOf: outside) == witness)
        var info = stat()
        #expect(lstat(linkedArtifact.path, &info) == 0,
            "recovery must preserve the rejected linked artifact for diagnosis")
    }

    @Test func appOwnedCacheRejectsUnsafeDirectoryWithoutTouchingOutsideWitness() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyR07IndexDirectory-\(UUID().uuidString)", isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("scan-index", isDirectory: true)
        let database = cacheDirectory.appendingPathComponent("cache.sqlite")
        let witness = Data("unsafe directory witness".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: cacheDirectory,
            withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        try witness.write(to: database)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: ScanIndexError.unsafeLocation) {
            _ = try ScanIndexStore.openAppOwned(databaseURL: database)
        }
        #expect(throws: ScanIndexError.unsafeLocation) {
            _ = try ScanIndexStore.recoverAppOwned(databaseURL: database)
        }
        #expect(try Data(contentsOf: database) == witness)
    }

    @Test func appOwnedCacheRejectsSymlinkedDirectoryWithoutTouchingOutsideWitness() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("TidyR07IndexDirectoryLink-\(UUID().uuidString)", isDirectory: true)
        let outsideDirectory = root.appendingPathComponent("outside", isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("scan-index", isDirectory: true)
        let database = cacheDirectory.appendingPathComponent("cache.sqlite")
        let outsideDatabase = outsideDirectory.appendingPathComponent("cache.sqlite")
        let witness = Data("outside directory witness".utf8)
        try FileManager.default.createDirectory(at: outsideDirectory,
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try witness.write(to: outsideDatabase)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(symlink(outsideDirectory.path, cacheDirectory.path) == 0)

        #expect(throws: ScanIndexError.unsafeLocation) {
            _ = try ScanIndexStore.openAppOwned(databaseURL: database)
        }
        #expect(throws: ScanIndexError.unsafeLocation) {
            _ = try ScanIndexStore.recoverAppOwned(databaseURL: database)
        }
        #expect(try Data(contentsOf: outsideDatabase) == witness)
    }
    // MARK: - ScanRootIdentity: pinning the String(describing:) assumption (T09 review item 8)

    @Test("resolveIsStableAndDistinguishesFiles")
    func resolveIsStableAndDistinguishesFiles() throws {
        let a = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: a) }
        let b = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: b) }

        let firstResolve = try #require(ScanRootIdentity.resolve(path: a.path))
        let secondResolve = try #require(ScanRootIdentity.resolve(path: a.path))
        #expect(firstResolve == secondResolve,
            "resolving the same path twice must produce an identical identity")

        let otherFile = try #require(ScanRootIdentity.resolve(path: b.path))
        #expect(otherFile.fileIdentity != firstResolve.fileIdentity,
            "two different files on the same volume must never collide to the same identity")
        #expect(otherFile.volumeUUID == firstResolve.volumeUUID,
            "two fixtures under the same temporary directory share one volume")

        #expect(ScanRootIdentity.resolve(path: a.path + "/does-not-exist") == nil,
            "a missing path must resolve to nil, never a substitute identity")
    }

    // MARK: - Storage primitives

    @Test("a fresh store has no record for any key")
    func freshStoreHasNoRecord() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        #expect(try await store.record(for: key) == nil)
    }

    @Test("commit then read round-trips every field")
    func commitRoundTrips() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let record = makeRecord(key: key, totalBytes: 12_345, generation: 3, cursor: 9)
        _ = try await store.commit(record)
        let fetched = try await store.record(for: key)
        #expect(fetched?.totalBytes == 12_345)
        #expect(fetched?.generation == 3)
        #expect(fetched?.cursor == 9)
        #expect(fetched?.isComplete == true)
    }

    @Test("partial scans never replace a previously complete record")
    func partialCannotReplaceComplete() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        _ = try await store.commit(makeRecord(key: key, totalBytes: 500, isComplete: true))
        await #expect(throws: ScanIndexError.partialCannotReplaceComplete) {
            _ = try await store.commit(makeRecord(key: key, totalBytes: 1, isComplete: false))
        }
        let stillComplete = try await store.record(for: key)
        #expect(stillComplete?.totalBytes == 500)
        #expect(stillComplete?.isComplete == true)
    }

    @Test("a partial record can still be recorded when nothing complete exists yet")
    func partialRecordedWhenNoCompleteExists() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        _ = try await store.commit(makeRecord(key: key, totalBytes: 77, isComplete: false))
        let fetched = try await store.record(for: key)
        #expect(fetched?.totalBytes == 77)
        #expect(fetched?.isComplete == false)
    }

    @Test("a corrupted database file is reported, never silently treated as empty")
    func corruptedDatabaseIsReported() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("index.sqlite")
        try Data("not a sqlite database".utf8).write(to: dbURL)

        await #expect(throws: ScanIndexError.corrupted) {
            _ = try ScanIndexStore(databaseURL: dbURL)
        }
        // The sanctioned recovery path: delete and reopen fresh.
        let recovered = try ScanIndexStore.recover(databaseURL: dbURL)
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try await recovered.record(for: makeKey(root: root)) == nil)
    }

    @Test("bounded eviction keeps the database at or under its configured cap")
    func evictionEnforcesCap() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        for index in 0..<200 {
            let root = try makeFixtureRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            var key = makeKey(root: root)
            key = ScanIndexKey(volumeUUID: key.volumeUUID, rootIdentity: key.rootIdentity,
                scannerVersion: 1, policyFingerprint: "fp-\(index)")
            _ = try await store.commit(makeRecord(key: key, totalBytes: Int64(index)))
        }
        // Comfortably above the WAL-mode `-shm` file's own fixed minimum footprint (typically one
        // 32 KiB index page that persists regardless of how many rows remain) plus a few schema
        // pages of the main database file — the point of this test is that eviction actually
        // shrinks the file via `incremental_vacuum`, not that it hits an exact byte count.
        let cap: Int64 = 131_072
        _ = try await store.evictToFit(capBytes: cap)
        #expect(try await store.diskUsageBytes() <= cap)
    }

    @Test("cursor and device UUID persist independently of any aggregate record")
    func cursorPersistence() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        #expect(try await store.persistedCursor(volumeUUID: "vol-1") == nil)
        try await store.persistCursor(volumeUUID: "vol-1", cursor: 42, deviceUUID: "device-a")
        #expect(try await store.persistedCursor(volumeUUID: "vol-1") == 42)
        #expect(try await store.persistedDeviceUUID(volumeUUID: "vol-1") == "device-a")
        // A later cursor update with a nil device UUID must not erase the one already stored.
        try await store.persistCursor(volumeUUID: "vol-1", cursor: 43, deviceUUID: nil)
        #expect(try await store.persistedCursor(volumeUUID: "vol-1") == 43)
        #expect(try await store.persistedDeviceUUID(volumeUUID: "vol-1") == "device-a")
    }

    // MARK: - Coordinator: generation/barrier publication protocol

    @Test("persisted generation collision after unreliable restart requires a fresh baseline")
    func unreliableRestartCannotReuseCollidingGeneration() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let stale = makeRecord(key: key, totalBytes: 111, generation: 1, cursor: 40)
        _ = try await store.commit(stale, volumeUUID: key.volumeUUID, cursor: 40,
            deviceUUID: "device-a")
        let source = FakeScanEventSource(initialBatches: [ScanEventBatch(events: [], cursor: 41,
            historyReliable: false)])
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))

        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        #expect(await coordinator.beginScan(root: root.path) == 1,
            "the fixture must reproduce the old process-local generation collision")
        #expect(await coordinator.status(for: key, root: root.path) != .cached(stale))

        let generation = await coordinator.beginScan(root: root.path)
        let refreshed = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 222,
            processedEntries: 2, isComplete: true, reasons: [])
        guard case .committed(let record) = refreshed else {
            Issue.record("fresh complete baseline was not committed: \(refreshed)"); return
        }
        #expect(await coordinator.status(for: key, root: root.path) == .cached(record))
    }

    @Test("status drains pending historical catch-up before returning a cached aggregate")
    func statusCannotRaceHistoricalCatchup() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let cached = makeRecord(key: key, totalBytes: 111, generation: 0, cursor: 40)
        _ = try await store.commit(cached, volumeUUID: key.volumeUUID, cursor: 40,
            deviceUUID: "device-a")
        let source = CatchupOnFlushSource(
            changedPath: root.appendingPathComponent("a").path, cursor: 41)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)

        guard case .stale(let record) = await coordinator.status(for: key, root: root.path) else {
            Issue.record("pending catch-up event was not drained before cache status"); return
        }
        #expect(record == cached)
    }

    @Test("cursor without persisted device identity requires a fresh baseline")
    func missingPersistedDeviceIdentityCannotReuseCache() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let stale = makeRecord(key: key, totalBytes: 111, generation: 1, cursor: 40)
        _ = try await store.commit(stale, volumeUUID: key.volumeUUID, cursor: 40,
            deviceUUID: nil)
        let source = FakeScanEventSource(initialBatches: [ScanEventBatch(events: [], cursor: 41,
            historyReliable: false)])
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))

        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        #expect(await source.lastResumeCursor == 40)
        #expect(await source.lastPersistedDeviceUUID == nil)
        #expect(await coordinator.status(for: key, root: root.path) != .cached(stale))
        let generation = await coordinator.beginScan(root: root.path)
        let refreshed = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 222,
            processedEntries: 2, isComplete: true, reasons: [])
        guard case .committed(let record) = refreshed else {
            Issue.record("fresh complete baseline was not committed: \(refreshed)"); return
        }
        #expect(await coordinator.status(for: key, root: root.path) == .cached(record))
    }

    @Test("unavailable live device identity cannot grant cache trust across restart")
    func unavailableLiveDeviceIdentityRequiresFreshBaselineAfterRestart() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let first = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: FakeScanEventSource()),
            deviceUUIDProvider: { _ in nil })
        await first.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        let firstGeneration = await first.beginScan(root: root.path)
        guard case .committed = await first.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: firstGeneration, totalBytes: 111,
            processedEntries: 1, isComplete: true, reasons: []) else {
            Issue.record("initial baseline failed"); return
        }
        #expect(try await store.persistedDeviceUUID(volumeUUID: key.volumeUUID) == nil)
        await first.stopWatching()

        let source = FakeScanEventSource(initialBatches: [ScanEventBatch(events: [], cursor: 1,
            historyReliable: false)])
        let restarted = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source), deviceUUIDProvider: { _ in nil })
        await restarted.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        guard case .cached = await restarted.status(for: key, root: root.path) else {
            let generation = await restarted.beginScan(root: root.path)
            let refreshed = await restarted.commitIfCurrent(key: key, root: root.path,
                volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 222,
                processedEntries: 2, isComplete: true, reasons: [])
            guard case .committed(let record) = refreshed else {
                Issue.record("fresh baseline after missing device proof failed: \(refreshed)"); return
            }
            #expect(await restarted.status(for: key, root: root.path) == .cached(record))
            return
        }
        Issue.record("restart reused a record without live/persisted device identity proof")
    }

    @Test("event ID wrap cannot collide with and reuse a persisted generation")
    func eventIDWrapRequiresFreshBaselineBeforeReuse() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let stale = makeRecord(key: key, totalBytes: 111, generation: 1, cursor: 40)
        _ = try await store.commit(stale, volumeUUID: key.volumeUUID, cursor: 40,
            deviceUUID: "device-a")
        let source = FakeScanEventSource(initialBatches: [ScanEventBatch(events: [], cursor: 1,
            historyReliable: false)])
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))

        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        #expect(await coordinator.beginScan(root: root.path) == stale.generation)
        #expect(await coordinator.status(for: key, root: root.path) != .cached(stale))
        let generation = await coordinator.beginScan(root: root.path)
        let refreshed = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 222,
            processedEntries: 2, isComplete: true, reasons: [])
        guard case .committed(let record) = refreshed else {
            Issue.record("fresh baseline after wrap failed: \(refreshed)"); return
        }
        #expect(await coordinator.status(for: key, root: root.path) == .cached(record))
    }

    @Test("failed FSEvents startup stays uncacheable even after a complete fresh walk")
    func failedWatchStartupCannotEstablishReusableBaseline() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let stale = makeRecord(key: key, totalBytes: 111, generation: 1, cursor: 40)
        _ = try await store.commit(stale, volumeUUID: key.volumeUUID, cursor: 40,
            deviceUUID: "device-a")
        let source = FakeScanEventSource(initialBatches: [ScanEventBatch(events: [], cursor: 41,
            historyReliable: false, deliveryAvailable: false)])
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))

        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        #expect(await coordinator.status(for: key, root: root.path)
            == .unavailable(.watchInactive))
        let generation = await coordinator.beginScan(root: root.path)
        #expect(await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 222,
            processedEntries: 2, isComplete: true, reasons: [])
            == .unavailable(.watchInactive))
        #expect(await coordinator.status(for: key, root: root.path)
            == .unavailable(.watchInactive))
    }

    @Test("an event for an already visited file during manual-Continue idle fails closed")
    func changedVisitedFileDuringContinuationGapCannotResumeRetainedTotals() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let changedFile = root.appendingPathComponent("a").path
        let source = FakeScanEventSource(initialBatches: [nil,
            ScanEventBatch(events: [ScanEvent(path: changedFile)], cursor: 1,
                historyReliable: true)])
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        let generation = await coordinator.beginScan(root: root.path)
        guard case .committed = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 4_096,
            processedEntries: 1, isComplete: true, reasons: []) else {
            Issue.record("baseline failed"); return
        }

        #expect(await coordinator.suspendWatchingForManualContinuation())
        #expect(await coordinator.isWatchActiveForTesting() == false)
        #expect(await coordinator.resumeWatchingForManualContinuation() == nil,
            "changed bytes accumulated before the gap must never survive Continue")
        #expect(await coordinator.isWatchActiveForTesting() == false)
    }

    @Test("an event after catch-up but before continuation publication invalidates the guard")
    func eventAfterContinuationResumeCannotPublishRetainedTotals() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let source = FakeScanEventSource(initialBatches: [nil,
            ScanEventBatch(events: [], cursor: 0, historyReliable: true)])
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: ScanInvalidation(source: source))
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        let generation = await coordinator.beginScan(root: root.path)
        guard case .committed = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 4_096,
            processedEntries: 1, isComplete: true, reasons: []) else {
            Issue.record("baseline failed"); return
        }
        #expect(await coordinator.suspendWatchingForManualContinuation())
        let continuationGuard = try #require(
            await coordinator.resumeWatchingForManualContinuation())

        await source.emit(events: [ScanEvent(path: root.appendingPathComponent("a").path)],
            historyReliable: true)
        #expect(await coordinator.consumeContinuationGuard(continuationGuard) == false)
    }

    @Test("commit succeeds and status reports cached when nothing invalidated the root")
    func commitSucceedsWhenGenerationUnchanged() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)

        let generation = await coordinator.beginScan(root: root.path)
        let outcome = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 4_096,
            processedEntries: 1, isComplete: true, reasons: [])
        guard case .committed(let record) = outcome else {
            Issue.record("expected committed, got \(outcome)")
            return
        }
        #expect(record.totalBytes == 4_096)
        let status = await coordinator.status(for: key, root: root.path)
        #expect(status == .cached(record))
    }

    @Test("invalidation immediately before commit retains stale, does not overwrite fresh totals")
    func invalidationBeforeCommitRetainsStale() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)

        // Seed a prior complete record so we can tell "left alone" from "overwritten".
        let generation1 = await coordinator.beginScan(root: root.path)
        let seeded = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation1, totalBytes: 1_000,
            processedEntries: 1, isComplete: true, reasons: [])
        guard case .committed = seeded else { Issue.record("seed failed"); return }

        let generation2 = await coordinator.beginScan(root: root.path)
        // An event lands on the root after the scan captured its generation but before commit.
        await source.emit(events: [ScanEvent(path: root.path)], historyReliable: true)
        let outcome = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation2, totalBytes: 999_999,
            processedEntries: 1, isComplete: true, reasons: [])
        #expect(outcome == .staleGeneration)

        let stored = try await store.record(for: key)
        #expect(stored?.totalBytes == 1_000, "the stale attempt must never overwrite the prior total")
        let status = await coordinator.status(for: key, root: root.path)
        guard case .stale(let record) = status else {
            Issue.record("expected stale, got \(status)")
            return
        }
        #expect(record.totalBytes == 1_000)
    }

    @Test("dropped events during the barrier are treated as history loss, not silently ignored")
    func droppedEventsDuringBarrierForceStale() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let unrelated = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: unrelated) }
        let key = makeKey(root: root)
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path, unrelated.path],
            volumeUUID: key.volumeUUID)

        let generation = await coordinator.beginScan(root: root.path)
        // A batch that reports it could not guarantee delivery (a coalesced/dropped event),
        // touching a completely unrelated root. Because history is no longer reliable, every
        // approved root — including the one being scanned — must be treated as touched.
        await source.emit(events: [ScanEvent(path: unrelated.path)], historyReliable: false)
        let outcome = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 1,
            processedEntries: 1, isComplete: true, reasons: [])
        #expect(outcome == .staleGeneration)
    }

    @Test("lostHistoryCannotReuseCachedAuthority")
    func lostHistoryCannotReuseCachedAuthority() {
        #expect(InvalidationDecision.decide(historyReliable: false) == .allApprovedRoots)
        #expect(InvalidationDecision.decide(historyReliable: true) == .affectedRoot)
    }

    @Test("indexing disabled reports unavailable and never starts a watch")
    func indexingDisabledIsExplicitlyUnavailable() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .disabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        #expect(await source.streamCount() == 0)
        #expect(await coordinator.status(for: key, root: root.path) == .unavailable(.indexingDisabled))
        let generation = await coordinator.beginScan(root: root.path)
        let outcome = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 1,
            processedEntries: 1, isComplete: true, reasons: [])
        #expect(outcome == .unavailable(.indexingDisabled))
    }

    @Test("an expired record is reported unavailable, never presented as cached")
    func expiredRecordIsUnavailable() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let ancient = ScanAggregateRecord(key: key, totalBytes: 10, processedEntries: 1,
            isComplete: true, reasons: [], generation: 0, cursor: 0,
            updatedAt: Date(timeIntervalSinceNow: -999_999))
        _ = try await store.commit(ancient)
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation, maximumAge: 60)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)
        #expect(await coordinator.status(for: key, root: root.path) == .unavailable(.expired))
    }

    @Test("a failed commit leaves both the aggregate and the volume cursor exactly as they were")
    func commitFailureLeavesAggregateAndCursorUnchanged() async throws {
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)

        let generation = await coordinator.beginScan(root: root.path)
        let seeded = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 500,
            processedEntries: 1, isComplete: true, reasons: [])
        guard case .committed = seeded else { Issue.record("seed failed"); return }
        let cursorAfterSeed = try await store.persistedCursor(volumeUUID: key.volumeUUID)

        // A partial result attempting to replace the just-committed complete one: `commit`
        // rejects this deep inside the same transaction that would otherwise also have written
        // the cursor. Per the T09 contract this is ONE transaction covering both tables, so a
        // rejection here must leave neither the aggregate nor the cursor touched — there is no
        // "aggregate committed, cursor pending" window to simulate separately any more.
        let generation2 = await coordinator.beginScan(root: root.path)
        let outcome = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation2, totalBytes: 999_999,
            processedEntries: 1, isComplete: false, reasons: [])
        #expect(outcome == .rejectedPartialOverComplete)

        let stored = try await store.record(for: key)
        #expect(stored?.totalBytes == 500, "the aggregate must be exactly as the seed left it")
        #expect(try await store.persistedCursor(volumeUUID: key.volumeUUID) == cursorAfterSeed,
            "the cursor must be exactly as the seed left it")
    }

    @Test("a successful commit durably persists the aggregate and the cursor/device UUID together")
    func successfulCommitPersistsAggregateAndCursorTogether() async throws {
        let (dbURL, store) = try makeStore()
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = makeKey(root: root)
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: key.volumeUUID)

        let generation = await coordinator.beginScan(root: root.path)
        let outcome = await coordinator.commitIfCurrent(key: key, root: root.path,
            volumeUUID: key.volumeUUID, capturedGeneration: generation, totalBytes: 4_096,
            processedEntries: 1, isComplete: true, reasons: [])
        guard case .committed = outcome else { Issue.record("commit failed: \(outcome)"); return }
        await store.close()

        // Reopening a fresh handle on the same file proves both writes actually reached disk in
        // the one transaction, not merely the in-memory actor state this test already trusts.
        let reopened = try ScanIndexStore(databaseURL: dbURL)
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let record = try await reopened.record(for: key)
        #expect(record?.totalBytes == 4_096)
        let cursor = try await reopened.persistedCursor(volumeUUID: key.volumeUUID)
        #expect(cursor != nil)
        #expect(try await reopened.persistedDeviceUUID(volumeUUID: key.volumeUUID) != nil,
            "commitIfCurrent must persist the live device UUID, not always nil")
    }

    // MARK: - HomeSurvey integration: reference-equals-incremental and visit reduction

    /// A small but non-trivial fixture tree: enough nesting/fan-out that a real walk performs
    /// far more than one metadata visit, so the ≥80%-reduction assertion below is meaningful
    /// without needing anything close to a literal 100k entries.
    private func makeNestedFixture() throws -> (root: URL, totalBytes: Int64) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanIndexTests-nested-\(UUID().uuidString)", isDirectory: true)
        var total: Int64 = 0
        for i in 0..<6 {
            let child = root.appendingPathComponent("child-\(i)", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            for j in 0..<6 {
                let file = child.appendingPathComponent("file-\(j)")
                let bytes = Data(repeating: UInt8(j + 1), count: 4_096)
                try bytes.write(to: file)
                total += Int64(bytes.count)
            }
        }
        return (root, total)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    @Test("an unchanged tree served from the index matches a fresh reference walk exactly")
    func indexedResultMatchesFreshReferenceWalk() async throws {
        let (root, _) = try makeNestedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: "vol-nested")

        let reference = HomeSurvey.walk(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false)

        let first = await HomeSurvey.walkIndexed(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false, scannerVersion: 1,
            policyFingerprint: "fp", coordinator: coordinator)
        #expect(first.source == .freshCommitted)
        #expect(first.result.totalBytes == reference.totalBytes)

        // Second call, nothing changed: must come from the cache and still match exactly.
        let second = await HomeSurvey.walkIndexed(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false, scannerVersion: 1,
            policyFingerprint: "fp", coordinator: coordinator)
        #expect(second.source == .cached)
        #expect(second.result.totalBytes == reference.totalBytes)
    }

    @Test("a change deep in the tree invalidates the cache and the next walk again matches a fresh reference")
    func indexedResultMatchesReferenceAfterDeepChange() async throws {
        let (root, _) = try makeNestedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: "vol-nested")

        _ = await HomeSurvey.walkIndexed(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false, scannerVersion: 1,
            policyFingerprint: "fp", coordinator: coordinator)

        let deepFile = root.appendingPathComponent("child-0/file-0")
        try Data(repeating: 9, count: 50_000).write(to: deepFile)
        await source.emit(events: [ScanEvent(path: root.appendingPathComponent("child-0").path)],
            historyReliable: true)
        try await invalidation.barrier()

        let reference = HomeSurvey.walk(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false)
        let afterChange = await HomeSurvey.walkIndexed(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false, scannerVersion: 1,
            policyFingerprint: "fp", coordinator: coordinator)
        #expect(afterChange.source == .freshCommitted)
        #expect(afterChange.result.totalBytes == reference.totalBytes)
    }

    @Test("the unchanged case reduces metadata visits by at least 80% versus a fresh walk")
    func unchangedCaseReducesMetadataVisitsSubstantially() async throws {
        let (root, _) = try makeNestedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: "vol-nested")

        let freshCounter = Counter()
        _ = await HomeSurvey.walkIndexed(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false, scannerVersion: 1,
            policyFingerprint: "fp", coordinator: coordinator,
            visitCounter: { freshCounter.increment() })
        let freshVisits = freshCounter.count
        #expect(freshVisits > 10, "the fixture must be large enough for the comparison to be meaningful")

        let cachedCounter = Counter()
        let cached = await HomeSurvey.walkIndexed(root: root.path, protectedRoots: [],
            largeFileThreshold: 0, breakOutChildren: false, scannerVersion: 1,
            policyFingerprint: "fp", coordinator: coordinator,
            visitCounter: { cachedCounter.increment() })
        #expect(cached.source == .cached)
        let reduction = 1.0 - (Double(cachedCounter.count) / Double(freshVisits))
        #expect(reduction >= 0.8)
    }

    @Test("policy fingerprint change is an independent record, never read as the old fingerprint's cache")
    func policyFingerprintChangeIsIndependentRecord() async throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: "vol-1")

        let oldKey = makeKey(root: root)
        let generation = await coordinator.beginScan(root: root.path)
        _ = await coordinator.commitIfCurrent(key: oldKey, root: root.path, volumeUUID: "vol-1",
            capturedGeneration: generation, totalBytes: 4_096, processedEntries: 1,
            isComplete: true, reasons: [])

        let newKey = ScanIndexKey(volumeUUID: oldKey.volumeUUID, rootIdentity: oldKey.rootIdentity,
            scannerVersion: oldKey.scannerVersion, policyFingerprint: "fp-changed")
        #expect(await coordinator.status(for: newKey, root: root.path) == .unavailable(.noRecord))
        #expect(await coordinator.status(for: oldKey, root: root.path) != .unavailable(.noRecord))
    }

    @Test("a moved root is not silently trusted: only an explicit invalidateAllApprovedRoots call protects it")
    func movedRootRequiresExplicitInvalidation() async throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store,
            invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [root.path], volumeUUID: "vol-1")

        let key = makeKey(root: root)
        let generation = await coordinator.beginScan(root: root.path)
        _ = await coordinator.commitIfCurrent(key: key, root: root.path, volumeUUID: "vol-1",
            capturedGeneration: generation, totalBytes: 4_096, processedEntries: 1,
            isComplete: true, reasons: [])

        // The app layer detects the move (a rename, a different root under the same key) and
        // must widen invalidation explicitly, since the scoped watch's own events cannot be
        // trusted to name the exact affected path across a rename.
        await coordinator.invalidateAllApprovedRoots()
        let status = await coordinator.status(for: key, root: root.path)
        guard case .stale = status else {
            Issue.record("expected stale after an explicit move invalidation, got \(status)")
            return
        }
    }

    // MARK: - T09 review pass: the cache must actually be consulted by ScanEngine, not just fed

    /// `HomeSurvey.walkBounded` (what `ScanEngine.runRegistered` actually calls) has no injectable
    /// visit counter — that seam only exists on the synchronous `HomeSurvey.walk`/`walkIndexed`
    /// path used by the unit tests above. So the proof here is structural instead: a fresh walk
    /// is the only way `topLevelHomeRanking` can ever be non-empty (per-child totals are never
    /// persisted to the cache — only the aggregate total is), so an unchanged second scan
    /// reporting an EMPTY ranking while the first scan reported a non-empty one is exactly as
    /// strong a proof that the walk was skipped as a visit-counter drop would be.
    @Test("a second ScanEngine.start on an unchanged fixture serves the home root from the index, skipping its walk entirely")
    @MainActor
    func secondScanServesHomeRootFromCacheEndToEnd() async throws {
        let rig = try await TraversalBridgeRig.make()
        let documents = rig.root.appendingPathComponent("Documents", isDirectory: true)
        let library = rig.root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 32_768).write(to: documents.appendingPathComponent("fixture.bin"))

        let (dbURL, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let source = FakeScanEventSource()
        let invalidation = ScanInvalidation(source: source)
        let coordinator = ScanIndexCoordinator(mode: .enabled, store: store, invalidation: invalidation)
        await coordinator.startWatching(approvedRoots: [rig.root.path, library.path],
            volumeUUID: "engine-integration-volume")

        let registry = ScanSessionRegistry()
        let environment = CleanEnvironment(homeDirectory: rig.root.path, detectedTools: [],
            gitRoots: [], protectedRoots: [])
        let dependencies = CoreScanDependencies(processProbe: { _, _ in .availableEmpty },
            testHook: nil)

        func runOneScan() async throws -> CoreScanResult {
            let handle = try await ScanEngine.start(environment: environment, registry: registry,
                sessions: rig.sessions, session: rig.session, dependencies: dependencies,
                indexCoordinator: coordinator)
            let subscription = try await registry.subscribe(sessionID: handle.sessionID)
            for await event in subscription.stream where event.terminal != nil { break }
            return try #require(await handle.latestResult())
        }

        let first = try await runOneScan()
        #expect(first.coverage.isComplete)
        #expect(!first.report.topLevelHomeRanking.isEmpty,
            "the first scan must have actually walked home to find the Documents fixture")
        guard case .cached(let firstRecord) = first.indexStatus else {
            Issue.record("expected the first scan to publish a cached record, got \(String(describing: first.indexStatus))")
            return
        }
        #expect(firstRecord.totalBytes >= 32_768)

        let second = try await runOneScan()
        #expect(second.coverage.isComplete)
        #expect(second.report.topLevelHomeRanking.isEmpty,
            "an empty ranking on the unchanged second scan proves the home walk was skipped")
        #expect(second.indexStatus == first.indexStatus,
            "a served-from-cache scan reads back exactly the record the first scan committed")

        await rig.cleanup()
    }
}
