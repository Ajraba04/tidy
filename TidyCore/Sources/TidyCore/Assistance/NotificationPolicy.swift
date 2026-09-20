import Foundation

public enum NotificationPermission: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public enum AssistanceNotificationEvent: Hashable, Codable, Sendable {
    case pressure
    case budget(BudgetID, volumeID: UUID)
}

public enum AssistanceNavigation: Hashable, Codable, Sendable {
    case headroomReview
    case budgetReview(BudgetID, volumeID: UUID)
}

public enum NotificationSuppression: String, Codable, Equatable, Sendable {
    case disabled
    case permissionRequired
    case permissionDenied
    case notEligible
    case quietHours
    case cooldown
    case monotonicDiscontinuity
}

public enum NotificationDecision: Equatable, Sendable {
    case deliver(AssistanceNavigation)
    case suppress(NotificationSuppression)
}

public struct NotificationConfiguration: Equatable, Sendable {
    private let authority: LocalAuthoritySnapshot
    public var enabled: Bool { authority.permits(.notifications) }
    public let pressureSustainSeconds: Int
    public let recoverySeconds: Int
    public let cooldownMinutes: Int
    public let quietHoursEnabled: Bool
    public let quietStartMinute: Int
    public let quietEndMinute: Int

    public static func resolve(policy: EffectivePolicy,
                               authority: LocalAuthoritySnapshot) -> Self {
        Self(authority: authority,
             pressureSustainSeconds: integer(policy, "notifications.pressureSustainSeconds", 60),
             recoverySeconds: integer(policy, "notifications.recoverySeconds", 120),
             cooldownMinutes: integer(policy, "notifications.cooldownMinutes", 60),
             quietHoursEnabled: boolean(policy, "notifications.quietHoursEnabled", false),
             quietStartMinute: minute(policy, "notifications.quietStart", 22 * 60),
             quietEndMinute: minute(policy, "notifications.quietEnd", 8 * 60))
    }

    public func isQuiet(at date: Date, calendar original: Calendar) -> Bool {
        guard quietHoursEnabled, quietStartMinute != quietEndMinute else { return false }
        let components = original.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return true }
        let localMinute = hour * 60 + minute
        if quietStartMinute < quietEndMinute {
            return quietStartMinute <= localMinute && localMinute < quietEndMinute
        }
        return localMinute >= quietStartMinute || localMinute < quietEndMinute
    }

    private static func integer(_ policy: EffectivePolicy, _ raw: String,
                                _ fallback: Int) -> Int {
        guard case .stored(.integer(let value))? = policy.fields[SettingID(rawValue: raw)]?.value,
              let result = Int(exactly: value) else { return fallback }
        return result
    }

    private static func boolean(_ policy: EffectivePolicy, _ raw: String,
                                _ fallback: Bool) -> Bool {
        guard case .stored(.bool(let value))? = policy.fields[SettingID(rawValue: raw)]?.value else {
            return fallback
        }
        return value
    }

    private static func minute(_ policy: EffectivePolicy, _ raw: String,
                               _ fallback: Int) -> Int {
        guard case .stored(.choice(let value))? = policy.fields[SettingID(rawValue: raw)]?.value else {
            return fallback
        }
        let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return fallback }
        return hour * 60 + minute
    }
}

public struct NotificationDedupState: Codable, Equatable, Sendable {
    private static let maximumBytes = 32 * 1_024
    private struct Record: Codable, Equatable, Sendable {
        let bootID: UUID
        let monotonicNanoseconds: UInt64
    }
    private var records: [AssistanceNotificationEvent: Record] = [:]
    private var global: Record?

    public init() {}

