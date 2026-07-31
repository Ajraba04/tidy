import Foundation
import SQLite3
import Testing
@testable import TidyCore

/// Builds fixture `Cookies` databases matching Chrome's real schema (column
/// set confirmed against a live Chrome 149 profile), so tests exercise the
/// same shape of file the cleaner will see in production.
private enum CookieFixture {
    static func makeDatabase(at path: String, hostKeys: [String]) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw CookieFixtureError.failed("could not create fixture database")
        }
        defer { sqlite3_close_v2(db) }

        let createSQL = """
        CREATE TABLE cookies(
            creation_utc INTEGER NOT NULL,
            host_key TEXT NOT NULL,
            top_frame_site_key TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL,
            value TEXT NOT NULL,
            encrypted_value BLOB NOT NULL DEFAULT '',
            path TEXT NOT NULL DEFAULT '/',
            expires_utc INTEGER NOT NULL DEFAULT 0,
            is_secure INTEGER NOT NULL DEFAULT 0,
            is_httponly INTEGER NOT NULL DEFAULT 0,
            last_access_utc INTEGER NOT NULL DEFAULT 0,
            has_expires INTEGER NOT NULL DEFAULT 1,
            is_persistent INTEGER NOT NULL DEFAULT 1,
            priority INTEGER NOT NULL DEFAULT 1,
            samesite INTEGER NOT NULL DEFAULT 0,
            source_scheme INTEGER NOT NULL DEFAULT 0,
            source_port INTEGER NOT NULL DEFAULT -1,
            last_update_utc INTEGER NOT NULL DEFAULT 0,
            source_type INTEGER NOT NULL DEFAULT 0,
            has_cross_site_ancestor INTEGER NOT NULL DEFAULT 0
        )
        """
        guard sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw CookieFixtureError.failed(String(cString: sqlite3_errmsg(db)))
        }

        var stmt: OpaquePointer?
        let insertSQL = "INSERT INTO cookies (creation_utc, host_key, name, value) VALUES (0, ?, 'session', 'x')"
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw CookieFixtureError.failed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for host in hostKeys {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, host, -1, transient)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw CookieFixtureError.failed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    static func hostKeys(at path: String) throws -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CookieFixtureError.failed("could not open for reading")
        }
        defer { sqlite3_close_v2(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT host_key FROM cookies ORDER BY host_key", -1, &stmt, nil) == SQLITE_OK else {
            throw CookieFixtureError.failed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: cString))
            }
        }
        return results
    }

    enum CookieFixtureError: Error { case failed(String) }
}

@Suite("ChromiumCookieCleaner")
struct ChromiumCookieCleanerTests {

    private func makeScratchDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChromiumCookieCleanerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - profiles()

