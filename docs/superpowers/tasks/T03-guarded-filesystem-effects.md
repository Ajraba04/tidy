# T03 — Guarded filesystem effects implementation-entry plan

> **For agentic workers:** REQUIRED SUB-SKILL: use executing-plans after independent controller review. This is a document-only entry card, not source implementation or test evidence. No source edits, tests, builds, cleanup or commits are authorized by preparation of this card.

**Goal:** Bound filesystem effects to reviewed identities and descendants, preserve protections through traversal, and report actual partial outcomes without inventing reclaimed bytes.

**Architecture:** Separate read-only anchored manifest capture, an internal descriptor-relative filesystem primitive, and the coordinator-owned production authority boundary. Scratch primitive tests prove mechanism behavior only. The first real filesystem `.M` adapter must supply an accepted ownership/exclusion contract before any production mutation is enabled.

**Tech Stack:** Native Swift 5.10+, Swift Testing, Foundation, Darwin and system CryptoKit SHA-256; macOS 14+, local TidyCore, no third-party runtime dependencies.

## Global Constraints

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

Design S01–S16 and every registry/default row apply. Performance values are proposed acceptance gates, not benchmark results. Read both binding specifications under `docs/superpowers/specs/2026-08-26-{developer-headroom-design,headroom-policy-and-adapter-contracts}.md` before implementation.

## Delivery boundaries and architectural stop

T01.A/B and T02 are dependencies, not implemented facts. Consume T02's proposed `ResourceIdentity`, `FileResourceIdentity`, `FileNodeIdentity`, `ReviewedManifestIdentity`, opaque `ConfirmedPlan`, private registered selection and single coordinator reservation. Consume its revised **synchronous policy-generation barrier**: actual leaf syscall must occur within `withCurrentPolicy(revision:body:)`, not after a returned Boolean/permit. The incoming T02 card is under review; reconcile its final names before editing source. No duplicate policy store or permissive compatibility overload.

**T03.A entry is implementable:** read-only manifest/protection checks, bounded representations, metadata comparisons, result semantics and safe internal primitive tests below. **T03.B production integration is not yet executable:** no accepted `.M` filesystem adapter currently supplies the required exclusion/ownership proof, and T02's coordinator/identity source is not present. This is a real dependency, not a reason to invent a trusted test adapter, flip `CapabilityRegistry`, create a test-only allowlist or accept an arbitrary supplied root as app authority.

Darwin `fstatat(parentFD,name,AT_SYMLINK_NOFOLLOW)` followed by `unlinkat(parentFD,name,flags)` is **not atomic inode-conditional unlink**. A concurrent writer can replace the final name between them. Keeping a directory FD open also does not prevent its rename/reparenting. Post-effect checks cannot undo an unintended unlink or prove which inode was removed. No use of `flock` owned only by Tidy excludes external writers, and rename-to-quarantine is itself an effect on a potentially replaced name, not a repair for this problem.

Therefore generic concurrently writable trees cannot meet the strict “new/replaced nodes remain intact” production contract using these syscalls alone. Useful accepted scope can be a producer-supported exclusive completed-object namespace with a lease covering name replacement, tree reparenting and content writes for the entire effect, together with fresh complete owner evidence. An adapter must establish that contract in its own `.M`, not through a Boolean argument from the UI/test. Unattended also requires its separate standing authorization and immutable/quiescent scope through effect; its initial allowlist remains empty. A manual inactivity acknowledgement does not supply exclusion. Enabling generic manual trees without such proof requires an explicit reviewed design decision; this card does not silently weaken S03/S07 or ship blanket-denial as completed useful cleanup.

The synchronous T02 policy barrier also has a latency limit: holding its lock across a filesystem syscall orders settings invalidation versus dispatch, but a blocked syscall can delay the submitting UI thread. T03.B must measure this on the accepted scope or propose a reviewed alternative with equivalent linearization. No guarantee of a hard syscall timeout or ≤100 ms UI response follows from a monotonic deadline. This remains an acceptance decision if the scope cannot supply a bounded operation.

