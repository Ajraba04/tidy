import Foundation

/// Fixed default-deny capability query. This is intentionally not a mutable
/// policy store or an authorization token: no current action is accepted.
public enum CapabilityRegistry: Sendable {
    public static let quarantineReason = "Unavailable: no accepted local-only, exact-scope, ownership, preflight, interruption and recovery contract."

    public static func denialReason(for action: CleanAction, itemID: String) -> String? {
        quarantineReason
    }
}
