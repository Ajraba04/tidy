import CryptoKit
import Darwin
import Foundation

enum GuardedFileError: Error, Equatable {
    case invalidComponent, unsafeRoot, symbolicLink, identityChanged
    case protectedScope, differentDevice, unsupportedNode, unavailableMetadata
    case manifestLimit, invalidManifest, invalidBudget
    case systemCall(Int32)
}

struct NodeSnapshot: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let generation: UInt64?
    let mode: UInt32
    let linkCount: UInt64
    let apparentBytes: Int64
    let allocatedBytes: Int64?
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    fileprivate var isDirectory: Bool { mode & UInt32(S_IFMT) == UInt32(S_IFDIR) }
    fileprivate var isRegular: Bool { mode & UInt32(S_IFMT) == UInt32(S_IFREG) }
    fileprivate func sameIdentity(as other: NodeSnapshot) -> Bool {
        device == other.device && inode == other.inode && generation == other.generation
            && mode == other.mode
    }
}

private extension NodeSnapshot {
    init(_ value: stat) throws {
        guard value.st_size >= 0, value.st_blocks >= 0 else { throw GuardedFileError.unavailableMetadata }
        device = UInt64(UInt32(bitPattern: value.st_dev))
        inode = UInt64(value.st_ino)
        generation = UInt64(value.st_gen)
        mode = UInt32(value.st_mode)
        linkCount = UInt64(value.st_nlink)
        apparentBytes = value.st_size
        let (allocated, overflow) = Int64(value.st_blocks).multipliedReportingOverflow(by: 512)
        allocatedBytes = overflow ? nil : allocated
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }
}

/// Read-only descriptor ownership, never coordinator or catalog authority.
/// Keeping these descriptors does NOT prevent external namespace replacement.
final class DirectoryAnchor {
    fileprivate let path: String
    private let components: [String]
    private let descriptors: [Int32]
    fileprivate let originalChain: [NodeSnapshot]
    fileprivate let volumeID: UUID
    private let mountID: [Int32]
    private let mountPath: String
    fileprivate var rootFD: Int32 { descriptors.last! }

    private init(path: String, components: [String], descriptors: [Int32],
                 chain: [NodeSnapshot], volumeID: UUID, mountID: [Int32], mountPath: String) {
        self.path = path
        self.components = components
        self.descriptors = descriptors
        self.originalChain = chain
        self.volumeID = volumeID
        self.mountID = mountID
        self.mountPath = mountPath
    }
    deinit { for fd in descriptors.reversed() { close(fd) } }

