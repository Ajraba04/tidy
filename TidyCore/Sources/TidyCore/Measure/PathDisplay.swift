import Foundation

/// Shortens `$HOME` to `~` for display, matching the shell script's
/// `tilde()`.
public enum PathDisplay: Sendable {
    public static func tilde(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        if path == homeDirectory {
            return "~"
        }
        if path.hasPrefix(homeDirectory + "/") {
            return "~/" + path.dropFirst(homeDirectory.count + 1)
        }
        return path
    }
}
