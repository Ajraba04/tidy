import Foundation

/// Finds big directories that no catalog item claims: the honest answer to
/// "what can't Tidy see?".
///
/// Written after `~/Library/Application Support/Claude` was found holding
/// 14 GB, of which one item covered `vm_bundles` while three siblings that
/// grew up later -- `local-agent-mode-sessions`, `simulator-builds`,
/// `claude-code` -- were covered by nothing. Adding three more rows would
/// have fixed that week and drifted again the next. This detects the drift
/// instead, and catches whole-tree gaps like `~/.codex` in the same pass.
///
/// Read-only by construction: it produces `RankedItem`, never `TargetPath`
/// or `CleanItem`, so there is no route from anything it reports into a
/// `CleanPlan`. Anything worth cleaning here becomes a catalog item that a
/// human wrote, reviewed, and gave a declared root.
public enum UnclaimedSpaceScanner: Sendable {
    /// Directories below this are noise, not drift.
    public static let defaultThresholdBytes: Int64 = 500 * 1024 * 1024
    static let maximumResults = 8
    /// A directory with more children than this is a data store, not a
    /// place where a few named siblings drifted out of coverage.
    static let maximumSiblingsPerParent = 64

    public static func find(
        measuredPaths: [String: Int64],
        environment: CleanEnvironment,
        catalog: [CleanItem] = CleanCatalog.allItems,
        thresholdBytes: Int64 = defaultThresholdBytes
    ) -> [RankedItem] {
        let claimed = claimedPaths(catalog: catalog, environment: environment)
        var found: [RankedItem] = []

        // 1. Whole top-level entries containing no claimed path at all.
        //    Already measured by the scan, so this costs nothing.
        for (path, bytes) in measuredPaths where bytes >= thresholdBytes {
            if !subtreeTouchesAnyClaim(path, claimed: claimed) {
                found.append(RankedItem(path: path, bytes: bytes))
            }
        }

        // 2. Siblings of claimed paths that are themselves unclaimed: the
        //    drift case, where coverage exists for one child of a directory
        //    and the directory has since grown others.
        let fm = FileManager.default
        var inspectedParents: Set<String> = []
        var candidates: Set<String> = []

        for claimedPath in claimed {
            let parent = (claimedPath as NSString).deletingLastPathComponent
            guard parent.count > 1, inspectedParents.insert(parent).inserted else { continue }
            guard let names = try? fm.contentsOfDirectory(atPath: parent),
                  names.count <= maximumSiblingsPerParent else { continue }

            for name in names {
                let sibling = parent + "/" + name
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: sibling, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                guard !subtreeTouchesAnyClaim(sibling, claimed: claimed) else { continue }
                candidates.insert(sibling)
            }
        }

        for candidate in candidates {
            let result = HomeSurvey.walk(
                root: candidate,
                protectedRoots: environment.protectedRoots,
                largeFileThreshold: 0,
                breakOutChildren: false
            )
            if result.totalBytes >= thresholdBytes {
                found.append(RankedItem(path: candidate, bytes: result.totalBytes))
            }
        }

        return Array(
            found
                .sorted { $0.bytes > $1.bytes }
                .prefix(maximumResults)
        )
    }

    /// Every path the catalog actually resolves to on this machine.
    /// Evaluating `locate` is read-only -- `CleanCatalogTests` already
    /// relies on that -- and items gated on absent toolchains are skipped so
    /// an uninstalled tool's directory does not read as covered.
    ///
    /// Declared roots are deliberately *not* claims. A declared root is a
    /// containment boundary, not a statement of coverage: most items
    /// declare `$HOME`, so counting roots as claims would mark the entire
    /// home directory covered and this scanner would never report anything.
    static func claimedPaths(catalog: [CleanItem], environment: CleanEnvironment) -> [String] {
        var paths: [String] = []
        for item in catalog where item.isRelevant(in: environment) {
            for target in item.locate(environment) where target.isFilesystemPath {
                paths.append(PathGuard.canonicalize(target.path))
            }
        }
        return paths
    }

    /// True when any claimed path is this path, sits inside it, or contains
    /// it. A directory holding even one claimed path is covered territory;
    /// reporting `~/Library` as "unclaimed" because no item names the
    /// directory itself would be noise, not a finding.
    static func subtreeTouchesAnyClaim(_ path: String, claimed: [String]) -> Bool {
        let canonical = PathGuard.canonicalize(path)
        return claimed.contains { claim in
            PathGuard.isEqualOrDescendant(claim, of: canonical)
                || PathGuard.isEqualOrDescendant(canonical, of: claim)
        }
    }
}
