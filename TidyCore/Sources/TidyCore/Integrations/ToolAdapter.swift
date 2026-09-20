import CryptoKit
import Darwin
import Foundation

public enum DeveloperResourceDisposition: String, Equatable, Sendable {
    case reportOnly
    case manualRisk
    case exactManualCandidate
}

public enum ToolEffectPreflight: String, Equatable, Sendable {
    case exactFilesystemIdentity
    case exactSimulatorIdentityAndState
    case exactDockerIdentityStateAndReferences
    case producerOwnershipAndQuiescence
}

public enum ToolEffectCompletionProbe: String, Equatable, Sendable {
    case resourceAbsentByExactIdentity
    case simulatorAbsentByUDID
    case simulatorStateByUDID
    case dockerObjectAbsentByID
    case reviewedLeavesRevalidated
}

public enum ToolEffectAvailability: Equatable, Sendable {
    case unavailable(String)
}

public struct ToolEffectSpec: Equatable, Sendable {
    public let adapterID: String
    public let adapterVersion: String
    public let resourceIDs: [String]
    public let descendantManifestDigest: Data?
    public let exactArgv: [String]?
    public let endpointIdentity: LocalSocketApproval?
    public let preflight: ToolEffectPreflight
    public let completionProbe: ToolEffectCompletionProbe
    public let availability: ToolEffectAvailability

    init(adapterID: String, adapterVersion: String, resourceIDs: [String],
         descendantManifestDigest: Data? = nil, exactArgv: [String]? = nil,
         endpointIdentity: LocalSocketApproval? = nil, preflight: ToolEffectPreflight,
         completionProbe: ToolEffectCompletionProbe, unavailable reason: String) {
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.resourceIDs = resourceIDs
        self.descendantManifestDigest = descendantManifestDigest
        self.exactArgv = exactArgv
        self.endpointIdentity = endpointIdentity
        self.preflight = preflight
        self.completionProbe = completionProbe
        self.availability = .unavailable(reason)
    }
}

public struct DeveloperInventoryEntry: Sendable {
    public let record: InventoryRecord
    public let disposition: DeveloperResourceDisposition
    public let effectSpec: ToolEffectSpec?
}

public struct AppleReadApproval: Sendable {
    public let executable: LocalExecutableApproval
    private let authority: LocalAuthoritySnapshot?
    private let nativeTrusted: Bool

    public static func nativeXcrun() throws -> Self {
        let url = URL(fileURLWithPath: "/usr/bin/xcrun")
        let executable = try LocalExecutableApproval.verify(executable: url)
        guard executable.canonicalPath == "/usr/bin/xcrun" else {
            throw LocalAuthorityError.invalidScope
        }
        return Self(executable: executable, authority: nil, nativeTrusted: true)
    }

    public init?(authority: LocalAuthoritySnapshot, executable: LocalExecutableApproval) {
        guard authority.permits(.localExecutable(executable)) else { return nil }
        self.executable = executable
        self.authority = authority
        self.nativeTrusted = false
    }

    var isCurrent: Bool {
        let unchanged = (try? LocalExecutableApproval.verify(
            executable: URL(fileURLWithPath: executable.canonicalPath))) == executable
        return unchanged && (nativeTrusted
            ? executable.canonicalPath == "/usr/bin/xcrun"
            : authority?.permits(.localExecutable(executable)) == true)
    }

    private init(executable: LocalExecutableApproval,
                 authority: LocalAuthoritySnapshot?, nativeTrusted: Bool) {
        self.executable = executable
        self.authority = authority
        self.nativeTrusted = nativeTrusted
    }
}

public struct DockerReadApproval: Sendable {
    public let executable: LocalExecutableApproval
    public let endpoint: String
    public let socket: LocalSocketApproval
    private let authority: LocalAuthoritySnapshot