## Owned files and sequencing

Create:

- `TidyCore/Sources/TidyCore/Execution/GuardedFileDeleter.swift`: anchored FD owner, read-only manifest, primitive and private production facade. Keep primitives internal; no public path/FD mutation entry point.
- `TidyCore/Tests/TidyCoreTests/GuardedDeletionTests.swift`: entire safe entry suite below.

Modify after dependencies land:

- `TidyCore/Sources/TidyCore/Safety/PathGuard.swift`: component-safe protected ancestor/descendant inspection; legacy display canonicalization is not authority.
- `TidyCore/Sources/TidyCore/Engine/CleanEngine.swift`: remove latent `FileManager.removeItem`/`emptyDirectory` effect bodies and `try?` swallowing. T02 internal raw execution stays unconditional denial; no return to `execute(plan:)` mutation.
- `TidyCore/Sources/TidyCore/Model/RunReport.swift`: additive typed per-target outcomes and optional observations, checked aggregation and legacy decoding.

Coordinated integration edits, **not owned by T03.A**: `ExecutionCoordinator.swift`, `ResourceIdentity.swift`, `ResourcePreflight.swift` (T02); `RunJournal`/mandatory admission store (T04); accepted adapter file (`.M` owner); results UI migration (controller assigns existing view owner). T03.B cannot be approved without an explicit allowlist for these files and complete production-bound tests. Do not implement a second authority inside CleanEngine to avoid coordinating them.

## Exact T03.A production interfaces

These declarations describe production code, not test implementations. Initializers omitted for public observation values are explicitly declared as shown; internal read-only capture values may have synthesized internal initializers but confer no execution permission.

```swift
public enum EffectStatus: String, Codable, Sendable {
    case succeeded, partial, failed, skipped, cancelled, uncertain
}
public struct ByteObservation: Codable, Equatable, Sendable {
    public let bytes: Int64?
    public let explanation: String?
    public init(bytes: Int64?, explanation: String?)
}
public struct TargetEffectOutcome: Codable, Equatable, Sendable {
    public let relativePath: String
    public let status: EffectStatus
    public let reason: String?
    public let completedRemovals: Int
    public let removedApparentBytes: ByteObservation
    public let removedAllocatedBytes: ByteObservation
    public let provenReclaimedBytes: ByteObservation
    public init(relativePath: String, status: EffectStatus, reason: String?,
                completedRemovals: Int, removedApparentBytes: ByteObservation,
                removedAllocatedBytes: ByteObservation, provenReclaimedBytes: ByteObservation)
}
public struct VolumeSpaceObservation: Codable, Equatable, Sendable {
    public let volumeID: UUID
    public let before: ByteObservation
    public let after: ByteObservation
    public var signedDelta: ByteObservation { get }
    public init(volumeID: UUID, before: ByteObservation, after: ByteObservation)
}
enum EffectAccounting {
    static func checkedSum(_ values: [ByteObservation]) -> ByteObservation
    static func aggregateStatus(_ values: [TargetEffectOutcome]) -> EffectStatus
    static func toolReclaimedBytes(exitCode: Int32,
                                   before: ByteObservation,
                                   after: ByteObservation) -> ByteObservation
}

enum ProtectedRelation: Equatable { case disjoint, insideProtected, containsProtected }
extension PathGuard {
    // Read-only, both arguments absolute standardized component paths.
    // Never resolves a failing path into authority; throws for malformed input.
    static func relation(candidate: String, protectedRoot: String) throws -> ProtectedRelation
}

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
}
final class DirectoryAnchor {
    // Read-only; owns FDs, closes in deinit; not Sendable or Codable.
    // Refuse all raw symlink components, including selected root.
    static func open(path: String) throws -> DirectoryAnchor
    func snapshot(relativePath: String) throws -> NodeSnapshot
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
    // Internal untrusted read-only value construction, never authorization.
    // Canonical header bytes are derived from the supplied immutable header.
    init(header: ReviewedManifestHeader, batches: [ReviewedBatch],
         excludedRelativePaths: [String], digest: Data)
    static func capture(anchor: DirectoryAnchor,
                        excluding: Set<String>, maxNodesPerBatch: Int = 5_000,
                        maxBytesPerBatch: Int = 8 * 1_024 * 1_024) throws -> ReviewedTree
    func entry(_ relativePath: String) -> ReviewedLeaf?
    func validateDigest(_ digest: Data) -> Bool
}
enum LeafEligibility: Equatable {
    case unchanged, missing, changed, protectedScope, differentDevice, unsupported
}
enum AnchoredFileOperations {
    static func eligibility(anchor: DirectoryAnchor, reviewed: ReviewedLeaf,
                            excludedRelativePaths: Set<String>) -> LeafEligibility
    // INTERNAL MECHANISM ONLY. Does not accept a path root, grant policy,
    // select catalog IDs, mint a lease or call the coordinator.
    // Actual syscall primitive shared by the private production facade.
    static func unlinkReviewedLeaf(anchor: DirectoryAnchor,
                                   reviewed: ReviewedLeaf,
                                   excludedRelativePaths: Set<String>) -> TargetEffectOutcome
}
enum SchedulingStop: Equatable { case cancelled, deadline, budget, unknownEstimate }
struct LeafScheduleBudget {
    init(allocatedByteLimit: Int64, leafLimit: Int,
         deadline: ContinuousClock.Instant) throws
    mutating func reserve(allocatedEstimate: Int64?, now: ContinuousClock.Instant,
                          cancelled: Bool) -> SchedulingStop?
    var reservedBytes: Int64 { get }
    var reservedLeaves: Int { get }
}
```

