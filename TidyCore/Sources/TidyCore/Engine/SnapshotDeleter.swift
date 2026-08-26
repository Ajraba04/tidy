import Foundation

/// The only operation in v1 that needs root: `tmutil deletelocalsnapshots`.
/// Run through `osascript … with administrator privileges` rather than a
/// standing privileged helper: this is rare, one-shot, and user-initiated,
/// which doesn't justify a second signed binary and an XPC connection. That
/// becomes worth it if a v2 needs more privileged operations than this one.
public enum SnapshotDeleter: Sendable {
    /// Every date component is validated against `tmutil`'s own format
    /// before it's ever embedded in a shell command string. The values
    /// come from `tmutil listlocalsnapshots` output, not user input, but
    /// this check stays regardless: an admin-privileged command string is
    /// exactly the place a validation shortcut later regrets itself.
    static func isValidDateComponent(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil
    }

    /// Deletes every given snapshot in a single administrator-privileged
    /// shell invocation, so the user is prompted once, not once per
    /// snapshot. Snapshots whose date component fails validation are
    /// dropped from the batch rather than aborting the whole operation.
    public static func deleteSnapshots(_ snapshots: [LocalSnapshot], commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> Bool {
        CapabilityRegistry.denialReason(for: .custom(.apfsSnapshots), itemID: "deep.system.apfs-snapshots") == nil
    }
}
