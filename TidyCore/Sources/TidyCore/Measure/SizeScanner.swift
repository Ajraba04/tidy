import Foundation

/// Walks directories with `FileManager.enumerator`, never a spawned `du`:
/// cancellable, streams results as they land, and caps concurrent walks so a
/// scan of many large caches cannot starve the machine it is trying to free
/// up.
public actor SizeScanner {
    public struct Result: Sendable, Equatable {
        public let path: String
        public let bytes: Int64
    }

    private var generation = 0
    private let maxConcurrentWalks: Int

    /// Defaults to the machine's core count, clamped: this walk is
    /// syscall-bound rather than seek-bound on APFS, so a fixed low
    /// concurrency left throughput on the table.
    ///
    /// There is deliberately no size cache. One was tried and removed: a
    /// directory's mtime only changes when its *immediate* children change,
    /// so a cache keyed on it serves stale sizes for deep trees like
    /// `~/.gradle/caches`, and sound incremental sizing needs a change feed
    /// (FSEvents with a persisted event ID), not an mtime. Measuring a
    /// deletion estimate is not a place to be approximately right.
    public init(maxConcurrentWalks: Int = max(4, min(8, ProcessInfo.processInfo.activeProcessorCount))) {
        self.maxConcurrentWalks = maxConcurrentWalks
    }

    /// Cancels any in-flight `scan` call. The next `scan` call starts fresh.
    public func cancelAll() {
        generation += 1
    }

    /// Measures each path's on-disk size, honoring `protectedRoots` and
    /// never crossing onto a different mounted volume. Calls `onItem` as
    /// each path finishes, in no particular order.
    public func scan(
        paths: [String],
        protectedRoots: [String],
        onItem: (@Sendable (Result) -> Void)? = nil
    ) async -> [Result] {
        let myGeneration = generation
        let canonicalProtectedRoots = protectedRoots.map(PathGuard.canonicalize)
        var byPath: [String: Int64] = [:]

        await withTaskGroup(of: Result.self) { group in
            var nextIndex = 0

            func launchNext() {
                guard nextIndex < paths.count else { return }
                let path = paths[nextIndex]
                nextIndex += 1
                group.addTask(priority: .utility) {
                    let bytes = Self.diskUsage(ofPath: path, protectedRoots: canonicalProtectedRoots)
                    return Result(path: path, bytes: bytes)
                }
            }

            for _ in 0..<min(maxConcurrentWalks, paths.count) {
                launchNext()
            }

            while let result = await group.next() {
                if isCurrentGeneration(myGeneration) {
                    byPath[result.path] = result.bytes
                    onItem?(result)
                    launchNext()
                } else {
                    group.cancelAll()
                    break
                }
            }
        }

        return paths.compactMap { path in byPath[path].map { Result(path: path, bytes: $0) } }
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        generation == self.generation
    }

    /// Sums allocated size (`.totalFileAllocatedSizeKey`, matching `du`)
    /// under `rootPath`, skipping protected roots and anything outside the
    /// root's own volume. Runs off the actor so up to `maxConcurrentWalks`
    /// of these can execute in parallel.
    nonisolated static func diskUsage(ofPath rootPath: String, protectedRoots: [String]) -> Int64 {
        let fm = FileManager.default
        let canonicalRoot = PathGuard.canonicalize(rootPath)

        if isProtected(canonicalRoot, protectedRoots: protectedRoots) {
            return 0
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: canonicalRoot, isDirectory: &isDirectory) else { return 0 }

        let rootURL = URL(fileURLWithPath: canonicalRoot)

        guard isDirectory.boolValue else {
            return allocatedSize(of: rootURL)
        }

        let rootVolumeID = try? rootURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .volumeIdentifierKey
        ]
        let keySet = Set(keys)
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: []) else {
            return 0
        }

        var total: Int64 = allocatedSize(of: rootURL)

        for case let fileURL as URL in enumerator {
            let canonicalChild = fileURL.path

            if isProtected(canonicalChild, protectedRoots: protectedRoots) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: keySet) else { continue }

            if let childVolumeID = values.volumeIdentifier as AnyObject?,
               let rootVolumeID = rootVolumeID as AnyObject?,
               !childVolumeID.isEqual(rootVolumeID) {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            if values.isSymbolicLink == true {
                continue
            }

            if values.isDirectory != true {
                total += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }

        return total
    }

    private static func isProtected(_ path: String, protectedRoots: [String]) -> Bool {
        protectedRoots.contains { PathGuard.isEqualOrDescendant(path, of: $0) }
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        (try? Int64(url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0)) ?? 0
    }
}
