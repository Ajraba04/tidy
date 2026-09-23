import Darwin
import Foundation
import Testing
@testable import TidyCore

@Suite("Reviewed manifest store", .serialized)
struct ReviewedManifestStoreTests {
    private func withFixture(_ body: (URL, URL, ReviewedFileResource) throws -> Void) throws {
        guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(resolved) }
        let temporary = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        let root = temporary
            .appendingPathComponent("Tidy-Manifest-Store-\(UUID())", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        let target = root.appendingPathComponent(
            "home/Library/Developer/Xcode/DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: journal,
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: target.appendingPathComponent("A/B"),
            withIntermediateDirectories: true)
        try Data("one".utf8).write(to: target.appendingPathComponent("A/one"))
        try Data("two".utf8).write(to: target.appendingPathComponent("A/B/two"))
        let reviewed = try ResourcePreflight.captureReviewedDirectory(
            at: target.path, protectedRoots: [], maxNodesPerBatch: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(journal, target, reviewed)
    }

    @Test("manifest batches publish immutably and stream only under the installation lock")
    func manifestRoundTripAndLockBoundary() throws {
        try withFixture { journalURL, _, reviewed in
            let admission = try MutationAdmissionStore(directory: journalURL)
            #expect(admission.acquire() == .ready)
            let store = ReviewedManifestStore(admission: admission)
            let reference = try store.persist(reviewed)
            #expect(reference.manifestDigest == reviewed.tree.digest)
            #expect(reference.batchCount == reviewed.tree.batches.count)
            #expect(reference.artifactCount == reference.batchCount + 1)
            #expect(reference.encodedBytes <= ReviewedManifestStore.maximumAggregateBytes)

            let header = try store.load(reference)
            #expect(header.header == reviewed.tree.header)
            #expect(header.protection == reviewed.protection)
            var paths: [String] = []
            try store.forEachBatch(reference) { batch in
                paths.append(contentsOf: batch.entries.map(\.relativePath))
            }
            #expect(paths == reviewed.tree.batches.flatMap(\.entries).map(\.relativePath))
            let names = try FileManager.default.contentsOfDirectory(atPath: journalURL.path)
            #expect(!names.contains { $0.hasPrefix(".effect-stage-") })

            admission.release()
            #expect(throws: JournalError.unavailable) { _ = try store.load(reference) }
        }
    }

    @Test("forged aggregate references and unknown effect artifacts fail closed without deletion")
    func forgedReferencesAndUnknownArtifactsRemain() throws {
        try withFixture { journalURL, _, reviewed in
            let admission = try MutationAdmissionStore(directory: journalURL)
            #expect(admission.acquire() == .ready)
            defer { admission.release() }
            let store = ReviewedManifestStore(admission: admission)
            let reference = try store.persist(reviewed)
            let forged = ReviewedManifestReference(id: reference.id,
                manifestDigest: reference.manifestDigest,
                protectionDigest: reference.protectionDigest,
                batchCount: reference.batchCount,
                artifactCount: reference.artifactCount,
                encodedBytes: ReviewedManifestStore.maximumAggregateBytes + 1)
            #expect(throws: EffectArtifactStoreError.invalidReference) {
                _ = try store.load(forged)
            }
            let unknown = journalURL.appendingPathComponent("effect-manifest-unknown")
            try Data("preserve".utf8).write(to: unknown)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: unknown.path)
            #expect(throws: EffectArtifactStoreError.corrupt) {
                _ = try store.persist(reviewed)
            }
            #expect(try Data(contentsOf: unknown) == Data("preserve".utf8))
        }
    }
}
