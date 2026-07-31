import Foundation
import SQLite3

/// `sqlite3_destructor_type`'s `SQLITE_TRANSIENT` sentinel (`(void*)-1`)
/// isn't imported by the C bridging layer, since it's a macro, not a
/// symbol. Passing `nil` (`SQLITE_STATIC`) instead would tell SQLite to
/// read the bytes later, but Swift's implicit `String` -> `UnsafePointer<CChar>`
/// bridging is only valid for the duration of the single call it's passed
/// to — a `nil`-destructor bind here would be a use-after-free.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct ChromeProfile: Sendable, Equatable {
    public let name: String
    public let path: String
}

public enum ChromeCookieOutcome: Sendable, Equatable {
    /// Nothing was touched: no keep-domains configured, Chrome is running,
    /// or no cookie database was found at this profile.
    case skipped(reason: String)
    case cleaned(total: Int, kept: Int, deleted: Int)
    /// The original database is intact or was successfully restored from
    /// backup.
    case failed(reason: String)
    /// The rare, serious case: something went wrong after the backup was
    /// taken and it could not be restored either. `backupPath` still holds
    /// the pre-clean database — never deleted in this outcome.
    case failedAndNotRestored(reason: String, backupPath: String)
}

enum CookieCleanerError: Error, CustomStringConvertible {
    case sqlite(String)
    var description: String {
        switch self { case .sqlite(let message): return message }
    }
}

