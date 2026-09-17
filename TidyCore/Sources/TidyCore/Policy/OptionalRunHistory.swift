import Darwin
import Foundation

public struct OptionalRunHistoryPolicy: Equatable, Sendable {
    public let enabled: Bool
    public let retentionDays: Int
    public let maxMiB: Int
    public init(enabled: Bool, retentionDays: Int, maxMiB: Int) {
        self.enabled = enabled; self.retentionDays = retentionDays; self.maxMiB = maxMiB
    }
    public static func resolve(_ policy: EffectivePolicy?) -> OptionalRunHistoryPolicy {
        func bool(_ id: String, _ fallback: Bool) -> Bool {
            guard case .stored(.bool(let value))? = policy?.fields[SettingID(rawValue: id)]?.value
            else { return fallback }; return value
        }
        func integer(_ id: String, _ fallback: Int) -> Int {
            guard case .stored(.integer(let value))? = policy?.fields[SettingID(rawValue: id)]?.value,
                  let converted = Int(exactly: value) else { return fallback }; return converted
        }
        return .init(enabled: policy?.allowedFeatures.contains("history") == true
            && bool("history.enabled", true),
            retentionDays: integer("history.retentionDays", 30),
            maxMiB: integer("history.maxMiB", 10))
    }
}

public enum OptionalRunHistoryOutcome: Equatable, Sendable {
    case recorded(retainedCount: Int), disabled, entryExceedsLimit
}

