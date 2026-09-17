import Foundation

/// Minimum T15.I inventory for the shared Xcode DerivedData root. This type
/// does not run Xcode, inspect user processes, or claim a producer lease.
/// Apple's supported command-line surface has no exclusion/lease interface
/// for the shared root, so production capability remains inventory-only.
public enum AppleDerivedDataInventory {
    public static let adapterID = "apple.xcode.derived-data"
    public static let contractVersion = "1"
    public static let unavailableReason = "Inventory only: no supported Xcode producer exclusion or complete shared-owner proof is available."

    public static func inspect(root: URL, observedAt: Date = Date()) throws -> InventoryRecord {
        let identity = try ResourcePreflight.captureFile(at: root.path)
        return record(resource: .filesystem(identity), observedAt: observedAt)
    }

    static func record(resource: ResourceIdentity, observedAt: Date) -> InventoryRecord {
        let identity: FileResourceIdentity
        switch resource {
        case .filesystem(let value): identity = value
        default:
            preconditionFailure("AppleDerivedDataInventory accepts only filesystem identities")
        }
        return InventoryRecord(
            id: "\(adapterID):\(identity.volumeID.uuidString):\(identity.inode)",
            adapterID: adapterID,
            adapterVersion: contractVersion,
            resource: resource,
            ownerIDs: [],
            scopeID: identity.canonicalPath,
            kind: "xcode-derived-data-root",
            capability: .inventoryOnly,
            allocatedBytes: nil,
            confidence: .partial,
            activity: .unknown,
            observedAt: observedAt,
            reason: unavailableReason
        )
    }

    /// Explicitly absent. A future implementation must be backed by a
    /// documented producer-owned primitive and separately accepted; this is
    /// not populated from process scans, Tidy locks or manual inactivity.
    static var productionLeaseProvider: (any ProducerExclusionLeaseProviding)? { nil }
}
