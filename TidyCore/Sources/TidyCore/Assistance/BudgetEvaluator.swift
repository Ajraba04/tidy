import Foundation

public enum BudgetID: String, CaseIterable, Codable, Hashable, Sendable {
    case appleDerivedData = "apple-derived-data"
    case appleSimulators = "apple-simulators"
    case android
    case docker
    case packageCaches = "package-caches"
    case models
    case ides
    case git
    case data
    case other
}

public struct BudgetTemplate: Equatable, Sendable {
    public let id: BudgetID
    public let suggestedHighBytes: Int64?
    public let enabledByDefault: Bool

    public init(id: BudgetID, suggestedHighBytes: Int64?, enabledByDefault: Bool) {
        self.id = id
        self.suggestedHighBytes = suggestedHighBytes
        self.enabledByDefault = enabledByDefault
    }
}

public struct BudgetMeasurement: Equatable, Sendable {
    public let budgetID: BudgetID
    public let volumeID: UUID
    public let allocatedBytes: Int64?

    public init(budgetID: BudgetID, volumeID: UUID, allocatedBytes: Int64?) {
        self.budgetID = budgetID
        self.volumeID = volumeID
        self.allocatedBytes = allocatedBytes
    }
}

public enum BudgetState: String, Codable, Equatable, Sendable {
    case disabled
    case withinBudget
    case alerting
    case unknown
}

public struct BudgetStatus: Codable, Equatable, Sendable {
    public let budgetID: BudgetID
    public let volumeID: UUID
    public let state: BudgetState
    public let alertLatched: Bool
    public let usedBytes: Int64?
    public let highBytes: Int64?
    public let lowBytes: Int64?

    public init(budgetID: BudgetID, volumeID: UUID, state: BudgetState,
                alertLatched: Bool, usedBytes: Int64?, highBytes: Int64?,
                lowBytes: Int64?) {
        self.budgetID = budgetID
        self.volumeID = volumeID
        self.state = state
        self.alertLatched = alertLatched
        self.usedBytes = usedBytes
        self.highBytes = highBytes
        self.lowBytes = lowBytes
    }
}

public struct BudgetEvaluation: Codable, Equatable, Sendable {
    public let volumeID: UUID
    public let statuses: [BudgetID: BudgetStatus]

    public init(volumeID: UUID, statuses: [BudgetID: BudgetStatus]) {
        self.volumeID = volumeID
        self.statuses = statuses
    }
}

public enum BudgetEvaluator {
    private static let gib: Int64 = 1_024 * 1_024 * 1_024

    public static let templates: [BudgetTemplate] = BudgetID.allCases.map { id in
        let suggestedGiB: Int64?
        switch id {
        case .appleDerivedData: suggestedGiB = 15
        case .appleSimulators: suggestedGiB = 25
        case .docker: suggestedGiB = 30
        case .packageCaches: suggestedGiB = 10
        case .models: suggestedGiB = 50
        default: suggestedGiB = nil
        }
        return BudgetTemplate(id: id,
            suggestedHighBytes: suggestedGiB.flatMap(checkedGiB), enabledByDefault: false)
    }

    public static func evaluate(policy: EffectivePolicy, volumeID: UUID,
                                measurements: [BudgetMeasurement],
                                previous: BudgetEvaluation? = nil) -> BudgetEvaluation {
        var statuses: [BudgetID: BudgetStatus] = [:]
        for id in BudgetID.allCases {
            let prior = previous?.volumeID == volumeID ? previous?.statuses[id] : nil
            let enabled = bool(policy, "budget.\(id.rawValue).enabled") == true
            guard enabled else {
                statuses[id] = BudgetStatus(budgetID: id, volumeID: volumeID,
                    state: .disabled, alertLatched: false, usedBytes: nil,
                    highBytes: nil, lowBytes: nil)
                continue
            }
            guard let high = bytes(policy, "budget.\(id.rawValue).highGiB"),
                  let low = bytes(policy, "budget.\(id.rawValue).lowGiB"),
                  high > low, low >= 0 else {
                statuses[id] = unknown(id: id, volumeID: volumeID, prior: prior,
                                       high: nil, low: nil)
                continue
            }
            let matching = measurements.filter { $0.budgetID == id && $0.volumeID == volumeID }
            guard matching.count == 1, let used = matching[0].allocatedBytes, used >= 0 else {
                statuses[id] = unknown(id: id, volumeID: volumeID, prior: prior,
                                       high: high, low: low)
                continue
            }
            let alerting = prior?.alertLatched == true ? used > low : used >= high
            statuses[id] = BudgetStatus(budgetID: id, volumeID: volumeID,
                state: alerting ? .alerting : .withinBudget, alertLatched: alerting,
                usedBytes: used, highBytes: high, lowBytes: low)
        }
        return BudgetEvaluation(volumeID: volumeID, statuses: statuses)
    }

    private static func unknown(id: BudgetID, volumeID: UUID, prior: BudgetStatus?,
                                high: Int64?, low: Int64?) -> BudgetStatus {
        BudgetStatus(budgetID: id, volumeID: volumeID, state: .unknown,
            alertLatched: prior?.alertLatched == true, usedBytes: nil,
            highBytes: high, lowBytes: low)
    }

    private static func bool(_ policy: EffectivePolicy, _ raw: String) -> Bool? {
        guard case .stored(.bool(let value))? = policy.fields[SettingID(rawValue: raw)]?.value else {
            return nil
        }
        return value
    }

    private static func bytes(_ policy: EffectivePolicy, _ raw: String) -> Int64? {
        guard let value = policy.fields[SettingID(rawValue: raw)]?.value else { return nil }
        switch value {
        case .bytes(let bytes): return bytes >= 0 ? bytes : nil
        case .stored(.integer(let gib)): return checkedGiB(gib)
        default: return nil
        }
    }

    private static func checkedGiB(_ amount: Int64) -> Int64? {
        guard amount >= 0 else { return nil }
        let (bytes, overflow) = amount.multipliedReportingOverflow(by: gib)
        return overflow ? nil : bytes
    }
}