    public init?(authority: LocalAuthoritySnapshot, executable: LocalExecutableApproval,
                 endpoint: String, socket: LocalSocketApproval) {
        guard authority.permits(.localExecutable(executable)),
              authority.permits(.localSocket(socket)),
              LocalEndpointGuard.permitsLocalEndpointSyntax(endpoint),
              endpoint == "unix://" + socket.canonicalPath else { return nil }
        self.executable = executable
        self.endpoint = endpoint
        self.socket = socket
        self.authority = authority
    }

    var isCurrent: Bool {
        authority.permits(.localExecutable(executable))
            && authority.permits(.localSocket(socket))
            && (try? LocalExecutableApproval.verify(
                executable: URL(fileURLWithPath: executable.canonicalPath))) == executable
            && LocalEndpointGuard.captureApproved(endpoint: endpoint,
                approved: [socket]).value == socket
    }
}

public struct DeveloperInventoryRequest: Sendable {
    public let apple: AppleReadApproval?
    public let docker: DockerReadApproval?

    public init(apple: AppleReadApproval? = nil, docker: DockerReadApproval? = nil) {
        self.apple = apple
        self.docker = docker
    }

    public static let none = DeveloperInventoryRequest()
}

public struct DeveloperInventoryLimits: Sendable {
    public let allocationNodes: Int
    public let deadlineSeconds: Int

    public init(allocationNodes: Int = 50_000, deadlineSeconds: Int = 30) {
        self.allocationNodes = allocationNodes
        self.deadlineSeconds = deadlineSeconds
    }

    public static let `default` = DeveloperInventoryLimits()
}

public enum LocalToolReadOperation: Sendable {
    case appleSimctlDevices(AppleReadApproval)
    case dockerImages(DockerReadApproval)
    case dockerContainers(DockerReadApproval)
}

public protocol LocalToolProbe: Sendable {
    func read(_ operation: LocalToolReadOperation) async throws -> Data
}

public struct DeveloperInventorySnapshot: Sendable {
    public let projects: ProjectInventorySnapshot
    public let entries: [DeveloperInventoryEntry]
    public let observedAt: Date
    public let probeIssues: [String]

    public var records: [InventoryRecord] { entries.map(\.record) }
}

