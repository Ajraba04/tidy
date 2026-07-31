import Foundation
import SQLite3

/// Suggests keep-domains by reading the user's own Chrome cookie database.
/// Read-only, computed locally, and never shipped as a default. The
/// domains list in `CleanEnvironment`/`TidyConfig` still ships empty; this
/// only powers a picker in Settings the user chooses from.
public enum CookieDomainSuggester: Sendable {
    public static func suggestDomains(homeDirectory: String = NSHomeDirectory(), limit: Int = 30) -> [String] {
        var domains: Set<String> = []
        for profile in ChromiumCookieCleaner.profiles(homeDirectory: homeDirectory) {
            for candidate in ["/Cookies", "/Network/Cookies"] {
                let dbPath = profile.path + candidate
                guard FileManager.default.fileExists(atPath: dbPath) else { continue }
                domains.formUnion(distinctRegistrableDomains(at: dbPath))
            }
        }
        return Array(domains.sorted().prefix(limit))
    }

    private static func distinctRegistrableDomains(at path: String) -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database = db else {
            sqlite3_close_v2(db)
            return []
        }
        defer { sqlite3_close_v2(database) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT DISTINCT host_key FROM cookies", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(stmt, 0) else { continue }
            if let registrable = registrableDomain(from: String(cString: cString)) {
                results.insert(registrable)
            }
        }
        return results
    }

    /// The last two dot-separated labels: a simplified heuristic, not a
    /// public-suffix-list lookup. Good enough for a suggestion the user
    /// still reviews and confirms; not used anywhere that treats it as a
    /// security boundary.
    static func registrableDomain(from hostKey: String) -> String? {
        let trimmed = hostKey.hasPrefix(".") ? String(hostKey.dropFirst()) : hostKey
        guard !trimmed.isEmpty else { return nil }
        let labels = trimmed.split(separator: ".")
        guard labels.count >= 2 else { return trimmed }
        return labels.suffix(2).joined(separator: ".")
    }
}
