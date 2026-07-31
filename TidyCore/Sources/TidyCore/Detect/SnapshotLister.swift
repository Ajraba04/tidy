import Foundation

/// An APFS local (Time Machine) snapshot. Deleting one only discards a
/// restore point — live data is unaffected — but that action itself is a
/// privileged operation (Phase 6). This lister is read-only.
public struct LocalSnapshot: Sendable, Identifiable, Equatable {
    public var id: String { identifier }
    /// e.g. "com.apple.TimeMachine.2026-07-31-120000.local"
    public let identifier: String

    /// The date component `tmutil deletelocalsnapshots` expects, e.g.
    /// "2026-07-31-120000".
    public var dateComponent: String {
        var value = identifier
        if value.hasPrefix("com.apple.TimeMachine.") {
            value.removeFirst("com.apple.TimeMachine.".count)
        }
        if value.hasSuffix(".local") {
            value.removeLast(".local".count)
        }
        return value
    }
}

public enum SnapshotLister: Sendable {
    public static func listLocalSnapshots(volumePath: String = "/") async -> [LocalSnapshot] {
        guard let tmutilPath = ToolLocator.locate("tmutil") else { return [] }
        guard let output = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: tmutilPath),
            arguments: ["listlocalsnapshots", volumePath]
        ), output.succeeded else {
            return []
        }

        return output.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine") }
            .map { LocalSnapshot(identifier: $0) }
    }
}
