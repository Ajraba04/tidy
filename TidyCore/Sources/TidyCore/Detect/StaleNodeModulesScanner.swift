import Foundation

/// Finds `node_modules` directories, under the user's configured project
/// roots, whose own modification time is older than the configured
/// threshold: reclonable dependency trees a project hasn't touched in a
/// while. Read-only: reports candidates, never deletes.
public enum StaleNodeModulesScanner: Sendable {
    public static func find(roots: [String], olderThanDays: Int, maxDepth: Int = 5) -> [TargetPath] {
        guard olderThanDays > 0 else { return [] }
        let threshold = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        let fm = FileManager.default
        var results: [TargetPath] = []

        for root in roots {
            // Canonicalize first: `FileManager`'s enumerator reports fully
            // resolved child paths (e.g. `/private/var/...`) regardless of
            // whether the root URL was resolved, which would otherwise
            // throw off the depth count by however many path components
            // the resolution adds.
            let rootURL = URL(fileURLWithPath: PathGuard.canonicalize(root))
            let rootDepth = rootURL.pathComponents.count

            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: []
            ) else { continue }

            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - rootDepth
                if depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                guard url.lastPathComponent == "node_modules",
                      let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                      values.isDirectory == true
                else { continue }

                // Prune: a node_modules dir's own contents are never
                // interesting to walk into, and doing so would be wasted
                // I/O on what is often the largest subtree in the project.
                enumerator.skipDescendants()

                guard let modified = values.contentModificationDate, modified < threshold else { continue }
                results.append(TargetPath(path: url.path, label: url.path))
            }
        }

        return results
    }

    /// Starts one bounded root through a caller-owned explicit bridge session. Multi-root fan-out
    /// remains with T08.4 so this low-level API cannot retain an unbounded page array. Matching
    /// `node_modules` directories prune their descendants in the bounded traversal.
    public static func findBounded(
        root: String,
        olderThanDays: Int,
        maxDepth: Int = 5,
        protectedRoots: [String] = CleanEnvironment.defaultProtectedRoots(homeDirectory: NSHomeDirectory()),
        sessions: BridgeExplicitSessions,
        session: WorkSession,
        sessionID: UUID,
        generation: UInt64,
        limits: TraversalLimits
    ) async -> BoundedTraversalPage? {
        guard olderThanDays > 0, maxDepth > 0 else { return nil }
        let threshold = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        let traversalLimits = limits.replacing(maxDepth: min(maxDepth, limits.maxDepth))
        let traversal = BoundedTraversal(sessions: sessions, limits: traversalLimits)
        let result = await traversal.start(
            root: root,
            session: session,
            sessionID: sessionID,
            generation: generation,
            options: TraversalOptions(
                protectedRoots: protectedRoots,
                recordSelection: .directory(named: "node_modules", modifiedBefore: threshold),
                pruneMatchedDirectories: true
            )
        )
        return BoundedTraversalPage(traversal: traversal, result: result)
    }
}