    static func open(path: String) throws -> DirectoryAnchor {
        guard path.hasPrefix("/"), path != "/" else { throw GuardedFileError.unsafeRoot }
        let names = try relativeComponents(String(path.dropFirst()))
        var fds: [Int32] = []
        do {
            let first = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard first >= 0 else { throw GuardedFileError.systemCall(errno) }
            fds.append(first)
            var chain = [try readSnapshot(first)]
            for (index, name) in names.enumerated() {
                let parent = fds.last!
                let before = try readSnapshot(parent, name)
                if before.mode & UInt32(S_IFMT) == UInt32(S_IFLNK) { throw GuardedFileError.symbolicLink }
                guard before.isDirectory else { throw GuardedFileError.unsupportedNode }
                let next = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw GuardedFileError.systemCall(errno) }
                fds.append(next)
                let opened = try readSnapshot(next)
                // Sibling creation may change ancestor mtime/ctime/link count.
                // Only the selected root gets a full metadata comparison here.
                let unchanged = index == names.count - 1 ? before == opened : before.sameIdentity(as: opened)
                guard unchanged else { throw GuardedFileError.identityChanged }
                chain.append(opened)
            }
            let root = fds.last!
            let volume = try volumeIdentity(root)
            let anchor = DirectoryAnchor(path: path, components: names, descriptors: fds,
                chain: chain, volumeID: volume.uuid, mountID: volume.mount, mountPath: volume.path)
            // Ownership transfers before validation, so an error closes only once.
            fds = []
            try anchor.validateNamespace()
            return anchor
        } catch {
            for fd in fds.reversed() { close(fd) }
            throw error
        }
    }

    func snapshot(relativePath: String) throws -> NodeSnapshot {
        try withParent(relativePath: relativePath) { parent, name, _ in
            try Self.readSnapshot(parent, name)
        }
    }

    fileprivate func validateNamespace() throws {
        for index in descriptors.indices {
            let current = try Self.readSnapshot(descriptors[index])
            guard current.sameIdentity(as: originalChain[index]) else { throw GuardedFileError.identityChanged }
            if index > 0 {
                let named = try Self.readSnapshot(descriptors[index - 1], components[index - 1])
                guard named.sameIdentity(as: current) else { throw GuardedFileError.identityChanged }
            }
        }
        try validateVolume(rootFD)
    }

    fileprivate func validateVolume(_ fd: Int32) throws {
        let actual = try Self.volumeIdentity(fd)
        guard actual.uuid == volumeID, actual.mount == mountID, actual.path == mountPath else {
            throw GuardedFileError.differentDevice
        }
        guard try Self.readSnapshot(fd).device == originalChain.last!.device else {
            throw GuardedFileError.differentDevice
        }
    }

    fileprivate func withParent<T>(relativePath: String,
                                   _ body: (Int32, String, [NodeSnapshot]) throws -> T) throws -> T {
        let names = try Self.relativeComponents(relativePath)
        try validateNamespace()
        var owned: [Int32] = []
        defer { for fd in owned.reversed() { close(fd) } }
        var parent = rootFD
        var chain = originalChain.dropLast().map { $0 }
        chain.append(try Self.readSnapshot(parent))
        for name in names.dropLast() {
            let before = try Self.readSnapshot(parent, name)
            guard before.isDirectory else { throw GuardedFileError.unsupportedNode }
            guard before.device == originalChain.last!.device else { throw GuardedFileError.differentDevice }
            let next = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw GuardedFileError.systemCall(errno) }
            owned.append(next)
            let opened = try Self.readSnapshot(next)
            guard before.sameIdentity(as: opened) else { throw GuardedFileError.identityChanged }
            try validateVolume(next)
            chain.append(opened)
            parent = next
        }
        return try body(parent, names.last!, chain)
    }

    fileprivate static func relativeComponents(_ path: String) throws -> [String] {
        let names = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.utf8.contains(0), names.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= Int(NAME_MAX)
        }) else { throw GuardedFileError.invalidComponent }
        return names
    }
    fileprivate static func readSnapshot(_ fd: Int32, _ name: String? = nil) throws -> NodeSnapshot {
        var value = stat()
        let result = name.map { fstatat(fd, $0, &value, AT_SYMLINK_NOFOLLOW) } ?? fstat(fd, &value)
        guard result == 0 else { throw GuardedFileError.systemCall(errno) }
        return try NodeSnapshot(value)
    }
    private static func volumeIdentity(_ fd: Int32) throws -> (uuid: UUID, mount: [Int32], path: String) {
        var mount = statfs()
        guard fstatfs(fd, &mount) == 0 else { throw GuardedFileError.systemCall(errno) }
        guard mount.f_flags & UInt32(MNT_LOCAL) != 0 else { throw GuardedFileError.unsafeRoot }
        // Same descriptor-backed ATTR_VOL_UUID representation as T02. f_fsid
        // and the kernel-reported mount point also reject mounted aliases.
        // This mount path is compared as metadata only, never reopened.
        let mountPath = withUnsafeBytes(of: mount.f_mntonname) { bytes -> String? in
            guard let end = bytes.firstIndex(of: 0) else { return nil }
            return String(bytes: bytes.prefix(end), encoding: .utf8)
        }
        guard let mountPath, mountPath.hasPrefix("/") else { throw GuardedFileError.unavailableMetadata }
        struct VolumeAttributes {
            var length: UInt32 = 0
            var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        }
        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_UUID)
        var attributes = VolumeAttributes()
        guard fgetattrlist(fd, &request, &attributes, MemoryLayout<VolumeAttributes>.size, 0) == 0,
              attributes.length == MemoryLayout<VolumeAttributes>.size,
              withUnsafeBytes(of: attributes.uuid, { $0.contains { $0 != 0 } }) else {
            throw GuardedFileError.unavailableMetadata
        }
        return (UUID(uuid: attributes.uuid), [mount.f_fsid.val.0, mount.f_fsid.val.1], mountPath)
    }
}

