import Foundation

/// Fixed quarantine capability query. This is intentionally not a mutable
/// policy store, a feature flag or a generic allow-list: every mutation stays
/// denied regardless of caller, item identifier, action, environment or build
/// configuration. A future accepted adapter must replace this quarantine only
/// after its exact-scope, ownership and recovery contracts are complete.
public enum CapabilityRegistry: Sendable {
    public static let quarantineReason = "Unavailable: no accepted local-only, exact-scope, ownership, preflight, interruption and recovery contract."

    public static func denialReason(for _: CleanAction, itemID _: String) -> String? {
        return quarantineReason
    }
}
