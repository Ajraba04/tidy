import Foundation
import SQLite3

/// Identifies one cacheable aggregate. `rootIdentity` must be a stable
/// identifier for the root directory itself (a file ID, not a path), so a
/// rename/move within the same volume does not fabricate a fresh, empty
/// history for what is really the same tree. `scannerVersion` and
/// `policyFingerprint` are part of the key, not a validity check on a shared
/// record: a scanner upgrade or a protected-root/policy change gets its own
/// row rather than silently reusing bytes measured under different rules.
public struct ScanIndexKey: Hashable, Sendable {
    public let volumeUUID: String
    public let rootIdentity: String
    public let scannerVersion: Int
    public let policyFingerprint: String

    public init(volumeUUID: String, rootIdentity: String, scannerVersion: Int,
                policyFingerprint: String) {
        self.volumeUUID = volumeUUID
        self.rootIdentity = rootIdentity
        self.scannerVersion = scannerVersion
        self.policyFingerprint = policyFingerprint
    }

    var compositeID: String {
        [volumeUUID, rootIdentity, String(scannerVersion), policyFingerprint]
            .joined(separator: "\u{1F}")
    }
}

/// Aggregate-only: totals, coverage and freshness. Never a path list. This is
/// the entire reason the record is safe to treat as non-authoritative — there
/// is nothing here a caller could mistake for a target to act on.
public struct ScanAggregateRecord: Equatable, Sendable {
    public let key: ScanIndexKey
    public let totalBytes: Int64
    public let processedEntries: Int
    public let isComplete: Bool
    public let reasons: Set<String>
    public let generation: UInt64
    public let cursor: UInt64
    public let updatedAt: Date

    public init(key: ScanIndexKey, totalBytes: Int64, processedEntries: Int, isComplete: Bool,
                reasons: Set<String>, generation: UInt64, cursor: UInt64, updatedAt: Date) {
        self.key = key
        self.totalBytes = totalBytes
        self.processedEntries = processedEntries
        self.isComplete = isComplete
        self.reasons = reasons
        self.generation = generation
        self.cursor = cursor
        self.updatedAt = updatedAt
    }
}

public enum ScanIndexUnavailableReason: Equatable, Sendable {
    case indexingDisabled
    case noRecord
    case expired
    case corrupted
    case evicted
    /// Indexing is enabled and a record may even exist, but nothing is currently watching for
    /// changes (`startWatching` was never called, or the watch was stopped/died) — a "generation
    /// unchanged" comparison is meaningless without a running watch to have moved it, so this is
    /// reported instead of ever trusting a record as `.cached`.
    case watchInactive
}

/// Everything a caller may ever learn from the cache: freshness/coverage
/// metadata, never a target list and never plan-input authority.
public enum ScanIndexStatus: Equatable, Sendable {
    /// Present and, as far as the invalidation ledger can tell, still
    /// event-consistent through the recorded watermark.
    case cached(ScanAggregateRecord)
    /// Present, but an event (or a loss of history) touching this root
    /// arrived after it was recorded. Still shown, explicitly marked stale.
    case stale(ScanAggregateRecord)
    case unavailable(ScanIndexUnavailableReason)
}

public enum ScanIndexError: Error, Equatable, Sendable {
    case openFailed(String)
    case corrupted
    case statementFailed(String)
    case partialCannotReplaceComplete
}

/// Outcome of one commit attempt through the generation/barrier protocol.
public enum ScanIndexCommitOutcome: Equatable, Sendable {
    case committed(ScanAggregateRecord)
    /// The root's generation moved since the scan captured it. The stored
    /// record (if any) is left untouched and reported `.stale`; the caller
    /// is expected to reschedule bounded work rather than treat this as
    /// success or failure.
    case staleGeneration
    case rejectedPartialOverComplete
    case unavailable(ScanIndexUnavailableReason)
}

