import Foundation

/// A bounded, opt-in ring of past `SystemSnapshot`s. Nothing here ever
/// stores a process, an argv, or anything process-related at all --
/// `SystemSnapshot` has no such field, so history built from snapshots
/// structurally cannot leak one. History exists purely so a trend (e.g. a
/// rising page-out rate) can be shown, not so an individual sample can be
/// replayed forever: it is always both count-bounded and age-bounded, and
/// recording only happens when the caller (see `SystemMonitor`) has
/// `monitor.rawHistoryEnabled` set. Turning history off and back on starts
/// empty; nothing is retained across that toggle.
public struct SignalHistory: Sendable, Equatable {
    public private(set) var entries: [SystemSnapshot] = []
    public let maxEntries: Int
    public let maxAgeSeconds: Double

    public init(maxEntries: Int, maxAgeSeconds: Double) {
        self.maxEntries = max(0, maxEntries)
        self.maxAgeSeconds = max(0, maxAgeSeconds)
    }

    public var isEmpty: Bool { entries.isEmpty }

    @discardableResult
    public mutating func record(_ snapshot: SystemSnapshot, now: Date) -> Self {
        guard maxEntries > 0, maxAgeSeconds > 0 else { entries = []; return self }
        entries.append(snapshot)
        prune(now: now)
        return self
    }

    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.observedAt) > maxAgeSeconds }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}