    public mutating func decide(event: AssistanceNotificationEvent,
                                navigation: AssistanceNavigation,
                                eligible: Bool,
                                configuration: NotificationConfiguration,
                                permission: NotificationPermission,
                                bootID: UUID,
                                nowMonotonicNanoseconds: UInt64,
                                nowWallDate: Date,
                                calendar: Calendar) -> NotificationDecision {
        guard configuration.enabled else { return .suppress(.disabled) }
        switch permission {
        case .notDetermined: return .suppress(.permissionRequired)
        case .denied: return .suppress(.permissionDenied)
        case .authorized: break
        }
        guard eligible else { return .suppress(.notEligible) }
        guard !configuration.isQuiet(at: nowWallDate, calendar: calendar) else {
            return .suppress(.quietHours)
        }
        let cooldown = UInt64(configuration.cooldownMinutes) * 60 * 1_000_000_000
        for previous in [global, records[event]].compactMap({ $0 }) {
            guard previous.bootID == bootID else { continue }
            guard nowMonotonicNanoseconds >= previous.monotonicNanoseconds else {
                return .suppress(.monotonicDiscontinuity)
            }
            if nowMonotonicNanoseconds - previous.monotonicNanoseconds < cooldown {
                return .suppress(.cooldown)
            }
        }
        let record = Record(bootID: bootID, monotonicNanoseconds: nowMonotonicNanoseconds)
        records[event] = record
        global = record
        if records.count > 64 {
            records = [event: record]
        }
        return .deliver(navigation)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= Self.maximumBytes else { throw NotificationStateError.capacity }
        return bytes
    }

    public static func decode(_ bytes: Data) throws -> Self {
        guard bytes.count <= maximumBytes else { throw NotificationStateError.capacity }
        _ = try StrictJSON.parse(bytes)
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.records.count <= 64 else { throw NotificationStateError.capacity }
        return value
    }
}

public enum NotificationStateError: Error, Equatable, Sendable {
    case capacity
}

public enum PressureNotificationCondition: String, Codable, Equatable, Sendable {
    case normal
    case warning
    case unknown
}

/// Monotonic sustain/recovery state. Unknown samples retain the current alert
/// instead of fabricating recovery, and boot changes restart elapsed windows.
public struct PressureNotificationState: Codable, Equatable, Sendable {
    public private(set) var isAlerting = false
    private var bootID: UUID?
    private var warningSinceNanoseconds: UInt64?
    private var recoverySinceNanoseconds: UInt64?

    public init() {}

    public mutating func observe(_ condition: PressureNotificationCondition,
                                 configuration: NotificationConfiguration,
                                 bootID currentBootID: UUID,
                                 nowMonotonicNanoseconds: UInt64) -> Bool {
        if bootID != currentBootID {
            bootID = currentBootID
            warningSinceNanoseconds = nil
            recoverySinceNanoseconds = nil
        }
        switch condition {
        case .unknown:
            return isAlerting
        case .warning:
            recoverySinceNanoseconds = nil
            if isAlerting { return true }
            guard let since = warningSinceNanoseconds else {
                warningSinceNanoseconds = nowMonotonicNanoseconds
                return false
            }
            guard nowMonotonicNanoseconds >= since else {
                warningSinceNanoseconds = nowMonotonicNanoseconds
                return false
            }
            let required = UInt64(configuration.pressureSustainSeconds) * 1_000_000_000
            if nowMonotonicNanoseconds - since >= required {
                isAlerting = true
                return true
            }
            return false
        case .normal:
            warningSinceNanoseconds = nil
            guard isAlerting else { return false }
            guard let since = recoverySinceNanoseconds else {
                recoverySinceNanoseconds = nowMonotonicNanoseconds
                return false
            }
            guard nowMonotonicNanoseconds >= since else {
                recoverySinceNanoseconds = nowMonotonicNanoseconds
                return true
            }
            let required = UInt64(configuration.recoverySeconds) * 1_000_000_000
            if nowMonotonicNanoseconds - since >= required {
                isAlerting = false
                recoverySinceNanoseconds = nil
            }
            return isAlerting
        }
    }
}
