import Foundation

/// The only operation in v1 that needs root: `tmutil deletelocalsnapshots`.
/// Run through `osascript … with administrator privileges` rather than a
/// standing privileged helper — this is rare, one-shot, and user-initiated,
/// which doesn't justify a second signed binary and an XPC connection. That
/// becomes worth it if a v2 needs more privileged operations than this one.
public enum SnapshotDeleter: Sendable {
    /// Every date component is validated against `tmutil`'s own format
    /// before it's ever embedded in a shell command string. The values
    /// come from `tmutil listlocalsnapshots` output, not user input, but
    /// this check stays regardless — an admin-privileged command string is
    /// exactly the place a validation shortcut later regrets itself.
    static func isValidDateComponent(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil
    }

    /// Deletes every given snapshot in a single administrator-privileged
    /// shell invocation, so the user is prompted once, not once per
    /// snapshot. Snapshots whose date component fails validation are
    /// dropped from the batch rather than aborting the whole operation.
    public static func deleteSnapshots(_ snapshots: [LocalSnapshot]) async -> Bool {
        let validComponents = snapshots.map(\.dateComponent).filter(isValidDateComponent)
        guard !validComponents.isEmpty else { return false }

        guard let osascriptPath = ToolLocator.locate("osascript") else { return false }
        guard let tmutilPath = ToolLocator.locate("tmutil") else { return false }

        let shellCommand = validComponents
            .map { "\(shellQuoted(tmutilPath)) deletelocalsnapshots \(shellQuoted($0))" }
            .joined(separator: " && ")
        let appleScript = "do shell script \(appleScriptQuoted(shellCommand)) with administrator privileges"

        let output = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: osascriptPath),
            arguments: ["-e", appleScript],
            timeout: 120
        )
        return output?.succeeded ?? false
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
