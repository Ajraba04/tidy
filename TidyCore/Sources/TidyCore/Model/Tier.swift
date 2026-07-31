/// A cleaning tier, matching the shell script's opt-in structure: each tier
/// out from `safe` costs either a re-download or local history.
public enum Tier: String, Codable, CaseIterable, Sendable, Comparable, Hashable {
    case scanOnly
    case safe
    case normal
    case deep

    /// Display order, from least to most aggressive.
    private var rank: Int {
        switch self {
        case .scanOnly: return 0
        case .safe: return 1
        case .normal: return 2
        case .deep: return 3
        }
    }

    public static func < (lhs: Tier, rhs: Tier) -> Bool {
        lhs.rank < rhs.rank
    }

    public var title: String {
        switch self {
        case .scanOnly: return "Scan"
        case .safe: return "Safe"
        case .normal: return "Normal"
        case .deep: return "Deep"
        }
    }
}
