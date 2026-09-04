import Foundation

public struct ChromeProfile: Sendable, Equatable {
    public let name: String
    public let path: String
}

public enum ChromeCookieOutcome: Sendable, Equatable {
    /// Retained for source compatibility with legacy callers. The current
    /// quarantine implementation always returns `.failed` instead.
    case skipped(reason: String)
    /// Retained for source compatibility with legacy callers. No cleanup is
    /// currently authorized to produce this outcome.
    case cleaned(total: Int, kept: Int, deleted: Int)
    /// The fixed quarantine outcome. The original database and any existing
    /// backup are untouched.
    case failed(reason: String)
    /// Retained for source compatibility with legacy callers. Quarantine
    /// never creates, removes, or restores a backup.
    case failedAndNotRestored(reason: String, backupPath: String)
}

/// Read-only Chrome profile discovery. Cookie database mutation remains
/// quarantined until a reviewed exact-scope adapter contract exists.
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
    /// as long as it's running, a narrower, faster-to-notice check than
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

    /// This is a fixed denial boundary: it performs no database, backup, or
    /// filesystem mutation.
    public static func clean(profile: ChromeProfile, keepDomains: [String], homeDirectory: String) -> ChromeCookieOutcome {
        .failed(reason: CapabilityRegistry.denialReason(for: .custom(.chromeCookies), itemID: "normal.chrome.cookies") ?? CapabilityRegistry.quarantineReason)
    }

}
