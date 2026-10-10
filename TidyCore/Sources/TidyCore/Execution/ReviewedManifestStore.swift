import CryptoKit
import Darwin
import Foundation

enum EffectArtifactStoreError: Error, Equatable {
    case invalidReference
    case corrupt
    case capacity
    case unavailable
    case publicationUncertain
}

struct StoredReviewedManifest: Sendable {
    let reference: ReviewedManifestReference
    let header: ReviewedManifestHeader
    let excludedRelativePaths: [String]
    let protection: ProtectionScopeIdentity
}
struct EffectArtifactOccupancy: Equatable, Sendable {
    let artifacts: Int
    let bytes: Int
    let hasStaging: Bool
}

/// Immutable large-artifact storage under the same installation lock as the
/// mandatory admission ledger. It never reuses the one-MiB journal publisher.
final class ReviewedManifestStore {
    static let maximumAggregateBytes = 256 * 1_048_576
    static let maximumArtifacts = 1_024
    static let retainedArtifactCeiling = maximumArtifacts
        - ReviewedManifestArchive.maximumBatchCount - 2
    private static let maximumArtifactBytes = 16 * 1_048_576
    private static let maximumIndexBytes = 1_048_576

    fileprivate struct Descriptor: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let bytes: Int
        let digest: Data
    }
    private struct Index: Codable {
        let schema: UInt32
        let reference: ReviewedManifestReference
        let header: ReviewedManifestHeader
        let excludedRelativePaths: [String]
        let protection: ProtectionScopeIdentity
        let batches: [Descriptor]
    }
    private struct Occupancy {
        let artifacts: Int
        let bytes: Int
        let hasStaging: Bool
        let proofNames: [String]
    }
    private struct RetirementIdentity: Codable, Equatable {
        let name: String
        let device: UInt64
        let inode: UInt64
    }
    private struct RetirementMarker: Codable, Equatable {
        let schema: UInt32
        let id: UUID
        let runID: UUID
        let journalName: String
        let journalDevice: UInt64
        let journalInode: UInt64
        let journalBytes: Int
        let artifacts: [RetirementIdentity]
    }
    struct PreparedManifestPublication: Sendable {
        let reference: ReviewedManifestReference
        fileprivate let reviewed: ReviewedFileResource
        fileprivate let descriptors: [Descriptor]
        fileprivate let indexBytes: Data
    }

    private let admission: MutationAdmissionStore
    init(admission: MutationAdmissionStore) { self.admission = admission }

    func retentionOccupancy() throws -> EffectArtifactOccupancy {
        try admission.withLockedStorage { directory, _, _ in
            let value = try Self.occupancy(directory)
            return EffectArtifactOccupancy(artifacts: value.artifacts,
                bytes: value.bytes, hasStaging: value.hasStaging)
        }
    }

    func persist(_ reviewed: ReviewedFileResource) throws -> ReviewedManifestReference {
        let prepared = try prepare(reviewed)
        try publish(prepared)
        return prepared.reference
    }

    func prepare(_ reviewed: ReviewedFileResource) throws -> PreparedManifestPublication {
        let id = UUID()
        var descriptors: [Descriptor] = []
        descriptors.reserveCapacity(reviewed.tree.batches.count)
        var batchBytes = 0
        for (ordinal, batch) in reviewed.tree.batches.enumerated() {
            let bytes = try Self.encodeCanonical(batch)
            guard !bytes.isEmpty, bytes.count <= Self.maximumArtifactBytes else {
                throw EffectArtifactStoreError.capacity
            }
            let (next, overflow) = batchBytes.addingReportingOverflow(bytes.count)
            guard !overflow, next <= Self.maximumAggregateBytes else {
                throw EffectArtifactStoreError.capacity
            }
            batchBytes = next
            let name = Self.batchName(id, ordinal: ordinal)
            descriptors.append(Descriptor(id: batch.id, name: name,
                bytes: bytes.count, digest: Data(SHA256.hash(data: bytes))))
        }
        guard !descriptors.isEmpty,
              descriptors.count == reviewed.tree.batches.count else {
            throw EffectArtifactStoreError.corrupt
        }

        var reference = ReviewedManifestReference(id: id,
            manifestDigest: reviewed.tree.digest,
            protectionDigest: reviewed.protection.digest,
            batchCount: descriptors.count,
            artifactCount: descriptors.count + 1, encodedBytes: batchBytes)
        var indexBytes = Data()
        var stable = false
        for _ in 0..<8 {
            let index = Index(schema: ReviewedManifestReference.schemaVersion,
                reference: reference, header: reviewed.tree.header,
                excludedRelativePaths: reviewed.tree.excludedRelativePaths,
                protection: reviewed.protection, batches: descriptors)
            indexBytes = try Self.encodeCanonical(index)
            guard !indexBytes.isEmpty, indexBytes.count <= Self.maximumIndexBytes else {
                throw EffectArtifactStoreError.capacity
            }
            let (total, overflow) = batchBytes.addingReportingOverflow(indexBytes.count)
            guard !overflow, total <= Self.maximumAggregateBytes else {
                throw EffectArtifactStoreError.capacity
            }
            if reference.encodedBytes == total {
                stable = true
                break
            }
            reference = ReviewedManifestReference(id: id,
                manifestDigest: reviewed.tree.digest,
                protectionDigest: reviewed.protection.digest,
                batchCount: descriptors.count,
                artifactCount: descriptors.count + 1, encodedBytes: total)
        }
        guard stable,
              let decoded = try? JSONDecoder().decode(Index.self, from: indexBytes),
              decoded.reference == reference else { throw EffectArtifactStoreError.corrupt }
        return PreparedManifestPublication(reference: reference, reviewed: reviewed,
            descriptors: descriptors, indexBytes: indexBytes)
    }

    func publish(_ prepared: PreparedManifestPublication) throws {
        let reviewed = prepared.reviewed
        let reference = prepared.reference
        let descriptors = prepared.descriptors
        try admission.withLockedStorage { directory, io, _ in
            let occupancy = try Self.occupancy(directory)
            guard !occupancy.hasStaging else { throw EffectArtifactStoreError.unavailable }
            try Self.reserve(occupancy: occupancy, addingArtifacts: reference.artifactCount,
                             addingBytes: reference.encodedBytes)
            for (ordinal, batch) in reviewed.tree.batches.enumerated() {
                let descriptor = descriptors[ordinal]
                let bytes = try Self.encodeCanonical(batch)
                guard bytes.count == descriptor.bytes,
                      Data(SHA256.hash(data: bytes)) == descriptor.digest else {
                    throw EffectArtifactStoreError.corrupt
                }
                try Self.publishImmutable(directory: directory, name: descriptor.name,
                                          bytes: bytes, io: io)
            }
            try Self.publishImmutable(directory: directory,
                name: Self.indexName(reference.id), bytes: prepared.indexBytes, io: io)
        }
    }

    func load(_ reference: ReviewedManifestReference) throws -> StoredReviewedManifest {
        try validate(reference)
        return try admission.withLockedStorage { directory, _, _ in
            let bytes = try Self.read(directory: directory, name: Self.indexName(reference.id),
                                      maximumBytes: Self.maximumIndexBytes)
            let index = try Self.decodeIndex(bytes, expected: reference)
            try Self.validateStoredBatches(directory: directory, index: index,
                                           indexBytes: bytes)
            return StoredReviewedManifest(reference: reference, header: index.header,
                excludedRelativePaths: index.excludedRelativePaths,
                protection: index.protection)
        }
    }

    func forEachBatch(_ reference: ReviewedManifestReference,
                      _ body: (ReviewedBatch) throws -> Void) throws {
        try forEachBatch(reference, reversed: false, body)
    }

    func forEachBatch(_ reference: ReviewedManifestReference, reversed: Bool,
                      _ body: (ReviewedBatch) throws -> Void) throws {
        try validate(reference)
        try admission.withLockedStorage { directory, _, _ in
            let indexBytes = try Self.read(directory: directory,
                name: Self.indexName(reference.id), maximumBytes: Self.maximumIndexBytes)
            let index = try Self.decodeIndex(indexBytes, expected: reference)
            try Self.validateStoredBatches(directory: directory, index: index,
                                           indexBytes: indexBytes)
            let descriptors = reversed ? Array(index.batches.reversed()) : index.batches
            for descriptor in descriptors {
                let bytes = try Self.read(directory: directory, name: descriptor.name,
                                          maximumBytes: Self.maximumArtifactBytes)
                guard bytes.count == descriptor.bytes,
                      Data(SHA256.hash(data: bytes)) == descriptor.digest else {
                    throw EffectArtifactStoreError.corrupt
                }
                let batch = try JSONDecoder().decode(ReviewedBatch.self, from: bytes)
                guard batch.id == descriptor.id,
                      try ManifestEncoding.batch(batch).count == batch.encodedBytes else {
                    throw EffectArtifactStoreError.corrupt
                }
                try body(batch)
            }
        }
    }

    func persist(_ proof: VerifiedEffectTerminalProof) throws -> EffectProofReference {
        let archive = proof.archive
        let bytes = try Self.encodeCanonical(archive)
        guard !bytes.isEmpty, bytes.count <= Self.maximumIndexBytes else {
            throw EffectArtifactStoreError.capacity
        }
        let reference = EffectProofReference(id: archive.proofID,
            operationID: archive.operationID, digest: Data(SHA256.hash(data: bytes)),
            encodedBytes: bytes.count)
        try admission.withLockedStorage { directory, io, _ in
            let occupancy = try Self.occupancy(directory)
            guard !occupancy.hasStaging else { throw EffectArtifactStoreError.unavailable }
            try Self.reserve(occupancy: occupancy, addingArtifacts: 1, addingBytes: bytes.count)
            try Self.publishImmutable(directory: directory, name: Self.proofName(reference.id),
                                      bytes: bytes, io: io)
        }
        return reference
    }

    func proof(_ reference: EffectProofReference,
               for intent: PendingEffectIntent) throws -> EffectTerminalProofArchive {
        guard reference.schema == EffectProofReference.schemaVersion,
              reference.operationID == intent.operationID,
              reference.encodedBytes > 0,
              reference.encodedBytes <= Self.maximumIndexBytes else {
            throw EffectArtifactStoreError.invalidReference
        }
        return try admission.withLockedStorage { directory, _, _ in
            let bytes = try Self.read(directory: directory, name: Self.proofName(reference.id),
                                      maximumBytes: Self.maximumIndexBytes)
            guard bytes.count == reference.encodedBytes,
                  Data(SHA256.hash(data: bytes)) == reference.digest else {
                throw EffectArtifactStoreError.corrupt
            }
            let archive = try JSONDecoder().decode(EffectTerminalProofArchive.self, from: bytes)
            guard CompiledEffectTerminalVerifier.validate(archive, intent: intent) else {
                throw EffectArtifactStoreError.corrupt
            }
            return archive
        }
    }

    /// Bounded discovery closes only the service proof-publication/event gap.
    /// No proof is inferred from a prepared intent, PID absence or object state.
    func findServiceProof(for intent: PendingEffectIntent) throws -> EffectProofReference? {
        guard intent.schemaVersion == 3, case .service? = intent.binding else {
            throw EffectArtifactStoreError.invalidReference
        }
        return try admission.withLockedStorage { directory, _, _ in
            let occupancy = try Self.occupancy(directory)
            guard !occupancy.hasStaging else { throw EffectArtifactStoreError.unavailable }
            var found: EffectProofReference?
            for name in occupancy.proofNames {
                let bytes = try Self.read(directory: directory, name: name, maximumBytes: Self.maximumIndexBytes)
                let archive = try JSONDecoder().decode(EffectTerminalProofArchive.self, from: bytes)
                guard archive.operationID == intent.operationID else { continue }
                guard found == nil, name == Self.proofName(archive.proofID),
                      CompiledEffectTerminalVerifier.validate(archive, intent: intent) else {
                    throw EffectArtifactStoreError.corrupt
                }
                found = EffectProofReference(id: archive.proofID, operationID: archive.operationID,
                    digest: Data(SHA256.hash(data: bytes)), encodedBytes: bytes.count)
            }
            return found
        }
    }

    func historicalProof(_ reference: EffectProofReference) throws
        -> EffectTerminalProofArchive {
        guard reference.schema == EffectProofReference.schemaVersion,
              reference.encodedBytes > 0,
              reference.encodedBytes <= Self.maximumIndexBytes else {
            throw EffectArtifactStoreError.invalidReference
        }
        return try admission.withLockedStorage { directory, _, _ in
            let bytes = try Self.read(directory: directory,
                name: Self.proofName(reference.id), maximumBytes: Self.maximumIndexBytes)
            guard bytes.count == reference.encodedBytes,
                  Data(SHA256.hash(data: bytes)) == reference.digest else {
                throw EffectArtifactStoreError.corrupt
            }
            let archive = try JSONDecoder().decode(EffectTerminalProofArchive.self,
                                                    from: bytes)
            guard CompiledEffectTerminalVerifier.validateHistorical(
                archive, reference: reference) else {
                throw EffectArtifactStoreError.corrupt
            }
            return archive
        }
    }

    func retireFinishedRun(runID: UUID, journalEntry: JournalStorageEntry,
                           events: [JournalEvent], storage: any JournalStorage) throws {
        let marker = try prepareRetirement(runID: runID,
            journalEntry: journalEntry, events: events)
        try completeRetirement(marker, storage: storage)
    }

    func resumeRetirements(storage: any JournalStorage) throws {
        let markers: [RetirementMarker] = try admission.withLockedStorage {
            directory, _, _ in
            try Self.retirementMarkerNames(directory).map {
                try Self.readRetirementMarker(directory: directory, name: $0)
            }
        }
        for marker in markers { try completeRetirement(marker, storage: storage) }
    }

    private func prepareRetirement(runID: UUID, journalEntry: JournalStorageEntry,
                                   events: [JournalEvent]) throws -> RetirementMarker {
        var names: [String] = []
        for terminal in events where terminal.phase == .itemTerminal {
            guard let proof = terminal.proof else { throw EffectArtifactStoreError.corrupt }
            let archive = try historicalProof(proof)
            guard archive.runID == runID else {
                throw EffectArtifactStoreError.corrupt
            }
            if let manifest = archive.manifest {
                let index = try admission.withLockedStorage { directory, _, _ -> Index in
                    let bytes = try Self.read(directory: directory,
                        name: Self.indexName(manifest.id), maximumBytes: Self.maximumIndexBytes)
                    let index = try Self.decodeIndex(bytes, expected: manifest)
                    try Self.validateStoredBatches(directory: directory, index: index, indexBytes: bytes)
                    return index
                }
                names.append(contentsOf: index.batches.map(\.name))
                names.append(Self.indexName(manifest.id))
            }
            names.append(Self.proofName(proof.id))
        }
        guard Set(names).count == names.count else { throw EffectArtifactStoreError.corrupt }
        return try admission.withLockedStorage { directory, io, _ in
            let identities = try names.sorted().map { name -> RetirementIdentity in
                let fd = try Self.open(directory: directory, name: name,
                                       maximumBytes: Self.maximumArtifactBytes)
                defer { close(fd) }
                var info = stat()
                guard fstat(fd, &info) == 0 else {
                    throw EffectArtifactStoreError.unavailable
                }
                return RetirementIdentity(name: name, device: UInt64(info.st_dev),
                                          inode: UInt64(info.st_ino))
            }
            let id = UUID()
            let marker = RetirementMarker(schema: 1, id: id, runID: runID,
                journalName: journalEntry.name, journalDevice: journalEntry.device,
                journalInode: journalEntry.inode, journalBytes: journalEntry.byteCount,
                artifacts: identities)
            let bytes = try Self.encodeCanonical(marker)
            guard bytes.count <= Self.maximumIndexBytes else {
                throw EffectArtifactStoreError.capacity
            }
            let occupancy = try Self.occupancy(directory)
            try Self.reserve(occupancy: occupancy, addingArtifacts: 1,
                             addingBytes: bytes.count,
                             artifactLimit: Self.maximumArtifacts,
                             byteLimit: Self.maximumAggregateBytes)
            try Self.publishImmutable(directory: directory,
                name: Self.retirementName(id), bytes: bytes, io: io)
            return marker
        }
    }

    private func completeRetirement(_ marker: RetirementMarker,
                                    storage: any JournalStorage) throws {
        let unfinished = try admission.unfinishedIntentsWhileLocked()
        guard marker.schema == 1,
              !unfinished.contains(where: { $0.runID == marker.runID }) else {
            throw EffectArtifactStoreError.corrupt
        }
        try admission.withLockedStorage { directory, io, _ in
            for artifact in marker.artifacts {
                var named = stat()
                if fstatat(directory, artifact.name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
                    guard errno == ENOENT else { throw EffectArtifactStoreError.unavailable }
                    continue
                }
                guard named.st_mode & S_IFMT == S_IFREG,
                      UInt64(named.st_dev) == artifact.device,
                      UInt64(named.st_ino) == artifact.inode,
                      unlinkat(directory, artifact.name, 0) == 0 else {
                    throw EffectArtifactStoreError.corrupt
                }
            }
            do { try io.syncDirectory(fd: directory) }
            catch { throw EffectArtifactStoreError.publicationUncertain }
        }
        let journals = try storage.journalEntries()
        if let entry = journals.first(where: { $0.name == marker.journalName }) {
            guard entry.device == marker.journalDevice,
                  entry.inode == marker.journalInode,
                  entry.byteCount == marker.journalBytes else {
                throw EffectArtifactStoreError.corrupt
            }
            try storage.removeJournal(entry)
        }
        try admission.withLockedStorage { directory, io, _ in
            let name = Self.retirementName(marker.id)
            guard try Self.readRetirementMarker(directory: directory, name: name) == marker else {
                throw EffectArtifactStoreError.corrupt
            }
            let fd = try Self.open(directory: directory, name: name,
                                   maximumBytes: Self.maximumIndexBytes)
            defer { close(fd) }
            var opened = stat()
            guard fstat(fd, &opened) == 0,
                  unlinkat(directory, name, 0) == 0 else {
                throw EffectArtifactStoreError.publicationUncertain
            }
            do { try io.syncDirectory(fd: directory) }
            catch { throw EffectArtifactStoreError.publicationUncertain }
        }
    }

    private func validate(_ reference: ReviewedManifestReference) throws {
        guard reference.schema == ReviewedManifestReference.schemaVersion,
              reference.manifestDigest.count == SHA256.Digest.byteCount,
              reference.protectionDigest.count == SHA256.Digest.byteCount,
              (1...ReviewedManifestArchive.maximumBatchCount).contains(reference.batchCount),
              reference.artifactCount == reference.batchCount + 1,
              reference.artifactCount <= Self.maximumArtifacts,
              reference.encodedBytes > 0,
              reference.encodedBytes <= Self.maximumAggregateBytes else {
            throw EffectArtifactStoreError.invalidReference
        }
    }

    private static func decodeIndex(_ bytes: Data, expected: ReviewedManifestReference) throws
        -> Index {
        let index = try JSONDecoder().decode(Index.self, from: bytes)
        guard index.schema == ReviewedManifestReference.schemaVersion,
              index.reference == expected, index.batches.count == expected.batchCount,
              index.protection.digest == expected.protectionDigest,
              Set(index.batches.map(\.id)).count == index.batches.count,
              Set(index.batches.map(\.name)).count == index.batches.count,
              index.batches.enumerated().allSatisfy({ ordinal, descriptor in
                  descriptor.name == batchName(expected.id, ordinal: ordinal)
                      && descriptor.bytes > 0
                      && descriptor.bytes <= maximumArtifactBytes
                      && descriptor.digest.count == SHA256.Digest.byteCount
              }) else { throw EffectArtifactStoreError.corrupt }
        return index
    }

    /// First pass validates the complete immutable set and canonical aggregate
    /// before a second pass is allowed to yield any batch to an effect.
    private static func validateStoredBatches(directory: Int32, index: Index,
                                              indexBytes: Data) throws {
        let protection = try ResourcePreflight.protectionScope(
            rootPath: index.header.canonicalRootPath,
            protectedRoots: index.protection.canonicalProtectedRoots)
        guard protection == index.protection else { throw EffectArtifactStoreError.corrupt }
        var hash = SHA256()
        hash.update(data: try ManifestEncoding.header(index.header))
        var exclusions = ManifestEncoding()
        exclusions.integer(UInt64(index.excludedRelativePaths.count))
        var priorExclusion: String?
        for path in index.excludedRelativePaths {
            _ = try DirectoryAnchor.relativeComponents(path)
            if let priorExclusion,
               !ManifestEncoding.ordered(priorExclusion, path) {
                throw EffectArtifactStoreError.corrupt
            }
            try exclusions.string(path)
            priorExclusion = path
        }
        hash.update(data: exclusions.data)
        var sequence = ManifestEncoding()
        sequence.integer(UInt64(index.batches.count))
        hash.update(data: sequence.data)
        var total = indexBytes.count
        for descriptor in index.batches {
            let bytes = try read(directory: directory, name: descriptor.name,
                                 maximumBytes: maximumArtifactBytes)
            guard bytes.count == descriptor.bytes,
                  Data(SHA256.hash(data: bytes)) == descriptor.digest else {
                throw EffectArtifactStoreError.corrupt
            }
            let batch = try JSONDecoder().decode(ReviewedBatch.self, from: bytes)
            let canonical = try ManifestEncoding.batch(batch)
            guard batch.id == descriptor.id,
                  canonical.count == batch.encodedBytes else {
                throw EffectArtifactStoreError.corrupt
            }
            let (next, overflow) = total.addingReportingOverflow(bytes.count)
            guard !overflow, next <= maximumAggregateBytes else {
                throw EffectArtifactStoreError.capacity
            }
            total = next
            hash.update(data: canonical)
        }
        guard total == index.reference.encodedBytes,
              Data(hash.finalize()) == index.reference.manifestDigest else {
            throw EffectArtifactStoreError.corrupt
        }
    }

    private static func reserve(occupancy: Occupancy, addingArtifacts: Int,
                                addingBytes: Int,
                                artifactLimit: Int = maximumArtifacts - 1,
                                byteLimit: Int = maximumAggregateBytes - maximumIndexBytes) throws {
        let (count, countOverflow) = occupancy.artifacts.addingReportingOverflow(addingArtifacts)
        let (bytes, byteOverflow) = occupancy.bytes.addingReportingOverflow(addingBytes)
        guard !countOverflow, !byteOverflow, count <= artifactLimit,
              bytes <= byteLimit else { throw EffectArtifactStoreError.capacity }
    }

    private static func occupancy(_ directory: Int32) throws -> Occupancy {
        let scanFD = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard scanFD >= 0, let stream = fdopendir(scanFD) else {
            if scanFD >= 0 { close(scanFD) }
            throw EffectArtifactStoreError.unavailable
        }
        defer { closedir(stream) }
        var count = 0, bytes = 0, staging = false
        var proofNames: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw EffectArtifactStoreError.unavailable }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(validatingCString: $0)
                }
            }
            guard let name else { throw EffectArtifactStoreError.corrupt }
            if name == "." || name == ".." { continue }
            let recognized = isPublishedName(name) || isStagingName(name)
            if !recognized {
                if name.hasPrefix("effect-") || name.hasPrefix(".effect-stage-") {
                    throw EffectArtifactStoreError.corrupt
                }
                continue
            }
            let fd = try open(directory: directory, name: name,
                              maximumBytes: maximumArtifactBytes)
            var info = stat()
            let statResult = fstat(fd, &info)
            close(fd)
            guard statResult == 0, info.st_size >= 0 else {
                throw EffectArtifactStoreError.unavailable
            }
            let (nextCount, countOverflow) = count.addingReportingOverflow(1)
            let (nextBytes, byteOverflow) = bytes.addingReportingOverflow(Int(info.st_size))
            guard !countOverflow, !byteOverflow, nextCount <= maximumArtifacts,
                  nextBytes <= maximumAggregateBytes else {
                throw EffectArtifactStoreError.capacity
            }
            count = nextCount; bytes = nextBytes
            if name.hasPrefix("effect-proof-") { proofNames.append(name) }
            staging = staging || isStagingName(name)
        }
        return Occupancy(artifacts: count, bytes: bytes, hasStaging: staging, proofNames: proofNames)
    }

    private static func publishImmutable(directory: Int32, name: String, bytes: Data,
                                         io: any JournalPOSIXIO) throws {
        guard isPublishedName(name), !bytes.isEmpty,
              bytes.count <= maximumArtifactBytes else {
            throw EffectArtifactStoreError.capacity
        }
        let temporary = ".effect-stage-" + UUID().uuidString
        let fd = openat(directory, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw EffectArtifactStoreError.unavailable }
        defer { close(fd) }
        var published = false
        do {
            try validate(fd: fd, directory: directory, name: temporary,
                         maximumBytes: maximumArtifactBytes)
            try JournalCheckedWrite.write(fd: fd, bytes: bytes, io: io)
            try validate(fd: fd, directory: directory, name: temporary,
                         maximumBytes: maximumArtifactBytes)
            try io.syncFile(fd: fd)
            guard renameatx_np(directory, temporary, directory, name,
                               UInt32(RENAME_EXCL)) == 0 else {
                throw EffectArtifactStoreError.unavailable
            }
            published = true
            try validate(fd: fd, directory: directory, name: name,
                         maximumBytes: maximumArtifactBytes)
            try io.syncDirectory(fd: directory)
        } catch {
            if published { throw EffectArtifactStoreError.publicationUncertain }
            throw (error as? EffectArtifactStoreError) ?? .unavailable
        }
    }

    private static func read(directory: Int32, name: String, maximumBytes: Int) throws -> Data {
        let fd = try open(directory: directory, name: name, maximumBytes: maximumBytes)
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= 0,
              info.st_size <= maximumBytes else { throw EffectArtifactStoreError.capacity }
        var result = Data()
        result.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let capacity = min(buffer.count, maximumBytes - result.count + 1)
            let count = Darwin.read(fd, &buffer, capacity)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw EffectArtifactStoreError.unavailable }
            if count == 0 { break }
            guard count <= maximumBytes - result.count else {
                throw EffectArtifactStoreError.capacity
            }
            result.append(contentsOf: buffer.prefix(count))
        }
        try validate(fd: fd, directory: directory, name: name, maximumBytes: maximumBytes)
        return result
    }

    private static func open(directory: Int32, name: String, maximumBytes: Int) throws -> Int32 {
        guard isPublishedName(name) || isStagingName(name) else {
            throw EffectArtifactStoreError.corrupt
        }
        let fd = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw EffectArtifactStoreError.unavailable }
        do { try validate(fd: fd, directory: directory, name: name, maximumBytes: maximumBytes) }
        catch { close(fd); throw error }
        return fd
    }

    private static func validate(fd: Int32, directory: Int32, name: String,
                                 maximumBytes: Int) throws {
        var opened = stat(), named = stat()
        guard fstat(fd, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG,
              opened.st_uid == geteuid(), opened.st_mode & 0o777 == 0o600,
              opened.st_nlink == 1, opened.st_size >= 0,
              opened.st_size <= maximumBytes,
              fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == opened.st_dev, named.st_ino == opened.st_ino else {
            throw EffectArtifactStoreError.corrupt
        }
    }

    private static func indexName(_ id: UUID) -> String {
        "effect-manifest-\(id.uuidString)-index.json"
    }
    private static func batchName(_ id: UUID, ordinal: Int) -> String {
        "effect-manifest-\(id.uuidString)-batch-\(String(format: "%04d", ordinal)).json"
    }
    private static func proofName(_ id: UUID) -> String { "effect-proof-\(id.uuidString).json" }
    private static func retirementName(_ id: UUID) -> String {
        "effect-retirement-\(id.uuidString).json"
    }
    private static func isPublishedName(_ name: String) -> Bool {
        if name.hasPrefix("effect-proof-"), name.hasSuffix(".json") {
            return name.utf8.count == 13 + 36 + 5
                && UUID(uuidString: String(name.dropFirst(13).dropLast(5))) != nil
        }
        if name.hasPrefix("effect-retirement-"), name.hasSuffix(".json") {
            return name.utf8.count == 18 + 36 + 5
                && UUID(uuidString: String(name.dropFirst(18).dropLast(5))) != nil
        }
        guard name.hasPrefix("effect-manifest-"), name.hasSuffix(".json") else { return false }
        let remainder = String(name.dropFirst(16).dropLast(5))
        guard remainder.count >= 36, let id = UUID(uuidString: String(remainder.prefix(36))),
              remainder.hasPrefix(id.uuidString) else { return false }
        let suffix = String(remainder.dropFirst(36))
        if suffix == "-index" { return true }
        guard suffix.hasPrefix("-batch-"), suffix.count == 11 else { return false }
        return Int(suffix.dropFirst(7)) != nil
    }
    private static func isStagingName(_ name: String) -> Bool {
        guard name.hasPrefix(".effect-stage-") else { return false }
        return UUID(uuidString: String(name.dropFirst(14))) != nil
    }

    private static func retirementMarkerNames(_ directory: Int32) throws -> [String] {
        let scanFD = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard scanFD >= 0, let stream = fdopendir(scanFD) else {
            if scanFD >= 0 { close(scanFD) }
            throw EffectArtifactStoreError.unavailable
        }
        defer { closedir(stream) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw EffectArtifactStoreError.unavailable }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(validatingCString: $0)
                }
            }
            guard let name else { throw EffectArtifactStoreError.corrupt }
            if name.hasPrefix("effect-retirement-") {
                guard isPublishedName(name), result.count < maximumArtifacts else {
                    throw EffectArtifactStoreError.corrupt
                }
                result.append(name)
            }
        }
        return result.sorted()
    }

    private static func readRetirementMarker(directory: Int32, name: String) throws
        -> RetirementMarker {
        let bytes = try read(directory: directory, name: name,
                             maximumBytes: maximumIndexBytes)
        let marker = try JSONDecoder().decode(RetirementMarker.self, from: bytes)
        guard marker.schema == 1, name == retirementName(marker.id),
              marker.journalName == "run-\(marker.runID.uuidString).journal",
              marker.journalBytes > 0,
              marker.artifacts.count <= maximumArtifacts,
              Set(marker.artifacts.map(\.name)).count == marker.artifacts.count,
              marker.artifacts.allSatisfy({ isPublishedName($0.name)
                  && !$0.name.hasPrefix("effect-retirement-") }) else {
            throw EffectArtifactStoreError.corrupt
        }
        return marker
    }

    private static func encodeCanonical<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
