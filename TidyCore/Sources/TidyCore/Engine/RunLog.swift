import Foundation

/// Appends one JSON line per run to `runs.jsonl`, generalizing the shell
/// script's `~/.claude/cleanup.log`.
public enum RunLog: Sendable {
    public static var defaultURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Tidy", isDirectory: true).appendingPathComponent("runs.jsonl")
    }

    public static func append(_ report: RunReport, to url: URL? = RunLog.defaultURL) {
        guard let url else { return }
        guard let data = try? JSONEncoder().encode(report), let line = String(data: data, encoding: .utf8) else {
            return
        }

        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let entry = (line + "\n").data(using: .utf8) ?? Data()
        if fm.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(entry)
        } else {
            try? entry.write(to: url, options: .atomic)
        }
    }

    public static func readAll(from url: URL? = RunLog.defaultURL) -> [RunReport] {
        guard let url, let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(RunReport.self, from: lineData)
            }
    }
}
