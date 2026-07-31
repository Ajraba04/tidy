import Foundation
import SQLite3
import Testing
@testable import TidyCore

@Suite("CookieDomainSuggester")
struct CookieDomainSuggesterTests {
    @Test("registrableDomain takes the last two labels", arguments: [
        ("accounts.google.com", "google.com"),
        ("www.apple.com", "apple.com"),
        (".apple.com", "apple.com"),
        ("apple.com", "apple.com"),
        ("localhost", "localhost")
    ])
    func registrableDomainTakesLastTwoLabels(hostKey: String, expected: String) {
        #expect(CookieDomainSuggester.registrableDomain(from: hostKey) == expected)
    }

    @Test("registrableDomain returns nil for an empty host")
    func registrableDomainReturnsNilForEmptyHost() {
        #expect(CookieDomainSuggester.registrableDomain(from: "") == nil)
    }

    @Test("suggests distinct registrable domains from a real Chrome profile's cookie database")
    func suggestsDistinctRegistrableDomainsFromRealProfile() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("CookieDomainSuggesterTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let root = ChromiumCookieCleaner.chromeRoot(homeDirectory: scratch.path)
        let profileDir = root + "/Default"
        try FileManager.default.createDirectory(atPath: profileDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: URL(fileURLWithPath: profileDir + "/Preferences"))

        try makeFixtureDatabase(
            at: profileDir + "/Cookies",
            hostKeys: ["accounts.google.com", "mail.google.com", "www.apple.com", "tracker.example.net"]
        )

        let suggestions = CookieDomainSuggester.suggestDomains(homeDirectory: scratch.path)
        #expect(Set(suggestions) == ["google.com", "apple.com", "example.net"])
    }

    @Test("returns nothing when there is no Chrome installation at all")
    func returnsNothingWithNoChrome() {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("CookieDomainSuggesterTests-empty-\(UUID().uuidString)")
        #expect(CookieDomainSuggester.suggestDomains(homeDirectory: scratch.path).isEmpty)
    }

    private func makeFixtureDatabase(at path: String, hostKeys: [String]) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            struct FixtureError: Error {}
            throw FixtureError()
        }
        defer { sqlite3_close_v2(db) }

        sqlite3_exec(db, "CREATE TABLE cookies(host_key TEXT NOT NULL, name TEXT NOT NULL DEFAULT 'x')", nil, nil, nil)

        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO cookies (host_key) VALUES (?)", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for host in hostKeys {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, host, -1, transient)
            sqlite3_step(stmt)
        }
    }
}
