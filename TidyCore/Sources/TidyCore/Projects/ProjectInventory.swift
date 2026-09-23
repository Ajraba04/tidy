import CryptoKit
import Darwin
import Foundation

public struct ProjectInventoryLimits: Equatable, Sendable {
    public let maximumNodes: Int
    public let maximumDepth: Int
    public let maximumProjects: Int
    public let maximumDirectoryEntries: Int
    public let maximumManifestBytes: Int
    public let maximumJSONDepth: Int
    public let maximumPathBytes: Int

    public init(maximumNodes: Int = 50_000, maximumDepth: Int = 8,
                maximumProjects: Int = 1_000, maximumDirectoryEntries: Int = 4_096,
                maximumManifestBytes: Int = 1_048_576, maximumJSONDepth: Int = 16,
                maximumPathBytes: Int = 4_096) {
        self.maximumNodes = maximumNodes
        self.maximumDepth = maximumDepth
        self.maximumProjects = maximumProjects
        self.maximumDirectoryEntries = maximumDirectoryEntries
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumJSONDepth = maximumJSONDepth
        self.maximumPathBytes = maximumPathBytes
    }

    public static let `default` = ProjectInventoryLimits()

    fileprivate var isValid: Bool {
        (1...1_000_000).contains(maximumNodes)
            && (0...64).contains(maximumDepth)
            && (1...100_000).contains(maximumProjects)
            && (1...65_536).contains(maximumDirectoryEntries)
            && (1...1_048_576).contains(maximumManifestBytes)
            && (1...64).contains(maximumJSONDepth)
            && (64...16_384).contains(maximumPathBytes)
    }
}

public enum ProjectInventoryError: Error, Equatable, Sendable {
    case invalidLimits
}

public enum ProjectInventoryCoverageReason: String, Hashable, Sendable {
    case excluded
    case symbolicLinkSkipped
    case unreadable
    case churn
    case nodeLimit
    case depthLimit
    case projectLimit
    case directoryEntryLimit
    case pathLimit
    case cancelled
    case authorizationExpired
}

public struct ProjectInventoryCoverage: Equatable, Sendable {
    public let isComplete: Bool
    public let reasons: Set<ProjectInventoryCoverageReason>
    public let visitedNodes: Int
    public let omittedPaths: [String]
}

public enum ProjectToolchain: String, CaseIterable, Hashable, Sendable {
    case node, npm, pnpm, yarn, swift, xcode, cocoapods
    case gradle, python, uv, rust, cargo, go, ruby
}

public enum ProjectManifestStatus: String, Equatable, Sendable {
    case validData
    case invalidData
    case oversized
    case unreadable
    case symbolicLinkRejected
}

public struct ProjectManifestRecord: Equatable, Sendable {
    public let name: String
    public let canonicalPath: String
    public let identity: FileResourceIdentity?
    public let status: ProjectManifestStatus
    public let byteCount: Int?
}

public enum ProjectGitLayout: String, Equatable, Sendable {
    case repository
    case linkedWorktree
    case invalid
}

public enum ProjectGitStatusEvidence: String, Equatable, Sendable {
    case unknown
}

public struct ProjectGitMetadata: Equatable, Sendable {
    public let layout: ProjectGitLayout
    public let markerIdentity: FileResourceIdentity?
    public let gitDirectoryIdentity: FileResourceIdentity?
    public let commonDirectoryIdentity: FileResourceIdentity?
    public let worktreeIdentity: FileResourceIdentity
    public let dirtyState: ProjectGitStatusEvidence
    public let untrackedState: ProjectGitStatusEvidence
}

public struct ProjectInventoryRecord: Equatable, Sendable {
    public let id: String
    public let canonicalRoot: String
    public let rootIdentity: FileResourceIdentity
    public let git: ProjectGitMetadata?
    public let manifests: [ProjectManifestRecord]
    public let toolchains: Set<ProjectToolchain>
    public let capability: AdapterCapability
    public let confidence: InventoryConfidence
    public let activity: ResourceActivity
    public let recommendationEligible: Bool
    public let reasons: [String]
}

