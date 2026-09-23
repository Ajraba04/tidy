import Foundation
import Darwin
import CryptoKit
enum ResourceCaptureError: Error { case unavailable, unsupported }

struct ProtectionScopeIdentity: Codable, Hashable, Sendable {
    let digest: Data
    let canonicalProtectedRoots: [String]
}

/// Exact review-time filesystem authority. The full tree remains internal so
/// callers cannot reconstruct authority from a digest or a display path. R03
/// persists its canonical header and batches before effects.
struct ReviewedFileResource: Sendable {
    let identity: FileResourceIdentity
    let protection: ProtectionScopeIdentity
    let tree: ReviewedTree

    func matchesProtectionScope(_ protectedRoots: [String]) -> Bool {
        guard let current = try? ResourcePreflight.protectionScope(
            rootPath: identity.canonicalPath, protectedRoots: protectedRoots) else { return false }
        return current == protection
    }

    var persistenceArchive: ReviewedManifestArchive {
        ReviewedManifestArchive(reviewed: self)
    }
}

/// Versioned, serializable R03 handoff. Each stored batch preserves its exact
/// reviewed names and descriptor-derived identities and independently retains
/// the existing 5,000-node / 8 MiB bound. Decoding never trusts Codable alone:
/// `restore()` re-encodes every value and verifies the canonical manifest and
/// protection digests before returning an internal review seal.
struct ReviewedManifestArchive: Codable, Sendable {
    static let currentSchemaVersion: UInt32 = 1
    static let maximumBatchCount = 20
    static let maximumNodeCount = 100_000
    static let maximumCanonicalBytes = 64 * 1_024 * 1_024
    static let maximumSerializedBytes = 96 * 1_024 * 1_024
    static let maximumProtectionRoots = 256

    let archiveSchemaVersion: UInt32
    let header: ReviewedManifestHeader
    let batches: [ReviewedBatch]
    let excludedRelativePaths: [String]
    let manifestDigest: Data
    let protection: ProtectionScopeIdentity

    init(reviewed: ReviewedFileResource) {
        archiveSchemaVersion = Self.currentSchemaVersion
        header = reviewed.tree.header
        batches = reviewed.tree.batches
        excludedRelativePaths = reviewed.tree.excludedRelativePaths
        manifestDigest = reviewed.tree.digest
        protection = reviewed.protection
    }

    func encodedBounded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumSerializedBytes else {
            throw GuardedFileError.manifestLimit
        }
        return data
    }

    static func decodeBounded(_ data: Data) throws -> Self {
        // R03 must bound its file read to the same value before allocating
        // `data`; this second gate prevents JSONDecoder from materializing an
        // attacker-sized array or payload inside the authority layer.
        guard data.count <= Self.maximumSerializedBytes else {
            throw GuardedFileError.manifestLimit
        }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        try archive.validateAggregateBounds()
        return archive
    }

    func restore() throws -> ReviewedFileResource {
        guard archiveSchemaVersion == Self.currentSchemaVersion,
              header.schemaVersion == 1 else { throw GuardedFileError.invalidManifest }
        try validateAggregateBounds()
        let recomputedProtection = try ResourcePreflight.protectionScope(
            rootPath: header.canonicalRootPath,
            protectedRoots: protection.canonicalProtectedRoots)
        guard recomputedProtection == protection else { throw GuardedFileError.invalidManifest }
        let derivedExclusions = try ResourcePreflight.descendantExclusions(
            rootPath: header.canonicalRootPath,
            protectedRoots: protection.canonicalProtectedRoots)
            .sorted(by: ManifestEncoding.ordered)
        guard derivedExclusions == excludedRelativePaths else {
            throw GuardedFileError.invalidManifest
        }
        let tree = ReviewedTree(header: header, batches: batches,
            excludedRelativePaths: excludedRelativePaths, digest: manifestDigest)
        guard tree.validateDigest(manifestDigest) else { throw GuardedFileError.invalidManifest }
        return try ResourcePreflight.makeReviewedResource(tree: tree, protection: protection)
    }

    private func validateAggregateBounds() throws {
        guard batches.count <= Self.maximumBatchCount,
              excludedRelativePaths.count <= Self.maximumProtectionRoots,
              protection.canonicalProtectedRoots.count <= Self.maximumProtectionRoots else {
            throw GuardedFileError.manifestLimit
        }
        var nodes = 0
        var exclusions = ManifestEncoding()
        exclusions.integer(UInt64(excludedRelativePaths.count))
        for path in excludedRelativePaths { try exclusions.string(path) }
        var bytes = try ManifestEncoding.header(header).count
        let (withExclusions, exclusionOverflow) = bytes.addingReportingOverflow(exclusions.data.count + 8)
        guard !exclusionOverflow else { throw GuardedFileError.manifestLimit }
        bytes = withExclusions
        for batch in batches {
            let (nextNodes, nodeOverflow) = nodes.addingReportingOverflow(batch.entries.count)
            let (nextBytes, byteOverflow) = bytes.addingReportingOverflow(batch.encodedBytes)
            guard !nodeOverflow, !byteOverflow,
                  nextNodes <= Self.maximumNodeCount,
                  nextBytes <= Self.maximumCanonicalBytes else {
                throw GuardedFileError.manifestLimit
            }
            nodes = nextNodes
            bytes = nextBytes
        }
    }
}

