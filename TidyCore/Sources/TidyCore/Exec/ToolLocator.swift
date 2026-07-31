import Foundation

/// Finds an executable's absolute path without ever trusting the caller's
/// inherited `PATH`. Xcode-owned tools resolve through `xcrun --find`; other
/// CLIs are looked up in a small, fixed list of install locations. If a tool
/// cannot be found this way, callers must render a "not found" row — never
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

    /// A tool's resolved path never changes mid-run, so results are cached
    /// by name. Beyond the obvious repeat-lookup saving, this bounds how
    /// many `xcrun --find` processes ever spawn (one per distinct name, not
    /// one per caller) — `locateViaXcrun` blocks its calling thread inside
    /// `Process.waitUntilExit()`'s own nested run loop, and enough
    /// concurrent callers (many catalog items checked at once, a large
    /// test suite) can exhaust Swift's cooperative thread pool the same way
    /// `ProcessRunner` guards against.
    private static let cache = LocatorCache()

    /// Caps concurrent `xcrun --find` spawns for names not yet cached (a
    /// cold-start thundering herd), independent of `ProcessRunner`'s gate
    /// since this path never goes through `ProcessRunner`.
    private static let concurrencyLimit = DispatchSemaphore(value: 4)

    public static func locate(_ name: String) -> String? {
        if let cached = cache.value(for: name) {
            return cached
        }
        concurrencyLimit.wait()
        defer { concurrencyLimit.signal() }

        // Another thread may have populated the cache while this one
        // waited on the semaphore.
        if let cached = cache.value(for: name) {
            return cached
        }

        let resolved = locateUncached(name)
        cache.store(resolved, for: name)
        return resolved
    }

    public static func isAvailable(_ name: String) -> Bool {
        locate(name) != nil
    }

    private static func locateUncached(_ name: String) -> String? {
        if let found = locateViaXcrun(name) {
            return found
        }
        for directory in fixedSearchDirectories {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func locateViaXcrun(_ name: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = ["--find", name]
        process.environment = ProcessRunner.minimalEnvironment

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty,
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
    private var storage: [String: String?] = [:]

    func value(for name: String) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        return storage[name]
    }

    func store(_ path: String?, for name: String) {
        lock.lock()
        storage[name] = path
        lock.unlock()
    }
}