struct ReviewedLeaf: Equatable, Sendable {
    let relativePath: String
    let parentChain: [NodeSnapshot]
    let snapshot: NodeSnapshot
}
struct ReviewedBatch: Sendable {
    let id: UUID
    let entries: [ReviewedLeaf]
    let encodedBytes: Int
}
struct ReviewedManifestHeader: Equatable, Sendable {
    let schemaVersion: UInt32
    let rootVolumeID: UUID
    let canonicalRootPath: String
    let rootSnapshot: NodeSnapshot
    let rootParentChain: [NodeSnapshot]
}
struct ReviewedTree: Sendable {
    let header: ReviewedManifestHeader
    let canonicalHeaderBytes: Data
    let batches: [ReviewedBatch]
    let digest: Data
    let excludedRelativePaths: [String]
    init(header: ReviewedManifestHeader, batches: [ReviewedBatch],
         excludedRelativePaths: [String], digest: Data) {
        self.header = header
        self.canonicalHeaderBytes = (try? ManifestEncoding.header(header)) ?? Data()
        self.batches = batches
        self.digest = digest
        self.excludedRelativePaths = excludedRelativePaths
    }
    static func capture(anchor: DirectoryAnchor, excluding: Set<String>,
                        maxNodesPerBatch: Int = 5_000,
                        maxBytesPerBatch: Int = 8 * 1_024 * 1_024) throws -> ReviewedTree {
        guard (1...5_000).contains(maxNodesPerBatch), (1...8 * 1_024 * 1_024).contains(maxBytesPerBatch) else {
            throw GuardedFileError.manifestLimit
        }
        for path in excluding { _ = try DirectoryAnchor.relativeComponents(path) }
        try anchor.validateNamespace()
        let root = try DirectoryAnchor.readSnapshot(anchor.rootFD)
        let header = ReviewedManifestHeader(schemaVersion: 1, rootVolumeID: anchor.volumeID,
            canonicalRootPath: anchor.path, rootSnapshot: root,
            rootParentChain: Array(anchor.originalChain.dropLast()))
        var batches: [ReviewedBatch] = []
        var entries: [ReviewedLeaf] = []
        var batchID = UUID()
        var batchBytes = 24 // UUID bytes plus UInt64 entry count.
        func append(_ entry: ReviewedLeaf) throws {
            let size = try ManifestEncoding.leaf(entry).count
            guard size <= maxBytesPerBatch - 24 else { throw GuardedFileError.manifestLimit }
            if entries.count == maxNodesPerBatch || size > maxBytesPerBatch - batchBytes {
                batches.append(ReviewedBatch(id: batchID, entries: entries, encodedBytes: batchBytes))
                entries = []; batchID = UUID(); batchBytes = 24
            }
            entries.append(entry)
            batchBytes += size
        }
        func walk(_ fd: Int32, prefix: String, parents: [NodeSnapshot]) throws {
            let before = try DirectoryAnchor.readSnapshot(fd)
            let enumerationFD = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard enumerationFD >= 0 else { throw GuardedFileError.systemCall(errno) }
            guard let directory = fdopendir(enumerationFD) else {
                let code = errno; close(enumerationFD); throw GuardedFileError.systemCall(code)
            }
            defer { closedir(directory) }
            var names: [String] = []
            while true {
                errno = 0
                guard let entry = readdir(directory) else {
                    if errno != 0 { throw GuardedFileError.systemCall(errno) }
                    break
                }
                let length = Int(entry.pointee.d_namlen)
                let name = withUnsafeBytes(of: entry.pointee.d_name) {
                    String(bytes: $0.prefix(length), encoding: .utf8)
                }
                guard let name else { throw GuardedFileError.invalidComponent }
                if name == "." || name == ".." { continue }
                _ = try DirectoryAnchor.relativeComponents(name)
                names.append(name)
            }
            for name in names.sorted(by: ManifestEncoding.ordered) {
                let relative = prefix.isEmpty ? name : prefix + "/" + name
                if excluding.contains(where: { PathGuard.isEqualOrDescendant(relative, of: $0) }) { continue }
                let snapshot = try DirectoryAnchor.readSnapshot(fd, name)
                guard snapshot.device == root.device else { throw GuardedFileError.differentDevice }
                guard snapshot.isDirectory || snapshot.isRegular else { throw GuardedFileError.unsupportedNode }
                let child = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
                    | (snapshot.isDirectory ? O_DIRECTORY : 0))
                guard child >= 0 else { throw GuardedFileError.systemCall(errno) }
                defer { close(child) }
                guard try DirectoryAnchor.readSnapshot(child) == snapshot else { throw GuardedFileError.identityChanged }
                try anchor.validateVolume(child)
                let entry = ReviewedLeaf(relativePath: relative, parentChain: parents, snapshot: snapshot)
                try append(entry)
                if snapshot.isDirectory { try walk(child, prefix: relative, parents: parents + [snapshot]) }
                guard try DirectoryAnchor.readSnapshot(fd, name) == snapshot else { throw GuardedFileError.identityChanged }
            }
            guard try DirectoryAnchor.readSnapshot(fd) == before else { throw GuardedFileError.identityChanged }
        }
        try walk(anchor.rootFD, prefix: "", parents: header.rootParentChain + [root])
        if !entries.isEmpty { batches.append(ReviewedBatch(id: batchID, entries: entries, encodedBytes: batchBytes)) }
        try anchor.validateNamespace()
        guard try DirectoryAnchor.readSnapshot(anchor.rootFD) == root else { throw GuardedFileError.identityChanged }
        // Reject a mixed snapshot if an earlier leaf changed while later names
        // were captured. This is read-only review, not an external-writer lease.
        for entry in batches.flatMap(\.entries) {
            try anchor.withParent(relativePath: entry.relativePath) { parent, name, chain in
                guard chain.count == entry.parentChain.count,
                      zip(chain, entry.parentChain).allSatisfy({ $0.sameIdentity(as: $1) }),
                      try DirectoryAnchor.readSnapshot(parent, name) == entry.snapshot else {
                    throw GuardedFileError.identityChanged
                }
            }
        }
        let exclusions = excluding.sorted(by: ManifestEncoding.ordered)
        let provisional = ReviewedTree(header: header, batches: batches, excludedRelativePaths: exclusions, digest: Data())
        let digest = try provisional.recomputedDigest()
        return ReviewedTree(header: header, batches: batches, excludedRelativePaths: exclusions, digest: digest)
    }
    func entry(_ relativePath: String) -> ReviewedLeaf? {
        batches.lazy.flatMap(\.entries).first { $0.relativePath == relativePath }
    }
    func validateDigest(_ expected: Data) -> Bool {
        guard let recomputed = try? recomputedDigest() else { return false }
        return recomputed == digest && recomputed == expected
    }
    private func recomputedDigest() throws -> Data {
        guard header.schemaVersion == 1, header.rootSnapshot.isDirectory,
              !header.rootParentChain.isEmpty,
              header.rootParentChain.allSatisfy({ $0.isDirectory }),
              canonicalHeaderBytes == (try ManifestEncoding.header(header)) else { throw GuardedFileError.invalidManifest }
        _ = try PathGuard.relation(candidate: header.canonicalRootPath, protectedRoot: "/")
        guard header.canonicalRootPath != "/",
              header.rootParentChain.count == header.canonicalRootPath.split(separator: "/").count else {
            throw GuardedFileError.invalidManifest
        }
        var hash = SHA256()
        hash.update(data: canonicalHeaderBytes)
        var exclusionBytes = ManifestEncoding()
        exclusionBytes.integer(UInt64(excludedRelativePaths.count))
        var lastExclusion: String?
        for path in excludedRelativePaths {
            _ = try DirectoryAnchor.relativeComponents(path)
            if let previous = lastExclusion, !ManifestEncoding.ordered(previous, path) { throw GuardedFileError.invalidManifest }
            try exclusionBytes.string(path)
            lastExclusion = path
        }
        hash.update(data: exclusionBytes.data)
        var sequence = ManifestEncoding()
        sequence.integer(UInt64(batches.count))
        hash.update(data: sequence.data)
        var ids = Set<UUID>()
        var previousPath: String?
        // Canonical preorder lets us retain only the active directory prefix,
        // including across batch boundaries, instead of searching all entries.
        var directories: [(name: String, snapshot: NodeSnapshot)] = []
        for batch in batches {
            guard ids.insert(batch.id).inserted, (1...5_000).contains(batch.entries.count) else {
                throw GuardedFileError.invalidManifest
            }
            let encoded = try ManifestEncoding.batch(batch)
            guard encoded.count == batch.encodedBytes, encoded.count <= 8 * 1_024 * 1_024 else {
                throw GuardedFileError.invalidManifest
            }
            for entry in batch.entries {
                let parts = try DirectoryAnchor.relativeComponents(entry.relativePath)
                guard entry.snapshot.isDirectory || entry.snapshot.isRegular,
                      entry.snapshot.device == header.rootSnapshot.device,
                      entry.parentChain.count == header.rootParentChain.count + parts.count,
                      entry.parentChain.prefix(header.rootParentChain.count) == header.rootParentChain[...],
                      entry.parentChain[header.rootParentChain.count] == header.rootSnapshot,
                      !excludedRelativePaths.contains(where: { PathGuard.isEqualOrDescendant(entry.relativePath, of: $0) }) else {
                    throw GuardedFileError.invalidManifest
                }
                if let previous = previousPath, !ManifestEncoding.ordered(previous, entry.relativePath) {
                    throw GuardedFileError.invalidManifest
                }
                var commonDepth = 0
                while commonDepth < min(directories.count, parts.count - 1),
                      directories[commonDepth].name == parts[commonDepth] {
                    commonDepth += 1
                }
                directories.removeLast(directories.count - commonDepth)
                guard directories.count == parts.count - 1 else { throw GuardedFileError.invalidManifest }
                for (index, directory) in directories.enumerated() {
                    let parent = entry.parentChain[header.rootParentChain.count + 1 + index]
                    guard parent.isDirectory, parent.device == header.rootSnapshot.device,
                          parent == directory.snapshot else { throw GuardedFileError.invalidManifest }
                }
                if entry.snapshot.isDirectory {
                    directories.append((name: parts[parts.count - 1], snapshot: entry.snapshot))
                }
                previousPath = entry.relativePath
            }
            hash.update(data: encoded)
        }
        return Data(hash.finalize())
    }
}

