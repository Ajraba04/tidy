import Foundation

/// Probes access with a cheap read rather than assuming a path is
/// reachable. Most catalog roots (`~/Library/Caches`, `~/.npm`, ...) never
/// prompt; Safari's sandboxed container is the one that needs Full Disk
/// Access, detected here rather than treated as a launch-time gate.
public enum PermissionBroker: Sendable {
    public static let fullDiskAccessSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    public static func canRead(path: String) -> Bool {
        FileManager.default.isReadableFile(atPath: path)
    }
}
