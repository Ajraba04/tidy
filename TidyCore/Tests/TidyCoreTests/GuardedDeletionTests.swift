import CryptoKit
import Darwin
import Foundation
import Testing
@testable import TidyCore

private struct DeletionScratch {
    let root: URL
    let selected: URL
    let sentinel: URL
    init() throws {
        // Canonicalize the known existing temp base only. T02 confirmed that
        // Foundation normalization may leave the /var ancestor symlink intact.
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(canonical) }
        let temporary = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
        root = temporary.appendingPathComponent("tidy-t03-" + UUID().uuidString)
        selected = root.appendingPathComponent("selected")
        sentinel = root.appendingPathComponent("outside/sentinel")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sentinel.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data("outside must survive".utf8).write(to: sentinel)
    }
    func file(_ name: String, _ text: String = "reviewed") throws -> URL {
        let url = selected.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    func finish() throws {
        #expect(try Data(contentsOf: sentinel) == Data("outside must survive".utf8))
        // Exact generated fixture only, no wildcard or user location.
        try FileManager.default.removeItem(at: root)
    }
}
private func inScratch(_ body: (DeletionScratch) throws -> Void) throws {
    let s = try DeletionScratch()
    do { try body(s) }
    catch { try s.finish(); throw error }
    try s.finish()
}
private func observed(_ bytes: Int64) -> ByteObservation {
    ByteObservation(bytes: bytes, explanation: nil)
}

@Test("overdeep anchor paths are rejected before acquiring ancestor descriptors")
func anchorDescriptorLimitPrecedesFilesystemAccess() {
    let path = "/" + Array(repeating: "missing-component", count: 65).joined(separator: "/")
    #expect(throws: GuardedFileError.manifestLimit) {
        _ = try DirectoryAnchor.open(path: path)
    }
}
private func unknown() -> ByteObservation {
    ByteObservation(bytes: nil, explanation: "Not measured")
}

// Pure value serialization, deliberately independent of validateDigest's
// structural checks. Malformed values built here are never executed.
private func rehashedTree(_ original: ReviewedTree, header: ReviewedManifestHeader? = nil,
                          transform: (ReviewedLeaf) -> ReviewedLeaf? = { $0 }) throws -> ReviewedTree {
    let header = header ?? original.header
    let batches = try original.batches.compactMap { batch -> ReviewedBatch? in
        let entries = batch.entries.compactMap(transform)
        guard !entries.isEmpty else { return nil }
        let provisional = ReviewedBatch(id: batch.id, entries: entries, encodedBytes: 0)
        return ReviewedBatch(id: batch.id, entries: entries,
                             encodedBytes: try ManifestEncoding.batch(provisional).count)
    }
    var hash = SHA256()
    hash.update(data: try ManifestEncoding.header(header))
    var exclusions = ManifestEncoding()
    exclusions.integer(UInt64(original.excludedRelativePaths.count))
    for path in original.excludedRelativePaths { try exclusions.string(path) }
    hash.update(data: exclusions.data)
    var sequence = ManifestEncoding()
    sequence.integer(UInt64(batches.count))
    hash.update(data: sequence.data)
    for batch in batches { hash.update(data: try ManifestEncoding.batch(batch)) }
    return ReviewedTree(header: header, batches: batches,
        excludedRelativePaths: original.excludedRelativePaths, digest: Data(hash.finalize()))
}

private func changedSnapshot(_ value: NodeSnapshot, field: String) -> NodeSnapshot {
    NodeSnapshot(device: field == "device" ? value.device ^ 1 : value.device,
        inode: field == "inode" ? value.inode ^ 1 : value.inode,
        generation: value.generation,
        mode: field == "type" ? (value.mode & ~UInt32(S_IFMT)) | UInt32(S_IFREG) : value.mode,
        linkCount: value.linkCount, apparentBytes: value.apparentBytes,
        allocatedBytes: value.allocatedBytes, modifiedSeconds: value.modifiedSeconds,
        modifiedNanoseconds: field == "metadata" ? (value.modifiedNanoseconds + 1) % 1_000_000_000
            : value.modifiedNanoseconds,
        changedSeconds: value.changedSeconds, changedNanoseconds: value.changedNanoseconds)
}

