import Foundation

/// Fixed default-deny capability query. This is intentionally not a mutable
/// policy store, a feature flag or a generic allow-list: exactly one
/// catalog item/action pair is accepted, hardcoded below, and every other
/// action stays denied regardless of caller, environment or build
/// configuration. Widening this beyond the single accepted pair requires a
/// new reviewed contract, not a parameter or an environment check.
public enum CapabilityRegistry: Sendable {
    public static let quarantineReason = "Unavailable: no accepted local-only, exact-scope, ownership, preflight, interruption and recovery contract."

    public static func denialReason(for action: CleanAction, itemID: String) -> String? {
        if itemID == DerivedDataEffectAdapter.acceptedItemID, case .deleteContents = action {
            return nil
        }
        return quarantineReason
    }
}
