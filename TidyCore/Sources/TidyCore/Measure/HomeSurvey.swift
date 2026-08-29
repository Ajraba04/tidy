import Foundation

/// One walk of a tree that yields every number Scan needs from it at once:
/// the subtree total, the single files at or above a threshold, and
/// optionally a per-immediate-child breakdown.
///
/// Scan used to derive those from three separate traversals: a total per
/// top-level home entry, a second pass measuring each child of `~/Library`,
/// and a third full walk of `$HOME` hunting for large files. Since
/// `homeTopLevelEntries` includes `Library`, that walked `~/Library` three
/// times and the rest of home twice, every scan.
///
/// This deliberately shares no code with `SizeScanner.diskUsage`. That
/// function is the measurement path behind deletion estimates, used by both
/// `makePlan` and `deleteTargets`; this one only feeds a read-only report.
/// Keeping them apart means a bug here can make the Scan report wrong but
/// can never change what a plan claims it will free. The duplicated
/// per-entry predicate is the price, and it is worth paying.
public enum HomeSurvey: Sendable {
    public struct Result: Sendable {
        /// Total of the root's own allocated size plus every non-directory
        /// descendant, matching `SizeScanner.diskUsage` exactly so the two
        /// remain comparable.
        public let totalBytes: Int64
        /// Single regular files at or above the requested threshold.
        public let largeFiles: [RankedItem]
        /// Per-immediate-child totals, empty unless `breakOutChildren`.
        public let childTotals: [RankedItem]

        public init(totalBytes: Int64, largeFiles: [RankedItem], childTotals: [RankedItem]) {
            self.totalBytes = totalBytes
            self.largeFiles = largeFiles
            self.childTotals = childTotals
        }
    }