private func withNestedManifest(_ body: (ReviewedTree) throws -> Void) throws {
    try inScratch { scratch in
        _ = try scratch.file("a/b/leaf")
        _ = try scratch.file("a-/leaf")
        _ = try scratch.file("keep/private")
        let anchor = try DirectoryAnchor.open(path: scratch.selected.path)
        let tree = try ReviewedTree.capture(anchor: anchor, excluding: ["keep"], maxNodesPerBatch: 1)
        // Establish the helper's real canonical digest against capture before
        // any negative assertion; stale digests cannot explain these failures.
        let rebuilt = try rehashedTree(tree)
        try #require(rebuilt.digest == tree.digest)
        try #require(rebuilt.validateDigest(tree.digest))
        try body(tree)
        #expect(try String(contentsOf: scratch.selected.appendingPathComponent("a/b/leaf"),
                           encoding: .utf8) == "reviewed")
    }
}

@Suite struct GuardedDeletionTests {
    @Test func correctlyHashedNonDirectoryHeaderAncestorsAreRejected() throws {
        try withNestedManifest { tree in
            for index in tree.header.rootParentChain.indices {
                var parents = tree.header.rootParentChain
                parents[index] = changedSnapshot(parents[index], field: "type")
                let header = ReviewedManifestHeader(schemaVersion: tree.header.schemaVersion,
                    rootVolumeID: tree.header.rootVolumeID, canonicalRootPath: tree.header.canonicalRootPath,
                    rootSnapshot: tree.header.rootSnapshot, rootParentChain: parents)
                let malformed = try rehashedTree(tree, header: header) { entry in
                    var chain = entry.parentChain
                    chain[index] = parents[index]
                    return ReviewedLeaf(relativePath: entry.relativePath, parentChain: chain, snapshot: entry.snapshot)
                }
                let accepted = malformed.validateDigest(malformed.digest)
                #expect(!accepted)
            }
        }
    }

    @Test(arguments: ["type", "device", "inode", "metadata"], ["a", "a/b"])
    func correctlyHashedInvalidNestedParentsAreRejected(field: String, parentPath: String) throws {
        try withNestedManifest { tree in
            let parent = try #require(tree.entry(parentPath))
            let changed = changedSnapshot(parent.snapshot, field: field)
            let parentIndex = tree.header.rootParentChain.count + parentPath.split(separator: "/").count
            let malformed = try rehashedTree(tree) { entry in
                var chain = entry.parentChain
                if entry.relativePath.hasPrefix(parentPath + "/") { chain[parentIndex] = changed }
                // A regular-file parent is consistently recorded as such, so
                // rejecting it requires directory structure, not digest mismatch.
                let snapshot = field == "type" && entry.relativePath == parentPath ? changed : entry.snapshot
                return ReviewedLeaf(relativePath: entry.relativePath, parentChain: chain, snapshot: snapshot)
            }
            #expect(malformed.digest != tree.digest)
            let accepted = malformed.validateDigest(malformed.digest)
            #expect(!accepted)
        }
    }

    @Test(arguments: ["a", "a/b"])
    func correctlyHashedMissingReviewedParentIsRejected(parentPath: String) throws {
        try withNestedManifest { tree in
            let malformed = try rehashedTree(tree) { $0.relativePath == parentPath ? nil : $0 }
            #expect(malformed.entry(parentPath) == nil)
            #expect(malformed.entry("a/b/leaf") != nil)
            let accepted = malformed.validateDigest(malformed.digest)
            #expect(!accepted)
        }
    }

    @Test func nestedCrossBatchManifestAllowsRootAncestorVolumeTransitions() throws {
        try withNestedManifest { tree in
            #expect(tree.batches.count == 5)
            #expect(tree.batches.flatMap(\.entries).map(\.relativePath) == ["a", "a/b", "a/b/leaf", "a-", "a-/leaf"])
            #expect(tree.validateDigest(tree.digest))
            // Pure metadata control, not a mounted-volume integration test.
            var parents = tree.header.rootParentChain
            parents[0] = changedSnapshot(tree.header.rootSnapshot, field: "device")
            let header = ReviewedManifestHeader(schemaVersion: tree.header.schemaVersion,
                rootVolumeID: tree.header.rootVolumeID, canonicalRootPath: tree.header.canonicalRootPath,
                rootSnapshot: tree.header.rootSnapshot, rootParentChain: parents)
            let transitioned = try rehashedTree(tree, header: header) { entry in
                var chain = entry.parentChain
                chain[0] = parents[0]
                return ReviewedLeaf(relativePath: entry.relativePath, parentChain: chain, snapshot: entry.snapshot)
            }
            #expect(transitioned.validateDigest(transitioned.digest))
        }
    }

