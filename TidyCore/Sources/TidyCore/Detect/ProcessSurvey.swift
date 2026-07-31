import Foundation

public struct ProcessUsage: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let residentBytes: Int64
}

/// Reads process memory via `ps`: there is no `FileManager`-based way to
/// enumerate per-process RSS, so this is one of the few places TidyCore
/// shells out for something other than a tool's own index/DB, matching what
/// the shell script itself does.
public enum ProcessSurvey: Sendable {
    public static func topMemoryConsumers(limit: Int = 8) async -> [ProcessUsage] {
        guard let psPath = ToolLocator.locate("ps") else { return [] }
        guard let output = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: psPath),
            arguments: ["-Ao", "rss,comm", "-m"]
        ), output.succeeded else {
            return []
        }

        let lines = output.standardOutput.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return [] }

        var results: [ProcessUsage] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let rssKB = Int64(parts[0]) else { continue }
            let name = (String(parts[1]) as NSString).lastPathComponent
            results.append(ProcessUsage(name: name, residentBytes: rssKB * 1024))
            if results.count == limit { break }
        }
        return results
    }
}
