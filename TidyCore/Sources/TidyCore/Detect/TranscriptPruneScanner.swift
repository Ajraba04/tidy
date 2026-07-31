import Foundation

/// Finds Claude Code session transcript files older than the configured
/// threshold under `~/.claude/projects`, while never walking into any
/// `memory/` directory — those hold hand-written, persistent memory files,
/// not transcripts, and age past any threshold just by being correct.
public enum TranscriptPruneScanner: Sendable {
    public static func findOldTranscripts(claudeProjectsDirectory: String, olderThanDays: Int) -> [TargetPath] {
        guard olderThanDays > 0 else { return [] }
        let threshold = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: claudeProjectsDirectory)

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else {
            return []
        }

        var results: [TargetPath] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]) else {
                continue
            }

            if values.isDirectory == true {
                if url.lastPathComponent == "memory" {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard let modified = values.contentModificationDate, modified < threshold else { continue }
            results.append(TargetPath(path: url.path, label: PathDisplay.tilde(url.path)))
        }
        return results
    }
}
