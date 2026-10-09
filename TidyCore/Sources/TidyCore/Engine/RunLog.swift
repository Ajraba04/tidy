import Darwin
import Foundation

public struct RunHistoryPolicy: Sendable {
    public let enabled: Bool
    public let days: Int
    public let maximumBytes: Int
    public init(enabled: Bool = true, days: Int = 30, maximumBytes: Int = 10_485_760) {
        self.enabled = enabled
        self.days = min(90, max(1, days))
        self.maximumBytes = min(52_428_800, max(1_048_576, maximumBytes))
    }
    public static func resolve(_ policy: EffectivePolicy?) -> Self {
        guard let policy else { return .init(enabled: false) }
        func integer(_ id: String, _ fallback: Int) -> Int {
            guard case .stored(.integer(let value))? = policy.fields[.init(rawValue: id)]?.value,
                  let result = Int(exactly: value) else { return fallback }
            return result
        }
        let enabled = policy.fields[.init(rawValue: "history.enabled")]?.value == .stored(.bool(true))
        return .init(enabled: enabled, days: integer("history.retentionDays", 30),
                     maximumBytes: integer("history.maxMiB", 10) * 1_048_576)
    }
}

/// Optional, bounded, path-redacted history. Mandatory recovery uses RunJournal separately.
public enum RunLog: Sendable {
    public static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Tidy/runs.jsonl")
    }
    public enum StorageError: Error { case unavailable, oversized }

    /// Compatibility entry point. Production callers use throwing update off the main actor.
    public static func append(_ report: RunReport, to url: URL? = RunLog.defaultURL) {
        guard let url else { return }
        try? update(report, at: url, policy: .init(), now: report.finishedAt)
    }

    public static func update(_ report: RunReport? = nil, at url: URL,
                              policy: RunHistoryPolicy, now: Date = Date()) throws {
        if report == nil && !FileManager.default.fileExists(atPath: url.path) { return }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw StorageError.unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw StorageError.unavailable }
        defer { _ = flock(fd, LOCK_UN) }
        guard fchmod(fd, 0o600) == 0 else { throw StorageError.unavailable }
        var retained: [RunReport] = []
        if policy.enabled, info.st_size <= 52_428_800 {
            let data = try readBounded(fd)
            retained = decode(data).filter { $0.finishedAt >= now.addingTimeInterval(-Double(policy.days) * 86_400) }
            if let report { retained.append(redacted(report)) }
        } else if policy.enabled, let report {
            retained = [redacted(report)]
        }
        var encoded: [Data] = []
        var count = 0
        for entry in retained.suffix(2_000).reversed() {
            var line = try JSONEncoder().encode(redacted(entry))
            line.append(10)
            guard line.count <= policy.maximumBytes - count else { break }
            encoded.append(line); count += line.count
        }
        var bytes = Data()
        for line in encoded.reversed() { bytes.append(line) }
        guard lseek(fd, 0, SEEK_SET) == 0, ftruncate(fd, 0) == 0 else { throw StorageError.unavailable }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw StorageError.unavailable }
                offset += written
            }
        }
        guard fsync(fd) == 0 else { throw StorageError.unavailable }
    }

    public static func readAll(from url: URL? = RunLog.defaultURL) -> [RunReport] {
        guard let url else { return [] }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        guard flock(fd, LOCK_SH | LOCK_NB) == 0, let data = try? readBounded(fd) else { return [] }
        return decode(data)
    }
    private static func readBounded(_ fd: Int32) throws -> Data {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= 52_428_800 else { throw StorageError.oversized }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count == 0 { return result }
            if count < 0 && errno == EINTR { continue }
            guard count > 0, count <= 52_428_800 - result.count else { throw StorageError.unavailable }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
    private static func decode(_ data: Data) -> [RunReport] {
        var result: [RunReport] = []
        var end = data.endIndex
        while end > data.startIndex && result.count < 2_000 {
            if data[end - 1] == 10 { end -= 1 }
            guard end > data.startIndex else { break }
            let start = data[..<end].lastIndex(of: 10).map { $0 + 1 } ?? data.startIndex
            if end - start <= 262_144,
               let report = try? JSONDecoder().decode(RunReport.self, from: Data(data[start..<end])) {
                result.append(report)
            }
            end = start
        }
        return result.reversed()
    }
    private static func redacted(_ report: RunReport) -> RunReport {
        RunReport(tier: report.tier, results: report.results.map {
            ItemResult(id: $0.id, title: $0.title, freedBytes: $0.freedBytes,
                       reclaimedMemoryBytes: $0.measuredReclaimedMemoryBytes,
                       succeeded: $0.succeeded, message: nil, targetOutcomes: nil, effectStatus: $0.effectStatus)
        }, startedAt: report.startedAt, finishedAt: report.finishedAt,
            freeSpaceBeforeBytes: report.freeSpaceBeforeBytes, freeSpaceAfterBytes: report.freeSpaceAfterBytes,
            disposition: report.disposition, coordinatorMeasurementsAvailable: report.coordinatorMeasurementsAvailable,
            volumeObservations: report.volumeObservations, provenReclaimedBytes: report.provenReclaimedBytes)
    }
}
