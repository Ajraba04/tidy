import Foundation

/// Human-readable byte counts, matching the shell script's `human()` but
/// using `ByteCountFormatter` for locale-correct, binary-prefixed output.
public enum ByteFormat: Sendable {
    public static func human(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