/// Serialized storage anchored to one owner-only directory and the exact
/// `runs.jsonl` filename. Callers cannot redirect an operation to a journal.
public actor OptionalRunHistoryStore {
    public enum Error: Swift.Error, Equatable, Sendable {
        case malformed, invalidPolicy, unsafeStorage, oversized, unavailable
    }
    private static let filename = "runs.jsonl"
    private let directory: URL

    public init(directory: URL) throws {
        let value = directory.standardizedFileURL
        guard value.isFileURL, value.path.hasPrefix("/"),
              value.lastPathComponent != ".", value.lastPathComponent != ".."
        else { throw Error.unsafeStorage }
        self.directory = value
    }
    public var fileURL: URL { directory.appendingPathComponent(Self.filename) }

    @discardableResult
    public func record(_ report: RunReport, policy: OptionalRunHistoryPolicy,
                       now: Date = Date()) throws -> OptionalRunHistoryOutcome {
        guard policy.enabled else { return try reconcile(policy: policy, now: now) }
        let limits = try validatedLimits(policy)
        let entry = try encodedLine(report)
        guard entry.count <= limits.maxBytes else { return .entryExceedsLimit }
        var retained = try load(maxBytes: limits.maxBytes).filter {
            now.timeIntervalSince($0.finishedAt) <= limits.maxAge
        }
        retained.append(report)
        var lines = try retained.map(encodedLine)
        var total = lines.reduce(0) { $0 + $1.count }
        while total > limits.maxBytes, !lines.isEmpty {
            total -= lines.removeFirst().count; retained.removeFirst()
        }
        try publish(lines)
        return .recorded(retainedCount: retained.count)
    }

    @discardableResult
    public func reconcile(policy: OptionalRunHistoryPolicy,
                          now: Date = Date()) throws -> OptionalRunHistoryOutcome {
        let limits = try validatedLimits(policy)
        guard policy.enabled else {
            try removeValidatedIfPresent(maxBytes: limits.maxBytes); return .disabled
        }
        var retained = try load(maxBytes: limits.maxBytes).filter {
            now.timeIntervalSince($0.finishedAt) <= limits.maxAge
        }
        var lines = try retained.map(encodedLine)
        var total = lines.reduce(0) { $0 + $1.count }
        while total > limits.maxBytes, !lines.isEmpty {
            total -= lines.removeFirst().count; retained.removeFirst()
        }
        try publish(lines)
        return .recorded(retainedCount: retained.count)
    }

    public func read(policy: OptionalRunHistoryPolicy) throws -> [RunReport] {
        try load(maxBytes: validatedLimits(policy).maxBytes)
    }

    private func validatedLimits(_ policy: OptionalRunHistoryPolicy)
        throws -> (maxAge: TimeInterval, maxBytes: Int) {
        guard (1...90).contains(policy.retentionDays), (1...50).contains(policy.maxMiB)
        else { throw Error.invalidPolicy }
        return (TimeInterval(policy.retentionDays) * 86_400, policy.maxMiB * 1_048_576)
    }

    private func openDirectory() throws -> Int32 {
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Error.unsafeStorage }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(), (info.st_mode & 0o022) == 0 else {
            Darwin.close(fd); throw Error.unsafeStorage
        }
        return fd
    }

    private func validatedFile(_ directoryFD: Int32, maxBytes: Int)
        throws -> (fd: Int32, identity: stat)? {
        let fd = openat(directoryFD, Self.filename,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw Error.unsafeStorage }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1 else {
            Darwin.close(fd); throw Error.unsafeStorage
        }
        guard info.st_size >= 0, info.st_size <= maxBytes else {
            Darwin.close(fd); throw Error.oversized
        }
        return (fd, info)
    }

    private func load(maxBytes: Int) throws -> [RunReport] {
        let directoryFD = try openDirectory(); defer { Darwin.close(directoryFD) }
        guard let opened = try validatedFile(directoryFD, maxBytes: maxBytes) else { return [] }
        defer { Darwin.close(opened.fd) }
        var bytes = Data(); bytes.reserveCapacity(Int(opened.identity.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(opened.fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw Error.unavailable }
            guard bytes.count + count <= maxBytes else { throw Error.oversized }
            bytes.append(buffer, count: count)
        }
        guard bytes.isEmpty || bytes.last == 0x0A else { throw Error.malformed }
        let decoder = JSONDecoder()
        return try bytes.split(separator: 0x0A).map { line in
            do { return try decoder.decode(RunReport.self, from: Data(line)) }
            catch { throw Error.malformed }
        }
    }

    private func removeValidatedIfPresent(maxBytes: Int) throws {
        let directoryFD = try openDirectory(); defer { Darwin.close(directoryFD) }
        guard let opened = try validatedFile(directoryFD, maxBytes: maxBytes) else { return }
        defer { Darwin.close(opened.fd) }
        var current = stat()
        guard fstatat(directoryFD, Self.filename, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_dev == opened.identity.st_dev, current.st_ino == opened.identity.st_ino,
              (current.st_mode & S_IFMT) == S_IFREG else { throw Error.unsafeStorage }
        guard unlinkat(directoryFD, Self.filename, 0) == 0 else { throw Error.unavailable }
        guard fsync(directoryFD) == 0 else { throw Error.unavailable }
    }

    private func publish(_ lines: [Data]) throws {
        if lines.isEmpty { return try removeValidatedIfPresent(maxBytes: 50 * 1_048_576) }
        let directoryFD = try openDirectory(); defer { Darwin.close(directoryFD) }
        if let existing = try validatedFile(directoryFD, maxBytes: 50 * 1_048_576) {
            Darwin.close(existing.fd)
        }
        let temporary = ".runs-" + UUID().uuidString
        let fd = openat(directoryFD, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Error.unavailable }
        var keepTemporary = true
        defer {
            Darwin.close(fd)
            if keepTemporary { _ = unlinkat(directoryFD, temporary, 0) }
        }
        for line in lines { try writeAll(line, to: fd) }
        guard fsync(fd) == 0,
              renameat(directoryFD, temporary, directoryFD, Self.filename) == 0,
              fsync(directoryFD) == 0 else { throw Error.unavailable }
        keepTemporary = false
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw Error.unavailable }
                offset += count
            }
        }
    }

    private func encodedLine(_ report: RunReport) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(report); data.append(0x0A); return data
    }
}
