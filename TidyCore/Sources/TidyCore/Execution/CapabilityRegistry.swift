import Foundation

/// Fixed default-deny capability query. This is intentionally not a mutable
/// policy store, feature flag, or generic allow-list. Tool detection is
/// inventory evidence, never ownership or producer-quiescence evidence.
public enum CapabilityRegistry: Sendable {
    public static let quarantineReason = "Unavailable: no accepted local-only, exact-scope, ownership, preflight, interruption and recovery contract."

    public static func denialReason(for action: CleanAction, itemID: String) -> String? {
        if itemID == DerivedDataEffectAdapter.acceptedItemID, case .deleteContents = action {
            return "Inventory only: Xcode build activity cannot yet be held quiescent through deletion."
        }
        return quarantineReason
    }
}