public enum DeveloperInventoryService {
    public static func scan(scope: AuthorizedScanScope, ownerID: UUID,
                            environment: CleanEnvironment,
                            projectLimits: ProjectInventoryLimits = .default,
                            pinnedProjectIDs: Set<String> = [],
                            currentProjectID: String? = nil,
                            request: DeveloperInventoryRequest = .none,
                            probe: (any LocalToolProbe)? = nil,
                            checkpoint: (@Sendable () async throws -> Void)? = nil,
                            limits: DeveloperInventoryLimits = .default,
                            now: Date = Date()) async throws -> DeveloperInventorySnapshot {
        guard limits.allocationNodes > 0, limits.allocationNodes <= 1_000_000,
              limits.deadlineSeconds > 0, limits.deadlineSeconds <= 300 else {
            throw ProjectInventoryError.invalidLimits
        }
        try scope.consumeForStart(ownerID: ownerID, environment: environment)
        try await checkpoint?()
        try scope.checkValidity()
        let roots = scope.roots.map(PathGuard.canonicalize)
        let exclusions = scope.excludedRoots.map(PathGuard.canonicalize)
        let projects: ProjectInventorySnapshot
        if enabled(scope.policy, "feature.projects") {
            projects = try await ProjectInventory.scanConsumed(roots: roots,
                excludedRoots: exclusions, environment: environment, limits: projectLimits,
                pinnedProjectIDs: pinnedProjectIDs, currentProjectID: currentProjectID,
                checkpoint: checkpoint, validity: { try scope.checkValidity() }, now: now)
        } else {
            projects = ProjectInventorySnapshot(records: [], coverage: .init(
                isComplete: true, reasons: [], visitedNodes: 0, omittedPaths: []),
                observedAt: now)
        }
        try await checkpoint?()
        try scope.checkValidity()
        let allocationBudget = InventoryAllocationBudget(maximumNodes: limits.allocationNodes,
            deadline: ContinuousClock.now.advanced(by: .seconds(limits.deadlineSeconds)),
            validity: { try scope.checkValidity() })
        let context = ToolAdapterContext(roots: roots, excludedRoots: exclusions,
            environment: environment, projects: projects, now: now,
            scopeID: "policy-\(scope.policyRevision)", budget: allocationBudget)
        let adapters: [any ToolAdapter] = [
            AppleDeveloperAdapter(), AndroidDeveloperAdapter(), NodeDeveloperAdapter(),
            LanguageCacheAdapter(), HomebrewAdapter(), DockerAdapter(), IDECacheAdapter(),
            LocalModelAdapter(), DataDirectoryAdapter(), GitStorageAdapter()
        ]
        var entries: [DeveloperInventoryEntry] = []
        let ecosystemsEnabled = enabled(scope.policy, "feature.ecosystems")
        for adapter in adapters where ecosystemsEnabled
            && enabled(scope.policy, "ecosystem.\(adapter.ecosystemID).inventory") {
            try Task.checkCancellation()
            try await checkpoint?()
            try scope.checkValidity()
            entries.append(contentsOf: try adapter.inventory(context: context))
            try allocationBudget.checkValidity()
        }
        let activeProbe: any LocalToolProbe = probe ?? ProcessRunnerLocalToolProbe()
        var probeIssues: [String] = []
        if ecosystemsEnabled, enabled(scope.policy, "ecosystem.apple.inventory"),
           let apple = request.apple {
            if !apple.isCurrent {
                probeIssues.append("Apple executable approval was stale or invalid.")
            } else {
                do {
                    let data = try await activeProbe.read(.appleSimctlDevices(apple))
                    guard apple.isCurrent else {
                        throw ProcessRunnerError.undeclaredInvocation
                    }
                    if let records = AppleDeveloperAdapter.inventoryRecords(
                        fromSimctlData: data, scopeID: context.scopeID, observedAt: now) {
                        entries.append(contentsOf: records.map {
                            DeveloperInventoryEntry(record: $0, disposition: .reportOnly,
                                                    effectSpec: nil)
                        })
                    } else {
                        probeIssues.append("Apple simctl output was unsupported or malformed.")
                    }
                } catch {
                    probeIssues.append("Apple inventory probe was unavailable.")
                }
            }
        }
        if ecosystemsEnabled, enabled(scope.policy, "ecosystem.docker.inventory"),
           let docker = request.docker {
            if !docker.isCurrent {
                probeIssues.append("Docker executable or endpoint approval was stale or invalid.")
            } else {
                do {
                    let imageData = try await activeProbe.read(.dockerImages(docker))
                    let containerData = try await activeProbe.read(.dockerContainers(docker))
                    if docker.isCurrent,
                       let images = DockerAdapter.parseObjectList(imageData),
                       let containers = DockerAdapter.parseObjectList(containerData) {
                        entries.append(contentsOf: DockerAdapter.inventoryEntries(
                            objects: images + containers, approval: docker,
                            scopeID: context.scopeID, observedAt: now))
                    } else {
                        probeIssues.append("Docker endpoint changed or output was unsupported.")
                    }
                } catch {
                    probeIssues.append("Docker inventory probe was unavailable.")
                }
            }
        }
        entries.sort {
            if $0.record.adapterID != $1.record.adapterID {
                return $0.record.adapterID < $1.record.adapterID
            }
            return $0.record.id < $1.record.id
        }
        try await checkpoint?()
        try scope.checkValidity()
        try allocationBudget.checkValidity()
        return DeveloperInventorySnapshot(projects: projects, entries: entries,
            observedAt: now, probeIssues: probeIssues)
    }

    private static func enabled(_ policy: EffectivePolicy, _ rawID: String) -> Bool {
        policy.fields[SettingID(rawValue: rawID)]?.value == .stored(.bool(true))
    }
}