/// Schema 1: fixed-width big-endian integers, UTF-8 byte lengths, explicit
/// optional tags. Payload limits include batch UUID and entry-count bytes.
/// Internal value serialization only; does not validate or authorize effects.
struct ManifestEncoding {
    var data = Data()
    mutating func integer<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
    }
    mutating func string(_ value: String) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= 8 * 1_024 * 1_024, data.count <= 8 * 1_024 * 1_024 - bytes.count - 8 else {
            throw GuardedFileError.manifestLimit
        }
        integer(UInt64(bytes.count)); data.append(bytes)
    }
    mutating func uuid(_ value: UUID) {
        var bytes = value.uuid
        withUnsafeBytes(of: &bytes) { data.append(contentsOf: $0) }
    }
    mutating func snapshot(_ value: NodeSnapshot) throws {
        guard value.apparentBytes >= 0, value.allocatedBytes.map({ $0 >= 0 }) ?? true,
              (0..<1_000_000_000).contains(value.modifiedNanoseconds),
              (0..<1_000_000_000).contains(value.changedNanoseconds) else { throw GuardedFileError.invalidManifest }
        integer(value.device); integer(value.inode)
        integer(UInt8(value.generation == nil ? 0 : 1))
        if let generation = value.generation { integer(generation) }
        integer(value.mode); integer(value.linkCount); integer(value.apparentBytes)
        integer(UInt8(value.allocatedBytes == nil ? 0 : 1))
        if let allocated = value.allocatedBytes { integer(allocated) }
        integer(value.modifiedSeconds); integer(value.modifiedNanoseconds)
        integer(value.changedSeconds); integer(value.changedNanoseconds)
        guard data.count <= 8 * 1_024 * 1_024 else { throw GuardedFileError.manifestLimit }
    }
    mutating func chain(_ values: [NodeSnapshot]) throws {
        integer(UInt64(values.count))
        for value in values { try snapshot(value) }
    }
    static func header(_ value: ReviewedManifestHeader) throws -> Data {
        var encoded = Self()
        encoded.integer(value.schemaVersion); encoded.uuid(value.rootVolumeID)
        try encoded.string(value.canonicalRootPath)
        try encoded.snapshot(value.rootSnapshot); try encoded.chain(value.rootParentChain)
        return encoded.data
    }
    static func leaf(_ value: ReviewedLeaf) throws -> Data {
        var encoded = Self()
        try encoded.string(value.relativePath)
        try encoded.chain(value.parentChain); try encoded.snapshot(value.snapshot)
        return encoded.data
    }
    static func batch(_ value: ReviewedBatch) throws -> Data {
        var encoded = Self()
        encoded.uuid(value.id); encoded.integer(UInt64(value.entries.count))
        for entry in value.entries {
            let bytes = try leaf(entry)
            guard bytes.count <= 8 * 1_024 * 1_024 - encoded.data.count else { throw GuardedFileError.manifestLimit }
            encoded.data.append(bytes)
        }
        return encoded.data
    }
    static func ordered(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: "/")
        let right = rhs.split(separator: "/")
        for (a, b) in zip(left, right) where a != b { return a.utf8.lexicographicallyPrecedes(b.utf8) }
        return left.count < right.count
    }
}
enum LeafEligibility: Equatable {
    case unchanged, missing, changed, protectedScope, differentDevice, unsupported
}
enum AnchoredFileOperations {
    static func eligibility(anchor: DirectoryAnchor, reviewed: ReviewedLeaf,
                            excludedRelativePaths: Set<String>) -> LeafEligibility {
        do {
            try withCheckedLeaf(anchor: anchor, reviewed: reviewed, exclusions: excludedRelativePaths) { _, _, _ in }
            return .unchanged
        } catch GuardedFileError.protectedScope { return .protectedScope }
        catch GuardedFileError.differentDevice { return .differentDevice }
        catch GuardedFileError.identityChanged { return .changed }
        catch GuardedFileError.systemCall(ENOENT) { return .missing }
        catch { return .unsupported }
    }