`DirectoryAnchor.open` is a low-level read-only mechanism, not catalog validation. The anchor retains descriptors for the opened root and ancestors; child traversal uses `openat(O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`, `fstat` and `fstatat(AT_SYMLINK_NOFOLLOW)`. Never follow a symlink to resolve an operation. Reject empty, absolute, dot/dot-dot, slash-containing individual components, NUL and unsupported name encoding; never concatenate an absolute mutation path. On macOS volume/firmlink identity capture must remain consistent with T02, not treat a lexical alias as a second authority. `/tmp` fixtures below are resolved once before entering the raw no-follow mechanism; production canonical acquisition still validates original supplied components independently.

Snapshots use checked `st_blocks * 512`, `st_size`, full nanosecond mtime/ctime, mode/type, nlink, device/inode and generation where supported. Capture errors do not become zero. Manifest records ancestors and entries in stable bytewise component order, excludes protected subtrees without walking them, and never serializes file contents. Capture detects root/parent identity churn and rejects mixed snapshots. Sibling-prefix matches are not descendants. Symlinks/special nodes are not eligible leaves, and a discovered mount is not traversed. During capture a nested mount gives `differentDevice` for the whole requested tree, not a silent incomplete “all descendants” claim. If the filesystem exposes same-device mount aliases, use mounted-volume metadata as well; absent reliable proof blocks the scope. Device-comparator and mounted-volume integration tests remain explicit acceptance gates below.

Bound every on-disk batch to ≤5,000 nodes and ≤8 MiB of actual encoded payload; API parameters can only LOWER these ceilings and must be positive. Split at boundaries; one oversized entry fails. Use schema-versioned canonical binary encoding (length-prefixed UTF-8 components, fixed-width integers in big-endian order, explicit optional tags; no native-memory struct hashing or JSON key-order assumption). SHA-256 commits schema, root volume/identity/parent chain, exclusions, batch sequence/IDs and all complete entries. `ReviewedTree` retains the immutable original header, canonical header bytes, exclusions and complete original batches, not merely a digest and relative leaf paths. `validateDigest(expected)` must recompute SHA-256 from those values, require canonical header re-encoding equals retained header bytes, verify actual encoded batch sizes and node counts, and require the recomputed digest equals both the stored digest and `expected`. Comparing `expected == digest` alone is incorrect. Any malformed/duplicate/unbounded field returns false. Internal construction of an untrusted read-only manifest value does not mint coordinator registration or authority; production execution still uses only the original private registered manifest. Batch files go in T02's private run storage with owner-only modes, no-follow opening and checked atomic writes; descriptor/manifest ownership lasts until terminal journal finalization. Validation rehashes stored original batches, not a fresh expanded walk. A second capture is a different review, even if content happens to match. Full manifest persistence and binding to `FileResourceIdentity.manifest` belong to T03.B integration, not scratch capture evidence.