private extension Result {
    var value: Success? { try? get() }
}

private struct ProcessRunnerLocalToolProbe: LocalToolProbe {
    func read(_ operation: LocalToolReadOperation) async throws -> Data {
        let output: ProcessRunner.Output
        switch operation {
        case .appleSimctlDevices(let approval):
            guard approval.isCurrent else {
                throw ProcessRunnerError.undeclaredInvocation
            }
            output = try await ProcessRunner.runApprovedSimctlDevices(approval: approval)
            guard approval.isCurrent else {
                throw ProcessRunnerError.undeclaredInvocation
            }
            guard output.succeeded else { throw ProcessRunnerError.undeclaredInvocation }
            return Data(output.standardOutput.utf8)
        case .dockerImages(let approval):
            output = try await ProcessRunner.runDockerImages(approval: approval)
            guard output.succeeded else { throw ProcessRunnerError.undeclaredInvocation }
            return try normalizeDockerLines(output.standardOutput, kind: .image)
        case .dockerContainers(let approval):
            output = try await ProcessRunner.runDockerContainers(approval: approval)
            guard output.succeeded else { throw ProcessRunnerError.undeclaredInvocation }
            return try normalizeDockerLines(output.standardOutput, kind: .container)
        }
    }

    private func normalizeDockerLines(_ text: String,
                                      kind: DockerObjectKind) throws -> Data {
        var rows: [[String: Any]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  var object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else {
                throw ProcessRunnerError.undeclaredInvocation
            }
            object["kind"] = kind.rawValue
            rows.append(object)
        }
        return try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    }
}

protocol ToolAdapter: Sendable {
    static var adapterID: String { get }
    static var contractVersion: String { get }
    static var ecosystemID: String { get }
    func inventory(context: ToolAdapterContext) throws -> [DeveloperInventoryEntry]
}

private extension ToolAdapter {
    var ecosystemID: String { Self.ecosystemID }
}

struct ToolAdapterContext: Sendable {
    let roots: [String]
    let excludedRoots: [String]
    let environment: CleanEnvironment
    let projects: ProjectInventorySnapshot
    let now: Date
    let scopeID: String
    let budget: InventoryAllocationBudget

    func authorizes(_ rawPath: String) -> Bool {
        guard budget.permitsRead() else { return false }
        return boundaryAuthorizes(rawPath)
    }

    private func boundaryAuthorizes(_ rawPath: String) -> Bool {
        let path = PathGuard.canonicalize(rawPath)
        return roots.contains { PathGuard.isEqualOrDescendant(path, of: $0) }
            && !excludedRoots.contains { PathGuard.isEqualOrDescendant(path, of: $0) }
            && !environment.protectedRoots.map(PathGuard.canonicalize).contains {
                PathGuard.isEqualOrDescendant(path, of: $0)
            }
    }

    func knownHomePath(_ relative: String) -> String? {
        let path = PathGuard.canonicalize(environment.path(relative))
        return authorizes(path) ? path : nil
    }

    func entry(adapterID: String, adapterVersion: String, path: String,
               kind: String, disposition: DeveloperResourceDisposition,
               reason: String, confidence: InventoryConfidence = .partial,
               activity: ResourceActivity = .unknown,
               effectSpec: ToolEffectSpec? = nil,
               sizeLimits: InventorySizeLimits = .default) -> DeveloperInventoryEntry? {
        guard authorizes(path),
              let identity = try? ResourcePreflight.captureFile(at: path) else { return nil }
        let allocated = budget.measure(identity: identity) {
            InventoryFilesystem.allocatedBytes(path: path, limits: sizeLimits, budget: budget,
                authorizes: { self.boundaryAuthorizes($0) })
        }
        let id = InventoryFilesystem.stableID(adapterID: adapterID, identity: identity)
        let record = InventoryRecord(id: id, adapterID: adapterID,
            adapterVersion: adapterVersion, resource: .filesystem(identity), ownerIDs: [],
            scopeID: scopeID, kind: kind, capability: .inventoryOnly,
            allocatedBytes: allocated.bytes, confidence: allocated.complete ? confidence : .partial,
            activity: activity, observedAt: now,
            reason: allocated.shared ? reason + " Allocation is shared with another record."
                : (allocated.complete ? reason : reason + " Size coverage is partial."))
        return DeveloperInventoryEntry(record: record, disposition: disposition,
                                       effectSpec: effectSpec)
    }
}

