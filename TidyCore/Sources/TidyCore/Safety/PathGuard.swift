import Darwin
import Foundation

enum ProtectedRelation: Equatable { case disjoint, insideProtected, containsProtected }

extension PathGuard {
    static func relation(candidate: String, protectedRoot: String) throws -> ProtectedRelation {
        func components(_ path: String) throws -> [Substring] {
            guard path.hasPrefix("/"), !path.utf8.contains(0) else {
                throw GuardedFileError.invalidComponent
            }
            if path == "/" { return [] }
            let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw GuardedFileError.invalidComponent
            }
            return parts
        }
        let candidateParts = try components(candidate)
        let protectedParts = try components(protectedRoot)
        if candidateParts.starts(with: protectedParts) { return .insideProtected }
        if protectedParts.starts(with: candidateParts) { return .containsProtected }
        return .disjoint
    }
}

/// Legacy display/planning path-validation errors, not execution authority.
public enum PathGuardError: Error, Equatable, Sendable, CustomStringConvertible {
    case empty
    case notAbsolute(path: String)
    case isRoot
    case isHome
    case isSystemRoot(path: String)
    case insideProtectedRoot(path: String, root: String)
    case outsideDeclaredRoot(path: String, root: String)

    public var description: String {
        switch self {
        case .empty:
            return "refusing empty path"
        case .notAbsolute(let path):
            return "refusing non-absolute path: '\(path)'"
        case .isRoot:
            return "refusing unsafe path: '/'"
        case .isHome:
            return "refusing unsafe path: home directory"
        case .isSystemRoot(let path):
            return "refusing system path: \(path)"
        case .insideProtectedRoot(let path, let root):
            return "refusing path overlapping protected root: \(path) (protected: \(root))"
        case .outsideDeclaredRoot(let path, let root):
            return "refusing path outside its declared root: \(path) (expected under \(root))"
        }
    }
}

/// Canonicalizes and validates legacy display/planning paths, not effects.
/// A successful check or lexical fallback never creates execution authority;
/// guarded filesystem mechanisms validate no-follow descriptor identities.
///
/// Ports the shell script's `protected()` + the unsafe-path guard inside
/// `nuke()`, plus one hardening rule the script didn't need: every candidate
/// must resolve to somewhere under the `CleanItem` that produced it, so a bug
/// in one item's `locate` closure cannot reach another item's territory.
public struct PathGuard: Sendable {
    /// Container directories that must never themselves be deleted or
    /// emptied, whatever an item's `locate` closure returns. Matched
    /// exactly, not by prefix: `/Library` is refused while
    /// `/Library/Developer/CoreSimulator/Caches` stays reachable, because
    /// the catastrophic case is emptying the container, not cleaning
    /// something inside it.
    ///
    /// Every catalog item today declares a root under `$HOME`, so nothing
    /// here is reachable in practice. This is the guardrail that has to
    /// exist *before* any item declares a root above `$HOME`, not after.
    static let systemContainerPaths: Set<String> = [
        "/Users", "/System", "/Library", "/Applications", "/usr", "/bin",
        "/sbin", "/etc", "/var", "/private", "/opt", "/cores", "/Network",
        "/Volumes", "/System/Volumes", "/System/Volumes/Data",
        "/private/var", "/private/etc", "/private/tmp", "/tmp"
    ]

    /// Subtrees that are refused wholesale. `/System/Volumes` is excluded
    /// deliberately: the data volume and the VM volume live under it, and
    /// firmlinked user paths must stay reachable.
    static let systemSubtrees: [String] = ["/System/Library", "/usr", "/bin", "/sbin"]

    public let protectedRoots: [String]

    public init(protectedRoots: [String]) {
        self.protectedRoots = protectedRoots.map(Self.canonicalize)
    }

    /// Resolves symlinks and standardizes the path so comparisons are exact
    /// prefix comparisons rather than string guesses.
    ///
    /// Uses POSIX `realpath(3)` rather than `NSString.resolvingSymlinksInPath`:
    /// the latter deliberately leaves `/tmp`, `/var`, and `/etc` unresolved
    /// for compatibility, while `FileManager`'s directory enumerator (used by
    /// `SizeScanner`) reports fully-resolved `/private/var/...`-style paths.
    /// Comparing a lexically-resolved protected root against an
    /// enumerator-reported child would silently fail to match under that
    /// mismatch, so both sides must go through the same, fully-resolving
    /// path here.
    public static func canonicalize(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        let expanded = (path as NSString).expandingTildeInPath

        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if let result = realpath(expanded, &buffer) {
            return String(cString: result)
        }

        // realpath fails when the path (or a component of it) does not
        // exist yet: fall back to lexical resolution so a not-yet-created
        // target still gets a stable, comparable form.
        let resolved = (expanded as NSString).resolvingSymlinksInPath
        if resolved.count > 1, resolved.hasSuffix("/") {
            return String(resolved.dropLast())
        }
        return resolved
    }

    /// Throws unless `rawPath` is safe to delete. When `declaredRoot` is
    /// given, the resolved path must additionally fall under it.
    public func validate(
        _ rawPath: String,
        mustBeUnder declaredRoot: String? = nil,
        home: String = NSHomeDirectory()
    ) throws {
        guard !rawPath.isEmpty else { throw PathGuardError.empty }
        guard rawPath.hasPrefix("/") else { throw PathGuardError.notAbsolute(path: rawPath) }

        let path = Self.canonicalize(rawPath)
        let canonicalHome = Self.canonicalize(home)

        if path == "/" { throw PathGuardError.isRoot }
        if path == canonicalHome { throw PathGuardError.isHome }

        if Self.systemContainerPaths.contains(path) {
            throw PathGuardError.isSystemRoot(path: path)
        }
        for subtree in Self.systemSubtrees where Self.isEqualOrDescendant(path, of: subtree) {
            throw PathGuardError.isSystemRoot(path: path)
        }

        for root in protectedRoots {
            if Self.isEqualOrDescendant(path, of: root) || Self.isEqualOrDescendant(root, of: path) {
                throw PathGuardError.insideProtectedRoot(path: path, root: root)
            }
        }

        if let declaredRoot {
            let canonicalDeclaredRoot = Self.canonicalize(declaredRoot)
            if !Self.isEqualOrDescendant(path, of: canonicalDeclaredRoot) {
                throw PathGuardError.outsideDeclaredRoot(path: path, root: canonicalDeclaredRoot)
            }
        }
    }

    public func isSafe(
        _ rawPath: String,
        mustBeUnder declaredRoot: String? = nil,
        home: String = NSHomeDirectory()
    ) -> Bool {
        (try? validate(rawPath, mustBeUnder: declaredRoot, home: home)) != nil
    }

    /// True when `path` equals `root` or sits strictly beneath it. A "/"
    /// boundary is required so a sibling with a matching prefix (e.g. a
    /// folder named "CloudStorageArchive" next to "CloudStorage") never
    /// matches.
    static func isEqualOrDescendant(_ path: String, of root: String) -> Bool {
        guard !root.isEmpty else { return false }
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }
}