`eligibility` is read-only and compares every ancestor plus leaf. Directory ancestor mtime changes due to our own completed approved leaf removals must not falsely invalidate all remaining siblings: compare ancestor identity/type/device; compare leaf metadata fully. Directory removal similarly checks original identity, exclusion ancestry and emptiness, not unchanged directory mtime. A new child may change directory metadata but never gains authority. `unlinkReviewedLeaf` repeats these checks then invokes one relative syscall (regular leaf: flags 0, reviewed empty directory: `AT_REMOVEDIR`). For a directory, `ENOTEMPTY` produces skipped/retained; never fall back to recursive removal. Failed child effects are retained individually. No retry through a freshly opened absolute path. ENOENT is skipped, not completed success; EACCES is failed with errno reason; unsupported/unreadable identity is skipped. A successful synchronous unlink is a completed primitive removal, not proven physical reclaim. FDs close on every error/exit; no persistent helper.

This primitive is intentionally internal and testable, like a filesystem client. It is not a new supported cleanup API. In T03.A, source review must find only this test file calling it; do not add a placeholder facade. In T03.B, the reviewed private production facade becomes its only production caller. Public modules cannot access it. Do not add `allowUnsafe`, trustedIDs, acceptsScratch, injected authorization callbacks, alternate registries or preflight-success hooks. Scratch exclusive ownership is a test setup fact, not a flag production can consume. The mechanism foundation may proceed without a user decision on unsupported production scope; enabling generic manual trees requires that separate decision and acceptance, not a foundation-only claim.

## Exact production authority boundary for T03.B

The coordinator holds its existing reservation and installation lock, exact selection, mandatory durable intent and original manifest. It validates fixed registry capability and adapter ownership before reaching this private method. Add it **in `ExecutionCoordinator.swift`, not as an exposed extension in another file** so all admission state remains private:

```swift
// Proposed additions inside ExecutionCoordinator, after T02 lands.
private func executeRegisteredFilesystemTarget(
    runID: UUID, registeredPlanID: UUID, selectedItemID: String,
    targetOrdinal: Int
) async -> [TargetEffectOutcome]
```

The arguments are private lookup keys, never raw identities/paths/commands supplied by a caller. The method reads the exact original `ResourceIdentity.filesystem` and stored manifest from the private registration; it cannot accept a replacement identity. It obtains and retains the accepted `.M` adapter's producer exclusion object through the effect and recovery boundary. Its concrete lease type/signature belongs to that adapter's reviewed contract; **there is no generic constructible `quiescent: true` lease in T03**. This is why T03.B remains blocked pending that contract, not a missing arbitrary permission constructor to fill in.

The private facade loops only original reviewed batches, never newly enumerated deletion candidates. Recheck policy revision, original manifest digest, catalog ownership, recognized producer instances/closed-state evidence (runtime evidence ≤5 seconds, immediately reacquired), pin/recency/user restrictions, local volume UUID, mandatory system/iCloud/provider protections and permissions before effect. Unknown shared ownership fails closed. User exclusions only union with mandatory protections; supplied `CleanEnvironment.protectedRoots` alone is insufficient to remove mandatory roots. DeleteContents keeps its root and preserves excluded descendants; DeletePath cannot remove an ancestor of a protected descendant. Unprotected reviewed siblings may proceed if separately safe; no whole-parent recursive call.