    /// Internal mechanism only. There is deliberately no production caller in
    /// T03.A. A future private coordinator facade must hold accepted producer
    /// exclusion plus the synchronous policy barrier across this call. Darwin
    /// does not supply inode-conditional unlink: check/unlink is NOT atomic.
    static func unlinkReviewedLeaf(anchor: DirectoryAnchor, reviewed: ReviewedLeaf,
                                   excludedRelativePaths: Set<String>) -> TargetEffectOutcome {
        let unknown = ByteObservation(bytes: nil, explanation: "Physical reclaim not established by unlink")
        func outcome(_ status: EffectStatus, _ reason: String?, removed: NodeSnapshot? = nil) -> TargetEffectOutcome {
            TargetEffectOutcome(relativePath: reviewed.relativePath, status: status, reason: reason,
                completedRemovals: removed == nil ? 0 : 1,
                removedApparentBytes: ByteObservation(bytes: removed?.apparentBytes,
                    explanation: removed == nil ? "No completed removal" : nil),
                removedAllocatedBytes: ByteObservation(bytes: removed?.allocatedBytes,
                    explanation: removed?.allocatedBytes != nil ? nil : "Allocation unavailable or no completed removal"),
                provenReclaimedBytes: unknown)
        }
        do {
            let removed = try withCheckedLeaf(anchor: anchor, reviewed: reviewed, exclusions: excludedRelativePaths) { parent, name, snapshot in
                let flags = reviewed.snapshot.isDirectory ? AT_REMOVEDIR : 0
                guard unlinkat(parent, name, flags) == 0 else { throw GuardedFileError.systemCall(errno) }
                return snapshot
            }
            return outcome(.succeeded, nil, removed: removed)
        } catch GuardedFileError.systemCall(let code) {
            let retained = [ENOENT, ENOTEMPTY, EEXIST, ELOOP, ENOTDIR].contains(code)
            return outcome(retained ? .skipped : .failed, "errno \(code): \(String(cString: strerror(code)))")
        } catch {
            return outcome(.skipped, String(describing: error))
        }
    }