/// Selective Chrome cookie deletion via the native SQLite3 C API — the
/// shell script's `sqlite3` CLI calls, ported with a materially safer
/// sequence: keep-domains go into a bound temp table rather than
/// string-concatenated SQL, the backup is a self-contained `VACUUM INTO`
/// snapshot rather than a raw file copy (immune to WAL/journal sidecar
/// mismatches), the count-then-delete happens inside one write-locked
/// transaction so the reported numbers can't go stale, and a
/// `PRAGMA integrity_check` gates whether the backup gets discarded or
/// restored.
///
/// Never decrypts `encrypted_value` — no Keychain access, no "Chrome Safe
/// Storage" prompt. Never touches `Extension Cookies` or
/// `Safe Browsing Cookies`, matching the shell script.
public enum ChromiumCookieCleaner: Sendable {
    public static let bundleIdentifiers = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary"
    ]

    public static func chromeRoot(homeDirectory: String) -> String {
        homeDirectory + "/Library/Application Support/Google/Chrome"
    }

    public static func isChromeRunning() -> Bool {
        bundleIdentifiers.contains { AppRunningCheck.isRunning(bundleIdentifier: $0) }
    }

    /// Chrome writes a `SingletonLock` symlink into its user-data dir for
    /// as long as it's running — a narrower, faster-to-notice check than
    /// polling the process list, used as a second gate right before
    /// opening each database.
    public static func hasSingletonLock(homeDirectory: String) -> Bool {
        let path = chromeRoot(homeDirectory: homeDirectory) + "/SingletonLock"
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    /// Real profile directories, identified by a `Preferences` file (component-
    /// updater payload dirs like `FileTypePolicies` don't have one), excluding
    /// the internal `System Profile` and `Guest Profile`.
    public static func profiles(homeDirectory: String) -> [ChromeProfile] {
        let root = chromeRoot(homeDirectory: homeDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return entries
            .filter { $0 != "System Profile" && $0 != "Guest Profile" }
            .compactMap { name -> ChromeProfile? in
                let path = root + "/" + name
                guard FileManager.default.fileExists(atPath: path + "/Preferences") else { return nil }
                return ChromeProfile(name: name, path: path)
            }
            .sorted { $0.name < $1.name }
    }

    private static func cookiesDatabasePath(profilePath: String) -> String? {
        for candidate in ["/Cookies", "/Network/Cookies"] {
            let path = profilePath + candidate
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// Synchronous and `nonisolated` by design — this does real file and
    /// SQLite I/O and must never run on the main actor. Callers dispatch it
    /// onto a background task.
    public static func clean(profile: ChromeProfile, keepDomains: [String], homeDirectory: String) -> ChromeCookieOutcome {
        guard !keepDomains.isEmpty else {
            return .skipped(reason: "no keep-domains configured")
        }
        guard !isChromeRunning(), !hasSingletonLock(homeDirectory: homeDirectory) else {
            return .skipped(reason: "Chrome is running")
        }
        guard let dbPath = cookiesDatabasePath(profilePath: profile.path) else {
            return .skipped(reason: "no cookie database found")
        }

        return cleanDatabase(at: dbPath, keepDomains: keepDomains.map { $0.lowercased() })
    }

    private static func cleanDatabase(at dbPath: String, keepDomains: [String]) -> ChromeCookieOutcome {
        let fm = FileManager.default
        let backupPath = dbPath + ".tidy-backup"

        var db: OpaquePointer?
        let openRC = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close_v2(db) }
        guard openRC == SQLITE_OK, let database = db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database"
            return .failed(reason: message)
        }

        sqlite3_busy_timeout(database, 5_000)

        do {
            let keepPredicate = try populateKeepTable(database, domains: keepDomains)

            // A cheap, non-authoritative check so a no-op run never pays for
            // a backup it doesn't need. The real numbers are recomputed
            // inside the write-locked transaction below.
            let precheckTotal = try scalarCount(database, "SELECT COUNT(*) FROM cookies")
            let precheckKept = try scalarCount(database, "SELECT COUNT(*) FROM cookies WHERE \(keepPredicate)")
            guard precheckTotal != precheckKept else {
                return .cleaned(total: precheckTotal, kept: precheckKept, deleted: 0)
            }

            if fm.fileExists(atPath: backupPath) {
                try fm.removeItem(atPath: backupPath)
            }
            try vacuumInto(database, destination: backupPath)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupPath)
            try validateBackup(at: backupPath, expectedTotal: precheckTotal)
        } catch {
            try? fm.removeItem(atPath: backupPath)
            return .failed(reason: "\(error)")
        }

        do {
            try exec(database, "BEGIN IMMEDIATE")

            let keepPredicate = try populateKeepTable(database, domains: keepDomains)
            let total = try scalarCount(database, "SELECT COUNT(*) FROM cookies")
            let kept = try scalarCount(database, "SELECT COUNT(*) FROM cookies WHERE \(keepPredicate)")

            try exec(database, "DELETE FROM cookies WHERE NOT \(keepPredicate)")
            let changed = Int(sqlite3_changes(database))

            guard changed == total - kept else {
                try exec(database, "ROLLBACK")
                try? fm.removeItem(atPath: backupPath)
                return .failed(reason: "unexpected delete count (\(changed), expected \(total - kept)); rolled back, original untouched")
            }

            try exec(database, "COMMIT")

            guard try integrityCheckPasses(database) else {
                return restoreFromBackup(dbPath: dbPath, backupPath: backupPath, reason: "post-delete integrity check failed")
            }

            try? fm.removeItem(atPath: backupPath)
            return .cleaned(total: total, kept: kept, deleted: changed)
        } catch {
            try? exec(database, "ROLLBACK")
            // The database itself was never modified before COMMIT above,
            // so on any failure up to and including a bad COMMIT, the
            // backup was for nothing — discard it rather than restore.
            try? fm.removeItem(atPath: backupPath)
            return .failed(reason: "\(error)")
        }
    }

    /// Builds `temp.keep(exact, pattern)` from bound parameters — never
    /// string-concatenated SQL — and returns the `EXISTS` predicate that
    /// both the count and delete statements share, so "how many would be
    /// kept" and "what gets deleted" can never drift apart.
    ///
    /// `pattern` is `%.` + the domain with `\`, `%`, and `_` escaped, used
    /// with `ESCAPE '\'` — SQLite's `LIKE` treats `_` and `%` as wildcards
    /// even inside what looks like a literal domain, so an unescaped
    /// pattern could silently widen the keep-set for a domain containing
    /// either character. `LIKE` is already ASCII case-insensitive; `=` is
    /// not, so the exact-match side uses `COLLATE NOCASE` to match.
    @discardableResult
    private static func populateKeepTable(_ db: OpaquePointer, domains: [String]) throws -> String {
        try exec(db, "DROP TABLE IF EXISTS temp.keep")
        try exec(db, "CREATE TEMP TABLE keep(exact TEXT NOT NULL, pattern TEXT NOT NULL)")

        let insert = try prepare(db, "INSERT INTO temp.keep(exact, pattern) VALUES (?, ?)")
        defer { sqlite3_finalize(insert) }

        for domain in domains {
            sqlite3_reset(insert)
            sqlite3_bind_text(insert, 1, domain, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(insert, 2, "%." + likeEscaped(domain), -1, SQLITE_TRANSIENT)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw CookieCleanerError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }

        return """
        EXISTS (SELECT 1 FROM temp.keep k WHERE cookies.host_key = k.exact COLLATE NOCASE \
        OR cookies.host_key LIKE k.pattern ESCAPE '\\')
        """
    }

    private static func likeEscaped(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "%", with: "\\%")
        result = result.replacingOccurrences(of: "_", with: "\\_")
        return result
    }

    private static func vacuumInto(_ db: OpaquePointer, destination: String) throws {
        let stmt = try prepare(db, "VACUUM INTO ?")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, destination, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CookieCleanerError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func validateBackup(at path: String, expectedTotal: Int) throws {
        var backupDB: OpaquePointer?
        let rc = sqlite3_open_v2(path, &backupDB, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close_v2(backupDB) }
        guard rc == SQLITE_OK, let database = backupDB else {
            throw CookieCleanerError.sqlite("backup validation: could not open backup copy")
        }
        let count = try scalarCount(database, "SELECT COUNT(*) FROM cookies")
        guard count == expectedTotal else {
            throw CookieCleanerError.sqlite("backup validation: row count \(count) does not match live database's \(expectedTotal)")
        }
    }

    private static func integrityCheckPasses(_ db: OpaquePointer) throws -> Bool {
        let stmt = try prepare(db, "PRAGMA integrity_check")
        defer { sqlite3_finalize(stmt) }
        var rows: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                rows.append(String(cString: cString))
            }
        }
        return rows == ["ok"]
    }

    /// Removes any sidecar journal files before restoring so SQLite never
    /// tries to replay a journal written for a different database state,
    /// then swaps the backup in atomically (`replaceItemAt`, not a
    /// remove-then-move pair a crash could interrupt between).
    private static func restoreFromBackup(dbPath: String, backupPath: String, reason: String) -> ChromeCookieOutcome {
        let fm = FileManager.default
        for suffix in ["-journal", "-wal", "-shm"] {
            try? fm.removeItem(atPath: dbPath + suffix)
        }
        do {
            if fm.fileExists(atPath: dbPath) {
                _ = try fm.replaceItemAt(URL(fileURLWithPath: dbPath), withItemAt: URL(fileURLWithPath: backupPath))
            } else {
                try fm.copyItem(atPath: backupPath, toPath: dbPath)
                try? fm.removeItem(atPath: backupPath)
            }
            return .failed(reason: reason + " — original restored from backup")
        } catch {
            return .failedAndNotRestored(reason: reason, backupPath: backupPath)
        }
    }

    // MARK: - Small SQLite helpers

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw CookieCleanerError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw CookieCleanerError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private static func scalarCount(_ db: OpaquePointer, _ sql: String) throws -> Int {
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw CookieCleanerError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }
}
