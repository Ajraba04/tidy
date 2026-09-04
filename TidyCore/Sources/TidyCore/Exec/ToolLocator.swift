import Foundation

/// Finds an executable's absolute path without ever trusting the caller's
/// inherited `PATH`. Xcode-owned tools resolve through `xcrun --find`; other
/// CLIs are looked up in a small, fixed list of install locations. If a tool
/// cannot be found this way, callers must render a "not found" row; never
/// fall back to a shell that would search the user's PATH.
public enum ToolLocator: Sendable {
    static let xcrunPath = "/usr/bin/xcrun"

    static let fixedSearchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    /// Synchronous catalog discovery is intentionally fixed-path-only. The
    /// later T08.4 async catalog owner can adopt `locateAsync`; this route
    /// never blocks a cooperative thread or starts a private process.
    private static let fixedCache = LocatorCache(limit: 128)
    private static let asyncCache = AsyncLocatorCache(resultLimit: 128, inFlightLimit: 32)

    public static func locate(_ name: String) -> String? {
        guard validName(name) else { return nil }
        if let cached = fixedCache.value(for: name) { return cached }
        let resolved = locateInFixedDirectories(name)
        fixedCache.store(resolved, for: name)
        return resolved
    }

    public static func isAvailable(_ name: String) -> Bool {
        locate(name) != nil
    }

    /// Async discovery adds the reviewed `xcrun --find` fallback through the
    /// sole bounded process runner. Same-name cold lookups share one in-flight
    /// task; both in-flight and retained result cardinality are finite.
    public static func locateAsync(_ name: String) async -> String? {
        guard validName(name) else { return nil }
        if let fixed = locate(name) { return fixed }
        return await asyncCache.resolve(name) { await locateViaXcrun(name) }
    }

    public static func isAvailableAsync(_ name: String) async -> Bool {
        await locateAsync(name) != nil
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 128
            && name.allSatisfy { $0.isLetter || $0.isNumber || "-._+".contains($0) }
    }

    private static func locateInFixedDirectories(_ name: String) -> String? {
        for directory in fixedSearchDirectories {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func locateViaXcrun(_ name: String) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else { return nil }
        guard let output = try? await ProcessRunner.runXcrunFind(name), output.succeeded else {
            return nil
        }
        let path = output.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
            FileManager.default.isExecutableFile(atPath: path)
        else {
            return nil
        }
        return path
    }
}

/// Lock-protected cache distinguishing "not yet looked up" from "looked up,
/// not found" (`nil`).
private final class LocatorCache: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage: [String: String?] = [:]
    private var order: [String] = []

    init(limit: Int) { self.limit = limit }

    func value(for name: String) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        return storage[name]
    }

    func store(_ path: String?, for name: String) {
        lock.lock()
        if storage[name] == nil {
            if order.count == limit, let oldest = order.first {
                order.removeFirst(); storage.removeValue(forKey: oldest)
            }
            order.append(name)
        }
        storage.updateValue(path, forKey: name)
        lock.unlock()
    }
}

private actor AsyncLocatorCache {
    private enum Entry { case found(String), missing }
    private let resultLimit: Int
    private let inFlightLimit: Int
    private var results: [String: Entry] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<String?, Never>] = [:]

    init(resultLimit: Int, inFlightLimit: Int) {
        self.resultLimit = resultLimit; self.inFlightLimit = inFlightLimit
    }

    func resolve(_ name: String, operation: @escaping @Sendable () async -> String?) async -> String? {
        if let entry = results[name] {
            if case .found(let path) = entry { return path }
            return nil
        }
        if let existing = inFlight[name] { return await existing.value }
        guard inFlight.count < inFlightLimit else { return nil }
        let task = Task { await operation() }
        inFlight[name] = task
        let value = await task.value
        inFlight.removeValue(forKey: name)
        if results[name] == nil {
            if order.count == resultLimit, let oldest = order.first {
                order.removeFirst(); results.removeValue(forKey: oldest)
            }
            order.append(name)
        }
        results[name] = value.map(Entry.found) ?? .missing
        return value
    }
}
