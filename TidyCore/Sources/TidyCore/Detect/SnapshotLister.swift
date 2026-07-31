import Foundation

/// An APFS local (Time Machine) snapshot. Deleting one only discards a
/// restore point (live data is unaffected), but that action itself is a
/// privileged operation. This lister is read-only.
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

    /// A synchronous existence check for use inside `CleanItem.locate`
    /// closures, which cannot be `async`. Safe as a same-thread,
    /// non-detached `run()`-then-`waitUntilExit()` sequence: the pattern
    /// that turned out to be unreliable was specifically calling
    /// `waitUntilExit()` from a *different* thread/task than `run()`
    /// (`ProcessRunner`'s original design); this never does that, and
    /// `tmutil listlocalsnapshots`'s output is small enough that reading it
    /// after `waitUntilExit()` returns can't hit the large-output pipe
    /// deadlock either.
    static func hasLocalSnapshotsSync(volumePath: String = "/") -> Bool {
        guard let tmutilPath = ToolLocator.locate("tmutil") else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmutilPath)
        process.arguments = ["listlocalsnapshots", volumePath]
        process.environment = ProcessRunner.minimalEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("com.apple.TimeMachine")
    }
}