struct InventorySizeLimits: Sendable {
    let nodes: Int
    let depth: Int
    let entriesPerDirectory: Int
    static let `default` = InventorySizeLimits(nodes: 20_000, depth: 16,
                                                entriesPerDirectory: 4_096)
}

final class InventoryAllocationBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var remainingNodes: Int
    private let deadline: ContinuousClock.Instant
    private let validity: @Sendable () throws -> Void
    private var seenNodes: Set<FileNodeIdentity> = []
    private var roots: [FileResourceIdentity: InventoryFilesystem.SizeResult] = [:]
    private var authorizationError: Error?

    init(maximumNodes: Int, deadline: ContinuousClock.Instant,
         validity: @escaping @Sendable () throws -> Void = {}) {
        self.remainingNodes = maximumNodes
        self.deadline = deadline
        self.validity = validity
    }

    func measure(identity: FileResourceIdentity,
                 _ body: () -> InventoryFilesystem.SizeResult)
        -> InventoryFilesystem.SizeResult {
        guard permitsRead() else {
            return .init(bytes: nil, complete: false, shared: false)
        }
        if let existing = lock.withLock({ roots[identity] }) {
            return .init(bytes: nil, complete: existing.complete, shared: true)
        }
        let measured = body()
        lock.withLock { roots[identity] = measured }
        return measured
    }

    func admit(_ node: FileNodeIdentity) -> (allowed: Bool, firstVisit: Bool) {
        guard permitsRead() else { return (false, false) }
        return lock.withLock {
            guard ContinuousClock.now <= deadline, !Task.isCancelled,
                  remainingNodes > 0 else { return (false, false) }
            if !seenNodes.insert(node).inserted { return (true, false) }
            remainingNodes -= 1
            return (true, true)
        }
    }

    func permitsRead() -> Bool {
        if lock.withLock({ authorizationError != nil }) { return false }
        do {
            try validity()
            return true
        } catch {
            lock.withLock { authorizationError = error }
            return false
        }
    }

    func checkValidity() throws {
        if let error = lock.withLock({ authorizationError }) { throw error }
        try validity()
    }
}

enum InventoryFilesystem {
    // Darwin's <sys/stat.h> defines SF_DATALESS as 0x40000000, but the macro
    // is not imported into Swift. Never read through an unhydrated object.
    private static let systemDatalessFlag: UInt32 = 0x40000000

    struct SizeResult {
        let bytes: Int64?
        let complete: Bool
        let shared: Bool
    }