    private static func withCheckedLeaf<T>(anchor: DirectoryAnchor, reviewed: ReviewedLeaf,
                                           exclusions: Set<String>, body: (Int32, String, NodeSnapshot) throws -> T) throws -> T {
        _ = try DirectoryAnchor.relativeComponents(reviewed.relativePath)
        for exclusion in exclusions {
            _ = try DirectoryAnchor.relativeComponents(exclusion)
            if PathGuard.isEqualOrDescendant(reviewed.relativePath, of: exclusion)
                || PathGuard.isEqualOrDescendant(exclusion, of: reviewed.relativePath) {
                throw GuardedFileError.protectedScope
            }
        }
        return try anchor.withParent(relativePath: reviewed.relativePath) { parent, name, chain in
            guard chain.count == reviewed.parentChain.count,
                  zip(chain, reviewed.parentChain).allSatisfy({ $0.sameIdentity(as: $1) }) else {
                throw GuardedFileError.identityChanged
            }
            func check(_ snapshot: NodeSnapshot) throws {
                guard snapshot.device == anchor.originalChain.last!.device else { throw GuardedFileError.differentDevice }
                guard snapshot.isRegular || snapshot.isDirectory else { throw GuardedFileError.unsupportedNode }
                let unchanged = snapshot.isDirectory ? snapshot.sameIdentity(as: reviewed.snapshot) : snapshot == reviewed.snapshot
                guard unchanged else { throw GuardedFileError.identityChanged }
            }
            try check(DirectoryAnchor.readSnapshot(parent, name))
            let leaf = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
                | (reviewed.snapshot.isDirectory ? O_DIRECTORY : 0))
            guard leaf >= 0 else { throw GuardedFileError.systemCall(errno) }
            defer { close(leaf) }
            try check(DirectoryAnchor.readSnapshot(leaf))
            try anchor.validateVolume(leaf)
            try anchor.validateNamespace()
            let final = try DirectoryAnchor.readSnapshot(parent, name)
            try check(final)
            return try body(parent, name, final)
        }
    }
}
enum SchedulingStop: Equatable { case cancelled, deadline, budget, unknownEstimate }
struct LeafScheduleBudget {
    private let allocatedByteLimit: Int64
    private let leafLimit: Int
    private let deadline: ContinuousClock.Instant
    private(set) var reservedBytes: Int64 = 0
    private(set) var reservedLeaves: Int = 0
    init(allocatedByteLimit: Int64, leafLimit: Int, deadline: ContinuousClock.Instant) throws {
        guard allocatedByteLimit >= 0, leafLimit > 0 else { throw GuardedFileError.invalidBudget }
        self.allocatedByteLimit = allocatedByteLimit
        self.leafLimit = leafLimit
        self.deadline = deadline
    }
    mutating func reserve(allocatedEstimate: Int64?, now: ContinuousClock.Instant,
                          cancelled: Bool) -> SchedulingStop? {
        if cancelled { return .cancelled }
        if now >= deadline { return .deadline }
        guard let estimate = allocatedEstimate, estimate >= 0 else { return .unknownEstimate }
        let (bytes, byteOverflow) = reservedBytes.addingReportingOverflow(estimate)
        let (leaves, leafOverflow) = reservedLeaves.addingReportingOverflow(1)
        guard !byteOverflow, !leafOverflow, bytes <= allocatedByteLimit, leaves <= leafLimit else { return .budget }
        reservedBytes = bytes; reservedLeaves = leaves
        return nil
    }
}