Reserve reviewed allocated estimates with checked Int64 arithmetic before each leaf; unknown estimate blocks dispatch, never treats it as zero cost. Also enforce resolved item caps (manual default 10 GiB/20 items; immutable max 100 GiB/100 items, strict explicit hard caps), bounded reviewed batches and unattended limits (default 1 GiB/5 items/60 seconds, immutable max 5 GiB/20 items/120 seconds). Leaf counting is a separate defensive node budget, not a substitution of files for product item counts. Recheck live metadata and remaining estimates immediately before each leaf. Charging reservations is conservative; a failed syscall never adds removed bytes, and a reservation need not be refunded to expand scheduling. Caps bound reviewed estimates/scheduling, not physical reclaim or atomic actual bytes.

Cancellation and `ContinuousClock` deadline prevent the next dispatch; each submitted syscall drains. After every syscall record elapsed monotonic time and overrun, update progress, preserve completed outcomes, and stop at the next boundary. Never signal user workloads, force-kill a mutation or auto-retry uncertainty. `withCurrentPolicy` must contain the actual non-suspending primitive syscall, not slow enumeration, an await or a newly queued task. A cancelled run with completed leaves is partial with cancellation reason; all remaining reviewed entries are explicitly cancelled. Journal intent before effect, then observed completion; crash between these leaves uncertainty even if the object is later missing. T04 reconciliation must prove quiescence; missing target/free lock/new PID is not proof. Do not write “succeeded” before durable completion.

## Complete safe T03.A failing test file

All files below are created beneath one unique disposable scratch root. The selected root is a sibling of `outside/sentinel`; every test with a fixture asserts the sentinel in a throwing teardown **before** cleanup, even when the test body throws. No home cache, permission change, mount, daemon, adapter registration or accepted coordinator mutation is used. Missing proposed APIs produce initial compile RED, then behavioral RED must be captured as implementations arrive. These are production helper/primitive tests, not accepted end-to-end cleanup tests.

```swift
import Darwin
import Foundation
import Testing
@testable import TidyCore

private struct DeletionScratch {
    let root: URL
    let selected: URL
    let sentinel: URL
    init() throws {
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
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
private func unknown() -> ByteObservation {
    ByteObservation(bytes: nil, explanation: "Not measured")
}

@Suite struct GuardedDeletionTests {
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
}
```

Tests using constructed observations/scheduling inputs are value-semantic tests, not actual permission/volume/daemon tests. `toolReclaimedBytes` intentionally always returns unavailable without a separate accepted physical-reclaim measurement contract; even exit 0 plus a volume delta cannot attribute all system free-space change to that command. This method must be used by report construction, not remain a disconnected test helper. Do not add measurements to the old `freedBytes` estimate on tool failure.

## Reports and compatibility (T03.A, then app integration)

Add `ItemResult.targetOutcomes: [TargetEffectOutcome]?`, `ItemResult.effectStatus: EffectStatus?`, `RunReport.volumeObservations: [VolumeSpaceObservation]?` and `RunReport.provenReclaimedBytes: ByteObservation`, using explicit custom decoding. Missing old fields decode to nil/unavailable with “Historical record did not measure this value”; never infer new observations from old `freedBytes`, `succeeded`, clamped delta or T02 placeholder zeros. Default initializer parameters preserve existing call sites while quarantined. Existing integer fields remain legacy compatibility only; new accepted effects/report UI cannot use them as measurements. The app migration must be assigned and verified before enabling an adapter.

`removedApparentBytes` and `removedAllocatedBytes` describe metadata of observed completed removals, not free space. Hardlinks require identity-aware deduplication; clones/shared extents have unknown/non-additive physical reclaim. Missing one summand makes a requested aggregate unavailable, with explanation; a separately labeled known subtotal is permitted but not a total. Checked arithmetic returns unavailable on overflow. Volume observations use the same stable volume UUID before/after and same metric; signed difference may be negative. Do not sum free-space across overlapping/aliased volumes or mix important-usage/purgeable estimates with ordinary free space.