    static func stableID(adapterID: String, identity: FileResourceIdentity) -> String {
        let material = adapterID + "|" + identity.volumeID.uuidString + "|"
            + String(identity.device) + "|" + String(identity.inode) + "|"
            + (identity.generation.map(String.init) ?? "none")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func allocatedBytes(path: String,
                               limits: InventorySizeLimits = .default,
                               budget: InventoryAllocationBudget,
                               authorizes: @escaping @Sendable (String) -> Bool) -> SizeResult {
        guard budget.permitsRead(), authorizes(path) else {
            return SizeResult(bytes: nil, complete: false, shared: false)
        }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return SizeResult(bytes: nil, complete: false, shared: false) }
        defer { close(fd) }
        var nodes = 0
        var complete = true
        var shared = false
        var total: Int64 = 0
        var rootDevice: dev_t?

        func walk(_ descriptor: Int32, path: String, depth: Int) {
            guard complete else { return }
            guard budget.permitsRead(), authorizes(path) else {
                complete = false; return
            }
            guard nodes < limits.nodes, depth <= limits.depth else {
                complete = false; return
            }
            nodes += 1
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0 else { complete = false; return }
            if let rootDevice {
                guard metadata.st_dev == rootDevice else { complete = false; return }
            } else {
                rootDevice = metadata.st_dev
            }
            let node = FileNodeIdentity(device: UInt64(UInt32(bitPattern: metadata.st_dev)),
                inode: UInt64(metadata.st_ino), generation: UInt64(metadata.st_gen),
                mode: UInt32(metadata.st_mode))
            let admission = budget.admit(node)
            guard admission.allowed else { complete = false; return }
            guard admission.firstVisit else { shared = true; return }
            guard metadata.st_flags & Self.systemDatalessFlag == 0 else {
                complete = false; return
            }
            let (bytes, overflow) = Int64(metadata.st_blocks).multipliedReportingOverflow(by: 512)
            let (next, sumOverflow) = total.addingReportingOverflow(bytes)
            guard !overflow, !sumOverflow, bytes >= 0 else { complete = false; return }
            total = next
            guard metadata.st_mode & S_IFMT == S_IFDIR else { return }
            let copied = dup(descriptor)
            guard copied >= 0, let directory = fdopendir(copied) else {
                if copied >= 0 { close(copied) }
                complete = false; return
            }
            defer { closedir(directory) }
            var names: [String] = []
            while let item = readdir(directory) {
                let name = withUnsafePointer(to: item.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self,
                                              capacity: Int(MAXNAMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                guard names.count < limits.entriesPerDirectory else {
                    complete = false; return
                }
                names.append(name)
            }
            for name in names.sorted() {
                let childPath = path == "/" ? "/" + name : path + "/" + name
                guard budget.permitsRead(), authorizes(childPath) else {
                    complete = false; return
                }
                var childMetadata = stat()
                guard fstatat(dirfd(directory), name, &childMetadata,
                              AT_SYMLINK_NOFOLLOW) == 0 else {
                    complete = false; return
                }
                guard childMetadata.st_dev == rootDevice else {
                    complete = false; return
                }
                guard childMetadata.st_mode & S_IFMT != S_IFLNK else { continue }
                let child = openat(dirfd(directory), name,
                    O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                guard child >= 0 else { complete = false; return }
                walk(child, path: childPath, depth: depth + 1)
                close(child)
                if !complete { return }
            }
        }

        walk(fd, path: path, depth: 0)
        return SizeResult(bytes: complete && !shared ? total : nil,
                          complete: complete, shared: shared)
    }
}

enum AdapterPaths {
    static func existing(_ candidates: [String], context: ToolAdapterContext) -> [String] {
        var seen: Set<String> = []
        return candidates.compactMap { raw in
            let path = PathGuard.canonicalize(raw)
            guard seen.insert(path).inserted, context.authorizes(path) else { return nil }
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory) else {
                return nil
            }
            return path
        }
    }

    static func child(_ name: String, of project: ProjectInventoryRecord,
                      context: ToolAdapterContext) -> String? {
        let path = project.canonicalRoot + "/" + name
        return existing([path], context: context).first
    }
}

enum BoundedAdapterData {
    static let maximumBytes = 1_048_576

    static func jsonObject(_ data: Data, maximumDepth: Int = 16) -> Any? {
        guard data.count <= maximumBytes,
              String(data: data, encoding: .utf8) != nil,
              validNesting(data, maximumDepth: maximumDepth) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func utf8(_ data: Data) -> String? {
        guard data.count <= maximumBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func validNesting(_ data: Data, maximumDepth: Int) -> Bool {
        var depth = 0
        var quoted = false
        var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { quoted = false }
            } else if byte == 0x22 {
                quoted = true
            } else if byte == 0x7B || byte == 0x5B {
                depth += 1
                if depth > maximumDepth { return false }
            } else if byte == 0x7D || byte == 0x5D {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return !quoted && depth == 0
    }
}