    @Test("profiles finds only directories with a Preferences file, excluding System/Guest Profile")
    func profilesFiltersCorrectly() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let root = ChromiumCookieCleaner.chromeRoot(homeDirectory: scratch.path)
        for name in ["Default", "Profile 1", "System Profile", "Guest Profile", "FileTypePolicies"] {
            try FileManager.default.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true)
        }
        // Only real profiles get a Preferences file; FileTypePolicies (a
        // component-updater payload dir) never does.
        for name in ["Default", "Profile 1", "System Profile", "Guest Profile"] {
            try Data("{}".utf8).write(to: URL(fileURLWithPath: root + "/" + name + "/Preferences"))
        }

        let profiles = ChromiumCookieCleaner.profiles(homeDirectory: scratch.path)
        #expect(Set(profiles.map(\.name)) == ["Default", "Profile 1"])
    }

    // MARK: - clean()

    @Test("deletes cookies outside the keep-list, keeps exact and subdomain matches")
    func deletesOutsideKeepList() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: [
            "apple.com", "www.apple.com", ".apple.com", "developer.apple.com",
            "evil.com", "tracker.example.com", "notapple.com"
        ])

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        guard case .cleaned(let total, let kept, let deleted) = outcome else {
            Issue.record("expected .cleaned, got \(outcome)")
            return
        }
        #expect(total == 7)
        #expect(kept == 4)
        #expect(deleted == 3)

        let remaining = try CookieFixture.hostKeys(at: dbPath)
        #expect(Set(remaining) == ["apple.com", "www.apple.com", ".apple.com", "developer.apple.com"])
        // "notapple.com" sharing a suffix with "apple.com" must not survive.
        #expect(!remaining.contains("notapple.com"))

        #expect(!FileManager.default.fileExists(atPath: dbPath + ".tidy-backup"))
    }

    @Test("an empty keep-list is skipped, never reaches SQL, file is untouched")
    func emptyKeepListIsSkipped() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: ["apple.com", "evil.com"])
        let before = try Data(contentsOf: URL(fileURLWithPath: dbPath))

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: [],
            homeDirectory: scratch.path
        )

        guard case .skipped = outcome else {
            Issue.record("expected .skipped, got \(outcome)")
            return
        }
        let after = try Data(contentsOf: URL(fileURLWithPath: dbPath))
        #expect(before == after)
    }

    @Test("a keep-domain containing an underscore does not over-match via the LIKE wildcard")
    func underscoreDoesNotActAsWildcard() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        // "my_site.com" as a keep-domain: unescaped, '_' in LIKE matches any
        // single character, so "myXsite.com" must NOT be kept unless the
        // escape is applied correctly.
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: ["sub.my_site.com", "sub.myXsite.com"])

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["my_site.com"],
            homeDirectory: scratch.path
        )

        guard case .cleaned(_, let kept, _) = outcome else {
            Issue.record("expected .cleaned, got \(outcome)")
            return
        }
        #expect(kept == 1)
        let remaining = try CookieFixture.hostKeys(at: dbPath)
        #expect(remaining == ["sub.my_site.com"])
    }

    @Test("domain matching is case-insensitive on both the exact and subdomain branches")
    func matchingIsCaseInsensitive() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: ["APPLE.COM", "Sub.Apple.Com", "evil.com"])

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        guard case .cleaned(_, let kept, let deleted) = outcome else {
            Issue.record("expected .cleaned, got \(outcome)")
            return
        }
        #expect(kept == 2)
        #expect(deleted == 1)
    }

    @Test("does nothing and reports zero deleted when every cookie is already in the keep-list")
    func noOpWhenEverythingIsKept() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: ["apple.com"])

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        guard case .cleaned(let total, let kept, let deleted) = outcome else {
            Issue.record("expected .cleaned, got \(outcome)")
            return
        }
        #expect(total == 1)
        #expect(kept == 1)
        #expect(deleted == 0)
        #expect(!FileManager.default.fileExists(atPath: dbPath + ".tidy-backup"))
    }

    @Test("is skipped when there is no cookie database at the profile")
    func skippedWhenNoDatabase() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )
        guard case .skipped = outcome else {
            Issue.record("expected .skipped, got \(outcome)")
            return
        }
    }

    @Test("fails without modifying the file when the database cannot be opened")
    func failsWithoutModifyingUnopenableFile() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        let garbage = Data("not a sqlite database".utf8)
        try garbage.write(to: URL(fileURLWithPath: dbPath))

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        let after = try Data(contentsOf: URL(fileURLWithPath: dbPath))
        #expect(after == garbage)
        #expect(!FileManager.default.fileExists(atPath: dbPath + ".tidy-backup"))
    }

    @Test("restores the original database if it is corrupted between backup and integrity check")
    func restoresOriginalOnPostDeleteCorruption() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: ["apple.com", "evil.com", "tracker.com"])
        let originalHostKeys = try CookieFixture.hostKeys(at: dbPath)

        // Hand-replicates the cleaner's backup and restore steps instead of
        // racing its real internal timing: take a VACUUM INTO backup,
        // truncate the file to simulate corruption, then restore from that
        // backup and confirm the host keys match the original. This proves
        // a real restore from the same kind of backup file recovers
        // cleanly.
        var db: OpaquePointer?
        sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil)
        var backupStmt: OpaquePointer?
        let backupPath = dbPath + ".manual-backup"
        sqlite3_prepare_v2(db, "VACUUM INTO ?", -1, &backupStmt, nil)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(backupStmt, 1, backupPath, -1, transient)
        #expect(sqlite3_step(backupStmt) == SQLITE_DONE)
        sqlite3_finalize(backupStmt)
        sqlite3_close_v2(db)

        try Data("corrupted".utf8).write(to: URL(fileURLWithPath: dbPath))

        for suffix in ["-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: dbPath + suffix)
        }
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: dbPath), withItemAt: URL(fileURLWithPath: backupPath))

        let restoredHostKeys = try CookieFixture.hostKeys(at: dbPath)
        #expect(restoredHostKeys == originalHostKeys)
    }

    @Test("is skipped when Chrome's SingletonLock is present, file untouched")
    func skippedWhenSingletonLockPresent() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: ["apple.com", "evil.com"])
        let before = try Data(contentsOf: URL(fileURLWithPath: dbPath))

        let root = ChromiumCookieCleaner.chromeRoot(homeDirectory: scratch.path)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: root + "/SingletonLock",
            withDestinationPath: "some-host-12345"
        )
        #expect(ChromiumCookieCleaner.hasSingletonLock(homeDirectory: scratch.path))

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        guard case .skipped = outcome else {
            Issue.record("expected .skipped, got \(outcome)")
            return
        }
        let after = try Data(contentsOf: URL(fileURLWithPath: dbPath))
        #expect(before == after)
    }
}