    /// Walks `root` once. `largeFileThreshold` of 0 disables large-file
    /// collection; `breakOutChildren` adds the per-child breakdown.
    ///
    /// Hardlinked files are counted once per walk, the way `du` does it, so
    /// the reported figure matches the tool a user is likely to check
    /// against. APFS *clones* still count once per clone: no public
    /// URLResourceKey exposes shared-extent accounting, and `du` overcounts
    /// them too.
    public static func walk(
        root rootPath: String,
        protectedRoots: [String],
        largeFileThreshold: Int64,
        breakOutChildren: Bool,
        visitCounter: (@Sendable () -> Void)? = nil
    ) -> Result {
        let fm = FileManager.default
        let canonicalRoot = PathGuard.canonicalize(rootPath)
        let canonicalProtectedRoots = protectedRoots.map(PathGuard.canonicalize)

        if isProtected(canonicalRoot, protectedRoots: canonicalProtectedRoots) {
            return Result(totalBytes: 0, largeFiles: [], childTotals: [])
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: canonicalRoot, isDirectory: &isDirectory) else {
            return Result(totalBytes: 0, largeFiles: [], childTotals: [])
        }

        let rootURL = URL(fileURLWithPath: canonicalRoot)
        let rootOwnBytes = allocatedSize(of: rootURL)

        // A file root measures as itself, mirroring `diskUsage`.
        guard isDirectory.boolValue else {
            let large = rootOwnBytes >= largeFileThreshold && largeFileThreshold > 0
                ? [RankedItem(path: canonicalRoot, bytes: rootOwnBytes)]
                : []
            return Result(totalBytes: rootOwnBytes, largeFiles: large, childTotals: [])
        }

        let rootVolumeID = try? rootURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .volumeIdentifierKey,
            .linkCountKey,
            .fileResourceIdentifierKey
        ]
        let keySet = Set(keys)
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: []) else {
            return Result(totalBytes: rootOwnBytes, largeFiles: [], childTotals: [])
        }

        var total = rootOwnBytes
        var largeFiles: [RankedItem] = []
        var childBytes: [String: Int64] = [:]
        var seenHardlinks: Set<NSObject> = []
        let prefixCount = canonicalRoot.hasSuffix("/") ? canonicalRoot.count : canonicalRoot.count + 1

        for case let fileURL as URL in enumerator {
            let path = fileURL.path

            if isProtected(path, protectedRoots: canonicalProtectedRoots) {
                enumerator.skipDescendants()
                continue
            }

            visitCounter?()
            guard let values = try? fileURL.resourceValues(forKeys: keySet) else { continue }

            if let childVolumeID = values.volumeIdentifier as AnyObject?,
               let rootVolumeID = rootVolumeID as AnyObject?,
               !childVolumeID.isEqual(rootVolumeID) {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }

            if values.isSymbolicLink == true { continue }

            let isDir = values.isDirectory == true
            let bytes = Int64(values.totalFileAllocatedSize ?? 0)

            // Count a hardlinked inode once per walk, as `du` does.
            if !isDir, (values.linkCount ?? 1) > 1,
               let identifier = values.fileResourceIdentifier as? NSObject {
                if seenHardlinks.contains(identifier) { continue }
                seenHardlinks.insert(identifier)
            }

            if !isDir {
                total += bytes
                if largeFileThreshold > 0, values.isRegularFile == true, bytes >= largeFileThreshold {
                    largeFiles.append(RankedItem(path: path, bytes: bytes))
                }
            }

            if breakOutChildren, path.count > prefixCount {
                let relative = path.dropFirst(prefixCount)
                let isImmediateChild = !relative.contains("/")
                // A child's total is its own allocated size plus every
                // non-directory descendant, matching a `diskUsage` call
                // made directly against that child.
                if isImmediateChild || !isDir {
                    let key = isImmediateChild
                        ? String(relative)
                        : String(relative[relative.startIndex..<(relative.firstIndex(of: "/") ?? relative.endIndex)])
                    childBytes[key, default: 0] += bytes
                }
            }
        }

        let childTotals = childBytes.map { key, bytes in
            RankedItem(path: canonicalRoot + "/" + key, bytes: bytes)
        }

        return Result(totalBytes: total, largeFiles: largeFiles, childTotals: childTotals)
    }

    /// Starts the T08 bounded form of the survey through a caller-owned explicit bridge session.
    /// The synchronous compatibility path above remains in place until ScanEngine adoption in
    /// T08.4; this adapter neither creates nor retains scheduler authority.
    public static func walkBounded(
        sessions: BridgeExplicitSessions,
        session: WorkSession,
        sessionID: UUID,
        generation: UInt64,
        root rootPath: String,
        protectedRoots: [String],
        largeFileThreshold: Int64,
        breakOutChildren: Bool,
        limits: TraversalLimits
    ) async -> BoundedTraversalPage {
        let traversal = BoundedTraversal(sessions: sessions, limits: limits)
        let result = await traversal.start(
            root: rootPath,
            session: session,
            sessionID: sessionID,
            generation: generation,
            options: TraversalOptions(
                protectedRoots: protectedRoots,
                minimumFileBytes: largeFileThreshold > 0 ? largeFileThreshold : nil,
                collectChildTotals: breakOutChildren,
                recordSelection: .none
            )
        )
        return BoundedTraversalPage(traversal: traversal, result: result)
    }

    /// Where an indexed walk's total came from, exposed only for tests and diagnostics — never
    /// something a caller branches deletion or planning behavior on.
    public enum IndexSource: Equatable, Sendable {
        /// The coordinator held a complete, still-current aggregate; the tree was not re-walked.
        case cached
        /// No usable cached aggregate existed, so a full walk ran and its result was committed.
        case freshCommitted
        /// A full walk ran, but the root's generation moved before the commit's barrier
        /// finished, so the fresh result is truthful but the index itself was not updated.
        case freshStaleAtCommit
        /// A full walk ran but indexing is off, unavailable, or the identity could not be
        /// resolved; nothing was cached either way.
        case liveOnly
    }

    /// The T09 entry point: consults `coordinator` for a still-current aggregate before doing
    /// any filesystem work at all, and only walks `root` when the cache cannot be trusted.
    /// `visitCounter`, when supplied, is called once per metadata fetch a real walk performs —
    /// the unchanged-tree case calls it at most once (a single existence check standing in for
    /// the walk that was skipped), which is how the ≥80% metadata-visit reduction is verified.
    ///
    /// A `.stale` or `.unavailable` status is never treated as a shortcut: only a `.cached`
    /// record whose coverage was already complete authorizes skipping the walk, matching the
    /// contract that partial scans never replace complete records and a cache can never be
    /// execution authority — here that means it can influence at most whether *this function*
    /// does its own redundant work, never what gets reported or cleaned.
    public static func walkIndexed(
        root rootPath: String,
        protectedRoots: [String],
        largeFileThreshold: Int64,
        breakOutChildren: Bool,
        scannerVersion: Int,
        policyFingerprint: String,
        coordinator: ScanIndexCoordinator,
        visitCounter: (@Sendable () -> Void)? = nil
    ) async -> (result: Result, source: IndexSource) {
        let canonicalRoot = PathGuard.canonicalize(rootPath)
        guard let identity = ScanRootIdentity.resolve(path: canonicalRoot) else {
            let result = walk(root: rootPath, protectedRoots: protectedRoots,
                largeFileThreshold: largeFileThreshold, breakOutChildren: breakOutChildren,
                visitCounter: visitCounter)
            return (result, .liveOnly)
        }
        let key = ScanIndexKey(volumeUUID: identity.volumeUUID, rootIdentity: identity.fileIdentity,
            scannerVersion: scannerVersion, policyFingerprint: policyFingerprint)
        let capturedGeneration = await coordinator.beginScan(root: canonicalRoot)
        if case .cached(let record) = await coordinator.status(for: key, root: canonicalRoot),
           record.isComplete {
            visitCounter?()
            return (Result(totalBytes: record.totalBytes, largeFiles: [], childTotals: []), .cached)
        }
        let result = walk(root: rootPath, protectedRoots: protectedRoots,
            largeFileThreshold: largeFileThreshold, breakOutChildren: breakOutChildren,
            visitCounter: visitCounter)
        let outcome = await coordinator.commitIfCurrent(key: key, root: canonicalRoot,
            volumeUUID: identity.volumeUUID, capturedGeneration: capturedGeneration,
            totalBytes: result.totalBytes, processedEntries: 0, isComplete: true, reasons: [])
        switch outcome {
        case .committed: return (result, .freshCommitted)
        case .staleGeneration, .rejectedPartialOverComplete, .unavailable:
            return (result, .freshStaleAtCommit)
        }
    }

    private static func isProtected(_ path: String, protectedRoots: [String]) -> Bool {
        protectedRoots.contains { PathGuard.isEqualOrDescendant(path, of: $0) }
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        (try? Int64(url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0)) ?? 0
    }
}
