import Foundation

/// Snapshot deletion is quarantined. The pure date-component parser remains
/// available for read-only snapshot discovery; this type never invokes an
/// administrator shell or mutates snapshots.
public enum SnapshotDeleter: Sendable {
    /// Pure parser for the date-component shape emitted by read-only
    /// `tmutil listlocalsnapshots` discovery.
    static func isValidDateComponent(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil
    }

    /// Legacy snapshot-deletion entry point. It is fixed-denied before any
    /// command transport call and always returns `false`.
    public static func deleteSnapshots(_ snapshots: [LocalSnapshot], commandRunner: any CleanupCommandRunning = SystemCleanupCommandRunner()) async -> Bool {
        if CapabilityRegistry.denialReason(for: .custom(.apfsSnapshots), itemID: "deep.system.apfs-snapshots") != nil {
            return false
        }
        return false
    }
}
