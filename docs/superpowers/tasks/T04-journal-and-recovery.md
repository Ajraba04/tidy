# T04 — Journal and process recovery implementation-entry plan

**FIFO ownership correction:** [Shared test-support amendment](2026-08-26-shared-fifo-test-support-amendment.md) permits the narrowly scoped helper extraction; all safety and behavioral assertions remain binding.

> **For agentic workers:** REQUIRED SUB-SKILL: use executing-plans after independent review and assignment of the specific unit below. Preparing this card authorizes documentation only: no source edits, tests, builds, host cleanup, restart, process signals or commits. Interfaces below are PROPOSED, not implemented evidence.

**Goal:** Persist intent before effects, bound subprocess resources, and keep every mutation blocked after ambiguous interruption until supported positive reconciliation proves quiescence.

**Architecture:** Extend T02's single mandatory admission store with a durable journal; do not create a competing lock or recovery authority. Separate persistence/state-machine foundation, real disposable subprocess mechanism tests, and accepted-adapter/coordinator integration. A process exit, missing PID, free lock, missing target or fresh review never supplies generic completion evidence.

**Tech Stack:** Native Swift/SwiftUI, macOS 14+, Swift Testing, Foundation, Dispatch, Darwin and system CryptoKit; local TidyCore; zero third-party runtime dependencies.

## Global Constraints

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

All design S01–S16 and every policy/default row in `docs/superpowers/specs/2026-08-26-developer-headroom-design.md` and `2026-08-26-headroom-policy-and-adapter-contracts.md` are binding. In particular: history 30 days/10 MiB, configurable 1–90 days/1–50 MiB, reserve 1 MiB for the unfinished ledger; history off never disables safety persistence. Aggregate Tidy command jobs ≤2 including the single mutator; Eco read-only limit 1, configurable 1–2. Retain ≤1 MiB per output stream. Runtime ownership evidence expires in 5 seconds and is reacquired immediately before effect. Launch recovery permits one bounded probe, or explicit Retry, never an idle polling loop. UI cancellation ≤100 ms is a proposed measured gate, not an achieved fact. Monotonic scheduling deadlines cannot force-stop a mutating syscall.

## Readiness and delivery boundaries

**Budget decision resolved; source entry still gated:** the user approved `history.maxMiB` (1…50/default 10) for optional completed reports only, with mandatory recovery separately bounded and never history-evicted. `T04-A-approved-budget-contract.md` controls exact accounting, eight reserved active-diagnostic slots, disabled-history API, completion/pruning and replacement/additional tests. The earlier inclusive equation/tests in `.superpowers/sdd/T04.A-entry-proposal.md` are superseded. Corrections 2–3 remain accepted at proposal level. Controller and independent review must approve this supplement and assign the actual source BASE before T04.A implementation. T03.B/T04.C also require numeric aggregate manifest/proof/staging admission and terminal-growth tests before positive effects; T04.D must account all optional writers under one shared history limit.

Read `.superpowers/sdd/T04-brief.md` and the final independently reviewed T02/T03 cards before execution. T02 foundation source through `10616b3` is independently approved, including the FIFO admission reader correction: `MutationAdmissionStore`, `PendingEffectIntent`, the synchronous `PolicyInvalidationBarrier`, schema-1 envelope and stable installation lock are real dependencies to extend rather than recreate. T03.A's internal mechanism foundation through `ec9dbc5` is independently approved; its `EffectStatus`/`TargetEffectOutcome` are real dependencies, but production integration remains gated. T01 legacy quarantine remains mandatory.

| Unit | Entry boundary | What passing means |
|---|---|---|
| T04.A | T02 admission store accepted, approved-budget supplement independently reviewed, actual BASE and file ownership assigned | Durable state/replay/fault behavior tested using real scratch persistence; simulated records are expressly not process recovery proof |
| T04.B | T04.A plus reviewed low-level launcher design | Real compiled disposable children, oversized output, inherited pipes, surviving work and abandonment windows exercise production mechanisms; no cleanup authority is granted |
| T04.C | First existing-scope `.M` with supported start/recovery protocol; separate complete integration test card reviewed | Real coordinator token→accepted effect→app-process crash→relaunch→positive adapter reconciliation; useful cleanup and S16 acceptance |
| T04.D | T03 report schema and assigned app integration owner | Typed results, graceful verified-instance app quit integration and compatibility; restart/purge remain separately quarantined without accepted contracts |

T04.A/B are bounded foundation units, not full T04 GREEN. This card gives complete safe entry tests for A/B. C/D cannot be entered on this card alone: their concrete adapter, app-host crash harness and UI test entry must be assigned and fully specified before implementation. This is an explicit dependency boundary, not permission to replace acceptance with fake ledger IDs or blanket-denial tests.

Two architectural blockers require review before C:

1. T02 requires the actual irreversible handshake release inside `withCurrentPolicy(revision:body:)`, synchronously while locked. Slow probes, journal fsync, waiting for child readiness and lifetime drainage belong outside that lock. A nonblocking one-byte release into a dedicated empty pipe is a candidate start linearization point for a cooperating child; its EAGAIN/EPIPE/error paths must not fall back to deferred release. O_NONBLOCK is not a universal wall-clock guarantee: prove the exact pipe behavior/identity/ownership and measure latency on supported OS versions. An arbitrary CLI does not implement that protocol. A transient owned launcher may eventually provide it, but requires an explicit packaged/signed launcher contract and actual post-exec identity/reconciliation tests; this card does not quietly introduce a persistent helper or enable arbitrary tools. `posix_spawn` followed by SIGSTOP is too late: effects may already have begun.
2. T03 holds the same lock across actual `unlinkat`; an uninterruptible syscall can block synchronous UI policy invalidation. Neither moving an earlier Boolean check outside the lock nor calling a queued Task fixes the race. Accepted bounded scope or a separately reviewed equivalent linearization redesign, with real latency evidence, is required. Do not claim hard 100 ms response from scratch fast-path tests or hold the lock through an entire asynchronous mutation.