public struct ProjectInventorySnapshot: Equatable, Sendable {
    public let records: [ProjectInventoryRecord]
    public let coverage: ProjectInventoryCoverage
    public let observedAt: Date
}

public enum ProjectInventory {
    public static func scan(scope: AuthorizedScanScope, ownerID: UUID,
                            environment: CleanEnvironment,
                            limits: ProjectInventoryLimits = .default,
                            pinnedProjectIDs: Set<String> = [],
                            currentProjectID: String? = nil,
                            checkpoint: (@Sendable () async throws -> Void)? = nil,
                            now: Date = Date()) async throws -> ProjectInventorySnapshot {
        guard limits.isValid else { throw ProjectInventoryError.invalidLimits }
        try scope.consumeForStart(ownerID: ownerID, environment: environment)
        return try await scanConsumed(roots: scope.roots,
            excludedRoots: scope.excludedRoots, environment: environment,
            limits: limits, pinnedProjectIDs: pinnedProjectIDs,
            currentProjectID: currentProjectID, checkpoint: checkpoint,
            validity: { try scope.checkValidity() }, now: now)
    }

    static func scanConsumed(roots: [String], excludedRoots: [String],
                             environment: CleanEnvironment,
                             limits: ProjectInventoryLimits = .default,
                             pinnedProjectIDs: Set<String> = [],
                             currentProjectID: String? = nil,
                             checkpoint: (@Sendable () async throws -> Void)? = nil,
                             validity: @escaping @Sendable () throws -> Void = {},
                             now: Date = Date()) async throws -> ProjectInventorySnapshot {
        guard limits.isValid else { throw ProjectInventoryError.invalidLimits }
        let canonicalRoots = roots.map(PathGuard.canonicalize)
        let exclusions = Set((excludedRoots + environment.protectedRoots)
            .map(PathGuard.canonicalize))
        let cancellation = ProjectInventoryCancellationState()
        return try await withTaskCancellationHandler {
            var records: [String: ProjectInventoryRecord] = [:]
            var reasons: Set<ProjectInventoryCoverageReason> = []
            var omitted: Set<String> = []
            var visited = 0
            for root in canonicalRoots {
                try Task.checkCancellation()
                try await checkpoint?()
                try validity()
                let remainingNodes = limits.maximumNodes - visited
                let remainingProjects = limits.maximumProjects - records.count
                guard remainingNodes > 0, remainingProjects > 0 else {
                    reasons.insert(remainingNodes <= 0 ? .nodeLimit : .projectLimit)
                    omitted.insert(root)
                    break
                }
                let batchLimits = ProjectInventoryLimits(maximumNodes: remainingNodes,
                    maximumDepth: limits.maximumDepth,
                    maximumProjects: remainingProjects,
                    maximumDirectoryEntries: limits.maximumDirectoryEntries,
                    maximumManifestBytes: limits.maximumManifestBytes,
                    maximumJSONDepth: limits.maximumJSONDepth,
                    maximumPathBytes: limits.maximumPathBytes)
                let batch = try await ProjectInventoryExecutor.shared.run {
                    try ProjectInventoryScanner(roots: [root],
                        authorizedRoots: canonicalRoots,
                        excludedRoots: Array(exclusions), limits: batchLimits,
                        pinnedProjectIDs: pinnedProjectIDs,
                        currentProjectID: currentProjectID, now: now,
                        cancellation: cancellation, validity: validity).run()
                }
                for record in batch.records { records[record.id] = record }
                reasons.formUnion(batch.coverage.reasons)
                omitted.formUnion(batch.coverage.omittedPaths)
                visited += batch.coverage.visitedNodes
                if cancellation.isCancelled { throw CancellationError() }
            }
            try await checkpoint?()
            try validity()
            return ProjectInventorySnapshot(records: records.values.sorted {
                $0.canonicalRoot < $1.canonicalRoot
            }, coverage: .init(isComplete: reasons.isEmpty, reasons: reasons,
                visitedNodes: visited, omittedPaths: omitted.sorted()), observedAt: now)
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class ProjectInventoryCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

private final class ProjectInventoryExecutor: @unchecked Sendable {
    static let shared = ProjectInventoryExecutor()
    private let queue: OperationQueue

    private init() {
        queue = OperationQueue()
        queue.name = "TidyCore.ProjectInventory.utility"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
    }

    func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.addOperation {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private final class ProjectInventoryScanner {
    private struct Entry {
        let name: String
        let metadata: stat
        var fileType: mode_t { metadata.st_mode & S_IFMT }
    }

    private enum BoundedRead {
        case data(Data, stat)
        case oversized
        case unreadable
    }

    private static let manifestToolchains: [String: Set<ProjectToolchain>] = [
        "package.json": [.node], "package-lock.json": [.node, .npm],
        "npm-shrinkwrap.json": [.node, .npm], "pnpm-lock.yaml": [.node, .pnpm],
        "yarn.lock": [.node, .yarn], "Package.swift": [.swift],
        "Package.resolved": [.swift], "Podfile": [.cocoapods],
        "Podfile.lock": [.cocoapods], "project.pbxproj": [.xcode],
        "build.gradle": [.gradle], "build.gradle.kts": [.gradle],
        "settings.gradle": [.gradle], "settings.gradle.kts": [.gradle],
        "pyproject.toml": [.python], "requirements.txt": [.python],
        "uv.lock": [.python, .uv], "Cargo.toml": [.rust, .cargo],
        "Cargo.lock": [.rust, .cargo], "go.mod": [.go], "go.sum": [.go],
        "Gemfile": [.ruby], "Gemfile.lock": [.ruby]
    ]

    private let roots: [String]
    private let authorizedRoots: [String]
    private let excludedRoots: [String]
    private let limits: ProjectInventoryLimits
    private let pinnedProjectIDs: Set<String>
    private let currentProjectID: String?
    private let now: Date
    private let cancellation: ProjectInventoryCancellationState
    private let validity: @Sendable () throws -> Void
    private var records: [ProjectInventoryRecord] = []
    private var coverageReasons: Set<ProjectInventoryCoverageReason> = []
    private var omittedPaths: Set<String> = []
    private var visitedNodes = 0
    private var stopped = false
    private var authorizationError: Error?

    init(roots: [String], authorizedRoots: [String]? = nil,
         excludedRoots: [String], limits: ProjectInventoryLimits,
         pinnedProjectIDs: Set<String>, currentProjectID: String?, now: Date,
         cancellation: ProjectInventoryCancellationState = .init(),
         validity: @escaping @Sendable () throws -> Void = {}) {
        self.roots = roots.sorted()
        self.authorizedRoots = (authorizedRoots ?? roots).sorted()
        self.excludedRoots = excludedRoots.sorted()
        self.limits = limits
        self.pinnedProjectIDs = pinnedProjectIDs
        self.currentProjectID = currentProjectID
        self.now = now
        self.cancellation = cancellation
        self.validity = validity
    }

    func run() throws -> ProjectInventorySnapshot {
        for root in roots where !stopped {
            guard isAuthorizedToContinue(root) else { break }
            guard !cancellation.isCancelled else {
                omit(root, .cancelled); stopped = true; break
            }
            guard !isExcluded(root) else {
                omit(root, .excluded)
                continue
            }
            guard root.utf8.count <= limits.maximumPathBytes else {
                omit(root, .pathLimit)
                continue
            }
            let descriptor = open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                omit(root, .unreadable)
                continue
            }
            defer { close(descriptor) }
            guard consumeNode(path: root) else { break }
            walk(directoryFD: descriptor, path: root, depth: 0)
        }
        if let authorizationError { throw authorizationError }
        let coverage = ProjectInventoryCoverage(
            isComplete: coverageReasons.isEmpty,
            reasons: coverageReasons,
            visitedNodes: visitedNodes,
            omittedPaths: omittedPaths.sorted())
        return ProjectInventorySnapshot(records: records.sorted { $0.canonicalRoot < $1.canonicalRoot },
            coverage: coverage, observedAt: now)
    }

    private func walk(directoryFD: Int32, path: String, depth: Int) {
        guard !stopped else { return }
        guard isAuthorizedToContinue(path) else { return }
        guard !cancellation.isCancelled else {
            omit(path, .cancelled); stopped = true; return
        }
        guard let entries = directoryEntries(directoryFD, path: path) else { return }
        let manifestEntries = entries.filter { Self.manifestToolchains[$0.name] != nil }
        if entries.contains(where: { $0.name == ".git" }) || !manifestEntries.isEmpty {
            if records.count >= limits.maximumProjects {
                omit(path, .projectLimit)
                stopped = true
                return
            }
            if let record = projectRecord(directoryFD: directoryFD, path: path,
                                          entries: entries,
                                          manifestEntries: manifestEntries) {
                records.append(record)
            }
        }

        for entry in entries where !stopped {
            guard consumeNode(path: childPath(path, entry.name)) else { return }
            let child = childPath(path, entry.name)
            if entry.fileType == S_IFLNK {
                omit(child, .symbolicLinkSkipped)
                continue
            }
            guard entry.fileType == S_IFDIR, entry.name != ".git" else { continue }
            guard !isExcluded(child) else {
                omit(child, .excluded)
                continue
            }
            guard depth < limits.maximumDepth else {
                omit(child, .depthLimit)
                continue
            }
            guard child.utf8.count <= limits.maximumPathBytes else {
                omit(child, .pathLimit)
                continue
            }
            let childFD = openat(directoryFD, entry.name,
                                 O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard childFD >= 0 else {
                omit(child, errno == ELOOP ? .symbolicLinkSkipped : .churn)
                continue
            }
            var opened = stat()
            guard fstat(childFD, &opened) == 0,
                  sameNode(opened, entry.metadata),
                  opened.st_mode & S_IFMT == S_IFDIR else {
                close(childFD)
                omit(child, .churn)
                continue
            }
            walk(directoryFD: childFD, path: child, depth: depth + 1)
            close(childFD)
        }
    }

    private func directoryEntries(_ directoryFD: Int32, path: String) -> [Entry]? {
        let copied = dup(directoryFD)
        guard copied >= 0, let directory = fdopendir(copied) else {
            if copied >= 0 { close(copied) }
            omit(path, .unreadable)
            return nil
        }
        defer { closedir(directory) }
        var entries: [Entry] = []
        while let item = readdir(directory) {
            guard isAuthorizedToContinue(path) else { return nil }
            guard !cancellation.isCancelled else {
                omit(path, .cancelled); stopped = true; return nil
            }
            let name = withUnsafePointer(to: item.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard entries.count < limits.maximumDirectoryEntries else {
                omit(path, .directoryEntryLimit)
                break
            }
            var metadata = stat()
            guard fstatat(dirfd(directory), name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
                omit(childPath(path, name), .churn)
                continue
            }
            entries.append(Entry(name: name, metadata: metadata))
        }
        return entries.sorted { $0.name < $1.name }
    }

    private func projectRecord(directoryFD: Int32, path: String, entries: [Entry],
                               manifestEntries: [Entry]) -> ProjectInventoryRecord? {
        guard var directoryMetadata = optionalStat(directoryFD),
              let rootIdentity = try? ResourcePreflight.captureFile(at: path),
              sameNode(directoryMetadata, rootIdentity) else {
            omit(path, .churn)
            return nil
        }
        guard fstat(directoryFD, &directoryMetadata) == 0,
              sameNode(directoryMetadata, rootIdentity) else {
            omit(path, .churn)
            return nil
        }
        let projectID = stableProjectID(rootIdentity)
        var reasons: [String] = []
        let manifests = manifestEntries.map {
            manifestRecord(directoryFD: directoryFD, projectPath: path, entry: $0)
        }
        var toolchains: Set<ProjectToolchain> = []
        for manifest in manifests where manifest.status == .validData {
            toolchains.formUnion(Self.manifestToolchains[manifest.name] ?? [])
        }
        let gitEntry = entries.first { $0.name == ".git" }
        let git: ProjectGitMetadata?
        if let gitEntry {
            git = gitMetadata(directoryFD: directoryFD, projectPath: path,
                              rootIdentity: rootIdentity, entry: gitEntry,
                              reasons: &reasons)
        } else {
            git = nil
        }
        let activity = ActivityResolver.inventory(projectID: projectID,
            pinnedProjectIDs: pinnedProjectIDs, currentProjectID: currentProjectID)
        reasons.append(contentsOf: activity.reasons)
        if manifests.contains(where: { $0.status != .validData }) {
            reasons.append("One or more recognized manifests were not safely readable as bounded data.")
        }
        var confidence: InventoryConfidence = .partial
        if git?.layout == .invalid || (gitEntry != nil && git == nil) {
            confidence = .unknown
        }
        return ProjectInventoryRecord(id: projectID, canonicalRoot: path,
            rootIdentity: rootIdentity, git: git, manifests: manifests,
            toolchains: toolchains, capability: .inventoryOnly,
            confidence: confidence, activity: activity.activity,
            recommendationEligible: activity.recommendationEligible,
            reasons: Array(Set(reasons)).sorted())
    }

    private func manifestRecord(directoryFD: Int32, projectPath: String,
                                entry: Entry) -> ProjectManifestRecord {
        let path = childPath(projectPath, entry.name)
        guard entry.fileType != S_IFLNK else {
            return .init(name: entry.name, canonicalPath: path, identity: nil,
                         status: .symbolicLinkRejected, byteCount: nil)
        }
        guard entry.fileType == S_IFREG else {
            return .init(name: entry.name, canonicalPath: path, identity: nil,
                         status: .invalidData, byteCount: nil)
        }
        switch readBoundedRegularFile(directoryFD: directoryFD, name: entry.name,
                                      expected: entry.metadata,
                                      maximumBytes: limits.maximumManifestBytes) {
        case .oversized:
            return .init(name: entry.name, canonicalPath: path, identity: nil,
                         status: .oversized, byteCount: nil)
        case .unreadable:
            return .init(name: entry.name, canonicalPath: path, identity: nil,
                         status: .unreadable, byteCount: nil)
        case .data(let data, let metadata):
            let identity = captureIdentity(path: path, expected: metadata)
            guard String(data: data, encoding: .utf8) != nil else {
                return .init(name: entry.name, canonicalPath: path, identity: identity,
                             status: .invalidData, byteCount: data.count)
            }
            if entry.name == "package.json",
               !validPackageJSON(data, maximumDepth: limits.maximumJSONDepth) {
                return .init(name: entry.name, canonicalPath: path, identity: identity,
                             status: .invalidData, byteCount: data.count)
            }
            return .init(name: entry.name, canonicalPath: path, identity: identity,
                         status: identity == nil ? .unreadable : .validData,
                         byteCount: data.count)
        }
    }

    private func gitMetadata(directoryFD: Int32, projectPath: String,
                             rootIdentity: FileResourceIdentity, entry: Entry,
                             reasons: inout [String]) -> ProjectGitMetadata? {
        let markerPath = childPath(projectPath, ".git")
        let markerIdentity = captureIdentity(path: markerPath, expected: entry.metadata)
        if entry.fileType == S_IFLNK {
            reasons.append("Git marker is a symbolic link and was not followed.")
            return ProjectGitMetadata(layout: .invalid, markerIdentity: nil,
                gitDirectoryIdentity: nil, commonDirectoryIdentity: nil,
                worktreeIdentity: rootIdentity, dirtyState: .unknown,
                untrackedState: .unknown)
        }

        let layout: ProjectGitLayout
        let gitDirectoryPath: String
        if entry.fileType == S_IFDIR {
            layout = .repository
            gitDirectoryPath = markerPath
        } else if entry.fileType == S_IFREG {
            layout = .linkedWorktree
            guard case .data(let data, _) = readBoundedRegularFile(
                directoryFD: directoryFD, name: ".git", expected: entry.metadata,
                maximumBytes: min(limits.maximumManifestBytes, 65_536)),
                  let text = String(data: data, encoding: .utf8),
                  let declared = parseGitDirectory(text, relativeTo: projectPath) else {
                reasons.append("Git worktree marker was invalid or unreadable.")
                return ProjectGitMetadata(layout: .invalid, markerIdentity: markerIdentity,
                    gitDirectoryIdentity: nil, commonDirectoryIdentity: nil,
                    worktreeIdentity: rootIdentity, dirtyState: .unknown,
                    untrackedState: .unknown)
            }
            gitDirectoryPath = declared
        } else {
            reasons.append("Git marker was not a regular file or directory.")
            return ProjectGitMetadata(layout: .invalid, markerIdentity: markerIdentity,
                gitDirectoryIdentity: nil, commonDirectoryIdentity: nil,
                worktreeIdentity: rootIdentity, dirtyState: .unknown,
                untrackedState: .unknown)
        }

        guard isAuthorized(gitDirectoryPath),
              let gitIdentity = try? ResourcePreflight.captureFile(at: gitDirectoryPath),
              gitIdentity.mode & UInt32(S_IFMT) == UInt32(S_IFDIR) else {
            reasons.append("Git directory is outside authorized roots or could not be captured.")
            return ProjectGitMetadata(layout: .invalid, markerIdentity: markerIdentity,
                gitDirectoryIdentity: nil, commonDirectoryIdentity: nil,
                worktreeIdentity: rootIdentity, dirtyState: .unknown,
                untrackedState: .unknown)
        }

        var commonIdentity: FileResourceIdentity? = gitIdentity
        let gitFD = open(gitDirectoryPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if gitFD >= 0 {
            defer { close(gitFD) }
            var commonMetadata = stat()
            if fstatat(gitFD, "commondir", &commonMetadata, AT_SYMLINK_NOFOLLOW) == 0 {
                if case .data(let data, _) = readBoundedRegularFile(directoryFD: gitFD,
                    name: "commondir", expected: commonMetadata, maximumBytes: 65_536),
                   let text = String(data: data, encoding: .utf8),
                   let commonPath = parseRelativePath(text, relativeTo: gitDirectoryPath),
                   isAuthorized(commonPath),
                   let captured = try? ResourcePreflight.captureFile(at: commonPath),
                   captured.mode & UInt32(S_IFMT) == UInt32(S_IFDIR) {
                    commonIdentity = captured
                } else {
                    commonIdentity = nil
                    reasons.append("Git common directory is outside authorized roots or invalid.")
                }
            } else if layout == .linkedWorktree {
                reasons.append("Linked worktree has no readable common-directory evidence.")
            }
        } else {
            commonIdentity = nil
            reasons.append("Git directory could not be opened without following links.")
        }
        return ProjectGitMetadata(layout: commonIdentity == nil ? .invalid : layout,
            markerIdentity: markerIdentity, gitDirectoryIdentity: gitIdentity,
            commonDirectoryIdentity: commonIdentity, worktreeIdentity: rootIdentity,
            dirtyState: .unknown, untrackedState: .unknown)
    }

    private func readBoundedRegularFile(directoryFD: Int32, name: String,
                                        expected: stat, maximumBytes: Int) -> BoundedRead {
        guard expected.st_mode & S_IFMT == S_IFREG else { return .unreadable }
        if expected.st_size < 0 || expected.st_size > maximumBytes {
            return .oversized
        }
        let descriptor = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return .unreadable }
        defer { close(descriptor) }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, sameNode(opened, expected),
              opened.st_mode & S_IFMT == S_IFREG else { return .unreadable }
        let readLimit = maximumBytes + 1
        var data = Data()
        data.reserveCapacity(min(maximumBytes, Int(max(0, opened.st_size))))
        var buffer = [UInt8](repeating: 0, count: min(65_536, readLimit))
        while data.count < readLimit {
            guard isAuthorizedToContinue(name) else { return .unreadable }
            guard !cancellation.isCancelled else { return .unreadable }
            let requested = min(buffer.count, readLimit - data.count)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, requested)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return .unreadable
            }
            data.append(buffer, count: count)
        }
        if data.count > maximumBytes { return .oversized }
        var final = stat()
        guard fstat(descriptor, &final) == 0, sameNode(final, opened),
              final.st_size == opened.st_size,
              final.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec else {
            return .unreadable
        }
        return .data(data, final)
    }

    private func validPackageJSON(_ data: Data, maximumDepth: Int) -> Bool {
        guard boundedJSONNesting(data, maximumDepth: maximumDepth) else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else { return false }
        return true
    }

    private func boundedJSONNesting(_ data: Data, maximumDepth: Int) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { inString = false }
                continue
            }
            if byte == 0x22 { inString = true; continue }
            if byte == 0x7B || byte == 0x5B {
                depth += 1
                if depth > maximumDepth { return false }
            } else if byte == 0x7D || byte == 0x5D {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return !inString && depth == 0
    }

    private func parseGitDirectory(_ text: String, relativeTo projectPath: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count == 1 else { return nil }
        let line = String(lines[0])
        guard line.hasPrefix("gitdir: ") else { return nil }
        return parseRelativePath(String(line.dropFirst("gitdir: ".count)),
                                 relativeTo: projectPath)
    }

    private func parseRelativePath(_ text: String, relativeTo base: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.utf8.contains(0),
              trimmed.utf8.count <= limits.maximumPathBytes else { return nil }
        let url = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(trimmed)
        let path = PathGuard.canonicalize(url.standardizedFileURL.path)
        return path.hasPrefix("/") && path.utf8.count <= limits.maximumPathBytes ? path : nil
    }

    private func stableProjectID(_ identity: FileResourceIdentity) -> String {
        let material = "\(identity.volumeID.uuidString)|\(identity.device)|"
            + "\(identity.inode)|\(identity.generation.map(String.init) ?? "none")"
        return "project-" + SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func captureIdentity(path: String, expected: stat) -> FileResourceIdentity? {
        guard let identity = try? ResourcePreflight.captureFile(at: path),
              sameNode(expected, identity) else { return nil }
        return identity
    }

    private func optionalStat(_ descriptor: Int32) -> stat? {
        var value = stat()
        return fstat(descriptor, &value) == 0 ? value : nil
    }

    private func sameNode(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private func sameNode(_ lhs: stat, _ rhs: FileResourceIdentity) -> Bool {
        UInt64(UInt32(bitPattern: lhs.st_dev)) == rhs.device
            && UInt64(lhs.st_ino) == rhs.inode
    }

    private func childPath(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }

    private func isAuthorized(_ path: String) -> Bool {
        authorizedRoots.contains { PathGuard.isEqualOrDescendant(path, of: $0) }
            && !isExcluded(path)
    }

    private func isExcluded(_ path: String) -> Bool {
        excludedRoots.contains { PathGuard.isEqualOrDescendant(path, of: $0) }
    }

    private func consumeNode(path: String) -> Bool {
        guard isAuthorizedToContinue(path) else { return false }
        guard visitedNodes < limits.maximumNodes else {
            omit(path, .nodeLimit)
            stopped = true
            return false
        }
        visitedNodes += 1
        return true
    }

    private func omit(_ path: String, _ reason: ProjectInventoryCoverageReason) {
        coverageReasons.insert(reason)
        omittedPaths.insert(path)
    }

    private func isAuthorizedToContinue(_ path: String) -> Bool {
        guard authorizationError == nil else { return false }
        do {
            try validity()
            return true
        } catch {
            authorizationError = error
            omit(path, .authorizationExpired)
            stopped = true
            return false
        }
    }
}