Aggregate status precedence: any uncertain outcome => uncertain; completed removals plus any failed/skipped/cancelled => partial; all completed => succeeded; no completions with any failed => failed; otherwise cancellation => cancelled; remaining no-effect cases => skipped. Empty selection stays T02 noWork, not a succeeded target. Retained parent due to exclusion/new child must remain visible. Every failure has errno/probe reason, not just “0 freed.” Syscall completed but durable finalization failed yields uncertainty at run level without erasing already observed leaf evidence.

## Ordered entry steps and review gates

- [ ] Reconcile the final reviewed T02 types/barrier and T01 quarantine before editing source. Controller assigns no conflicting owned files. Confirm T03.A is mechanism/report work only.
- [ ] Add the complete safe test file. Run `cd TidyCore && swift test --filter GuardedDeletionTests` only after controller confirms other package jobs are idle. Expected RED is missing proposed types/APIs. Do not claim this compile failure proves behavior.
- [ ] Implement the exact read-only relations/anchors/snapshots and bounded in-memory capture. Run focused tests and preserve behavioral RED/GREEN for ancestor protection, symlink/replacement, missing/growing entries and invalid batch limits.
- [ ] Implement internal relative primitive and scheduling/accounting types. Run the same focused suite. Verify successful scratch unlink and actual hardlink preservation, excluded/new child retention, and zero proven-reclaim claims. Inspect all callers with `rg 'unlinkReviewedLeaf|removeItem|unlinkat|emptyDirectory' TidyCore/Sources TidyCore/Tests/TidyCoreTests/GuardedDeletionTests.swift`; no public arbitrary-path mutation API or old engine effect body may remain.
- [ ] Run the supplied historical-decode and partial-roundtrip tests before changing Codable, then implement the explicit compatibility decoding and rerun focused tests plus `swift test --filter RunLogTests`. The supplied literal matches the inspected existing RunReport/ItemResult schema; no new observations are inferred from its successful legacy result. App display migration remains a separate acceptance gate.
- [ ] T03.A compile-negative external client check after building TidyCore: `import TidyCore` without `@testable` must reject `DirectoryAnchor.open` and `AnchoredFileOperations.unlinkReviewedLeaf`. Verify rejection is access-control, not missing module/search flags. Do not create a placeholder coordinator facade to test an API that belongs to T03.B. Once that real private method is implemented during reviewed T03.B integration, independently verify external access to `ExecutionCoordinator.executeRegisteredFilesystemTarget` is rejected. Public coordinator token API remains the only external execution route.
- [ ] Controller schedules full safe suite and unsigned app build after host-effect audit; record exact commands/results. No source claim of x86_64/arm64/macOS 14 acceptance without those runs and device evidence. No commit is authorized here.
- [ ] Independent source/diff review before T03.B: check no trusted test capability, no arbitrary-path public mutation, all node walks no-follow, bounded actual encoded bytes, all FD lifetime/error paths, overflow handling, original manifest digest binding, mandatory/user protection union, raw CleanEngine denial and uncompleted integration gates.

## Mandatory remaining T03 acceptance tests — no silent omission

These cases are required by the brief but are **not satisfied** by the safe entry suite. Each fixture must be expanded into complete reviewed production-bound test code at the indicated entry gate before implementation of that subunit. Do not claim full T03 GREEN based on internal all-denied or scheduling-only tests.

