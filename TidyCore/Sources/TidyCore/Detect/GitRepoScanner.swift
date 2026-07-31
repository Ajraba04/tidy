import Foundation

/// Finds git repositories (directories containing a `.git`) under the
/// user's configured roots, bounded by depth and never entering a
/// protected root.
public enum GitRepoScanner: Sendable {
    public static func findRepositories(roots: [String], protectedRoots: [String], maxDepth: Int = 5) -> [String] {
        let fm = FileManager.default
        let canonicalProtectedRoots = protectedRoots.map(PathGuard.canonicalize)
        var results: [String] = []

        for root in roots {
            let canonicalRoot = PathGuard.canonicalize(root)
            let rootURL = URL(fileURLWithPath: canonicalRoot)
            let rootDepth = rootURL.pathComponents.count

            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }

            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - rootDepth
                if depth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }

                if canonicalProtectedRoots.contains(where: { PathGuard.isEqualOrDescendant(url.path, of: $0) }) {
                    enumerator.skipDescendants()
                    continue
                }

                guard url.lastPathComponent == ".git",
                      let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                      isDirectory
                else { continue }

                enumerator.skipDescendants()
                results.append(url.deletingLastPathComponent().path)
            }
        }
        return results
    }
}
