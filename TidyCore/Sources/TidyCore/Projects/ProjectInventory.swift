import CryptoKit
import Foundation

public enum ProjectGitLayout: String, Sendable, Equatable {
    case directory, indirection, notObserved
}

/// Marker evidence describes a location. It never establishes ownership, clean Git
/// state, inactivity, or eligibility to remove its contents.
public struct ProjectInventoryRecord: Identifiable, Sendable, Equatable {
    public let id: String
    public let path: String
    public let markers: [String]
    public let gitLayout: ProjectGitLayout
    public let activity: ActivityEvidence
    public let observedAt: Date
    public let reason: String
}

public struct ProjectInventoryReport: Sendable, Equatable {
    public let records: [ProjectInventoryRecord]
    public let coverage: TraversalCoverage
    public let approvedRootCount: Int

    public init(records: [ProjectInventoryRecord], coverage: TraversalCoverage, approvedRootCount: Int) {
        self.records = records
        self.coverage = coverage
        self.approvedRootCount = approvedRootCount
    }
}

public enum ProjectInventory {
    public static let maximumProjects = 256
    // These are exact names, not expressions or tool commands. Contents are never evaluated.
    private static let files: Set<String> = [
        "package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "requirements.txt",
        "Gemfile", "go.mod", "pubspec.yaml", "build.gradle", "build.gradle.kts", "pom.xml"
    ]
    private static let pruneDirectories: Set<String> = [
        ".git", "node_modules", ".build", ".gradle", "target", ".venv", "venv",
        "Pods", ".next", ".dart_tool"
    ]

    /// A location ID is used only for protective pins. A same-path replacement does
    /// not inherit any positive activity or filesystem-identity evidence.
    public static func locationID(path: String) -> String {
        "project-" + SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    internal static func selects(_ record: TraversalRecord) -> Bool {
        let name = (record.path as NSString).lastPathComponent
        if record.kind == .directory {
            return pruneDirectories.contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
        }
        return record.kind == .regularFile && (files.contains(name) || name == ".git")
    }

    /// Pure bounded projection. Worktree indirections remain unresolved; neither
    /// Git configuration nor a .git file is followed to another directory.
    internal static func summarize(records: [TraversalRecord], root: String,
        coverage: TraversalCoverage, pinnedIDs: Set<String> = [], currentID: String? = nil,
        observedAt: Date = Date()) -> ProjectInventoryReport {
        var reasons = coverage.reasons
        var grouped: [String: [(String, TraversalRecordKind)]] = [:]
        if records.count > 4_096 { reasons.insert(.resultLimit) }
        for record in records.prefix(4_096) {
            guard record.path.utf8.count <= 4_096,
                  record.kind == .regularFile || record.kind == .directory,
                  record.path.hasPrefix("/"), !record.path.utf8.contains(0),
                  !record.path.split(separator: "/").contains(".."),
                  PathGuard.isEqualOrDescendant(record.path, of: root) else { continue }
            let name = (record.path as NSString).lastPathComponent
            let recognized = name == ".git" || (record.kind == .regularFile && files.contains(name))
                || (record.kind == .directory && (name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")))
            guard recognized else { continue }
            let project = (record.path as NSString).deletingLastPathComponent
            guard PathGuard.isEqualOrDescendant(project, of: root) else { continue }
            grouped[project, default: []].append((name, record.kind))
        }
        if grouped.count > maximumProjects { reasons.insert(.resultLimit) }
        let projects = grouped.keys.sorted().prefix(maximumProjects).map { path in
            let markers = grouped[path]!
            let id = locationID(path: path)
            let protected = pinnedIDs.contains(id) || currentID == id
            let git = markers.first { $0.0 == ".git" }
            return ProjectInventoryRecord(id: id, path: path,
                markers: Array(Set(markers.map { $0.0 })).sorted(),
                gitLayout: git.map { $0.1 == .directory ? .directory : .indirection } ?? .notObserved,
                activity: protected ? .pinned : .unknown, observedAt: observedAt,
                reason: protected ? "Protected by a pin or current-project selection."
                    : "Markers only. Producers, shared owners, and uncommitted or untracked changes are unknown; cleanup is blocked.")
        }
        return ProjectInventoryReport(records: projects,
            coverage: .init(isComplete: coverage.isComplete && reasons.isEmpty, reasons: reasons), approvedRootCount: 1)
    }

    internal static func scan(root: String, context: CoreOrchestrationContext,
        environment: CleanEnvironment) async -> ProjectInventoryReport {
        let traversal = BoundedTraversal(sessions: context.sessions,
            limits: context.traversalLimits.replacing(maxDepth: min(6, context.traversalLimits.maxDepth), topN: 0, sliceSeconds: 30))
        let result = await traversal.start(root: root, session: context.session,
            sessionID: context.sessionID, generation: context.generation,
            options: .init(protectedRoots: environment.protectedRoots,
                recordSelection: .projectMarkers, pruneMatchedDirectories: true))
        // Project pages are intentionally not retained as a second continuation authority.
        await traversal.invalidate(sessionID: context.sessionID)
        let policy = environment.effectivePolicy
        var pins: Set<String> = []
        var current: String?
        if case .stored(.strings(let ids))? = policy?.fields[.init(rawValue: "scope.pinnedProjects")]?.value {
            pins = Set(ids)
        }
        if case .stored(.choice(let id))? = policy?.fields[.init(rawValue: "scope.currentProject")]?.value {
            current = id
        }
        return summarize(records: result.records, root: PathGuard.canonicalize(root),
            coverage: result.coverage, pinnedIDs: pins, currentID: current)
    }
}