| Required case | Safe fixture and entry dependency | Acceptance evidence |
|---|---|---|
| Production selected tree, manifest binding, no later expansion | Accepted in-scope `.M` recognizes its own disposable resource through production inventory/parser; T02 review stores real bounded manifest and issues token | Selected unchanged leaves removed through coordinator, deselected/excluded/new leaves and outside sentinel intact; tampered stored batch/digest rejects before syscall |
| Runtime ownership/policy change before a leaf | Same adapter with producer-supported exclusion lease; T02 real generation update after first leaf; effect transport controlled only at syscall boundary | Policy change orders against actual dispatch; no second leaf scheduled, fresh owner/unknown shared owner rejects; no injected authorization success |
| Cancellation/deadline/cap mid many-file batch | Same supported fixture with enough small leaves; narrow monotonic-clock/cancel observation seam, not custom eligibility | At least one real accepted completed removal then remaining leaves retained; partial outcome and reason; no dispatch after next safe boundary; measured syscall overrun recorded |
| Mount child / volume identity | First test pure production metadata comparator with different captured device/volume identities, then explicitly provisioned disposable mounted volume only with separate approved host setup | Different-device and same-device mount alias both refused before traversal; unchanged outside sentinel. No disk image creation/mount/unmount or volume mutation authorized by this card |
| Permission denied child | Narrow internal syscall client returns actual-shaped `EACCES` only at unlink/fstat for one selected relative name; real other scratch syscall succeeds, no fake policy | Exact child failure surfaced, sibling success retained as partial, failed child not counted; simulation clearly labeled. Real denied-volume/ACL/TCC case needs provisioned acceptance environment; do not chmod/chown host data or weaken permissions |
| Symlink/final-component swap during check/effect | Deterministic pre-check scratch churn plus accepted producer lease exclusion test | Pre-check changes skipped (entry suite); lease prevents in-gap replacement. Do not advertise concurrent hostile swap proof from pre-check test; absent lease remains architectural block |
| Root rename/reparent and excluded ancestor | Accepted lease covers root/ancestor namespace; controlled change before acquisition | Refuse stale parent chain, do not continue through a fresh absolute path or mutate moved excluded scope |
| Same-size content metadata changes / inode reuse | Controlled disposable replacement and mtime/ctime observations through real capture; generation when supported | Changed/replaced node skipped. Missing reliable identity evidence refuses rather than guessing; no forced reuse claim from a one-shot inode replacement |
| APFS clone physical bytes | Explicit APFS scratch fixture using native clone facility only within generated root; capability unavailable/non-APFS is recorded, not silently skipped as pass | Clone content retained after peer unlink; removed allocation is not proven reclaimed; per-volume difference remains separately labeled. Hardlink scratch test is not clone evidence |
| Failed tool with unchanged free space | T04 real accepted tool report path, failed disposable child, same-volume actual before/after probes | Failure remains failed; proven reclaimed unavailable; zero measured delta only if both real samples exactly equal; no planned estimate counted |
| Persistence/abort/FD leaks | T04 mandatory ledger fault injection at original batch write, intent write, after leaf syscall and finalization; 20 bounded scratch cycles | Missing/corrupt manifest refuses; possible unrecorded effect persists uncertain; no automatic retry; no FD growth; unfinished batches not evicted by history settings |
| UI/report historical correctness | Existing historical RunLog decoding and app results flows using real new report | Old bytes unavailable, failed/partial/skipped/cancelled/uncertain distinct; apparent/allocated/observed-volume labels separate; cap/deadline limitation beside settings |
| Physical platforms/performance | Provisioned 8 GiB Intel + Apple Silicon, oldest macOS 14 and current supported OS | Full core/app flows, syscall latency/UI cancellation and scheduling evidence; unavailable hardware explicitly leaves acceptance incomplete |

The recording/faulting syscall client is an allowed future **effect-only** seam, never a replacement policy/registry/parser/coordinator. Its protocol and full error tests must be reviewed before adding it; T03.A intentionally does not invent a fake filesystem engine to satisfy physical requirements. Host permissions, mounts, APFS privileged cases and physical hardware remain pending where safe automation is unavailable.

**Permitted handoff wording:** “T03.A card prepared/reviewed” now; after implementation evidence, “anchored mechanism and scratch tests verified; accepted adapter/coordinator integration and specified physical gates remain incomplete.” Full T03 completion requires every applicable brief case and real useful accepted cleanup, not just a manifest type, denial checks or zero mutations.