The **dispatch principle is accepted**: submission of one exact already-prepared operation to an already-owned waiting worker may be the irreversible start point, after durable intent/identity persistence, allowing that one dispatched operation to drain outside the policy lock and prohibiting later dispatch after invalidation. This is not a returned caller permit. The concrete helper/handshake protocol and universal boundedness are **not approved**. A transient unprivileged filesystem worker is a material architecture option requiring reviewed scope, namespace/lease lifetime, descriptor transfer, crash identity and packaging decisions; it is not introduced by A/B. The original scheduling contract permits syscall overruns and does not demand impossible hard OS timing guarantees. Primary reference notes are in `.superpowers/sdd/os-io-references.md`; [Apple's write manual](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/write.2) and [unlinkat manual](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/unlink.2) support investigation, not macOS 14 compatibility or measured latency claims.

## Exact owned files

A creates `TidyCore/Sources/TidyCore/Execution/RunJournal.swift`, `JournalStorage.swift`, `JournalPOSIXIO.swift`, and `TidyCore/Tests/TidyCoreTests/RunRecoveryTests.swift`. A modifies T02 `Execution/MutationAdmissionStore.swift` under a single assigned owner. No second storeID, lock, bootstrap or authority map.

**T04.A shared-I/O ownership is singular:** the assigned T04.A owner moves/extends the shared low-level persistence path exactly once so both T02 mandatory-envelope publication and T04 diagnostic journal storage use `JournalPOSIXIO`; T04 owns that coordinated modification. T05 A.2F consumes this shared journal I/O only after T04 lands. T05 may own explicitly approved settings-specific reader/store/bootstrap work, but must not duplicate `JournalPOSIXIO` or introduce a second mutation authority.

B modifies `TidyCore/Sources/TidyCore/Exec/ProcessRunner.swift`; creates `Exec/ProcessSession.swift`, `Exec/ProcessIdentity.swift`, `Exec/ProcessJobGate.swift`, `TidyCore/Tests/TidyCoreTests/BoundedProcessRunnerTests.swift`, and `TidyCore/Tests/TidyCoreTests/Fixtures/T04ProcessFixture.c`. Modify `TidyCore/Package.swift` only to exclude `Fixtures` from Swift test source discovery. Compile that controlled fixture during tests into a UUID scratch directory, not into the repository or any user's tool directory.

C integration edits, not A/B-owned: T02 `ExecutionCoordinator.swift` and `ResourceIdentity.swift`; accepted adapter `.M` source; T03 journal/manifest call sites. Existing `Engine/MemoryReclaimer.swift` and `Engine/SnapshotDeleter.swift` stay fixed-denial: no application-name AppleScript, snapshot relisting or shell reintroduction.

D edits `Engine/RunLog.swift`, T03 `Model/RunReport.swift`, `Tidy/Clean/CleanResultsView.swift`, and creates `Tidy/Execution/VerifiedApplicationTerminator.swift` and corresponding app test file. Controller assigns these overlapping files before entry. Current ProcessRunner retains unbounded `readDataToEndOfFile`, signals on all timeouts, has a four-job gate and can wait forever for a descendant's pipe EOF; those mechanisms must be removed, not hidden behind a new unused API. Current RunLog silently ignores errors and skips corrupt lines; it is optional history only and must never serve as mandatory recovery storage.

## A: Production persistence interfaces

All declarations are internal except the observation-only `RecoveryDecision`. Internal tests may construct untrusted persisted data to test fail-closed parsing; this never registers an accepted capability. Only the coordinator invokes the production effect path. Initializers below are exact, with synthesized internal initializers for record structs.

```swift
public enum RecoveryDecision: Equatable, Sendable {
    case blockMutations, requireFreshReview
    public static func forUnfinishedEffect(quiescenceProven: Bool) -> Self {
        quiescenceProven ? .requireFreshReview : .blockMutations
    }
}
enum JournalPhase: String, Codable, Sendable {
    case planned, confirmed, started, itemTerminal, finished
}
struct JournalEvent: Codable, Equatable, Sendable {
    let runID: UUID
    let sequence: UInt64
    let phase: JournalPhase
    let operationID: UUID?
    let status: EffectStatus?
    let reason: String?
}
enum JournalError: Error, Equatable {
    case invalidTransition, corrupt, unavailable, capacity, unsupportedSchema
}
protocol JournalPOSIXIO: Sendable {
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int
    func syncFile(fd: Int32) throws
    func replace(directoryFD: Int32, temporary: String, destination: String) throws
    func syncDirectory(fd: Int32) throws
}
struct DarwinJournalIO: JournalPOSIXIO {
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int
    func syncFile(fd: Int32) throws
    func replace(directoryFD: Int32, temporary: String, destination: String) throws
    func syncDirectory(fd: Int32) throws
}
protocol JournalStorage: Sendable {
    // Opens the named diagnostic/metadata leaf descriptor with
    // O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, validates that that
    // opened FD is the owner-only regular file still named by this anchored
    // directory, then performs the bounded read.
    func read(name: String) throws -> Data
    func replace(name: String, bytes: Data) throws
}
final class DurableJournalStorage: JournalStorage, @unchecked Sendable {
    init(directory: URL, io: any JournalPOSIXIO = DarwinJournalIO()) throws
    func read(name: String) throws -> Data
    func replace(name: String, bytes: Data) throws
}
// Only test fault seam is storage I/O; never policy/registry/recovery success.
final class RunJournal {
    init(store: MutationAdmissionStore, storage: any JournalStorage) throws
    func append(_ event: JournalEvent) throws
    func events(runID: UUID) throws -> [JournalEvent]
    func persistIntent(_ intent: PendingEffectIntent) throws
    func recordChild(_ intent: PendingEffectIntent) throws
    func finish(runID: UUID) throws
    func applyHistoryLimits(days: Int, bytes: Int, now: Date) throws
}
enum JournalSequence {
    static func next(after value: UInt64) throws -> UInt64
}
// Add inside the existing MutationAdmissionStore class (not an extension
// that tries to replace a let dependency after delegating initialization):
// init(directory: URL, io: any JournalPOSIXIO) throws
// Existing init(directory:) delegates with DarwinJournalIO().
```

RunJournal borrows the acquired T02 store lock; every operation checks lock ownership. It may not acquire/release an unrelated lock or allow `finish` to clear unfinished entries. T02 `persistIntentWhileLocked` remains the sole mandatory admission publication primitive. `persistIntent` forwards to it after validating planned→confirmed and unique operation/run association. `recordChild` updates that existing operation, never replaces other unresolved operations. Sequence starts at 1 per run, strictly increments with checked overflow, requires planned then confirmed before started; per-item terminal needs started and the same operationID. Finished requires all started operations durably terminal AND positively reconciled/cleared through coordinator-only completion below. Uncertain is not a quiescent terminal outcome. Planned/confirmed without any effect intent cannot retrospectively create an effect or auto-resume.

**Preserve T02's schema-1 JSON format exactly:** `unfinished-effects.json` remains `{ "schema": 1, "storeID": "<same UUID>", "unfinished": [<PendingEffectIntent>] }`; bootstrap JSON, storeID and stable lock are unchanged. Framing/checksums apply only to diagnostic `run-<runID>.journal` files, not the mandatory envelope. No implicit JSON→binary migration. Admission still uses T02 strict bounded envelope decoding and incomplete-bootstrap rules.

Diagnostic journals are owner-only, anchored/no-follow, bounded length-prefixed versioned records with sequence and SHA-256 checksums, not unbounded JSONL decoding. Maximum event payload 64 KiB, maximum unresolved-admission envelope 1 MiB, maximum active diagnostic segment 1 MiB; reject capacity before dispatch rather than evict unresolved data. `JournalSequence.next(after:)` uses checked addition and is the actual append/parser sequence helper, not disconnected test code. Large manifests remain T03 bounded separate files referenced by digest. No env, raw argv, credentials or stream contents are persisted. Keep actual executable identity and adapter operation identity privately in the mandatory store; redacted exports omit them. Every `DurableJournalStorage.read` of metadata or a diagnostic segment opens with `O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC`; before reading it validates the opened FD as the expected owner-only single-link regular file and compares its no-follow directory entry identity to that FD. This is the T02 FIFO correction applied to the new reader contract: never call a potentially blocking `O_RDONLY` open before `fstat`, and never treat a FIFO, symlink, replacement or other special node as empty/corrupt journal input. **Source gate before the first `read(2)`: the opened descriptor must pass that regular-file/owner/mode/link/identity validation; `JournalError.unavailable` is the typed result for a nonregular leaf.** The bounded watchdog below can only rescue a pre-fix blocking open; it never validates or makes safe a blocking read. T04.A and T05 A.2F both require pre-read FD validation; neither new reader should deliberately introduce a blocking bug to manufacture RED. Record natural missing-API RED separately from any genuine behavioral failure; a correct new FIFO reader may pass on its first behavioral run. Reject unsafe modes/owner, symlink, truncated envelope, unknown schema, checksum mismatch and sequence gaps. Preserve original bytes; do not truncate a corrupt tail to manufacture success.

Storage replacement: exclusive owner-only temporary file `.pending-<UUID>` in the same anchored directory, complete checked writes, durable file synchronization, atomic rename, directory synchronization. The SAME low-level `JournalPOSIXIO` seam services both diagnostic storage and T02 mandatory-envelope publication; no injected alternative persistence algorithm. `write` returns actual positive bytes written, so production loops with checked offset until complete; zero or out-of-range count fails, EINTR is retried, and other errno propagates. The test seam delegates real short writes and real renames, not just throwing before any production I/O. File creation/open/owner/no-follow checks stay production-only. `replace` calls descriptor-relative `renameat`; an error does not prove it was unpublished. File sync is checked; use appropriate supported Darwin durability primitives and check failures, not an assumption that `.atomic` is durable. Directory sync is independently checked.

Any persistence error latches the current store unavailable; it cannot continue dispatch or report a successful append. Do not delete failed staging files, roll back a possibly published envelope, or erase prior unresolved entries. On reacquire, detectable `.pending-*` remnants/invalid bytes fail closed. An ambiguous post-rename/dir-sync error may leave a complete new envelope, which is preserved and still blocks through its unfinished entries. Tests intentionally begin with an existing unresolved operation so fail-closed relaunch does not depend on a successfully written error flag. No effect is issued when intent persistence fails, including a first-intent failure. All tests are injected I/O-failure simulations over real files, **not physical power-loss evidence**; an error latch that cannot be persisted provides no additional cross-power-loss promise. Terminal persistence order: durable observed outcome → independently verified terminal evidence → atomically remove exactly reconciled operation from admission envelope → finish run. Optional history failures cannot erase safety state.

### Continuity and threat limits

An unkeyed SHA-256 checksum detects accidental corruption, not modification by the directory owner. Owner-only modes and no-follow opening mitigate wrong-user/path hazards; they do not make an owner's writable store tamperproof. A bootstrap/lock/envelope kept in the same directory cannot detect wholesale removal or rollback of that directory to a previously valid snapshot. No external tamperproof anchor is introduced or claimed. Detectable missing/mismatching files in an initialized installation fail closed; complete external removal/rollback is outside the promised continuity threat model and requires explicit disclosure. No app history/reset/import path may remove, relocate or reinitialize the canonical safety store, nor automatically choose a new directory after error. If a stronger rollback-resistant installation identity is required, that is a separate reviewed design, not inferred from checksums.

### Complete A RED test file

The following file is a foundation simulation, not evidence that a child or daemon actually survived. `PendingEffectIntent` is T02's exact schema. A deliberately unknown adapter remains unresolved. The low-level wrapper delegates actual scratch file writes/rename and faults individual I/O boundaries, never authorization. T02's two existing `ConfirmedExecutionTests.fifoMetadataBlocksPromptly` filename cases remain its regression coverage for the mandatory bootstrap/envelope reader; the additional T04 case below is deliberately limited to the newly proposed diagnostic reader and does not duplicate or create fake admission authority.

```swift
import Darwin
import Foundation
import Testing
@testable import TidyCore

private enum IOFault: CaseIterable, Equatable, Sendable {
    case shortWriteThenENOSPC, fileSync, renameBefore, renameAfter, directorySync
}
private final class FaultIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var armed: IOFault?
    private var failFollowingWrite = false
    private var shortOnly = false
    private var trace: [String] = []
    func arm(_ fault: IOFault) { lock.lock(); armed = fault; trace = []; lock.unlock() }
    func armShortWriteOnly() { lock.lock(); shortOnly = true; trace = []; lock.unlock() }
    func calls() -> [String] { lock.lock(); defer { lock.unlock() }; return trace }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        lock.lock()
        trace.append("write")
        if failFollowingWrite {
            failFollowingWrite = false; lock.unlock(); throw POSIXError(.ENOSPC)
        }
        let short = shortOnly || armed == .shortWriteThenENOSPC
        if armed == .shortWriteThenENOSPC { armed = nil; failFollowingWrite = true }
        shortOnly = false
        lock.unlock()
        if short {
            // A real one-byte write to the actual production-created staging FD.
            return try base.write(fd: fd, bytes: Data(bytes[offset..<(offset + 1)]), offset: 0)
        }
        return try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws {
        lock.lock(); trace.append("fileSync")
        let fail = armed == .fileSync; if fail { armed = nil }; lock.unlock()
        if fail { throw POSIXError(.EIO) }
        try base.syncFile(fd: fd)
    }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        lock.lock(); trace.append("rename")
        let before = armed == .renameBefore, after = armed == .renameAfter
        if before || after { armed = nil }; lock.unlock()
        if before { throw POSIXError(.EIO) }
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
        if after { throw POSIXError(.EIO) } // bytes really published; caller receives ambiguity
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock(); trace.append("directorySync")
        let fail = armed == .directorySync; if fail { armed = nil }; lock.unlock()
        if fail { throw POSIXError(.EIO) }
        try base.syncDirectory(fd: fd)
    }
}
private struct AdmissionEnvelope: Decodable {
    let schema: Int
    let storeID: UUID
    let unfinished: [PendingEffectIntent]
}
private func envelope(_ root: URL) throws -> AdmissionEnvelope {
    try JSONDecoder().decode(AdmissionEnvelope.self,
        from: Data(contentsOf: root.appendingPathComponent("unfinished-effects.json")))
}
private func intent(_ run: UUID, operation: UUID = UUID(), pid: Int32? = nil,
                    path: String = "/untrusted/not-executed") -> PendingEffectIntent {
    PendingEffectIntent(runID: run, operationID: operation, adapterID: "unknown-untrusted-record",
        bootID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        executablePath: path, executableDevice: 1, executableInode: 1,
        childPID: pid, childStartSeconds: pid == nil ? nil : 100,
        childStartMicroseconds: pid == nil ? nil : 1, phase: .prepared)
}
private func journalScratch(_ body: (URL) throws -> Void) throws {
    // Canonicalize only this known existing temporary base before the UUID
    // allocation. Foundation resolvingSymlinksInPath can retain /var/folders
    // under its /var ancestor symlink; production no-follow rules stay strict.
    guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { free(canonical) }
    let root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
        .appendingPathComponent("tidy-t04-journal-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                           attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}
private func event(_ run: UUID, _ seq: UInt64, _ phase: JournalPhase,
                   operation: UUID? = nil) -> JournalEvent {
    JournalEvent(runID: run, sequence: seq, phase: phase,
                 operationID: operation, status: nil, reason: nil)
}
// Shared FIFOReadWatchdog is defined in TidyCoreTests/FIFOReadWatchdog.swift.
@Suite struct RunRecoveryTests {
    @Test func transitionAndRoundTrip() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let run = UUID()
            #expect(throws: JournalError.invalidTransition) {
                try journal.append(event(run, 1, .confirmed))
            }
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            #expect(throws: JournalError.invalidTransition) {
                try journal.append(event(run, 2, .confirmed))
            }
            let reopened = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            #expect(try reopened.events(runID: run).map(\.phase) == [.planned, .confirmed])
        }
    }
    @Test(arguments: IOFault.allCases)
    func actualPublicationFaultRetainsEvidenceAndBlocks(_ fault: IOFault) throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root, io: io))
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let first = intent(run), second = intent(run)
            try journal.persistIntent(first)
            let ledger = root.appendingPathComponent("unfinished-effects.json")
            let prior = try Data(contentsOf: ledger)
            let priorStoreID = try envelope(root).storeID
            io.arm(fault)
            #expect(throws: (any Error).self) { try journal.persistIntent(second) }
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
            let observed = try envelope(root)
            #expect(observed.schema == 1 && observed.storeID == priorStoreID)
            #expect(observed.unfinished.contains(first))
            switch fault {
            case .renameAfter, .directorySync:
                #expect(observed.unfinished.contains(second))
                #expect(io.calls().contains("rename"))
            case .shortWriteThenENOSPC, .fileSync, .renameBefore:
                #expect(try Data(contentsOf: ledger) == prior)
                let staged = try FileManager.default.contentsOfDirectory(at: root,
                    includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".pending-") }
                #expect(!staged.isEmpty)
                if fault == .shortWriteThenENOSPC {
                    #expect(io.calls().filter { $0 == "write" }.count == 2)
                    #expect(try staged.contains { try Data(contentsOf: $0).count == 1 })
                } else {
                    let retained = try #require(staged.first)
                    let attempted = try JSONDecoder().decode(AdmissionEnvelope.self,
                        from: Data(contentsOf: retained))
                    #expect(attempted.unfinished.contains(first) && attempted.unfinished.contains(second))
                }
            }
            if fault == .fileSync { #expect(io.calls().contains("fileSync")) }
            if fault == .directorySync { #expect(io.calls().contains("directorySync")) }
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            let admission = reopened.acquire()
            #expect(admission == .storageUnavailable || admission == .uncertainAndPossiblyRunning)
            reopened.release()
            #expect(try envelope(root).unfinished.contains(first))
        }
    }
    @Test func positiveShortWriteRetriesWithoutTruncation() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root, io: io))
            let run = UUID(), operation = intent(UUID())
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let expected = intent(run, operation: operation.operationID)
            io.armShortWriteOnly()
            try journal.persistIntent(expected)
            #expect(io.calls().filter { $0 == "write" }.count >= 2)
            #expect(try envelope(root).unfinished == [expected])
        }
    }
    @Test func capacityAndSequenceOverflowDoNotPublish() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), first = intent(UUID())
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(intent(run, operation: first.operationID))
            let before = try Data(contentsOf: root.appendingPathComponent("unfinished-effects.json"))
            #expect(throws: JournalError.capacity) {
                try journal.persistIntent(intent(run, path: "/" + String(repeating: "x", count: 1_048_576)))
            }
            #expect(try Data(contentsOf: root.appendingPathComponent("unfinished-effects.json")) == before)
            let tooLarge = JournalEvent(runID: run, sequence: 3, phase: .started,
                operationID: first.operationID, status: nil, reason: String(repeating: "x", count: 65_536))
            #expect(throws: JournalError.capacity) { try journal.append(tooLarge) }
            #expect(try journal.events(runID: run).count == 2)
            #expect(throws: JournalError.capacity) { _ = try JournalSequence.next(after: UInt64.max) }
            #expect(try JournalSequence.next(after: 2) == 3)
            #expect(store.readAdmissionWhileLocked() != .ready)
        }
    }
    @Test func childUpdatePreservesOtherUnresolvedOperation() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            let run = UUID()
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let first = intent(run), second = intent(run)
            try journal.persistIntent(first)
            try journal.persistIntent(second)
            let captured = intent(run, operation: first.operationID, pid: 123)
            try journal.recordChild(captured) // untrusted record simulation, no PID signal/probe
            let items = try envelope(root).unfinished
            #expect(items.count == 2 && items.contains(captured) && items.contains(second))
            #expect(!items.contains(first))
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            reopened.release()
        }
    }
    @Test func preparedWithoutPIDSurvivesHistoryPruningAndRelaunch() throws {
        try journalScratch { root in
            let run = UUID(), operation = UUID()
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            let intent = PendingEffectIntent(runID: run, operationID: operation,
                adapterID: "unknown-untrusted-record", bootID: UUID(),
                executablePath: "/untrusted/not-executed", executableDevice: 1,
                executableInode: 1, childPID: nil, childStartSeconds: nil,
                childStartMicroseconds: nil, phase: .prepared)
            try journal.persistIntent(intent)
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: run) }
            try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            reopened.release()
        }
    }
    @Test func corruptLedgerNeverBecomesEmpty() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            store.release()
            let ledger = root.appendingPathComponent("unfinished-effects.json")
            var bytes = try Data(contentsOf: ledger)
            bytes.append(contentsOf: [0xff, 0x00])
            try bytes.write(to: ledger)
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .storageUnavailable)
            reopened.release()
            #expect(try Data(contentsOf: ledger) == bytes)
        }
    }
    @Test func diagnosticCorruptTailIsPreservedAndDoesNotClearAdmission() throws {
        try journalScratch { root in
            let run = UUID()
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: root))
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(intent(run))
            let file = root.appendingPathComponent("run-\(run.uuidString).journal")
            var bytes = try Data(contentsOf: file)
            try #require(!bytes.isEmpty)
            bytes.removeLast()
            try bytes.write(to: file)
            #expect(throws: JournalError.corrupt) { _ = try journal.events(runID: run) }
            #expect(try Data(contentsOf: file) == bytes)
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() != .ready)
            reopened.release()
            #expect(try Data(contentsOf: file) == bytes)
        }
    }
    @Test func diagnosticFIFOReaderRejectsPromptlyAndPreservesUnfinishedAdmission() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID(), unresolved = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(unresolved)
            let target = root.appendingPathComponent("run-\(run.uuidString).journal")
            let targetBytes = try Data(contentsOf: target)
            let backup = root.appendingPathComponent(".t04-fifo-original-\(UUID())")
            try FileManager.default.moveItem(at: target, to: backup)
            // Snapshot after the move, before the FIFO exists. This includes the
            // owned neutral backup and every other regular metadata byte.
            let movedNames = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
            var preservedBytes: [String: Data] = [:]
            for name in movedNames {
                preservedBytes[name] = try Data(contentsOf: root.appendingPathComponent(name))
            }
            #expect(mkfifo(target.path, 0o600) == 0)
            var before = stat()
            try #require(lstat(target.path, &before) == 0)
            try #require(before.st_mode & S_IFMT == S_IFIFO)
            let watchdog = try FIFOReadWatchdog(fifo: target)
            // No cancellation, task race, throwing check or scratch cleanup between
            // the actual proposed reader call and draining its owned watchdog.
            let received: JournalError?
            do { _ = try storage.read(name: target.lastPathComponent); received = nil }
            catch let error as JournalError { received = error }
            catch { received = nil }
            let watchdogFired = watchdog.finishAndDrain()

            #expect(received == .unavailable)
            #expect(!watchdogFired, "Journal reader needed FIFO rescue after five seconds")
            var after = stat()
            try #require(lstat(target.path, &after) == 0)
            #expect(after.st_mode & S_IFMT == S_IFIFO)
            #expect(after.st_dev == before.st_dev && after.st_ino == before.st_ino)
            #expect(after.st_mode == before.st_mode)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
                == (movedNames + [target.lastPathComponent]).sorted())
            #expect(try Data(contentsOf: backup) == targetBytes)
            for (name, bytes) in preservedBytes {
                #expect(try Data(contentsOf: root.appendingPathComponent(name)) == bytes)
            }
            #expect(try envelope(root).unfinished.contains(unresolved))
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }
}
```

## B: Exact process mechanism interfaces and implementation contract

Public legacy `ProcessRunner.run` remains read-only only after auditing every caller; it must not accept a caller-provided mutation flag. Denied old effects remain denied. Internal mechanism APIs below are not an alternate cleanup registration surface; tests call them only for the compiled helper. Production mutations can reach them only from the coordinator's private registered-effect method after registry/preflight/journal admission. No trustedIDs, fake `.M`, test-authorized root or public raw-command mutation entry.

```swift
struct ProcessInstanceIdentity: Codable, Equatable, Sendable {
    let bootID: UUID
    let pid: Int32
    let startSeconds: Int64
    let startMicroseconds: Int32
    let executablePath: String
    let executableDevice: UInt64
    let executableInode: UInt64
}
enum ProcessJobKind: Sendable { case readOnly, mutation }
struct ProcessRequest: Sendable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let kind: ProcessJobKind
    let deadline: Duration
}
enum ProcessEnd: Equatable, Sendable {
    case exited(Int32), cancelledBeforeStart, readOnlyTimedOut, uncertainAndPossiblyRunning
}
struct CapturedStream: Sendable {
    let bytes: Data
    let truncated: Bool
    let eofObserved: Bool
}
struct BoundedProcessOutput: Sendable {
    let end: ProcessEnd
    let stdout: CapturedStream
    let stderr: CapturedStream
    let identity: ProcessInstanceIdentity?
}
actor ProcessJobGate {
    init(limit: Int) throws // 1...2 only; shared production instance
    func acquire() async throws -> UUID
    func release(_ reservation: UUID)
    func snapshot() -> ProcessGateSnapshot
}
struct ProcessGateSnapshot: Sendable { let active: Int; let queued: Int }
// Additive internal observation on the EXISTING production runner. Its
// public run()/runDiscardingOutput() use this same single replacement gate.
extension ProcessRunner {
    static func jobSnapshot() async -> ProcessGateSnapshot
}
enum OwnedProcessExit: Equatable, Sendable {
    case reaped(ProcessInstanceIdentity, Int32), unproven
}
final class ProcessSession: @unchecked Sendable {
    static func launch(_ request: ProcessRequest, gate: ProcessJobGate) async throws -> ProcessSession
    var identity: ProcessInstanceIdentity { get }
    func collect() async -> BoundedProcessOutput
    func releaseStartByte() throws // nonblocking; only controlled waiting-child protocol
    func abandonWithoutSignal() // closes local control/read handles; never a terminal claim
    func observeOwnedExit(within timeout: Duration) async -> OwnedProcessExit
}
enum ProcessIdentity {
    static func capture(pid: Int32) throws -> ProcessInstanceIdentity
    static func matches(_ expected: ProcessInstanceIdentity) -> Bool
    static func parentPID(of expected: ProcessInstanceIdentity) throws -> Int32
}
```

Capture actual boot identity and process start time from Darwin process APIs, plus no-follow executable device/inode/path and appropriate signature identity for accepted tools. Missing/denied identity fails closed. PID and PGID are not durable identities. Probe full instance identity immediately before any permitted signal; do not send a group signal on PID-only evidence. For read-only trees, only signal a group whose continuing exclusive ownership is established by launcher design; an escaped descendant or reused group is not authorized. Otherwise close bounded pipe drains and report incomplete drainage, retaining permit/ownership tracking as necessary. Never send timeout/cancel/abandon signals to a mutation or a user process. A mutation's permit is retained while possibly active; global admission blocks new mutation even if local collector returned. Permits are cancellation-safe FIFO reservations: cancelled queued waiter is removed, cannot later launch, no increment-after-resume oversubscription, each reservation releases once. Do not create a new gate per run in production.

`observeOwnedExit` is a bounded read-only observation of the retained launch-time identity and actual `waitpid` reaping result for the direct owned child; cache that result for repeated calls. It does not infer exit from `kill(pid,0)`, absence or another process's exit status and does not itself prove descendant quiescence. `abandonWithoutSignal` retains this exit supervisor even when it closes local observation handles. **`launch` may throw `CancellationError` only before any spawn**, after removing any queued reservation. Once any process has been spawned, cancellation must return a retained, tracked session/uncertain observation, even if the direct child was already reaped: a forked descendant may still survive. Direct-child reaping never restores eligibility for this pre-spawn-only error. Do not discard the session or its descendant-tracking obligation on a post-spawn cancellation path. The fixture's kqueue watch is a separate positive exit observation for its one verified descendant; it cannot be promoted to generic adapter reconciliation.

Use O_NONBLOCK pipe reads with bounded chunks (≤64 KiB), concurrent stdout/stderr Dispatch sources, and monotonic deadlines. Retained bytes never exceed 1,048,576 per stream, even on partial UTF-8; keep bounded Data and decode at presentation. Continue draining/discarding after cap while observation remains open. EOF has a separate bounded drain deadline (250 ms proposed for fixture tests); inherited pipe ownership must not keep `collect` alive forever. On observation timeout close the read endpoints and mark eofObserved false, never pretend full output. Mutation whose safe terminal state is unproven returns uncertain even if its CLI exit code is zero. A deadline may return uncertainty without waiting for a surviving child; retained supervisor tracks eventual exit without freeing global safety admission. Closing a pipe can affect a writer through SIGPIPE; it is not a semantic cancellation guarantee and the accepted adapter must account for it. No unbounded detached blocking `readDataToEndOfFile` or unbounded reaping wait.

### Complete disposable subprocess fixture: Fixtures/T04ProcessFixture.c

This controlled executable writes only within the test-supplied UUID scratch root. It never signals any process, purges memory or restarts the machine. Poll delays are requested waits, **not hard lifetime bounds**: scheduling, writes, fsync and inherited output can stall. `gated` can wait 2 seconds and then work for another 1.2 seconds. Teardown requires positive direct-child reaping and, for the one explicitly forked descendant, a registered instance-bound exit event. Timeout preserves scratch and reports incomplete cleanup. `orphan` publishes its one child PID and both processes wait for a fixture observer acknowledgement before the parent exits; that lets tests register real exit observation before creating the orphan. This is a fixture protocol, not an accepted production adapter.

```c
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <limits.h>

static void mark(const char *root, const char *name) {
    char path[PATH_MAX];
    if (snprintf(path, sizeof(path), "%s/%s", root, name) >= sizeof(path)) _exit(90);
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0 || write(fd, "observed", 8) != 8 || fsync(fd) != 0) _exit(91);
    close(fd);
}
static void pause_ms(int ms) { (void)poll(NULL, 0, ms); }
static void publish_child(const char *root, pid_t child) {
    char path[PATH_MAX], text[32];
    if (snprintf(path, sizeof(path), "%s/descendant.pid", root) >= sizeof(path)) _exit(98);
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    int count = snprintf(text, sizeof(text), "%d", child);
    if (fd < 0 || write(fd, text, count) != count || fsync(fd) != 0) _exit(98);
    close(fd);
}
static int observer_ready(const char *root) {
    char path[PATH_MAX];
    if (snprintf(path, sizeof(path), "%s/descendant-observed", root) >= sizeof(path)) return 0;
    for (int i = 0; i < 200; ++i) {
        if (access(path, F_OK) == 0) return 1;
        pause_ms(10);
    }
    return 0;
}
int main(int argc, char **argv) {
    if (argc != 3 || argv[2][0] != '/') return 92;
    if (!strcmp(argv[1], "flood")) {
        char bytes[4096]; memset(bytes, 'x', sizeof(bytes));
        for (int i = 0; i < 768; ++i) {
            if (write(1, bytes, sizeof(bytes)) != sizeof(bytes)) return 93;
            if (write(2, bytes, sizeof(bytes)) != sizeof(bytes)) return 94;
        }
        return 0;
    }
    if (!strcmp(argv[1], "orphan")) {
        pid_t child = fork();
        if (child < 0) return 95;
        if (child > 0) { publish_child(argv[2], child); return observer_ready(argv[2]) ? 0 : 99; }
        if (!observer_ready(argv[2])) return 99;
        mark(argv[2], "alive");
        pause_ms(1500); mark(argv[2], "done"); return 0;
    }
    if (!strcmp(argv[1], "gated")) {
        mark(argv[2], "ready");
        struct pollfd gate = { .fd = 0, .events = POLLIN };
        char byte = 0;
        if (poll(&gate, 1, 2000) <= 0 || read(0, &byte, 1) != 1 || byte != 'G') return 96;
        mark(argv[2], "effect");
        pause_ms(1200); mark(argv[2], "done"); return 0;
    }
    if (!strcmp(argv[1], "slow")) {
        mark(argv[2], "alive");
        pause_ms(1500); mark(argv[2], "done"); return 0;
    }
    return 97;
}
```

### Complete B RED test file

Compiling this fixed checked-in C fixture with `/usr/bin/clang` is the only compiler subprocess in these tests. Compilation is local, no shell/network/packages; tests must be run only after the controller authorizes B execution. Compiler output and TMPDIR live in a separate UUID `build` directory, retained for inspection because this test does not prove the complete compiler/linker descendant tree exited. The `run` sibling is removable only after all fixture direct/descendant exits are positively observed; no elapsed-time or marker-only shortcut. No teardown kill, pkill or process-group guessing. Abandonment tests create actual surviving work, but simulate loss of the owning session rather than claiming a real killed Tidy-app process. C still requires the real process-crash harness.

```swift
import Darwin
import Foundation
import Testing
@testable import TidyCore

private enum FixtureError: Error { case observationIncomplete, markerMissing }
private final class FixtureExitWatch {
    let identity: ProcessInstanceIdentity
    private let queue: Int32
    init(pid: Int32, executable: URL, parent: ProcessInstanceIdentity) throws {
        let captured = try ProcessIdentity.capture(pid: pid)
        guard captured.executablePath == executable.path, ProcessIdentity.matches(parent),
              try ProcessIdentity.parentPID(of: captured) == parent.pid else {
            throw FixtureError.observationIncomplete
        }
        let fd = kqueue()
        guard fd >= 0 else { throw FixtureError.observationIncomplete }
        var registration = Darwin.kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT), fflags: NOTE_EXIT, data: 0, udata: nil)
        guard Darwin.kevent(fd, &registration, 1, nil, 0, nil) == 0,
              ProcessIdentity.matches(captured) else {
            close(fd); throw FixtureError.observationIncomplete
        }
        queue = fd
        identity = captured
    }
    deinit { close(queue) }
    func observeExit(within timeout: Duration) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            var result = Darwin.kevent()
            var immediate = timespec(tv_sec: 0, tv_nsec: 0)
            let count = Darwin.kevent(queue, nil, 0, &result, 1, &immediate)
            if count == 1 {
                return result.ident == UInt(identity.pid) && result.filter == Int16(EVFILT_PROC)
                    && result.fflags & NOTE_EXIT != 0 && result.flags & UInt16(EV_ERROR) == 0
            }
            if count < 0 { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
private final class ProcessScratch: @unchecked Sendable {
    let root: URL
    let binary: URL
    private let lock = NSLock()
    private var sessions: [ProcessSession] = []
    private var watchers: [FixtureExitWatch] = []
    private var ambiguousLaunch = false
    private var unobservedDescendants = 0
    init() async throws {
        // Canonicalize only the known existing temporary base before UUID
        // allocation. Do not dilute production O_NOFOLLOW handling because
        // Foundation's resolvingSymlinksInPath can retain /var/folders.
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(canonical) }
        let artifactRoot = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
            .appendingPathComponent("tidy-t04-process-\(UUID())", isDirectory: true)
        root = artifactRoot.appendingPathComponent("run")
        let build = artifactRoot.appendingPathComponent("build")
        binary = build.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/T04ProcessFixture.c")
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: ["-O0", "-Wall", source.path, "-o", binary.path],
            environment: ["PATH": "/usr/bin:/bin", "HOME": build.path, "TMPDIR": build.path],
            kind: .readOnly, deadline: .seconds(30))
        let compiler = try await ProcessSession.launch(request, gate: ProcessJobGate(limit: 1))
        let output = await compiler.collect()
        guard output.end == .exited(0) else {
            Issue.record("Fixture compilation failed; preserved scratch: \(artifactRoot.path)")
            throw CocoaError(.executableLoad)
        }
        print("Retained compiler artifacts (descendant tree not proven): \(build.path)")
    }
    private func add(_ session: ProcessSession, orphan: Bool) {
        lock.lock(); sessions.append(session)
        if orphan { unobservedDescendants += 1 }; lock.unlock()
    }
    private func markAmbiguousLaunch() { lock.lock(); ambiguousLaunch = true; lock.unlock() }
    func launch(_ request: ProcessRequest, gate: ProcessJobGate) async throws -> ProcessSession {
        do {
            let session = try await ProcessSession.launch(request, gate: gate)
            add(session, orphan: request.arguments.first == "orphan")
            return session
        } catch is CancellationError {
            // Production contract: this error proves NO spawn occurred.
            // Every post-spawn cancellation returns a session through add(),
            // even if the direct child exited but a descendant may survive.
            throw CancellationError()
        }
        catch { markAmbiguousLaunch(); throw error }
    }
    func registerOrphanBeforeParentExit(_ session: ProcessSession) async throws {
        try await waitFor("descendant.pid")
        let text = try String(contentsOf: root.appendingPathComponent("descendant.pid"), encoding: .utf8)
        guard let pid = Int32(text), pid > 0 else { throw FixtureError.observationIncomplete }
        let watch = try FixtureExitWatch(pid: pid, executable: binary, parent: session.identity)
        retain(watch)
        try Data("observing".utf8).write(to: root.appendingPathComponent("descendant-observed"))
    }
    private func retain(_ watch: FixtureExitWatch) {
        lock.lock(); watchers.append(watch); unobservedDescendants -= 1; lock.unlock()
    }
    func preserveOnIncomplete() { markAmbiguousLaunch() }
    func request(_ mode: String, _ kind: ProcessJobKind, seconds: Double = 5) -> ProcessRequest {
        ProcessRequest(executable: binary, arguments: [mode, root.path],
            environment: ["HOME": root.path, "PATH": "/usr/bin:/bin"],
            kind: kind, deadline: .seconds(seconds))
    }
    func has(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }
    func waitFor(_ name: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !has(name), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard has(name) else { throw FixtureError.markerMissing }
    }
    private func tracked() -> ([ProcessSession], [FixtureExitWatch], Bool) {
        lock.lock(); defer { lock.unlock() }
        return (sessions, watchers, ambiguousLaunch || unobservedDescendants != 0)
    }
    func dispose() async throws {
        let (owned, descendants, incomplete) = tracked()
        var proven = !incomplete
        for session in owned {
            let exit = await session.observeOwnedExit(within: .seconds(6))
            if case .reaped(let identity, _) = exit {
                proven = proven && identity == session.identity
            } else { proven = false }
        }
        for watch in descendants {
            let exited = (try? await watch.observeExit(within: .seconds(6))) ?? false
            proven = proven && exited
        }
        guard proven else {
            Issue.record("Fixture exit not proven; preserved run scratch: \(root.path)")
            throw FixtureError.observationIncomplete
        }
        try FileManager.default.removeItem(at: root)
    }
}
private func withProcessScratch(_ body: (ProcessScratch) async throws -> Void) async throws {
    let s = try await ProcessScratch()
    do { try await body(s) } catch { try await s.dispose(); throw error }
    try await s.dispose()
}
private actor QueueReceipt {
    enum Result: Equatable, Sendable { case granted(UUID), launched, cancelled, failed }
    private var result: Result?
    func record(_ value: Result) { result = value }
    func value() -> Result? { result }
}
private func waitForQueued(_ gate: ProcessJobGate, count: Int) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while ContinuousClock.now < deadline {
        if await gate.snapshot().queued == count { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw FixtureError.observationIncomplete
}
private func waitForReceipt(_ receipt: QueueReceipt) async throws -> QueueReceipt.Result {
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while ContinuousClock.now < deadline {
        if let value = await receipt.value() { return value }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw FixtureError.observationIncomplete
}
@Suite(.serialized) struct BoundedProcessRunnerTests {
    @Test func bothStreamsDrainWithBoundedRetention() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("flood", .readOnly),
                                                         gate: ProcessJobGate(limit: 1))
            let out = await session.collect()
            #expect(out.end == .exited(0))
            #expect(out.stdout.bytes.count == 1_048_576)
            #expect(out.stderr.bytes.count == 1_048_576)
            #expect(out.stdout.truncated && out.stderr.truncated)
            #expect(out.stdout.eofObserved && out.stderr.eofObserved)
        }
    }
    @Test func descendantOutlivesCLIAndPipeDeadline() async throws {
        try await withProcessScratch { s in
            let start = ContinuousClock.now
            let session = try await s.launch(s.request("orphan", .mutation, seconds: 0.4),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.registerOrphanBeforeParentExit(session)
            let out = await session.collect()
            #expect(out.end == .uncertainAndPossiblyRunning)
            #expect(start.duration(to: .now) < .seconds(1))
            #expect(!out.stdout.eofObserved || !out.stderr.eofObserved)
            try await s.waitFor("done") // real descendant survived its CLI, no signal
        }
    }
    @Test func mutatingTimeoutLeavesActualChildRunning() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("slow", .mutation, seconds: 0.2),
                                                         gate: ProcessJobGate(limit: 1))
            let out = await session.collect()
            #expect(out.end == .uncertainAndPossiblyRunning)
            #expect(s.has("alive") && !s.has("done"))
            #expect(ProcessIdentity.matches(session.identity))
            try await s.waitFor("done")
        }
    }
    @Test func abandonmentBeforeReleaseDoesNotPerformFixtureEffect() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("gated", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.waitFor("ready")
            #expect(!s.has("effect"))
            session.abandonWithoutSignal()
            let exit = await session.observeOwnedExit(within: .seconds(6))
            guard case .reaped(let identity, _) = exit, identity == session.identity else {
                throw FixtureError.observationIncomplete
            }
            #expect(!s.has("effect"))
        }
    }
    @Test func abandonmentAfterReleaseDoesNotEraseSurvivingEffect() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("gated", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.waitFor("ready")
            try session.releaseStartByte()
            try await s.waitFor("effect")
            session.abandonWithoutSignal()
            try await s.waitFor("done")
            #expect(s.has("effect"))
        }
    }
    @Test func realSurvivingChildKeepsReopenedCoordinatorBlocked() async throws {
        try await withProcessScratch { s in
            let directory = s.root.appendingPathComponent("journal")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let store = try MutationAdmissionStore(directory: directory)
            #expect(store.acquire() == .ready)
            let journal = try RunJournal(store: store, storage: DurableJournalStorage(directory: directory))
            let run = UUID(), operation = UUID()
            try journal.append(JournalEvent(runID: run, sequence: 1, phase: .planned,
                operationID: nil, status: nil, reason: nil))
            try journal.append(JournalEvent(runID: run, sequence: 2, phase: .confirmed,
                operationID: nil, status: nil, reason: nil))
            var metadata = stat()
            guard lstat(s.binary.path, &metadata) == 0 else { throw CocoaError(.fileReadUnknown) }
            let boot = try ProcessIdentity.capture(pid: getpid()).bootID
            try journal.persistIntent(PendingEffectIntent(runID: run, operationID: operation,
                adapterID: "untrusted-fixture-not-a-capability", bootID: boot,
                executablePath: s.binary.path, executableDevice: UInt64(metadata.st_dev),
                executableInode: UInt64(metadata.st_ino), childPID: nil, childStartSeconds: nil,
                childStartMicroseconds: nil, phase: .prepared))
            let session = try await s.launch(s.request("gated", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            try await s.waitFor("ready")
            let child = session.identity
            try journal.recordChild(PendingEffectIntent(runID: run, operationID: operation,
                adapterID: "untrusted-fixture-not-a-capability", bootID: child.bootID,
                executablePath: child.executablePath, executableDevice: child.executableDevice,
                executableInode: child.executableInode, childPID: child.pid,
                childStartSeconds: child.startSeconds, childStartMicroseconds: child.startMicroseconds,
                phase: .prepared))
            try session.releaseStartByte()
            try await s.waitFor("effect")
            session.abandonWithoutSignal()
            store.release() // simulate owner loss; real child has not completed
            let coordinator = ExecutionCoordinator(environment: CleanEnvironment(
                homeDirectory: s.root.path, detectedTools: [], protectedRoots: []),
                journalDirectory: directory)
            #expect(await coordinator.mutationAdmission() == .uncertainAndPossiblyRunning)
            try await s.waitFor("done")
            // Even actual completion/PID disappearance cannot clear an unknown adapter.
            #expect(await coordinator.mutationAdmission() == .uncertainAndPossiblyRunning)
        }
    }
    @Test func queuedCancellationNeverLaunchesChild() async throws {
        try await withProcessScratch { s in
            let gate = try ProcessJobGate(limit: 1)
            let reservation = try await gate.acquire()
            let receipt = QueueReceipt()
            let queued = Task {
                do {
                    _ = try await s.launch(s.request("slow", .readOnly), gate: gate)
                    await receipt.record(.launched)
                } catch is CancellationError {
                    // Pre-spawn only; the held first lease and absent marker
                    // below exercise this exact no-child contract.
                    await receipt.record(.cancelled)
                }
                catch { await receipt.record(.failed) }
            }
            do {
                try await waitForQueued(gate, count: 1) // prove it actually queued
                queued.cancel()
                let result = try await waitForReceipt(receipt)
                try #require(result == .cancelled)
                await queued.value // first reservation is STILL held
                #expect(await gate.snapshot().queued == 0)
                #expect(await gate.snapshot().active == 1)
                #expect(!s.has("alive"))
                await gate.release(reservation)
                let next = try await s.launch(s.request("slow", .readOnly), gate: gate)
                #expect(await next.collect().end == .exited(0))
            } catch {
                s.preserveOnIncomplete()
                queued.cancel()
                await gate.release(reservation)
                throw error
            }
        }
    }
    @Test func releasedSlotIsTransferredBeforeWaiterResumes() async throws {
        let gate = try ProcessJobGate(limit: 1)
        let first = try await gate.acquire()
        let queued = Task { try await gate.acquire() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await gate.snapshot().queued != 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await gate.snapshot().queued == 1)
        await gate.release(first)
        let newcomer = Task { try await gate.acquire() }
        let second = try await queued.value
        let nextDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await gate.snapshot().queued != 1, ContinuousClock.now < nextDeadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await gate.snapshot().active == 1)
        #expect(await gate.snapshot().queued == 1)
        await gate.release(second)
        let third = try await newcomer.value
        await gate.release(third)
        #expect(await gate.snapshot().active == 0)
    }
    @Test func transferRacingCancellationDoesNotLeakOrDuplicateReservation() async throws {
        let gate = try ProcessJobGate(limit: 1)
        for _ in 0..<25 {
            let first = try await gate.acquire()
            let receipt = QueueReceipt()
            let queued = Task {
                do { await receipt.record(.granted(try await gate.acquire())) }
                catch is CancellationError { await receipt.record(.cancelled) }
                catch { await receipt.record(.failed) }
            }
            try await waitForQueued(gate, count: 1)
            let release = Task { await gate.release(first) }
            let cancel = Task { queued.cancel() }
            await release.value; await cancel.value
            let result = try await waitForReceipt(receipt)
            await queued.value
            switch result {
            case .granted(let reservation): await gate.release(reservation)
            case .cancelled: break
            case .launched, .failed: Issue.record("Invalid acquisition outcome")
            }
            #expect(await gate.snapshot().active == 0)
            #expect(await gate.snapshot().queued == 0)
            let next = try await gate.acquire()
            await gate.release(next)
        }
    }
    @Test func existingPublicRunnerUsesAggregateReplacementGate() async throws {
        // Deliberately retain this run directory: public-runner sessions are
        // not handed to this fixture's per-session teardown supervisor.
        let s = try await ProcessScratch()
        defer { print("Retained aggregate-runner evidence: \(s.root.path)") }
        var roots: [URL] = []
        for name in ["one", "two", "three", "four"] {
            let root = s.root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            roots.append(root)
        }
        let jobs = roots.map { root in
            Task {
                try await ProcessRunner.run(executableURL: s.binary,
                    arguments: ["slow", root.path],
                    environment: ["HOME": root.path, "PATH": "/usr/bin:/bin"], timeout: 8)
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            let snapshot = await ProcessRunner.jobSnapshot()
            if snapshot.queued > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let snapshot = await ProcessRunner.jobSnapshot()
        #expect(snapshot.active >= 1 && snapshot.active <= 2)
        #expect(snapshot.queued >= 1)
        let markers = roots.filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("alive").path)
        }
        #expect(markers.count <= 2)
        for job in jobs { #expect(try await job.value.succeeded) }
        #expect(await ProcessRunner.jobSnapshot().active == 0)
        #expect(await ProcessRunner.jobSnapshot().queued == 0)
    }
    @Test func reusedPIDShapeCannotMatchActualIdentity() async throws {
        try await withProcessScratch { s in
            let session = try await s.launch(s.request("slow", .mutation),
                                                         gate: ProcessJobGate(limit: 1))
            let actual = session.identity
            let mismatched = ProcessInstanceIdentity(bootID: actual.bootID, pid: actual.pid,
                startSeconds: actual.startSeconds + 1, startMicroseconds: actual.startMicroseconds,
                executablePath: actual.executablePath, executableDevice: actual.executableDevice,
                executableInode: actual.executableInode)
            #expect(ProcessIdentity.matches(actual))
            #expect(!ProcessIdentity.matches(mismatched))
            _ = await session.collect()
        }
    }
}
```

The mismatched-start test verifies identity comparison, not actual kernel PID reuse. The orphan fixture verifies real inherited descriptors and surviving subprocess behavior, not a Docker/service daemon protocol. The marker files are observed fixture effects, never a magic success file accepted by production reconciliation or teardown. `FixtureExitWatch` verifies executable identity and parent relationship while the parent is still waiting, registers NOTE_EXIT, then rechecks the full child identity; unsupported/denied/missed observation preserves scratch, not a PID-disappearance fallback. Compiler/build artifacts and the aggregate public-runner fixture are deliberately retained; other run roots are removed only after real direct-child reaping and every registered descendant exit event. Interrupted supervision never authorizes teardown signals or deletion. Process helper start/pipe APIs and macOS 14 kqueue behavior must be reviewed before this suite is run. T08 must consume this same production process gate through its shared scheduler, not introduce a second independent budget. A per-test gate isolates mechanical tests only; the public-runner aggregate test calls the existing API and its same-gate observation to catch an unused replacement gate. Run this focused serialized suite in isolation from other package jobs so unrelated test launches cannot alter the aggregate counts.

## C: Mandatory durable effect sequence and terminal proof

Only these additions inside the existing coordinator are production authority; private registry lookups, not raw argv/resource/proof arguments:

```swift
// Inside ExecutionCoordinator.swift; not public, not an alternate actor.
private func executeRegisteredProcessItem(runID: UUID, registeredPlanID: UUID,
                                          selectedItemID: String) async -> TargetEffectOutcome
public func reconcileUnfinishedEffects() async -> RecoveryDecision
private func reconcileRegisteredOperation(runID: UUID, operationID: UUID) async throws
```

`reconcileUnfinishedEffects` loads existing mandatory evidence under the same installation lock and running reservation, performs only compiled adapter-specific read-only bounded probes, and never starts/resumes/retries a mutation. No `clearUncertainty`, `markQuiescent(true)`, user-supplied proof, exported terminal setter or generic “PID gone” reset. The exact accepted adapter's private proof type is assigned in C's `.M` card; it must bind operation ID, adapter/version, original resource/executable/endpoint identity, probe freshness and terminal semantics. A constructed `RecoveryDecision` has no authority to change storage.

1. Reserve coordinator and global process slot, check fixed registry/current original selection, policy, cancellation, budget, exact scope and ownership. Allocate adapter operation ID before submission. Durable intent first; failure means zero effect calls.
2. Prepare a controlled waiting child without releasing effects. Capture actual start/boot/executable identity; durably append it to the same intent. Awaiting readiness and persistence is outside the policy barrier. Failure closes the unopened start gate; surviving/ambiguous process stays blocked. Adapter-less subprocess fixture success cannot enable real CLIs.
3. Immediately revalidate identity, runtime evidence and original registry/policy. The synchronous policy barrier contains only the actual bounded irreversible release. Persisted intent covers a crash just before/after release. A “submitted” write afterward is diagnostic, never the first crash evidence. No await/check-then-queue race.
4. For a daemon operation: require preallocated operation ID and documented idempotent submission/query semantics. Journal endpoint/object identity before the bounded local submission. Lost reply, CLI exit 0, daemon reconnect or service restart never proves completion; query original operation, do not resubmit. Unsupported operation discovery or token allocation keeps `.M` unavailable.
5. Drain bounded streams. Cancellation stops the next item immediately, but mutating timeout/cancel waits only for the adapter boundary, otherwise records uncertainty and stops all later items. Record completed leaf observations separately; do not translate already submitted work into cancelled-before-start.
6. Persist observed outcome. Reconcile active child tree AND persistent daemon job through adapter positive evidence. Child reaped alone is sufficient only for an accepted protocol proving no detached/daemon work; otherwise uncertainty remains. Changed boot may help only when that adapter proves no persisted/restarted job can survive boot.
7. Under the store lock persist terminal proof then remove only that operation. All unresolved operations must be reconciled before admission becomes ready. Once all are quiescent, return requireFreshReview, invalidate every old registration/token, and require fresh inventory/confirmation for remaining work. Never replay completed IDs. A previously missing target is skipped/unavailable until supported accounting proof, not retroactive success.

### C acceptance matrix — entry blocked until complete adapter-bound tests exist

Each row must call the production coordinator/adapter and observe an actual controlled effect or actual denial, not seed a fake accepted intent. The C card must supply full driver source, exact packaged build invocation and safe teardown before source work begins.

| Required case | Physical fixture and assertions |
|---|---|
| Crash before intent / persistence full disk | Narrow journal I/O fault (ENOSPC, short write, file sync, rename, directory sync) with controlled waiting helper; zero release/effect when durable preparation is unproven; original bytes preserved; global block on ambiguous publication |
| Crash after intent, before launch / after launch, before identity persistence | Separate owned Swift driver running production coordinator, forced `_exit` at instrumented boundaries; restart separate driver; actual child either absent or survives gated; no new mutation, no generic absent-PID clearing |
| Crash after identity persistence, before/after release | Same driver; actual owned gated helper observed across driver exit; effect marker absent before release, present afterward; reopened coordinator globally blocks both related and unrelated accepted mutations; no replay |
| Effect completed before terminal fsync | Actual fixture completion followed by driver crash; durable unfinished state survives; adapter positive query proves terminal result; only then fresh review available; terminal-write failure retains block |
| Daemon survives CLI exit / ambiguous reply | Provisioned local controlled service implements the accepted adapter protocol, operation token/status and expiry; job actually continues after CLI/driver exits; denied/missing/unknown query stays blocked; verified completed token clears only its matching operation |
| Second app process / free lock | Two real driver PIDs; lock serializes while first lives, its death frees lock but unfinished ledger still blocks; no separate journal directory accepted as a reset path |
| PID reuse / process group | Compare actual full start/boot/executable identity against deliberately mismatching instance; zero signals to sentinel sibling process. Actual reused PID/group acceptance is separate OS stress evidence, not asserted from value construction |
| Cancellation and policy order | Pause at controlled ready gate, begin synchronous T02 update, then attempt release: zero effect. Reverse order: one accepted effect drains, no next dispatch. Measure UI response and syscall/handshake latency; no timeout promises for unbounded unlink |
| Corrupt tail / future schema / missing manifest | Corrupt actual journal/ledger after real interrupted effect; preserve bytes, block, no truncate/reset/eviction; unresolved manifest batches retained regardless history settings |
| Failed command and measurements | Real fixture exits nonzero; T03 result remains failed; no planned/legacy bytes credited, missing measurements unavailable, separately signed real-volume observations |
| Leak and output stress | 20 actual launch/drain/cancel cycles, both streams >1 MiB, descendant pipes, invalid UTF-8, cancelled queue and timeout; measure peak retained buffers, FDs/workers, ≤2 aggregate jobs including mutator; unresolved work remains accounted |
| Platform and app lifecycle | macOS 14/current OS, Intel and Apple Silicon physical Macs; sleep/wake, window close, ordinary quit and abrupt process death; unavailable hardware explicitly incomplete |

## D: App requests, history and truthful results

AppKit belongs in the app layer. Proposed internal app API: `@MainActor protocol VerifiedApplicationTerminating { func requestTermination(of identity: VerifiedApplicationIdentity) -> Bool }`, where `VerifiedApplicationIdentity` stores verified bundle URL, bundle identifier and T04 `ProcessInstanceIdentity`. The concrete app implementation resolves `NSRunningApplication(processIdentifier:)`, rechecks full identity and bundle, then calls `terminate()` only. `Bool` means request accepted, not app terminated or RAM reclaimed. Never `forceTerminate`, name interpolation, AppleScript or PID-only acceptance. Injection replaces the transport only; coordinator registry/selection/per-instance consent and journal authority remain production. A separately reviewed app-layer bridge must expose observation identity safely without making internal process launch APIs public.

Advanced restart is off/unselected, independent per-run confirmation, never Build Prep or automation and never described as guaranteed swap recovery. Purge, restart and snapshots remain unavailable until their respective accepted contracts exist. This card does not authorize a test reboot or host application quit. D's app test fixture must be an explicitly launched disposable test application, with unrelated verified sentinel app left untouched.

RunLog becomes throwing on append and returns explicit read errors/partial history diagnostics instead of silently skipping corruption. It is optional derived history, not a source of recovery truth. Clear history/retention only removes resolved optional reports; it cannot remove bootstrap, lock, active journal, unresolved admission/proof/manifests. Cap exhaustion blocks new effects; neither history off nor reset provides recovery relief.

CleanResultsView consumes T03 typed outcomes: succeeded/partial/failed/skipped/cancelled/uncertain each distinct, per-item reason available without truncation hiding it. Show removed apparent/allocated metadata, proven reclaim only when available, per-volume signed before/after observations and RAM observations separately. Legacy missing measurements say unavailable, not zero. Exit 0 and app termination request are not reclaimed memory. Uncertainty message: “An earlier operation may still be running. New changes are blocked until its status can be verified.” Offer bounded Retry verification, no dismiss/reset that removes the block. Completed IDs remain visible but cannot be silently selected for replay.

## Ordered execution and review steps

- [ ] T02 foundation through `10616b3` and T03.A foundation through `ec9dbc5` are approved; controller still assigns the single T04.A owner and reviews the exact shared-`JournalPOSIXIO` source/API change before entry. T03 production integration remains gated. Add the entire A test file and exact proposed declarations. Run `cd TidyCore && swift test --filter RunRecoveryTests` after other package jobs are idle. Initial missing-symbol RED is scaffolding evidence only; record behavioral RED before implementing transitions/storage.
- [ ] Implement anchored durable storage and the assigned shared-I/O extension of the existing admission store; no second safety ledger or persistence seam. Rerun A and T02 `ConfirmedExecutionTests`, including the existing mandatory-reader FIFO cases; review the additional bounded diagnostic-reader FIFO fixture before accepting it. Verify retained uncertainty after releasing/reopening and after minimum history pruning. Review lock lifetime, fsync/rename ambiguity and capacity before accepting A.
- [ ] Review B launcher/FD/identity design and compiler lifecycle before adding the entire C helper and B test file. Audit all ProcessRunner production callers with `rg -n 'ProcessRunner|runDiscardingOutput|kill\\(|SIGKILL|readDataToEndOfFile' TidyCore/Sources Tidy`. Quarantined mutation bodies must not reappear as read-only callers.
- [ ] Run `cd TidyCore && swift test --filter BoundedProcessRunnerTests`; initial API RED, then actual flood/pipe/timeout/queued-cancel behavior RED. Implement the nonblocking drain/gate/identity mechanisms and rerun. Record actual surviving fixture marker observations and elapsed pipe deadline; do not substitute seeded journal records.
- [ ] Run `cd TidyCore && swift test --filter 'RunRecoveryTests|BoundedProcessRunnerTests'` plus existing `ProcessRunnerTests` only after auditing their host commands. Review that no signal can reach mutations/user processes and no public mutation classifier/bypass exists. Compile-negative external client must fail access to `ProcessSession` and any low-level mutation API because of access control, not module lookup failure.
- [ ] Stop before C: obtain accepted `.M`, explicit controlled app-crash driver and full tests for every C row. No successful A/B test can open the capability registry. Resolve T02/T03 boundedness conflict or leave that capability unavailable and disclose incomplete useful-cleanup delivery.
- [ ] Assign D report/app file ownership, create its full app/compatibility tests before edits, then implement. Test actual per-instance graceful request only in a provisioned fixture app; retain purge/restart/snapshot quarantine.
- [ ] Controller runs full safe suite, unsigned app build, diff review and physical-platform acceptance when all units are integrated. No signing/publishing/remote change or commit is authorized by this card. Report exact tests run, behavior observed, unsupported reconciliation and hardware gaps separately.

**Handoff wording:** “T04 entry card prepared; A/B foundation tests specified, C/D integration gated.” After A/B implementation, say “durable-state foundation and real disposable subprocess mechanisms verified”; never “T04 complete,” “crash-safe cleanup,” or “daemon recovery verified” without C/D evidence.