    @Test func unavailableBytesRemainUnavailable() {
        let value = ByteObservation(bytes: nil, explanation: "Permission denied")
        #expect(value.bytes == nil)
        #expect(value.explanation != nil)
    }

    @Test func componentRelationsProtectAncestorsNotPrefixSiblings() throws {
        #expect(try PathGuard.relation(candidate: "/a/cache", protectedRoot: "/a/cache/keep")
                == .containsProtected)
        #expect(try PathGuard.relation(candidate: "/a/cache/keep/x", protectedRoot: "/a/cache/keep")
                == .insideProtected)
        #expect(try PathGuard.relation(candidate: "/a/cache-old", protectedRoot: "/a/cache")
                == .disjoint)
    }

    @Test func excludedDescendantNeverEntersManifestOrRemoval() throws {
        try inScratch { s in
            let kept = try s.file("keep/private", "keep this")
            let removed = try s.file("remove")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: a, excluding: ["keep"])
            #expect(tree.entry("keep") == nil)
            #expect(tree.entry("keep/private") == nil)
            let entry = try #require(tree.entry("remove"))
            let result = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: entry, excludedRelativePaths: ["keep"])
            #expect(result.status == .succeeded)
            #expect(result.completedRemovals == 1)
            #expect(result.provenReclaimedBytes.bytes == nil)
            #expect(!FileManager.default.fileExists(atPath: removed.path))
            #expect(try String(contentsOf: kept, encoding: .utf8) == "keep this")
        }
    }

    @Test func addedExclusionStopsPreviouslyReviewedLeaf() throws {
        try inScratch { s in
            let file = try s.file("keep")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let entry = try #require(ReviewedTree.capture(anchor: a, excluding: []).entry("keep"))
            #expect(AnchoredFileOperations.eligibility(anchor: a, reviewed: entry,
                    excludedRelativePaths: ["keep"]) == .protectedScope)
            let result = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: entry, excludedRelativePaths: ["keep"])
            #expect(result.status == .skipped)
            #expect(result.completedRemovals == 0)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func reviewedSiblingsThenEmptyDirectoryAreRemoved() throws {
        try inScratch { s in
            let first = try s.file("folder/first", "first")
            let second = try s.file("folder/second", "second")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: a, excluding: [])
            let firstEntry = try #require(tree.entry("folder/first"))
            let secondEntry = try #require(tree.entry("folder/second"))
            let directoryEntry = try #require(tree.entry("folder"))
            let firstResult = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: firstEntry, excludedRelativePaths: [])
            #expect(firstResult.status == .succeeded)
            #expect(firstResult.completedRemovals == 1)
            // The first unlink changes the common parent's metadata. The
            // second leaf must still match its identity and own metadata.
            let secondResult = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: secondEntry, excludedRelativePaths: [])
            #expect(secondResult.status == .succeeded)
            #expect(secondResult.completedRemovals == 1)
            let directoryResult = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: directoryEntry, excludedRelativePaths: [])
            #expect(directoryResult.status == .succeeded)
            #expect(directoryResult.completedRemovals == 1)
            #expect(!FileManager.default.fileExists(atPath: first.path))
            #expect(!FileManager.default.fileExists(atPath: second.path))
            #expect(!FileManager.default.fileExists(atPath: s.selected.appendingPathComponent("folder").path))
        }
    }

    @Test func reviewedParentWithExcludedDescendantIsRetained() throws {
        try inScratch { s in
            let removed = try s.file("folder/remove")
            let kept = try s.file("folder/keep/private", "preserve excluded child")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: a, excluding: ["folder/keep"])
            let leaf = try #require(tree.entry("folder/remove"))
            let directory = try #require(tree.entry("folder"))
            #expect(tree.entry("folder/keep/private") == nil)
            #expect(AnchoredFileOperations.unlinkReviewedLeaf(anchor: a, reviewed: leaf,
                    excludedRelativePaths: ["folder/keep"]).status == .succeeded)
            let retained = AnchoredFileOperations.unlinkReviewedLeaf(anchor: a, reviewed: directory,
                excludedRelativePaths: ["folder/keep"])
            #expect(retained.status == .skipped)
            #expect(retained.completedRemovals == 0)
            #expect(!FileManager.default.fileExists(atPath: removed.path))
            #expect(FileManager.default.fileExists(atPath: s.selected.appendingPathComponent("folder").path))
            #expect(try String(contentsOf: kept, encoding: .utf8) == "preserve excluded child")
        }
    }

    @Test func symlinkSwapIsRejectedBeforeEffect() throws {
        try inScratch { s in
            let victim = try s.file("victim")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let entry = try #require(ReviewedTree.capture(anchor: a, excluding: []).entry("victim"))
            try FileManager.default.removeItem(at: victim)
            try FileManager.default.createSymbolicLink(at: victim, withDestinationURL: s.sentinel)
            #expect(AnchoredFileOperations.eligibility(anchor: a, reviewed: entry,
                    excludedRelativePaths: []) != .unchanged)
            let result = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: entry, excludedRelativePaths: [])
            #expect(result.status == .skipped)
            #expect(result.completedRemovals == 0)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: victim.path)
                    == s.sentinel.path)
        }
    }

    @Test func replacedDirectoryIdentityDoesNotAuthorizeNewChild() throws {
        try inScratch { s in
            _ = try s.file("directory/leaf")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let entry = try #require(ReviewedTree.capture(anchor: a, excluding: []).entry("directory/leaf"))
            try FileManager.default.moveItem(at: s.selected.appendingPathComponent("directory"),
                                              to: s.selected.appendingPathComponent("old-directory"))
            let replacement = try s.file("directory/leaf", "new identity")
            let result = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: entry, excludedRelativePaths: [])
            #expect(result.status == .skipped)
            #expect(result.completedRemovals == 0)
            #expect(try String(contentsOf: replacement, encoding: .utf8) == "new identity")
            #expect(FileManager.default.fileExists(atPath: s.selected.appendingPathComponent("old-directory/leaf").path))
        }
    }

    @Test func missingTargetIsNotSuccessfulRemoval() throws {
        try inScratch { s in
            let file = try s.file("gone")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let entry = try #require(ReviewedTree.capture(anchor: a, excluding: []).entry("gone"))
            try FileManager.default.removeItem(at: file)
            let result = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: entry, excludedRelativePaths: [])
            #expect(result.status == .skipped)
            #expect(result.completedRemovals == 0)
            #expect(result.provenReclaimedBytes.bytes == nil)
        }
    }

    @Test func growthIsSkippedAndNewChildIsNotAuthorized() throws {
        try inScratch { s in
            let file = try s.file("folder/reviewed", "a")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: a, excluding: [])
            let entry = try #require(tree.entry("folder/reviewed"))
            let directory = try #require(tree.entry("folder"))
            try Data("much larger replacement contents".utf8).write(to: file)
            let newFile = try s.file("folder/new", "unreviewed")
            #expect(tree.entry("folder/new") == nil)
            #expect(AnchoredFileOperations.unlinkReviewedLeaf(anchor: a, reviewed: entry,
                    excludedRelativePaths: []).status == .skipped)
            #expect(AnchoredFileOperations.unlinkReviewedLeaf(anchor: a, reviewed: directory,
                    excludedRelativePaths: []).status == .skipped)
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(try String(contentsOf: newFile, encoding: .utf8) == "unreviewed")
        }
    }

    @Test func hardlinkRemovalNeverClaimsSharedStorageReclaimed() throws {
        try inScratch { s in
            let original = try s.file("original", String(repeating: "x", count: 8192))
            let alias = s.root.appendingPathComponent("outside/alias")
            try FileManager.default.linkItem(at: original, to: alias)
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let entry = try #require(ReviewedTree.capture(anchor: a, excluding: []).entry("original"))
            #expect(entry.snapshot.linkCount >= 2)
            let result = AnchoredFileOperations.unlinkReviewedLeaf(
                anchor: a, reviewed: entry, excludedRelativePaths: [])
            #expect(result.status == .succeeded)
            #expect(result.completedRemovals == 1)
            #expect(result.provenReclaimedBytes.bytes == nil)
            #expect(try Data(contentsOf: alias).count == 8192)
        }
    }

    @Test func boundedBatchesAndDigestDoNotExpandReview() throws {
        try inScratch { s in
            for index in 0..<7 { _ = try s.file("file-\(index)") }
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: a, excluding: [], maxNodesPerBatch: 3)
            #expect(tree.batches.count == 3)
            #expect(tree.batches.allSatisfy { $0.entries.count <= 3 && $0.encodedBytes <= 8 * 1024 * 1024 })
            #expect(tree.batches.flatMap(\.entries).count == 7)
            #expect(tree.validateDigest(tree.digest))
            #expect(!tree.validateDigest(Data(repeating: 0, count: 32)))
            _ = try s.file("new")
            #expect(tree.entry("new") == nil)
            #expect(throws: GuardedFileError.manifestLimit) {
                _ = try ReviewedTree.capture(anchor: a, excluding: [], maxNodesPerBatch: 5_001)
            }
            #expect(throws: GuardedFileError.manifestLimit) {
                _ = try ReviewedTree.capture(anchor: a, excluding: [], maxBytesPerBatch: 1)
            }
        }
    }

    @Test func rawSymlinkRootAndTraversalComponentsAreRejected() throws {
        try inScratch { s in
            let alias = s.root.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: s.selected)
            #expect(throws: GuardedFileError.symbolicLink) { _ = try DirectoryAnchor.open(path: alias.path) }
            let a = try DirectoryAnchor.open(path: s.selected.path)
            #expect(throws: GuardedFileError.invalidComponent) { _ = try a.snapshot(relativePath: "../outside/sentinel") }
            #expect(throws: GuardedFileError.invalidComponent) { _ = try a.snapshot(relativePath: s.sentinel.path) }
        }
    }

    @Test func digestRecomputesEntriesHeaderAndExclusions() throws {
        try inScratch { s in
            _ = try s.file("reviewed")
            let a = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: a, excluding: [])
            let batch = try #require(tree.batches.first)
            let entry = try #require(batch.entries.first)
            #expect(tree.validateDigest(tree.digest))

            // Same-length relative name isolates content hashing from the
            // independent encoded-length guard. No forged tree is executed.
            let changedEntry = ReviewedLeaf(relativePath: "replaced", parentChain: entry.parentChain,
                                             snapshot: entry.snapshot)
            let changedBatch = ReviewedBatch(id: batch.id, entries: [changedEntry],
                                               encodedBytes: batch.encodedBytes)
            let changedEntries = ReviewedTree(header: tree.header, batches: [changedBatch],
                excludedRelativePaths: tree.excludedRelativePaths, digest: tree.digest)
            #expect(!changedEntries.validateDigest(tree.digest))

            let header = tree.header
            let otherVolume = header.rootVolumeID == UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                ? UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
                : UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            let changedHeader = ReviewedManifestHeader(schemaVersion: header.schemaVersion,
                rootVolumeID: otherVolume, canonicalRootPath: header.canonicalRootPath,
                rootSnapshot: header.rootSnapshot, rootParentChain: header.rootParentChain)
            let changedVolume = ReviewedTree(header: changedHeader, batches: tree.batches,
                excludedRelativePaths: tree.excludedRelativePaths, digest: tree.digest)
            #expect(!changedVolume.validateDigest(tree.digest))

            let changedExclusions = ReviewedTree(header: header, batches: tree.batches,
                excludedRelativePaths: ["reviewed"], digest: tree.digest)
            #expect(!changedExclusions.validateDigest(tree.digest))
            #expect(FileManager.default.fileExists(atPath: s.selected.appendingPathComponent("reviewed").path))
        }
    }

    @Test func schedulingStopsAtEachLeafWithoutRefundOrOverflow() throws {
        let now = ContinuousClock.now
        var budget = try LeafScheduleBudget(allocatedByteLimit: 10, leafLimit: 3,
                                             deadline: now.advanced(by: .seconds(60)))
        #expect(budget.reserve(allocatedEstimate: 6, now: now, cancelled: false) == nil)
        #expect(budget.reserve(allocatedEstimate: 5, now: now, cancelled: false) == .budget)
        #expect(budget.reservedBytes == 6)
        #expect(budget.reserve(allocatedEstimate: nil, now: now, cancelled: false) == .unknownEstimate)
        #expect(budget.reserve(allocatedEstimate: 1, now: now, cancelled: true) == .cancelled)
        #expect(budget.reserve(allocatedEstimate: 1, now: now.advanced(by: .seconds(60)), cancelled: false) == .deadline)
        #expect(budget.reservedLeaves == 1)
        #expect(budget.reserve(allocatedEstimate: Int64.max, now: now, cancelled: false) == .budget)
        #expect(budget.reservedBytes == 6)
    }

    @Test("review capture enforces cancellation node depth name and work bounds before expansion")
    func captureBudgetRejectsBeforeUnboundedTraversal() throws {
        try inScratch { scratch in
            _ = try scratch.file("a")
            _ = try scratch.file("b")
            _ = try scratch.file("c")
            let token = EffectCancellationToken()
            let limits = ManifestCaptureLimits(maximumNodes: 2,
                maximumNameBytes: 64, maximumDepth: 4, maximumWorkUnits: 16,
                deadline: ContinuousClock.now.advanced(by: .seconds(1)),
                cancellation: token)
            #expect(throws: GuardedFileError.manifestLimit) {
                _ = try ResourcePreflight.captureReviewedDirectory(at: scratch.selected.path,
                    protectedRoots: [], limits: limits)
            }
            token.cancel()
            #expect(throws: GuardedFileError.manifestLimit) {
                _ = try ResourcePreflight.captureReviewedDirectory(at: scratch.selected.path,
                    protectedRoots: [], limits: .production(cancellation: token))
            }
            #expect(try Data(contentsOf: scratch.selected.appendingPathComponent("a"))
                == Data("reviewed".utf8))
        }
    }

    @Test func accountingDoesNotTurnFailureExitOrMissingMeasurementIntoSuccess() {
        #expect(EffectAccounting.checkedSum([observed(Int64.max), observed(1)]).bytes == nil)
        #expect(EffectAccounting.checkedSum([observed(10), unknown()]).bytes == nil)
        #expect(EffectAccounting.toolReclaimedBytes(exitCode: 1, before: observed(100), after: observed(100)).bytes == nil)
        #expect(EffectAccounting.toolReclaimedBytes(exitCode: 0, before: observed(100), after: observed(200)).bytes == nil)
        let volume = VolumeSpaceObservation(volumeID: UUID(), before: observed(200), after: observed(100))
        #expect(volume.signedDelta.bytes == -100)
        #expect(VolumeSpaceObservation(volumeID: UUID(), before: unknown(), after: observed(100)).signedDelta.bytes == nil)
        let success = TargetEffectOutcome(relativePath: "a", status: .succeeded, reason: nil,
            completedRemovals: 1, removedApparentBytes: observed(1), removedAllocatedBytes: observed(512),
            provenReclaimedBytes: unknown())
        let failure = TargetEffectOutcome(relativePath: "b", status: .failed, reason: "Permission denied",
            completedRemovals: 0, removedApparentBytes: unknown(), removedAllocatedBytes: unknown(),
            provenReclaimedBytes: unknown())
        #expect(EffectAccounting.aggregateStatus([success, failure]) == .partial)
        #expect(EffectAccounting.aggregateStatus([failure]) == .failed)
    }

    @Test func historicalRecordRemainsReadableWithoutInventedObservations() throws {
        // Actual legacy RunReport/ItemResult Codable keys inspected in source;
        // dates use the existing default JSONEncoder reference-date strategy.
        let bytes = Data(#"{"tier":"safe","results":[{"id":"x","title":"X","freedBytes":100,"reclaimedMemoryBytes":0,"succeeded":true}],"startedAt":721692800,"finishedAt":721692810,"freeSpaceBeforeBytes":1000,"freeSpaceAfterBytes":1100}"#.utf8)
        let report = try JSONDecoder().decode(RunReport.self, from: bytes)
        #expect(report.results.count == 1)
        #expect(report.results[0].freedBytes == 100) // compatibility value only
        #expect(report.results[0].targetOutcomes == nil)
        #expect(report.results[0].effectStatus == nil)
        #expect(report.volumeObservations == nil)
        #expect(report.provenReclaimedBytes.bytes == nil)
        #expect(report.provenReclaimedBytes.explanation == "Historical record did not measure this value")
        let decodedAgain = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
        #expect(decodedAgain.provenReclaimedBytes == report.provenReclaimedBytes)
    }

    @Test func partialTargetRoundTripsWithoutLosingUnavailableBytes() throws {
        let target = TargetEffectOutcome(relativePath: "folder", status: .partial,
            reason: "One child denied", completedRemovals: 1,
            removedApparentBytes: observed(8), removedAllocatedBytes: observed(512),
            provenReclaimedBytes: unknown())
        let decoded = try JSONDecoder().decode(TargetEffectOutcome.self,
                                               from: JSONEncoder().encode(target))
        #expect(decoded == target)
        #expect(decoded.provenReclaimedBytes.bytes == nil)
    }

    @Test func directoryOutcomeUsesMetadataAtRemovalNotBeforeChildrenWereRemoved() throws {
        try inScratch { s in
            _ = try s.file("folder/child")
            let anchor = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: anchor, excluding: [])
            let child = try #require(tree.entry("folder/child"))
            let folder = try #require(tree.entry("folder"))
            #expect(AnchoredFileOperations.unlinkReviewedLeaf(anchor: anchor, reviewed: child,
                excludedRelativePaths: []).status == .succeeded)
            let empty = try anchor.snapshot(relativePath: "folder")
            let result = AnchoredFileOperations.unlinkReviewedLeaf(anchor: anchor, reviewed: folder,
                excludedRelativePaths: [])
            #expect(result.status == .succeeded)
            #expect(result.removedApparentBytes.bytes == empty.apparentBytes)
            #expect(result.removedAllocatedBytes.bytes == empty.allocatedBytes)
        }
    }

    @Test func movedRootCannotUseRetainedDescriptorToRemoveMovedLeaf() throws {
        try inScratch { s in
            _ = try s.file("reviewed")
            let anchor = try DirectoryAnchor.open(path: s.selected.path)
            let leaf = try #require(ReviewedTree.capture(anchor: anchor, excluding: []).entry("reviewed"))
            let moved = s.root.appendingPathComponent("moved-selected")
            try FileManager.default.moveItem(at: s.selected, to: moved)
            let replacement = try s.file("reviewed", "replacement")
            #expect(AnchoredFileOperations.eligibility(anchor: anchor, reviewed: leaf,
                excludedRelativePaths: []) == .changed)
            #expect(AnchoredFileOperations.unlinkReviewedLeaf(anchor: anchor, reviewed: leaf,
                excludedRelativePaths: []).completedRemovals == 0)
            #expect(try String(contentsOf: replacement, encoding: .utf8) == "replacement")
            #expect(try String(contentsOf: moved.appendingPathComponent("reviewed"), encoding: .utf8) == "reviewed")
        }
    }

    @Test func invalidInputsAndMalformedBatchSizesFailClosed() throws {
        #expect(throws: GuardedFileError.invalidComponent) {
            try PathGuard.relation(candidate: "/a/../b", protectedRoot: "/a")
        }
        #expect(throws: GuardedFileError.invalidBudget) {
            _ = try LeafScheduleBudget(allocatedByteLimit: -1, leafLimit: 1, deadline: .now)
        }
        try inScratch { s in
            _ = try s.file("reviewed")
            let anchor = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: anchor, excluding: [])
            let batch = try #require(tree.batches.first)
            let wrongSize = ReviewedBatch(id: batch.id, entries: batch.entries, encodedBytes: 0)
            let tampered = ReviewedTree(header: tree.header, batches: [wrongSize],
                excludedRelativePaths: [], digest: tree.digest)
            #expect(!tampered.validateDigest(tree.digest))
            #expect(throws: GuardedFileError.invalidComponent) {
                _ = try ReviewedTree.capture(anchor: anchor, excluding: ["../outside"])
            }
            #expect(throws: GuardedFileError.manifestLimit) {
                _ = try ReviewedTree.capture(anchor: anchor, excluding: [], maxNodesPerBatch: 0)
            }
            #expect(throws: GuardedFileError.manifestLimit) {
                _ = try ReviewedTree.capture(anchor: anchor, excluding: [], maxBytesPerBatch: 8 * 1024 * 1024 + 1)
            }
        }
    }

    @Test func reportConstructionDoesNotAttributeLegacyToolEstimates() {
        let report = RunReport(tier: .safe,
            results: [ItemResult(id: "tool", title: "Tool", freedBytes: 4096, succeeded: false)],
            startedAt: Date(), finishedAt: Date(), freeSpaceBeforeBytes: 100, freeSpaceAfterBytes: 100,
            toolExitCode: 1)
        #expect(report.provenReclaimedBytes.bytes == nil)
        #expect(report.provenReclaimedBytes.explanation == "Failed tool did not establish physical reclaim")
    }

    @Test func genericReportIsNeutralAndActualToolCodeIsNotInferredFromLegacySuccess() {
        let neutral = RunReport(tier: .safe, results: [], startedAt: Date(), finishedAt: Date(),
            freeSpaceBeforeBytes: 0, freeSpaceAfterBytes: 0, disposition: .noWork)
        #expect(neutral.provenReclaimedBytes.bytes == nil)
        #expect(neutral.provenReclaimedBytes.explanation == "Physical reclaim was not measured")
        let tool = RunReport(tier: .safe,
            results: [ItemResult(id: "tool", title: "Tool", freedBytes: 4096, succeeded: false)],
            startedAt: Date(), finishedAt: Date(), freeSpaceBeforeBytes: 100, freeSpaceAfterBytes: 200,
            toolExitCode: 0)
        #expect(tool.provenReclaimedBytes.bytes == nil)
        #expect(tool.provenReclaimedBytes.explanation == "Tool exit and volume delta do not prove attributable physical reclaim")
    }

    @Test func missingLegacyMemoryDoesNotSilentlyBecomeMeasuredZero() throws {
        let bytes = Data(#"{"id":"x","title":"X","freedBytes":100,"succeeded":true}"#.utf8)
        let item = try JSONDecoder().decode(ItemResult.self, from: bytes)
        #expect(item.measuredReclaimedMemoryBytes == nil)
        let report = RunReport(tier: .safe, results: [item],
            startedAt: Date(timeIntervalSince1970: 100), finishedAt: Date(timeIntervalSince1970: 101),
            freeSpaceBeforeBytes: 1000, freeSpaceAfterBytes: 1000)
        #expect(report.measuredTotalReclaimedMemoryBytes == nil)
        let roundTrip = try JSONDecoder().decode(RunReport.self, from: JSONEncoder().encode(report))
        #expect(roundTrip.results[0].measuredReclaimedMemoryBytes == nil)
        #expect(roundTrip.measuredTotalReclaimedMemoryBytes == nil)
    }

    @Test func componentOrderedTraversalAndSiblingPrefixesAgreeWithDigest() throws {
        try inScratch { s in
            _ = try s.file("a/leaf")
            _ = try s.file("a-")
            let anchor = try DirectoryAnchor.open(path: s.selected.path)
            let tree = try ReviewedTree.capture(anchor: anchor, excluding: [], maxNodesPerBatch: 1)
            #expect(tree.batches.flatMap(\.entries).map(\.relativePath) == ["a", "a/leaf", "a-"])
            #expect(tree.validateDigest(tree.digest))
            let sibling = try #require(tree.entry("a-"))
            #expect(AnchoredFileOperations.unlinkReviewedLeaf(anchor: anchor, reviewed: sibling,
                excludedRelativePaths: ["a"]).status == .succeeded)
            #expect(FileManager.default.fileExists(atPath: s.selected.appendingPathComponent("a/leaf").path))
        }
    }
}