enum ResourcePreflight {
    /// Read-only no-follow capture. This is not an anchored deletion capability.
    static func captureFile(at path: String) throws -> FileResourceIdentity {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { throw ResourceCaptureError.unavailable }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..") else {
            throw ResourceCaptureError.unavailable
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ResourceCaptureError.unavailable }
        defer { close(fd) }
        var parents: [FileNodeIdentity] = []
        for component in components.dropLast() {
            var parent = stat()
            guard fstat(fd, &parent) == 0 else { throw ResourceCaptureError.unavailable }
            parents.append(FileNodeIdentity(device: UInt64(UInt32(bitPattern: parent.st_dev)),
                                            inode: UInt64(parent.st_ino), generation: UInt64(parent.st_gen),
                                            mode: UInt32(parent.st_mode)))
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ResourceCaptureError.unavailable }
            close(fd); fd = next
        }
        var parent = stat()
        guard fstat(fd, &parent) == 0 else { throw ResourceCaptureError.unavailable }
        parents.append(FileNodeIdentity(device: UInt64(UInt32(bitPattern: parent.st_dev)),
                                        inode: UInt64(parent.st_ino), generation: UInt64(parent.st_gen),
                                        mode: UInt32(parent.st_mode)))
        let leaf = components.last!
        var metadata = stat()
        guard fstatat(fd, leaf, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
              [S_IFREG, S_IFDIR].contains(metadata.st_mode & S_IFMT) else {
            throw ResourceCaptureError.unavailable
        }
        let leafFD = openat(fd, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard leafFD >= 0 else { throw ResourceCaptureError.unavailable }
        defer { close(leafFD) }
        var opened = stat()
        var volume = statfs()
        guard fstat(leafFD, &opened) == 0, opened.st_dev == metadata.st_dev,
              opened.st_ino == metadata.st_ino, fstatfs(leafFD, &volume) == 0,
              volume.f_flags & UInt32(MNT_LOCAL) != 0 else { throw ResourceCaptureError.unavailable }
        let canonical = "/" + components.joined(separator: "/")
        // Darwin's ATTR_VOL_UUID is uuid_t. Read it from the retained no-follow
        // descriptor, never by reopening a potentially replaced path namespace.
        struct VolumeAttributes {
            var length: UInt32 = 0
            var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        }
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_UUID)
        var volumeAttributes = VolumeAttributes()
        guard fgetattrlist(leafFD, &attributes, &volumeAttributes,
                          MemoryLayout<VolumeAttributes>.size, 0) == 0,
              volumeAttributes.length == MemoryLayout<VolumeAttributes>.size,
              withUnsafeBytes(of: volumeAttributes.uuid, { $0.contains { $0 != 0 } }) else {
            throw ResourceCaptureError.unsupported
        }
        let volumeID = UUID(uuid: volumeAttributes.uuid)
        var final = stat()
        guard fstatat(fd, leaf, &final, AT_SYMLINK_NOFOLLOW) == 0,
              final.st_dev == opened.st_dev, final.st_ino == opened.st_ino,
              final.st_mode == opened.st_mode, final.st_size == opened.st_size,
              final.st_mtimespec.tv_sec == opened.st_mtimespec.tv_sec,
              final.st_mtimespec.tv_nsec == opened.st_mtimespec.tv_nsec else {
            throw ResourceCaptureError.unavailable
        }
        return FileResourceIdentity(volumeID: volumeID, device: UInt64(UInt32(bitPattern: opened.st_dev)),
            inode: UInt64(opened.st_ino), generation: UInt64(opened.st_gen), canonicalPath: canonical,
            mode: UInt32(opened.st_mode), size: opened.st_size,
            modifiedSeconds: Int64(opened.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(opened.st_mtimespec.tv_nsec), parentChain: parents, manifest: nil)
    }
    static func unchanged(_ identity: FileResourceIdentity) -> Bool {
        guard let current = try? captureFile(at: identity.canonicalPath) else { return false }
        return current.withoutManifest == identity.withoutManifest
    }

    static func captureReviewedDirectory(at path: String, protectedRoots: [String],
                                         maxNodesPerBatch: Int = 5_000,
                                         maxBytesPerBatch: Int = 8 * 1_024 * 1_024,
                                         limits: ManifestCaptureLimits = .production()) throws
      -> ReviewedFileResource {
        let anchor = try DirectoryAnchor.open(path: path)
        let protection = try protectionScope(rootPath: anchor.path, protectedRoots: protectedRoots)
        let relativeExclusions = try descendantExclusions(
            rootPath: anchor.path, protectedRoots: protection.canonicalProtectedRoots)
        let tree = try ReviewedTree.capture(anchor: anchor, excluding: relativeExclusions,
            maxNodesPerBatch: maxNodesPerBatch, maxBytesPerBatch: maxBytesPerBatch,
            limits: limits)
        return try makeReviewedResource(tree: tree, protection: protection)
    }

    static func makeReviewedResource(tree: ReviewedTree,
                                     protection: ProtectionScopeIdentity) throws -> ReviewedFileResource {
        guard tree.batches.count <= ReviewedManifestArchive.maximumBatchCount,
              protection.canonicalProtectedRoots.count <= ReviewedManifestArchive.maximumProtectionRoots,
              tree.excludedRelativePaths.count <= ReviewedManifestArchive.maximumProtectionRoots else {
            throw GuardedFileError.manifestLimit
        }
        let nodeCount = try tree.batches.reduce(0) { count, batch in
            let (next, overflow) = count.addingReportingOverflow(batch.entries.count)
            guard !overflow, next <= ReviewedManifestArchive.maximumNodeCount else {
                throw GuardedFileError.manifestLimit
            }
            return next
        }
        var exclusions = ManifestEncoding()
        exclusions.integer(UInt64(tree.excludedRelativePaths.count))
        for path in tree.excludedRelativePaths { try exclusions.string(path) }
        let (baseBytes, baseOverflow) = tree.canonicalHeaderBytes.count
            .addingReportingOverflow(exclusions.data.count + 8)
        guard !baseOverflow, baseBytes <= ReviewedManifestArchive.maximumCanonicalBytes else {
            throw GuardedFileError.manifestLimit
        }
        let encodedBytes = try tree.batches.reduce(baseBytes) { count, batch in
            let (next, overflow) = count.addingReportingOverflow(batch.encodedBytes)
            guard !overflow, next <= ReviewedManifestArchive.maximumCanonicalBytes else {
                throw GuardedFileError.manifestLimit
            }
            return next
        }
        let root = tree.header.rootSnapshot
        let identity = FileResourceIdentity(
            volumeID: tree.header.rootVolumeID,
            device: root.device,
            inode: root.inode,
            generation: root.generation,
            canonicalPath: tree.header.canonicalRootPath,
            mode: root.mode,
            size: root.apparentBytes,
            modifiedSeconds: root.modifiedSeconds,
            modifiedNanoseconds: root.modifiedNanoseconds,
            parentChain: tree.header.rootParentChain.map {
                FileNodeIdentity(device: $0.device, inode: $0.inode,
                                 generation: $0.generation, mode: $0.mode)
            },
            manifest: ReviewedManifestIdentity(
                schemaVersion: tree.header.schemaVersion,
                digest: tree.digest,
                protectionDigest: protection.digest,
                batchIDs: tree.batches.map(\.id),
                nodeCount: nodeCount,
                encodedBytes: encodedBytes
            )
        )
        return ReviewedFileResource(identity: identity, protection: protection, tree: tree)
    }

    static func openValidated(_ reviewed: ReviewedFileResource,
                              currentProtectedRoots: [String]) throws -> DirectoryAnchor {
        guard reviewed.matchesProtectionScope(currentProtectedRoots) else {
            throw ResourceAuthorityError.protectionScopeChanged
        }
        guard let manifest = reviewed.identity.manifest,
              manifest.schemaVersion == reviewed.tree.header.schemaVersion,
              manifest.digest == reviewed.tree.digest,
              manifest.protectionDigest == reviewed.protection.digest,
              manifest.batchIDs == reviewed.tree.batches.map(\.id),
              reviewed.tree.validateDigest(manifest.digest) else {
            throw GuardedFileError.invalidManifest
        }
        let anchor = try DirectoryAnchor.open(path: reviewed.identity.canonicalPath)
        guard anchor.volumeID == reviewed.identity.volumeID,
              anchor.path == reviewed.identity.canonicalPath,
              anchor.originalChain.last == reviewed.tree.header.rootSnapshot,
              Array(anchor.originalChain.dropLast()) == reviewed.tree.header.rootParentChain else {
            throw GuardedFileError.identityChanged
        }
        return anchor
    }

    static func protectionScope(rootPath: String,
                                protectedRoots: [String]) throws -> ProtectionScopeIdentity {
        let canonicalRoot = PathGuard.canonicalize(rootPath)
        guard canonicalRoot == rootPath else { throw GuardedFileError.identityChanged }
        let roots = Array(Set(protectedRoots.map(PathGuard.canonicalize)))
            .sorted(by: ManifestEncoding.ordered)
        var encoding = ManifestEncoding()
        encoding.integer(UInt32(1))
        try encoding.string(canonicalRoot)
        encoding.integer(UInt64(roots.count))
        for root in roots {
            _ = try PathGuard.relation(candidate: canonicalRoot, protectedRoot: root)
            try encoding.string(root)
        }
        return ProtectionScopeIdentity(digest: Data(SHA256.hash(data: encoding.data)),
                                       canonicalProtectedRoots: roots)
    }

    fileprivate static func descendantExclusions(rootPath: String,
                                                 protectedRoots: [String]) throws -> Set<String> {
        var exclusions: Set<String> = []
        for protected in protectedRoots {
            switch try PathGuard.relation(candidate: rootPath, protectedRoot: protected) {
            case .insideProtected:
                throw GuardedFileError.protectedScope
            case .containsProtected:
                let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
                guard protected.hasPrefix(prefix) else { throw GuardedFileError.invalidComponent }
                let relative = String(protected.dropFirst(prefix.count))
                _ = try DirectoryAnchor.relativeComponents(relative)
                exclusions.insert(relative)
            case .disjoint:
                break
            }
        }
        return exclusions
    }
}

private extension FileResourceIdentity {
    var withoutManifest: FileResourceIdentity {
        FileResourceIdentity(volumeID: volumeID, device: device, inode: inode,
            generation: generation, canonicalPath: canonicalPath, mode: mode, size: size,
            modifiedSeconds: modifiedSeconds, modifiedNanoseconds: modifiedNanoseconds,
            parentChain: parentChain, manifest: nil)
    }
}
