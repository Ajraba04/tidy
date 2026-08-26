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

    @Test("clean is quarantined and preserves a disposable database and existing backup")
    func cleanDeniesWithoutMutatingDatabaseOrBackup() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let dbPath = profileDir.appendingPathComponent("Cookies").path
        try CookieFixture.makeDatabase(at: dbPath, hostKeys: ["apple.com", "evil.com"])
        let databaseBefore = try Data(contentsOf: URL(fileURLWithPath: dbPath))
        let backup = URL(fileURLWithPath: dbPath + ".tidy-backup")
        let backupBefore = Data("retain existing backup bytes".utf8)
        try backupBefore.write(to: backup)

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        #expect(outcome == .failed(reason: CapabilityRegistry.quarantineReason))
        #expect(try Data(contentsOf: URL(fileURLWithPath: dbPath)) == databaseBefore)
        #expect(try Data(contentsOf: backup) == backupBefore)
    }

    @Test("clean denies an empty keep list and preserves a disposable database and backup")
    func cleanDeniesEmptyKeepListWithoutMutatingDatabaseOrBackup() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let database = profileDir.appendingPathComponent("Cookies")
        try CookieFixture.makeDatabase(at: database.path, hostKeys: ["apple.com", "evil.com"])
        let databaseBefore = try Data(contentsOf: database)
        let backup = URL(fileURLWithPath: database.path + ".tidy-backup")
        let backupBefore = Data("retain empty-list backup bytes".utf8)
        try backupBefore.write(to: backup)

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: [],
            homeDirectory: scratch.path
        )

        #expect(outcome == .failed(reason: CapabilityRegistry.quarantineReason))
        #expect(try Data(contentsOf: database) == databaseBefore)
        #expect(try Data(contentsOf: backup) == backupBefore)
    }

    @Test("clean denies with SingletonLock present and preserves a disposable database and backup")
    func cleanDeniesSingletonLockWithoutMutatingDatabaseOrBackup() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let database = profileDir.appendingPathComponent("Cookies")
        try CookieFixture.makeDatabase(at: database.path, hostKeys: ["apple.com", "evil.com"])
        let databaseBefore = try Data(contentsOf: database)
        let backup = URL(fileURLWithPath: database.path + ".tidy-backup")
        let backupBefore = Data("retain lock backup bytes".utf8)
        try backupBefore.write(to: backup)
        let root = ChromiumCookieCleaner.chromeRoot(homeDirectory: scratch.path)
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/SingletonLock", withDestinationPath: "fixture-lock")
        #expect(ChromiumCookieCleaner.hasSingletonLock(homeDirectory: scratch.path))

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        #expect(outcome == .failed(reason: CapabilityRegistry.quarantineReason))
        #expect(try Data(contentsOf: database) == databaseBefore)
        #expect(try Data(contentsOf: backup) == backupBefore)
    }

    @Test("clean denies a missing database and preserves an existing backup")
    func cleanDeniesMissingDatabaseWithoutCreatingOneOrMutatingBackup() throws {
        let scratch = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let profileDir = scratch.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let database = profileDir.appendingPathComponent("Cookies")
        let backup = URL(fileURLWithPath: database.path + ".tidy-backup")
        let backupBefore = Data("retain missing-database backup bytes".utf8)
        try backupBefore.write(to: backup)

        let outcome = ChromiumCookieCleaner.clean(
            profile: ChromeProfile(name: "Default", path: profileDir.path),
            keepDomains: ["apple.com"],
            homeDirectory: scratch.path
        )

        #expect(outcome == .failed(reason: CapabilityRegistry.quarantineReason))
        #expect(!FileManager.default.fileExists(atPath: database.path))
        #expect(try Data(contentsOf: backup) == backupBefore)
    }
}