/// The sole SQLite authority for the aggregate cache. One file, WAL mode, one
/// actor serializing every access — there is no scenario where two callers
/// touch the handle concurrently. Every SQLite return code is checked; a
/// mismatch never silently proceeds.
public actor ScanIndexStore {
    private var db: OpaquePointer?
    private let databaseURL: URL

    /// Opens (creating if absent) the database at `databaseURL`. Throws
    /// `.corrupted` rather than crashing or quietly starting empty when the
    /// file exists but SQLite cannot open or validate it — the caller
    /// decides whether to recover by deleting and recreating.
    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(handle)
            throw ScanIndexError.openFailed(message)
        }
        // Deliberately routed through `nonisolated static` helpers that take `opened` explicitly
        // rather than the instance `exec(_:)`/`checkIntegrity()`/`createSchema()` used everywhere
        // else: `db` is assigned two lines below this comment, but an actor's own stored property
        // isn't a safe handle to isolated instance methods until the initializer has finished
        // constructing `self`, so calling `self.exec` here would be calling into this actor's
        // isolation from a context that is not yet actually isolated. Passing `opened` as a plain
        // parameter sidesteps the question entirely instead of relying on initializer-phase
        // isolation rules.
        db = opened
        do {
            // Required for `evictToFit`'s `incremental_vacuum` to actually shrink the file: SQLite
            // only reclaims freed pages back into the filesystem when auto_vacuum is enabled, and
            // the setting is baked into the database header by whichever write initializes it —
            // `PRAGMA journal_mode=WAL` counts. So this must be the very first statement on a
            // fresh database, before WAL mode and before `createSchema`; on an existing database
            // it is a harmless no-op.
            try Self.execStatement("PRAGMA auto_vacuum = INCREMENTAL;", on: opened)
            try Self.execStatement("PRAGMA journal_mode=WAL;", on: opened)
            try Self.execStatement("PRAGMA synchronous=NORMAL;", on: opened)
            try Self.execStatement("PRAGMA foreign_keys=ON;", on: opened)
            try Self.checkIntegrity(on: opened)
            try Self.createSchema(on: opened)
        } catch {
            sqlite3_close_v2(opened)
            db = nil
            throw ScanIndexError.corrupted
        }
    }

    /// Deletes the database (and its WAL/SHM siblings) and reopens fresh.
    /// The one sanctioned response to a detected corruption: never patch a
    /// damaged file in place.
    public static func recover(databaseURL: URL) throws -> ScanIndexStore {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let path = databaseURL.path + suffix
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
        return try ScanIndexStore(databaseURL: databaseURL)
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    public func close() {
        if let db {
            sqlite3_close_v2(db)
        }
        db = nil
    }

    /// init-only: takes the raw handle explicitly instead of reading `self.db`, since these run
    /// before `self` is available as an isolated actor instance. See the comment in `init`.
    nonisolated private static func checkIntegrity(on db: OpaquePointer) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check;", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0),
              String(cString: text) == "ok" else {
            throw ScanIndexError.corrupted
        }
    }

    /// init-only: see `checkIntegrity(on:)`.
    nonisolated private static func createSchema(on db: OpaquePointer) throws {
        try execStatement("""
        CREATE TABLE IF NOT EXISTS scan_records (
            composite_id TEXT PRIMARY KEY,
            volume_uuid TEXT NOT NULL,
            root_identity TEXT NOT NULL,
            scanner_version INTEGER NOT NULL,
            policy_fingerprint TEXT NOT NULL,
            total_bytes INTEGER NOT NULL,
            processed_entries INTEGER NOT NULL,
            is_complete INTEGER NOT NULL,
            reasons TEXT NOT NULL,
            generation INTEGER NOT NULL,
            cursor INTEGER NOT NULL,
            updated_at REAL NOT NULL
        );
        """, on: db)
        try execStatement("CREATE INDEX IF NOT EXISTS scan_records_updated_at ON scan_records(updated_at);",
            on: db)
        try execStatement("""
        CREATE TABLE IF NOT EXISTS volume_watch (
            volume_uuid TEXT PRIMARY KEY,
            cursor INTEGER NOT NULL,
            device_uuid TEXT
        );
        """, on: db)
        try execStatement("""
        CREATE TABLE IF NOT EXISTS index_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """, on: db)
        try execStatement("INSERT OR IGNORE INTO index_meta(key, value) VALUES ('schema_version', '1');",
            on: db)
    }

    /// init-only: see `checkIntegrity(on:)`. Every other actor method uses the instance
    /// `exec(_:)` below, which reads `self.db` from within an already-isolated context.
    nonisolated private static func execStatement(_ sql: String, on db: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw ScanIndexError.statementFailed(message)
        }
    }

    private func exec(_ sql: String) throws {
        guard let db else { throw ScanIndexError.corrupted }
        try Self.execStatement(sql, on: db)
    }

    // MARK: - Records

    public func record(for key: ScanIndexKey) throws -> ScanAggregateRecord? {
        guard let db else { throw ScanIndexError.corrupted }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = """
        SELECT total_bytes, processed_entries, is_complete, reasons, generation, cursor, updated_at
        FROM scan_records WHERE composite_id = ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ScanIndexError.statementFailed(lastErrorMessage())
        }
        bindText(statement, 1, key.compositeID)
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            guard step == SQLITE_DONE else { throw ScanIndexError.statementFailed(lastErrorMessage()) }
            return nil
        }
        let totalBytes = sqlite3_column_int64(statement, 0)
        let processedEntries = Int(sqlite3_column_int64(statement, 1))
        let isComplete = sqlite3_column_int64(statement, 2) != 0
        let reasons = decodeReasons(sqlite3_column_text(statement, 3))
        let generation = UInt64(bitPattern: sqlite3_column_int64(statement, 4))
        let cursor = UInt64(bitPattern: sqlite3_column_int64(statement, 5))
        let updatedAt = sqlite3_column_double(statement, 6)
        return ScanAggregateRecord(key: key, totalBytes: totalBytes,
            processedEntries: processedEntries, isComplete: isComplete, reasons: reasons,
            generation: generation, cursor: cursor,
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt))
    }

    /// Commits one record — and, when `volumeUUID`/`cursor` are supplied, that volume's watch
    /// cursor/device UUID — in a SINGLE transaction. The contract calls for one transaction per
    /// completed batch, not one for the aggregate and a separate one for the cursor: two
    /// transactions would leave a real crash window where the aggregate was published but the
    /// cursor it was published under was not (or vice versa), silently desynchronizing what the
    /// next resume replays from what was actually measured.
    ///
    /// A partial (`isComplete == false`) record is never allowed to replace a previously complete
    /// one for the same key — the caller must widen scope and try again with a complete result,
    /// or accept `.rejectedPartialOverComplete`. Every failure path below rolls back explicitly:
    /// a transient I/O error partway through (even in the pre-check read) must never leave an
    /// open `BEGIN IMMEDIATE` wedging every later call against this handle.
    @discardableResult
    public func commit(_ record: ScanAggregateRecord, volumeUUID: String? = nil,
                       cursor: UInt64? = nil, deviceUUID: String? = nil) throws -> ScanAggregateRecord {
        guard db != nil else { throw ScanIndexError.corrupted }
        try exec("BEGIN IMMEDIATE;")
        do {
            if let existing = try self.record(for: record.key), existing.isComplete, !record.isComplete {
                throw ScanIndexError.partialCannotReplaceComplete
            }
            try insertOrUpdateScanRecordStatement(record)
            if let volumeUUID, let cursor {
                try upsertVolumeWatchStatement(volumeUUID: volumeUUID, cursor: cursor,
                    deviceUUID: deviceUUID)
            }
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
        try exec("COMMIT;")
        return record
    }

    private func insertOrUpdateScanRecordStatement(_ record: ScanAggregateRecord) throws {
        guard let db else { throw ScanIndexError.corrupted }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO scan_records
            (composite_id, volume_uuid, root_identity, scanner_version, policy_fingerprint,
             total_bytes, processed_entries, is_complete, reasons, generation, cursor, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(composite_id) DO UPDATE SET
            total_bytes = excluded.total_bytes,
            processed_entries = excluded.processed_entries,
            is_complete = excluded.is_complete,
            reasons = excluded.reasons,
            generation = excluded.generation,
            cursor = excluded.cursor,
            updated_at = excluded.updated_at;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = lastErrorMessage()
            sqlite3_finalize(statement)
            throw ScanIndexError.statementFailed(message)
        }
        bindText(statement, 1, record.key.compositeID)
        bindText(statement, 2, record.key.volumeUUID)
        bindText(statement, 3, record.key.rootIdentity)
        sqlite3_bind_int64(statement, 4, Int64(record.key.scannerVersion))
        bindText(statement, 5, record.key.policyFingerprint)
        sqlite3_bind_int64(statement, 6, record.totalBytes)
        sqlite3_bind_int64(statement, 7, Int64(record.processedEntries))
        sqlite3_bind_int64(statement, 8, record.isComplete ? 1 : 0)
        bindText(statement, 9, encodeReasons(record.reasons))
        sqlite3_bind_int64(statement, 10, Int64(bitPattern: record.generation))
        sqlite3_bind_int64(statement, 11, Int64(bitPattern: record.cursor))
        // `timeIntervalSinceReferenceDate` is `Date`'s own canonical storage. Round-tripping
        // through `timeIntervalSince1970` instead would add/subtract the ~978,307,200-second
        // 1970-2001 offset on the way in and out — two separately-rounded floating point
        // operations that are not guaranteed to invert exactly, which was silently failing the
        // `record == fetchedRecord` equality this store's callers rely on. Storing the reference
        // date directly is a single lossless round trip: the same 8-byte double in, the same one
        // back out.
        sqlite3_bind_double(statement, 12, record.updatedAt.timeIntervalSinceReferenceDate)
        let step = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard step == SQLITE_DONE else { throw ScanIndexError.statementFailed(lastErrorMessage()) }
    }

    // Staleness is deliberately not a stored bit: it is derived at read time
    // by comparing a record's `generation` against the live invalidation
    // ledger (see `ScanIndexCoordinator.status`). A crash between "mark
    // stale" and "the ledger actually moved" could otherwise desynchronize
    // the two; deriving it avoids that state entirely.

    public func deleteAll() throws {
        try exec("DELETE FROM scan_records;")
    }

    // MARK: - Cursor / device UUID persistence

    public func persistedCursor(volumeUUID: String) throws -> UInt64? {
        guard let db else { throw ScanIndexError.corrupted }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT cursor FROM volume_watch WHERE volume_uuid = ?;",
            -1, &statement, nil) == SQLITE_OK else {
            throw ScanIndexError.statementFailed(lastErrorMessage())
        }
        bindText(statement, 1, volumeUUID)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return UInt64(bitPattern: sqlite3_column_int64(statement, 0))
    }

    public func persistedDeviceUUID(volumeUUID: String) throws -> String? {
        guard let db else { throw ScanIndexError.corrupted }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT device_uuid FROM volume_watch WHERE volume_uuid = ?;",
            -1, &statement, nil) == SQLITE_OK else {
            throw ScanIndexError.statementFailed(lastErrorMessage())
        }
        bindText(statement, 1, volumeUUID)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    /// Standalone cursor/device-UUID write, wrapped in its own transaction. `commit(_:volumeUUID:
    /// cursor:deviceUUID:)` uses the same statement (`upsertVolumeWatchStatement`) inside its own
    /// single transaction instead of calling this method, so the aggregate and the cursor land
    /// atomically together during a real scan commit.
    public func persistCursor(volumeUUID: String, cursor: UInt64, deviceUUID: String?) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try upsertVolumeWatchStatement(volumeUUID: volumeUUID, cursor: cursor, deviceUUID: deviceUUID)
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
        try exec("COMMIT;")
    }

    private func upsertVolumeWatchStatement(volumeUUID: String, cursor: UInt64,
                                            deviceUUID: String?) throws {
        guard let db else { throw ScanIndexError.corrupted }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO volume_watch (volume_uuid, cursor, device_uuid) VALUES (?, ?, ?)
        ON CONFLICT(volume_uuid) DO UPDATE SET cursor = excluded.cursor,
            device_uuid = COALESCE(excluded.device_uuid, volume_watch.device_uuid);
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = lastErrorMessage()
            sqlite3_finalize(statement)
            throw ScanIndexError.statementFailed(message)
        }
        bindText(statement, 1, volumeUUID)
        sqlite3_bind_int64(statement, 2, Int64(bitPattern: cursor))
        if let deviceUUID { bindText(statement, 3, deviceUUID) } else { sqlite3_bind_null(statement, 3) }
        let step = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard step == SQLITE_DONE else { throw ScanIndexError.statementFailed(lastErrorMessage()) }
    }

    // MARK: - Bounded eviction

    /// Deletes the least-recently-updated records until the database file
    /// (including its WAL/SHM siblings) is at or under `capBytes`, then
    /// truncates the WAL so the cap reflects real bytes on disk rather than
    /// an unflushed journal. Bounded to `maxIterations` deletion rounds so a
    /// pathological cap (smaller than one row can ever be) fails closed
    /// instead of spinning forever.
    @discardableResult
    public func evictToFit(capBytes: Int64, maxIterations: Int = 10_000) throws -> Int {
        guard capBytes >= 0 else { return 0 }
        // Called after every commit, so the common case — comfortably under the cap — must be
        // cheap: check the raw file size first and only pay for a WAL checkpoint plus an
        // incremental vacuum when actually over budget, instead of doing both unconditionally.
        guard try diskUsageBytes() > capBytes else { return 0 }
        var deleted = 0
        var iterations = 0
        try checkpoint()
        while try diskUsageBytes() > capBytes {
            guard iterations < maxIterations else { break }
            iterations += 1
            guard let db else { throw ScanIndexError.corrupted }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "DELETE FROM scan_records WHERE composite_id IN " +
                "(SELECT composite_id FROM scan_records ORDER BY updated_at ASC LIMIT 32);",
                -1, &statement, nil) == SQLITE_OK else {
                throw ScanIndexError.statementFailed(lastErrorMessage())
            }
            let step = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard step == SQLITE_DONE else { throw ScanIndexError.statementFailed(lastErrorMessage()) }
            let removedThisRound = sqlite3_changes(db)
            deleted += Int(removedThisRound)
            try checkpoint()
            if removedThisRound == 0 { break }
        }
        return deleted
    }

    private func checkpoint() throws {
        // SQLite never shrinks the main database file on `DELETE` — freed pages go on an
        // internal free list, not back to the filesystem — so a checkpoint alone caps the WAL,
        // not the file `evictToFit` is actually trying to bound. `incremental_vacuum` (enabled by
        // `PRAGMA auto_vacuum = INCREMENTAL` at database creation, see `init`) moves those freed
        // pages out of the file and truncates it; without it, eviction could delete every row and
        // still sit at the file's high-water mark.
        try exec("PRAGMA wal_checkpoint(TRUNCATE);")
        try exec("PRAGMA incremental_vacuum;")
        // `incremental_vacuum` writes its own page moves through the WAL, so the file can grow
        // again immediately after the vacuum; checkpoint once more to fold that back in.
        try exec("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    public func diskUsageBytes() throws -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? Int64 else { continue }
            total += size
        }
        return total
    }

    // MARK: - Helpers

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "no handle" }
        return String(cString: sqlite3_errmsg(db))
    }

    /// Joined with the unit separator rather than a comma: `reasons` today only ever holds
    /// `TraversalCoverageReason.rawValue` identifiers, which can't contain a comma, but a plain
    /// comma join is one careless future caller away from silently merging or splitting reasons
    /// that happen to contain one. `\u{1F}` cannot appear in any reasonable reason string and
    /// matches the separator `ScanIndexKey.compositeID` already uses for the same purpose.
    private static let reasonsSeparator: Character = "\u{1F}"

    private func encodeReasons(_ reasons: Set<String>) -> String {
        reasons.sorted().joined(separator: String(Self.reasonsSeparator))
    }

    private func decodeReasons(_ text: UnsafePointer<UInt8>?) -> Set<String> {
        guard let text else { return [] }
        let string = String(cString: text)
        guard !string.isEmpty else { return [] }
        return Set(string.split(separator: Self.reasonsSeparator).map(String.init))
    }
}

/// A stable identity for a scan root: which volume it lives on, and which
/// file it is on that volume. Neither field is a path, so a rename that
/// keeps the same inode does not manufacture a new cache entry, and a
/// same-named directory recreated after a delete does not silently inherit
/// the old one's history.
public struct ScanRootIdentity: Equatable, Sendable {
    public let volumeUUID: String
    public let fileIdentity: String

    public init(volumeUUID: String, fileIdentity: String) {
        self.volumeUUID = volumeUUID
        self.fileIdentity = fileIdentity
    }

    /// Resolves identity from the live filesystem. Returns nil when either
    /// resource key is unavailable (the root is missing, unreadable, or the
    /// volume does not vend an identifier) — callers must treat that as
    /// `.unavailable`, never fall back to the path as a substitute identity.
    ///
    /// `String(describing:)` on `.volumeIdentifierKey`/`.fileResourceIdentifierKey`'s opaque
    /// `(NSCopying & NSSecureCoding & NSObjectProtocol)` values is undocumented behavior: Apple
    /// does not promise their `description` is a stable, collision-free encoding of the
    /// underlying identity rather than, say, an address-derived string. In practice these values
    /// are backed by simple value types (observed as boxed integers/strings, never addresses)
    /// and `ScanRootIdentityTests.resolveIsStableAndDistinguishesFiles` pins exactly the
    /// assumption this relies on — same path resolves identically twice, and two different files
    /// resolve to different identities — so a future OS change that broke it would fail loudly
    /// here instead of silently corrupting cache keys. If that test ever needs to be loosened,
    /// switch to hashing `NSKeyedArchiver.archivedData` of the resource value instead of trusting
    /// its `description`.
    public static func resolve(path: String) -> ScanRootIdentity? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(
            forKeys: [.volumeIdentifierKey, .fileResourceIdentifierKey]),
              let volumeIdentifier = values.volumeIdentifier,
              let fileIdentifier = values.fileResourceIdentifier else {
            return nil
        }
        return ScanRootIdentity(volumeUUID: String(describing: volumeIdentifier),
            fileIdentity: String(describing: fileIdentifier))
    }
}

/// Ties `ScanIndexStore` (durable aggregates) to `ScanInvalidation` (live
/// generations) so a caller only ever sees the two operations the contract
/// actually needs: capture a generation before scanning, and try to publish
/// under it afterward. Everything about barriers, staleness and eviction is
/// internal to that pair of calls.
public actor ScanIndexCoordinator {
    public enum Mode: Equatable, Sendable { case enabled, disabled }

    private let mode: Mode
    private let store: ScanIndexStore?
    private let invalidation: ScanInvalidation
    private let capBytes: Int64
    private let maximumAge: TimeInterval

    public init(mode: Mode, store: ScanIndexStore?, invalidation: ScanInvalidation,
                capBytes: Int64 = 64 * 1024 * 1024, maximumAge: TimeInterval = 7 * 24 * 3_600) {
        self.mode = mode
        self.store = mode == .enabled ? store : nil
        self.invalidation = invalidation
        self.capBytes = capBytes
        self.maximumAge = maximumAge
    }

    /// Must be called before baseline traversal starts. No-op (and no event
    /// stream exists) when indexing is off.
    public func startWatching(approvedRoots: [String], volumeUUID: String) async {
        guard mode == .enabled, let store else { return }
        let resumeCursor = try? await store.persistedCursor(volumeUUID: volumeUUID)
        // Read fresh every start: the persisted device UUID can change between runs (a prior
        // session may have observed and recorded a swap), and threading it through here — rather
        // than baking it into whatever `ScanEventSource` was constructed with — is what actually
        // lets `FSEventsScanEventSource` detect "this volume's event history is not the one I
        // remember" on the very next watch.
        let persistedDeviceUUID = try? await store.persistedDeviceUUID(volumeUUID: volumeUUID)
        await invalidation.start(approvedRoots: approvedRoots, resumeCursor: resumeCursor,
            persistedDeviceUUID: persistedDeviceUUID)
    }

    public func stopWatching() async {
        await invalidation.stop()
    }

    /// Explicit widening for signals outside the event stream's vocabulary:
    /// a policy/protected-root change, a detected volume swap. Always
    /// invalidates every approved root, matching
    /// `InvalidationDecision.decide(historyReliable: false)`.
    public func invalidateAllApprovedRoots() async {
        await invalidation.invalidateAllApprovedRoots()
    }

    /// The generation a scan must capture before it starts walking `root`.
    public func beginScan(root: String) async -> UInt64 {
        await invalidation.currentGeneration(for: root)
    }

    public func status(for key: ScanIndexKey, root: String) async -> ScanIndexStatus {
        guard mode == .enabled, let store else { return .unavailable(.indexingDisabled) }
        // Fail closed: with no running watch, `currentGeneration` cannot have moved no matter
        // what happened on disk, so a bare generation-equality check would report every record
        // `.cached` forever. A record can only ever be trusted while something is actually
        // watching for the events that would invalidate it.
        guard await invalidation.isWatchActive() else { return .unavailable(.watchInactive) }
        let record: ScanAggregateRecord?
        do { record = try await store.record(for: key) }
        catch { return .unavailable(.corrupted) }
        guard let record else { return .unavailable(.noRecord) }
        if Date().timeIntervalSince(record.updatedAt) > maximumAge {
            return .unavailable(.expired)
        }
        let liveGeneration = await invalidation.currentGeneration(for: root)
        return liveGeneration == record.generation ? .cached(record) : .stale(record)
    }

    /// The one publication path. Drains the barrier, re-checks the
    /// generation, and only then commits — all inside the actor, so no
    /// second caller can interleave a commit between the check and the
    /// write. On any mismatch or failure the previous record (if any) is
    /// left exactly as it was.
    public func commitIfCurrent(key: ScanIndexKey, root: String, volumeUUID: String,
                                capturedGeneration: UInt64, totalBytes: Int64,
                                processedEntries: Int, isComplete: Bool,
                                reasons: Set<String>) async -> ScanIndexCommitOutcome {
        guard mode == .enabled, let store else { return .unavailable(.indexingDisabled) }
        // Same fail-closed rule as `status`: publishing under a generation nothing is actively
        // watching would let a stale total masquerade as current the instant a watch resumes.
        guard await invalidation.isWatchActive() else { return .unavailable(.watchInactive) }
        do { try await invalidation.barrier() }
        catch { return .staleGeneration }
        let current = await invalidation.currentGeneration(for: root)
        guard current == capturedGeneration else { return .staleGeneration }
        let cursor = await invalidation.currentCursor()
        let record = ScanAggregateRecord(key: key, totalBytes: totalBytes,
            processedEntries: processedEntries, isComplete: isComplete, reasons: reasons,
            generation: current, cursor: cursor, updatedAt: Date())
        // The live device UUID, persisted in the same transaction as the aggregate below, is
        // what lets the *next* `startWatching` on this volume detect a reformat/swap that
        // happened while nothing was watching.
        let deviceUUID = FSEventsScanEventSource.currentDeviceUUID(forPathOnVolume: root)
        do {
            let committed = try await store.commit(record, volumeUUID: volumeUUID, cursor: cursor,
                deviceUUID: deviceUUID)
            try await store.evictToFit(capBytes: capBytes)
            return .committed(committed)
        } catch ScanIndexError.partialCannotReplaceComplete {
            return .rejectedPartialOverComplete
        } catch {
            return .unavailable(.corrupted)
        }
    }
}
