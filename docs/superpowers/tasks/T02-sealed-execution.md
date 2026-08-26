# T02 — Sealed review and serial execution implementation plan

> **For agentic workers:** Execute only after independent review of this card, using executing-plans. This document contains proposed interfaces and tests, not implementation or verification evidence. No source edits, builds, cleanup, or commits are authorized by preparing this card.

**Goal:** Make the app-owned coordinator the only cleanup admission route, bind confirmation to an immutable registered selection, and preserve an unresolved-effect block across process lifetimes.

**Architecture:** One production actor owns registered engine discoveries, review revisions, opaque one-use tokens, and an explicit running reservation. A private on-disk admission ledger and advisory lock protect the same installation across instances. Existing effects remain quarantined; empty selections are legitimate reviewed no-ops, allowing honest token lifecycle tests without pretending a cleanup adapter has been accepted.

**Tech stack:** Swift/SwiftUI, Swift Testing, Foundation and Darwin; local TidyCore, no new runtime dependencies.

## Global constraints and prerequisites

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

Design S01–S16, recursive scope limits and every policy/adapter appendix row remain binding. T01.A/B in `docs/superpowers/tasks/T01-action-review-and-quarantine.md` are prerequisites, not implemented facts. Consume their `CapabilityRegistry`, `PlanSelection`, `reviewItems`, `.unavailable` action and denied direct helpers without inventing replacement policy.

T02 has two delivery boundaries. **Foundation:** real token lifecycle, app ownership, admission persistence, negative authorization and no-op execution can be implemented now after T01.A/B. **Full T02 acceptance:** positive selected mutations, await-spanning mutation serialization, per-item live policy/resource preflight, child/daemon uncertainty and cross-process interruption need T03/T04 plus the first accepted existing-scope adapter. An empty/no-op run proves token mechanics, not mutation serialization or useful cleanup. Neither blanket denial nor this foundation closes the program's supported-useful-cleanup goal.

Do not introduce a new Tidy-cache mutation contract here merely to make tests green. The appendix permits app-owned resources only with a documented versioned path, complete owner/instance evidence, fresh closed-state proof and appropriate exclusion/immutability lease. An arbitrary scratch directory or test ID is not that contract. A separately reviewed in-scope `.M` adapter may later supply a production-bound disposable fixture; it must be the same compiled contract used by the app.

## Exact files and responsibility

Create:

- `TidyCore/Sources/TidyCore/Execution/ConfirmedPlan.swift`: public immutable review views/errors and opaque token; token construction is fileprivate, in the same file as a narrowly scoped coordinator extension that issues it.
- `TidyCore/Sources/TidyCore/Execution/ExecutionCoordinator.swift`: sole actor, private registries, selection and policy revisions, running reservation and admission order.
- `TidyCore/Sources/TidyCore/Execution/ResourcePreflight.swift`: typed resource capture and fail-closed preflight; no mutation or rediscovery.
- `TidyCore/Sources/TidyCore/Model/ResourceIdentity.swift`: exact identity values, including descendant manifest binding.
- `TidyCore/Sources/TidyCore/Execution/MutationAdmissionStore.swift`: minimal mandatory unresolved-effect ledger and lock, needed by S04/S16 even before T04. T04 extends this store through RunJournal; it must not replace it with a second independent authority.
- `TidyCore/Sources/TidyCore/Execution/ExecutionPolicyBridge.swift`: the production main-actor persistence/update bridge owned by AppExecutionServices, with deterministic core tests; not a parallel policy resolver.
- `TidyCore/Sources/TidyCore/Execution/PolicyInvalidationBarrier.swift`: coordinator-owned thread-safe synchronous invalidation/commit boundary; not another policy store or caller-granted execution permit.
- `TidyCore/Tests/TidyCoreTests/ConfirmedExecutionTests.swift`: entire safe core test file below.
- `Tidy/Execution/AppExecutionServices.swift`: app-lifetime dependencies, shared by all windows.

Modify:

- `TidyCore/Sources/TidyCore/Engine/CleanEngine.swift`: retain discovery, internalize raw execution as denial-only compatibility, add no public mutation bypass.
- `TidyCore/Sources/TidyCore/Engine/DefaultCustomActionExecutors.swift`: keep denial behavior; registration cannot install trusted capabilities or replace a confirmed operation.
- `TidyCore/Sources/TidyCore/Engine/ConfigStore.swift`: make save throwing; propagate encoding/directory/write failures instead of `try?`. Full load/schema migration remains T05.
- `TidyCore/Sources/TidyCore/Model/TidyConfig.swift`: add the pure, explicit-input `makePolicyEnvironment` projection below; keep discovery out of T02 launch/settings wiring. The legacy discovery-bearing `makeEnvironment` remains outside this path pending T08.
- `TidyCore/Tests/TidyCoreTests/ConfigStoreTests.swift`: add `throws`/`try` to existing successful save tests; never suppress new save errors. Change the existing field-projection test to call `makePolicyEnvironment(homeDirectory: "/Users/tester", detectedTools: [])`, so the prescribed focused suite does not launch ambient tool probes through the old helper.
- `TidyCore/Sources/TidyCore/Model/RunReport.swift`: additive admission disposition and optional coordinator measurement availability, as described below; full per-target outcomes remain T03/T04.
- `Tidy/TidyApp.swift`, `Tidy/Clean/CleanView.swift`, `Tidy/Custom/CustomView.swift`, both view models, `Tidy/Clean/PlanSelectionModel.swift`, and `Tidy/Settings/AppConfigStore.swift`: explicit shared dependency injection, frozen confirmation binding, config invalidation.
- `Tidy/Clean/CleanResultsView.swift`: distinguish no-work/denial from cleanup success and suppress unavailable measurements.
- `Tidy.xcodeproj/project.pbxproj`: generated through XcodeGen only if needed by `project.yml` source discovery.

This adds the smallest ledger/app/report files needed to enforce the T02 brief; it does not implement T03 deletion, T04 subprocess management or T07's full policy resolver.

## Production interfaces

All declarations here are real production contracts. Internal declarations are visible to `@testable` for observations, not alternate policy injection. No constructor accepts a registry, trusted IDs, action executor map, eligibility function or preflight-success closure.

```swift
public struct ReviewBinding: Equatable, Sendable {
    public let planID: UUID
    public let planRevision: UInt64
    public let policyRevision: UInt64
    public let selectedIDs: Set<String>
    public init(planID: UUID, planRevision: UInt64,
                policyRevision: UInt64, selectedIDs: Set<String>)
    public func matches(_ other: Self) -> Bool { self == other }
}

public struct RegisteredReview: Sendable {
    public let binding: ReviewBinding
    public let plan: CleanPlan
    public let selection: PlanSelection
    // Internal initializer only. Value copies convey no execution authority.
}

public enum ConfirmationError: Error, Equatable, Sendable {
    case unknownPlan, staleReview, stalePolicy, unknownSelectedID
    case unavailableSelection, busy, recoveryBlocked, storageUnavailable
}

public struct ConfirmedPlan: Sendable {
    internal let coordinatorID: UUID
    internal let nonce: UUID
    fileprivate init(coordinatorID: UUID, nonce: UUID) {
        self.coordinatorID = coordinatorID
        self.nonce = nonce
    }
    // No public/internal initializer, Codable, rawValue, unsafe initializer
    // or reconstruct-from-binding API. Explicit init suppresses memberwise init.
}

public enum RunDisposition: String, Codable, Sendable {
    case completed, noWork, invalidToken, staleReview, stalePolicy
    case busy, recoveryBlocked, storageUnavailable, unavailableSelection
}

public actor ExecutionCoordinator {
    public init(environment: CleanEnvironment, journalDirectory: URL)
    public func prepareReview(engine: CleanEngine, tier: Tier,
                              selectDefaults: Bool) async throws -> RegisteredReview
    public func setSelection(planID: UUID, selectedIDs: Set<String>) throws -> RegisteredReview
    public func confirm(binding: ReviewBinding) throws -> ConfirmedPlan
    public func execute(_ token: ConfirmedPlan,
                        currentPolicyRevision: UInt64) async -> RunReport
    public nonisolated func beginPolicyUpdate() throws -> PolicyUpdateTicket
    public nonisolated func policyAdmission() -> PolicyAdmission
    internal func commitPolicyUpdate(_ ticket: PolicyUpdateTicket,
                                     environment: CleanEnvironment) throws -> PolicyCommit
    public func currentPolicyRevision() -> UInt64
    public func discardReview(planID: UUID)
    public func mutationAdmission() -> MutationAdmission
}

public enum MutationAdmission: Equatable, Sendable {
    case ready, busy, uncertainAndPossiblyRunning, storageUnavailable
}

public struct PolicyUpdateTicket: Sendable {
    internal let coordinatorID: UUID
    internal let revision: UInt64
    internal let nonce: UUID
    fileprivate init(coordinatorID: UUID, revision: UInt64, nonce: UUID) {
        self.coordinatorID = coordinatorID; self.revision = revision; self.nonce = nonce
    }
}
public enum PolicyAdmission: Equatable, Sendable {
    case ready(revision: UInt64), updating(revision: UInt64), unavailable
}
internal enum PolicyCommit: Equatable, Sendable {
    case applied(revision: UInt64), superseded
}
```

Initial policy revision is 1. `beginPolicyUpdate` is nonisolated and **synchronous**: it locks the coordinator-owned barrier, checked-increments revision even for reset-to-identical-policy, replaces its pending opaque ticket and marks admission updating before returning. It does not queue an actor Task. All old tokens/reviews become immediately invalid because admission compares their revision against this barrier, even before the actor can remove old map entries. An already queued execute or per-item actor continuation cannot use the old actor environment while the barrier is updating. Overflow permanently marks unavailable and throws; no reset/force-enable API.

After actual save success, the bridge calls actor-isolated `commitPolicyUpdate`. Under the same barrier lock it checks issuer/revision/nonce against the **latest** pending ticket, installs the coordinator's immutable environment and ready revision atomically, and returns applied. An older ticket returns superseded without changing environment, revision, pending state or admission; it cannot clear a newer pending update. Failed persistence never commits, so pending admission remains blocked. No commit path clears durable uncertainty or grants a capability. `currentPolicyRevision()` reads the barrier's actual revision; supplied execute revision is a stale-UI hint only. T07 later supplies resolved snapshots through this authority boundary, without per-window stores.

Barrier's exact internal shape: `final class PolicyInvalidationBarrier: @unchecked Sendable` with private NSLock and private revision/pending/failure state; every access, including diagnostic snapshot, is locked. It is a private nonisolated let owned by ExecutionCoordinator, never injected or exposed. Define `beginUpdate() throws -> PolicyUpdateTicket`, `snapshot() -> PolicyAdmission`, `commit<Result>(_ ticket: PolicyUpdateTicket, install: () throws -> Result) throws -> Result?`, and `withCurrentPolicy<Result>(revision: UInt64, body: () throws -> Result) throws -> Result` as internal synchronous methods. `commit` returns nil on superseded tickets; it runs install and changes ready state while still locked. `withCurrentPolicy` throws stalePolicy unless ready at exactly the requested revision, and runs its nonescaping, non-async body **while the lock is held**, not after returning a Boolean/permit. The ticket initializer and barrier live together in PolicyInvalidationBarrier.swift; the private registry stays in the coordinator. No caller-supplied closure is exposed through a public coordinator API.

The actual final admission/no-op completion and future mutating submission use `withCurrentPolicy` around their non-suspending commit point, so update begin and dispatch have a defined order. For accepted T03/T04 adapters, the body must contain the actual leaf effect or irreversible start-handshake release, not merely check/copy a permit for later use; no await, queued Task, returned permission, preflight callback or deferred syscall may sit between check and effect start. All slow discovery/preflight/journal preparation occurs outside the lock and is revalidated at the boundary. If a dispatch committed first, that operation is already in flight and drains under S12; a subsequently begun update blocks every later dispatch. If update began first, dispatch is denied. Actual syscall/handshake boundedness and UI responsiveness need T03/T04 acceptance: do not hold this lock across an async effect lifetime, and do not claim that no-op tests prove safe bounded real-file/daemon integration. An adapter unable to supply the required atomic boundary remains unavailable, rather than weakening it to a check-then-dispatch race.

`prepareReview` first checks current durable admission (busy => busy, uncertainty => recoveryBlocked, storage error => storageUnavailable), then supplies only `CleanCatalog.allItems` to the passed real engine. It never accepts caller `CleanPlan`, `PlannedItem`, `ActionDescriptor`, `CleanItem`, identity or executor payload. An engine can be shared or separate, but cannot mint registrations/tokens itself. Snapshot policy/environment before discovery; after await, reject stale policy rather than registering old discovery. Reject duplicate IDs rather than arbitrarily picking one. Register the complete discovery privately, including original canonical targets and captured identities, and return a projection. `setSelection` validates requested IDs first (unknown => unknownSelectedID; known but ineligible => unavailableSelection), then uses T01's production `PlanSelection`. Do not silently intersect and confirm a different selection. Every successful selection replacement, even an identical set, increments planRevision and invalidates previously issued tokens for that plan.

Empty registered selection is allowed at this core boundary, with disposition `noWork`, no effect, no measurements claimed, and normal single-use token consumption. App confirmation stays disabled at selectedCount == 0. Empty selection must not carry denied selected IDs silently discarded by setSelection. `confirm` compares the entire binding to the coordinator-held binding, confirms current policy and admission, rechecks fixed registry for every selected item, and mints one stored token. A fresh confirm for the same revision revokes any older token for that revision. Unknown binding cannot create a registration.

`ConfirmedPlan` issuance must remain in a same-file extension in `ConfirmedPlan.swift`. Its internal `ExecutionCoordinator.mintConfirmedPlan(binding: ReviewBinding) throws -> ConfirmedPlan` calls the actor-isolated internal `reserveConfirmation(binding: ReviewBinding) throws -> (coordinatorID: UUID, nonce: UUID)` after full validation, then invokes the fileprivate initializer. `confirm` delegates to this bridge. Internal immutable token fields allow ExecutionCoordinator.swift to read issuer/nonce; only their construction is fileprivate. The nonce/registration maps remain private to the actor. No API accepts caller nonce strings or exposes a trusted constructor. External clients cannot construct tokens. All token data is held only in memory; relaunch requires new review and never resumes a token.

### Resource capture and T03 boundary

```swift
public enum ResourceIdentity: Hashable, Sendable {
    case filesystem(FileResourceIdentity)
    case simulator(udid: UUID, runtimeID: String)
    case snapshot(volumeID: UUID, exactSnapshotID: String)
}
public struct FileResourceIdentity: Hashable, Sendable {
    public let volumeID: UUID
    public let device: UInt64
    public let inode: UInt64
    public let generation: UInt64?
    public let canonicalPath: String
    public let mode: UInt32
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let parentChain: [FileNodeIdentity]
    public let manifest: ReviewedManifestIdentity?
    // Internal capture-only initializer, not caller-supplied authority.
}
public struct FileNodeIdentity: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let generation: UInt64?
}
public struct ReviewedManifestIdentity: Hashable, Sendable {
    public let digest: Data
    public let batchIDs: [UUID]
    public let nodeCount: Int
    public let encodedBytes: Int
}
enum ResourceCaptureError: Error { case unavailable, unsupported }
enum ResourcePreflight {
    static func captureFile(at path: String) throws -> FileResourceIdentity
    static func unchanged(_ identity: FileResourceIdentity) -> Bool
}
```

The filesystem capture walks parent components without following symlinks, checks local volume identity, and uses no-follow metadata. Missing/denied/unsupported identity is unavailable; never manufacture inode/volume/generation defaults. `unchanged` reacquires the same identity/metadata, returning false on any mismatch or probe error. It is a read-only guard, **not deletion authorization or a race-resistant deletion implementation**. T03 owns anchored descriptors across effect, bounded descendant manifests, protected descendants/mounts, leaf metadata/caps and partial results. Until T03 provides an actual manifest for recursive work, `manifest == nil` means recursive effects cannot be enabled. The stored manifest consists of reviewed batches, each ≤5,000 nodes/8 MiB, not a digest of a later re-enumeration.

Simulator/snapshot variants are reserved representations; they do not enable legacy operations. Capture exact UDID/runtime or volume/snapshot identifiers through an accepted adapter at planning; names, `all`, `unavailable`, and execution-time inventory expansion cannot become identities. Other adapter identity variants must be added with their separately reviewed `.M` contract, not encoded as unvalidated strings here.

### Durable admission contract and T04 boundary

`MutationAdmissionStore` owns one stable `mutation.lock`, durable `bootstrap.json` initialization evidence and `unfinished-effects.json` in a private 0700 journal directory, all owner-only 0600; reject symlinks, foreign owner, unsafe permissions and unsupported format rather than repairing an unknown location. Default app location is the existing app support directory plus `execution`; no arbitrary root from imports. Scratch directory injection in tests changes storage location only, not authorization.

```swift
final class MutationAdmissionStore {
    init(directory: URL) throws
    func acquire() -> MutationAdmission
    func release()                         // releases only this object's FD
    func readAdmissionWhileLocked() -> MutationAdmission
    func persistIntentWhileLocked(_ intent: PendingEffectIntent) throws
    // No clear/reset/mark-finished API in T02. T04 adds verified reconciliation.
}
struct PendingEffectIntent: Codable, Equatable, Sendable {
    let runID: UUID
    let operationID: UUID                  // allocated before submission
    let adapterID: String
    let bootID: UUID
    let executablePath: String
    let executableDevice: UInt64
    let executableInode: UInt64
    let childPID: Int32?
    let childStartSeconds: Int64?
    let childStartMicroseconds: Int32?
    let phase: SubmissionPhase
}
enum SubmissionPhase: String, Codable, Sendable {
    case prepared, submitted, uncertainAndPossiblyRunning
}
```

Initialization evidence JSON is `{"schema":1,"storeID":"<UUID>","state":"initialized"}`. Ledger envelope JSON is `{"schema":1,"storeID":"<same UUID>","unfinished":[<PendingEffectIntent>]}`. **Empty means a valid matching envelope containing an empty array, never a zero-byte or missing file.** Only the first bootstrap may create an empty ledger: the instance must have established an otherwise empty validated private directory and exclusively created the stable lock with O_CREAT|O_EXCL (existing lock is not proof of a new store). While holding its advisory lock, durably publish bootstrap state `initializing`, durably publish the valid empty ledger, then durably replace bootstrap state with `initialized`; synchronize files and directory at each boundary before declaring ready. An incomplete bootstrap is storageUnavailable, not permission to reset; recovery requires separate inspection, never automatic recreation.

On every subsequent open/acquire, require the stable lock, initialized marker and valid same-store envelope. Missing ledger after initialization, missing/zero-byte marker, zero-byte ledger, storeID mismatch, corrupt/truncated/unknown schema/unreadable bytes all mean storageUnavailable and block every mutation. Do not recreate missing files on relaunch. Existing unrelated files in an allegedly new journal directory fail closed. A competing instance that did not exclusively create the lock cannot bootstrap when the marker is missing; it returns busy while held, otherwise storageUnavailable. If bootstrap crashes before durable marker publication, the surviving lock still prevents treating the next launch as a first initialization. No effect is admitted during bootstrap.

Any nonempty unfinished array, including `prepared` with no PID, unknown adapter, different boot or absent child, means uncertainAndPossiblyRunning. Existing record identity is evidence to reconcile, never executable authority. No parser trusts adapterID to bypass the compiled registry. No history retention/reset/delete path may remove the marker, ledger or lock. Releasing a lock, resetting settings, or creating another coordinator cannot remove uncertainty or repair missing initialized state.

Acquire `flock(LOCK_EX | LOCK_NB)` on an opened no-follow stable file, hold the FD through the entire admitted run, and never unlink/replace the lock to release it. `acquire` returns busy for lock contention; after obtaining the lock it checks the ledger, returns uncertainty/storage errors, and retains the FD until release even on those results. Owner may release explicitly or in deinit; coordinator uses defer for all paths. `mutationAdmission` obtains a transient lease, reads durable state and releases it; it conveys no future permission. Every execute reacquires and rechecks. Two open FDs in one test demonstrate lock contention only; a real second-process gate remains mandatory below.

`persistIntentWhileLocked` must atomically publish an owner-only envelope with durable file and directory synchronization before returning. Failure blocks dispatch and does not erase prior ledger bytes. T02 supports writing/reading fail-closed intent even while registry denies all effects. Actual coordinator must never write an effect intent for a quarantined/no-op selection. Tests may seed persisted unfinished records through this production persistence method to simulate startup state; this grants no adapter permission.

T04 owns launch/start handshake, actual boot/executable/start identity acquisition, full run journal, bounded subprocess I/O, daemon operation reconciliation and terminal outcome persistence. A null child start in `prepared` is NOT proof of non-start: any ambiguity blocks. Before accepted subprocess effect: durably persist operation intent; launch only a controlled stopped/waiting child; obtain and durably persist actual child start/executable/boot identity; release its mutation handshake only after persistence. Direct daemon submission requires preallocated adapter operation token and an accepted queryable completion protocol. Unsupported handshake/reconciliation keeps capability unavailable. T02 does not substitute a PID-only marker, an in-memory flag, empty JSON placeholder, free lock, new boot or fresh review for this prerequisite.

## Coordinator execution and result edits

Use one actor and a private state `idle` / `running(runID: UUID)`. Before the first await in execute, reject actor busy, validate issuer/nonce, reserve running, and synchronously try the installation lock. Lock contention releases the reservation and returns busy without consuming the token. Otherwise atomically remove the nonce before continuing; an admitted attempt consumes it even if policy/preflight/storage/uncertainty checks fail. Consumption and reservation cannot be separated by an await. Keep running through all awaiting preflight, effect, drain and durable finalization; actor isolation alone is insufficient. Clear transient running on every terminal return, but do not clear disk uncertainty. Cancellation stops scheduling; T04 decides the in-flight boundary/outcome.

Under the installation lock load the ledger; compare actual policy + hint; validate registered binding and current fixed registry; iterate only registered selected rows in original review order. Before each row and after each await, check current policy revision, cancellation and registered resource identity/preflight. Pass only those sealed identities to eventual internal T03/T04 effect entry. Never call locate, relist snapshots, expand a directory or read a newly changed custom handler. Appends/extra IDs/target changes require prepareReview + explicit confirmation. Once uncertain, no next item may start.

A copied token consumed on the wrong coordinator returns invalidToken and cannot alter its owner's registry. Within the issuing coordinator a consumed/unknown nonce returns invalidToken; an invalidated known nonce may return staleReview/stalePolicy using a bounded rejection record, but cannot be executed again. Tests below require staleReview for selection invalidation and stalePolicy for policy invalidation; retain these reasons only for the in-memory lifetime of the associated registered review. `discardReview` invalidates tokens and removes that review/reasons. Views discard on replacement/window teardown, never cancel another window's active run.

Add `RunReport.disposition: RunDisposition` and `RunReport.coordinatorMeasurementsAvailable: Bool?` with defaulted initializer arguments (`.completed`, nil). Decode older missing fields with these defaults. Coordinator rejection/no-op reports set the appropriate disposition and `coordinatorMeasurementsAvailable = false`, empty results and existing numeric compatibility fields 0. These zeros are legacy storage placeholders, **not observations**: CleanResultsView must render “Not measured” and no reclaimed/space-delta success for these reports. T03 replaces legacy measurements with optional byte observations; no accepted mutation may ship on this transitional report shape. Historical nil retains old presentation until T03 migration. No-op displays “No items selected; nothing was run.” Busy/recovery/stale policy are distinct actionable denial text, not successful empty cleanup.

Raw `CleanEngine.execute(plan:environment:)` becomes internal, unconditional denial-only; retain it temporarily solely for T01's negative core tests. It may never be a real effect route, even after `.M` adapters arrive. Remove production raw call sites and latent broad mutation bodies. A future internal effect operation requires a coordinator-held lease and sealed identities; do not re-enable raw execute. Public `register` may retain denial callbacks for source compatibility but can never supply accepted authority. No UI access via `@testable`.

## Complete safe failing tests: ConfirmedExecutionTests.swift

These tests exercise real catalog discovery, selection, token actor, file identity capture and disk admission store. They contain no host command runner, allow-all policy, fake trusted item, or fake effect. Empty reviews deliberately select nothing; eligible positive mutations remain separately gated. T01 must have removed unsafe discovery before running these tests.

```swift
import Foundation
import Testing
@testable import TidyCore

private struct ExecutionScratch {
    let root: URL
    let home: URL
    let journal: URL
    let leaf: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("T02-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        journal = root.appendingPathComponent("journal", isDirectory: true)
        leaf = home.appendingPathComponent("sentinel")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try Data("preserve me".utf8).write(to: leaf)
    }
    var environment: CleanEnvironment {
        CleanEnvironment(homeDirectory: home.path, detectedTools: [], protectedRoots: [])
    }
    func coordinator() -> ExecutionCoordinator {
        ExecutionCoordinator(environment: environment, journalDirectory: journal)
    }
    func intact() throws { #expect(try Data(contentsOf: leaf) == Data("preserve me".utf8)) }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private func review(_ coordinator: ExecutionCoordinator) async throws -> RegisteredReview {
    try await coordinator.prepareReview(engine: CleanEngine(sizeScanner: SizeScanner()),
                                         tier: .deep, selectDefaults: false)
}

private func persistPolicy(_ coordinator: ExecutionCoordinator,
                           scratch: ExecutionScratch) async throws -> UInt64 {
    let ticket = try coordinator.beginPolicyUpdate()
    try ConfigStore.save(TidyConfig(), to: scratch.home.appendingPathComponent("config.json"))
    let commit = try await coordinator.commitPolicyUpdate(ticket, environment: scratch.environment)
    guard case .applied(let revision) = commit else {
        throw ConfirmationError.stalePolicy
    }
    return revision
}

private func expectConfirmationError(
    _ expected: ConfirmationError,
    _ operation: () async throws -> Void
) async {
    do { try await operation(); Issue.record("Expected \(expected)") }
    catch let error as ConfirmationError { #expect(error == expected) }
    catch { Issue.record("Wrong error: \(error)") }
}

private func interruptedIntent(phase: SubmissionPhase) -> PendingEffectIntent {
    PendingEffectIntent(
        runID: UUID(), operationID: UUID(), adapterID: "legacy.unreconciled",
        bootID: UUID(), executablePath: "/unavailable/previous-child",
        executableDevice: 99, executableInode: 123,
        childPID: nil, childStartSeconds: nil, childStartMicroseconds: nil,
        phase: phase)
}

@Suite("Confirmed execution")
struct ConfirmedExecutionTests {
    @Test("Unknown review cannot mint a token")
    func unknownReview() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let b = ReviewBinding(planID: UUID(), planRevision: 1,
                              policyRevision: 1, selectedIDs: [])
        await expectConfirmationError(.unknownPlan) { _ = try await c.confirm(binding: b) }
        try s.intact()
    }

    @Test("Binding must equal the registered selection, not merely its plan ID")
    func forgedBindingAndUnknownSelection() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let forged = ReviewBinding(planID: r.binding.planID,
            planRevision: r.binding.planRevision, policyRevision: r.binding.policyRevision,
            selectedIDs: ["caller.added.effect"])
        await expectConfirmationError(.staleReview) { _ = try await c.confirm(binding: forged) }
        await expectConfirmationError(.unknownSelectedID) {
            _ = try await c.setSelection(planID: r.binding.planID,
                                         selectedIDs: ["caller.added.effect"])
        }
        let token = try await c.confirm(binding: r.binding)
        let report = await c.execute(token, currentPolicyRevision: r.binding.policyRevision)
        #expect(report.disposition == .noWork)
        #expect(report.results.isEmpty)
        #expect(report.coordinatorMeasurementsAvailable == false)
        try s.intact()
    }

    @Test("Actual quarantined catalog item cannot become selected")
    func productionDenialRemainsMandatory() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let row = try #require(r.plan.reviewItems.first { $0.id == "deep.simulator.erase-all" })
        #expect(!row.review.isSelectable)
        await expectConfirmationError(.unavailableSelection) {
            _ = try await c.setSelection(planID: r.binding.planID, selectedIDs: [row.id])
        }
        let token = try await c.confirm(binding: r.binding)
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .noWork)
        try s.intact()
    }

    @Test("Real no-op token is single-use, and cross-coordinator use cannot consume its owner")
    func tokenReplayAndIssuer() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let owner = s.coordinator(); let other = s.coordinator()
        let r = try await review(owner)
        let token = try await owner.confirm(binding: r.binding)
        #expect(await other.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        #expect(await owner.execute(token, currentPolicyRevision: 1).disposition == .noWork)
        #expect(await owner.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        try s.intact()
    }

    @Test("Concurrent copies of one genuine no-op token cannot both complete")
    func concurrentTokenCopies() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let dispositions = await withTaskGroup(of: RunDisposition.self) { group in
            for _ in 0..<2 {
                group.addTask { await c.execute(token, currentPolicyRevision: 1).disposition }
            }
            var output: [RunDisposition] = []
            for await disposition in group { output.append(disposition) }
            return output
        }
        #expect(dispositions.filter { $0 == .noWork }.count == 1)
        #expect(dispositions.allSatisfy { [.noWork, .busy, .invalidToken].contains($0) })
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        // One-use concurrency only, not positive mutation serialization.
        try s.intact()
    }

    @Test("Selection revision revokes earlier real token and old confirmation binding")
    func changedSelectionRevision() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let old = try await review(c)
        let token = try await c.confirm(binding: old.binding)
        let new = try await c.setSelection(planID: old.binding.planID, selectedIDs: [])
        #expect(new.binding.planRevision == old.binding.planRevision + 1)
        await expectConfirmationError(.staleReview) { _ = try await c.confirm(binding: old.binding) }
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .staleReview)
        let fresh = try await c.confirm(binding: new.binding)
        #expect(await c.execute(fresh, currentPolicyRevision: 1).disposition == .noWork)
    }

    @Test("Actual coordinator policy update invalidates reviews even when old hint is supplied")
    func changedPolicy() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let revision = try await persistPolicy(c, scratch: s)
        #expect(revision == 2)
        await expectConfirmationError(.stalePolicy) { _ = try await c.confirm(binding: r.binding) }
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        let current = try await review(c)
        let second = try await c.confirm(binding: current.binding)
        #expect(await c.execute(second, currentPolicyRevision: 1).disposition == .stalePolicy)
        #expect(await c.execute(second, currentPolicyRevision: 2).disposition == .invalidToken)
        try s.intact()
    }

    @Test("Separate engines share coordinator registration and token ownership")
    func twoEnginesOneCoordinator() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        let a = try await review(c); let b = try await review(c)
        #expect(a.binding.planID != b.binding.planID)
        let ta = try await c.confirm(binding: a.binding)
        let tb = try await c.confirm(binding: b.binding)
        let ra = await c.execute(ta, currentPolicyRevision: 1)
        let rb = await c.execute(tb, currentPolicyRevision: 1)
        #expect(ra.disposition == .noWork && rb.disposition == .noWork)
        // Lifecycle evidence only: no await-spanning mutation happened here.
        try s.intact()
    }

    @Test("Changed and symlink-replaced resource fails real identity probe")
    func changedResourceIdentity() throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let original = try ResourcePreflight.captureFile(at: s.leaf.path)
        #expect(ResourcePreflight.unchanged(original))
        try Data("larger changed payload".utf8).write(to: s.leaf)
        #expect(!ResourcePreflight.unchanged(original))
        let moved = s.home.appendingPathComponent("original")
        try FileManager.default.moveItem(at: s.leaf, to: moved)
        try FileManager.default.createSymbolicLink(at: s.leaf, withDestinationURL: moved)
        #expect(!ResourcePreflight.unchanged(original))
        #expect(throws: (any Error).self) { try ResourcePreflight.captureFile(at: s.leaf.path) }
        #expect(try Data(contentsOf: moved) == Data("larger changed payload".utf8))
    }

    @Test("Stable advisory lock contends across independent store descriptors")
    func instanceLockDescriptors() throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let a = try MutationAdmissionStore(directory: s.journal)
        let b = try MutationAdmissionStore(directory: s.journal)
        defer { a.release(); b.release() }
        #expect(a.acquire() == .ready)
        #expect(b.acquire() == .busy)
        a.release()
        #expect(b.acquire() == .ready)
        // Not claimed as second-process/child-survival verification.
    }

    @Test("Coordinator honors occupied installation lock without consuming the token")
    func coordinatorHonorsInstanceLock() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let holder = try MutationAdmissionStore(directory: s.journal)
        defer { holder.release() }
        #expect(holder.acquire() == .ready)
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .busy)
        holder.release()
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .noWork)
        try s.intact()
    }

    @Test("Unfinished intent survives free lock, new coordinator and policy reset",
          arguments: [SubmissionPhase.prepared, .submitted, .uncertainAndPossiblyRunning])
    func durableUncertainty(phase: SubmissionPhase) async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let writer = try MutationAdmissionStore(directory: s.journal)
        #expect(writer.acquire() == .ready)
        try writer.persistIntentWhileLocked(interruptedIntent(phase: phase))
        writer.release()
        let c = s.coordinator()
        #expect(await c.mutationAdmission() == .uncertainAndPossiblyRunning)
        _ = try await persistPolicy(c, scratch: s)
        #expect(await c.mutationAdmission() == .uncertainAndPossiblyRunning)
        await expectConfirmationError(.recoveryBlocked) { _ = try await review(c) }
        let relaunched = s.coordinator()
        #expect(await relaunched.mutationAdmission() == .uncertainAndPossiblyRunning)
        try s.intact()
    }

    @Test("Uncertainty created after confirmation blocks even a real no-op token")
    func uncertaintyBeforeExecution() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let writer = try MutationAdmissionStore(directory: s.journal)
        #expect(writer.acquire() == .ready)
        try writer.persistIntentWhileLocked(interruptedIntent(phase: .prepared))
        writer.release()
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .recoveryBlocked)
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        try s.intact()
    }

    @Test("First bootstrap persists initialized identity and a valid empty envelope")
    func firstInitialization() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator()
        #expect(await c.mutationAdmission() == .ready)
        let markerData = try Data(contentsOf: s.journal.appendingPathComponent("bootstrap.json"))
        let ledgerData = try Data(contentsOf: s.journal.appendingPathComponent("unfinished-effects.json"))
        let marker = try #require(try JSONSerialization.jsonObject(with: markerData) as? [String: Any])
        let ledger = try #require(try JSONSerialization.jsonObject(with: ledgerData) as? [String: Any])
        #expect(marker["schema"] as? Int == 1)
        #expect(marker["state"] as? String == "initialized")
        let storeID = try #require(marker["storeID"] as? String)
        #expect(UUID(uuidString: storeID) != nil)
        #expect(ledger["storeID"] as? String == storeID)
        #expect(ledger["schema"] as? Int == 1)
        #expect((ledger["unfinished"] as? [Any])?.isEmpty == true)
        #expect(await s.coordinator().mutationAdmission() == .ready)
        try s.intact()
    }

    @Test("Deleting an initialized unfinished ledger never bootstraps an empty replacement")
    func missingInitializedLedgerBlocksRelaunch() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let writer = try MutationAdmissionStore(directory: s.journal)
        #expect(writer.acquire() == .ready)
        try writer.persistIntentWhileLocked(interruptedIntent(phase: .submitted))
        writer.release()
        let marker = s.journal.appendingPathComponent("bootstrap.json")
        let markerBytes = try Data(contentsOf: marker)
        let ledger = s.journal.appendingPathComponent("unfinished-effects.json")
        try FileManager.default.removeItem(at: ledger) // exact disposable fixture only
        let relaunched = s.coordinator()
        #expect(await relaunched.mutationAdmission() == .storageUnavailable)
        _ = try await persistPolicy(relaunched, scratch: s)
        #expect(await relaunched.mutationAdmission() == .storageUnavailable)
        await expectConfirmationError(.storageUnavailable) { _ = try await review(relaunched) }
        #expect(!FileManager.default.fileExists(atPath: ledger.path))
        #expect(try Data(contentsOf: marker) == markerBytes)
        try s.intact()
    }

    @Test("Zero-byte ledger and unknown schema remain blocked and byte-preserved",
          arguments: [Data(), Data("{\"schema\":99,\"unfinished\":[]}".utf8)])
    func invalidInitializedLedger(bytes: Data) async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        #expect(await s.coordinator().mutationAdmission() == .ready)
        let ledger = s.journal.appendingPathComponent("unfinished-effects.json")
        try bytes.write(to: ledger)
        let relaunched = s.coordinator()
        #expect(await relaunched.mutationAdmission() == .storageUnavailable)
        await expectConfirmationError(.storageUnavailable) { _ = try await review(relaunched) }
        #expect(try Data(contentsOf: ledger) == bytes)
        try s.intact()
    }

    @Test("Real settings persistence error leaves production app bridge disabled with error")
    @MainActor
    func settingsSaveFailureBlocksBridge() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let blocker = s.home.appendingPathComponent("not-a-directory")
        let blockerBytes = Data("preserve blocking file".utf8)
        try blockerBytes.write(to: blocker)
        let impossibleConfigURL = blocker.appendingPathComponent("config.json")
        #expect(throws: ConfigSaveError.directoryCreationFailed) {
            try ConfigStore.save(TidyConfig(), to: impossibleConfigURL)
        }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let bridge = ExecutionPolicyBridge(coordinator: c, configURL: impossibleConfigURL,
                                           homeDirectory: s.home.path, detectedTools: [])
        var config = TidyConfig()
        config.transcriptAgeThresholdDays = 90
        let update = bridge.submit(config: config)
        #expect(!bridge.isExecutionEnabled)
        #expect(bridge.policyUpdatePending)
        // No await since submit: the coordinator barrier is already invalidated,
        // independently of whether the persistence Task has started.
        #expect(c.policyAdmission() == .updating(revision: 2))
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        await update.value
        #expect(!bridge.isExecutionEnabled)
        #expect(!bridge.policyUpdatePending)
        #expect(bridge.persistenceError == "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again.")
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .invalidToken)
        await expectConfirmationError(.stalePolicy) { _ = try await review(c) }
        #expect(try Data(contentsOf: blocker) == blockerBytes)
        #expect(!FileManager.default.fileExists(atPath: impossibleConfigURL.path))
        try s.intact()
    }

    @Test("Policy projection copies explicit metadata and restrictions without discovery")
    func purePolicyProjection() throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        var config = TidyConfig()
        config.gitRoots = [s.home.appendingPathComponent("project").path]
        config.keepCookieDomains = ["example.invalid"]
        config.simulatorsApprovedForDeletion = ["inert legacy name"]
        config.appsApprovedForQuit = ["inert legacy app name"]
        config.allowRestartToReclaimSwap = true
        config.staleNodeModulesThresholdDays = 90
        config.transcriptAgeThresholdDays = 120
        let unknown = config.makePolicyEnvironment(homeDirectory: s.home.path, detectedTools: [])
        #expect(unknown.detectedTools.isEmpty)
        #expect(!unknown.hasTool(.git))
        let metadataOnly = config.makePolicyEnvironment(homeDirectory: s.home.path,
                                                        detectedTools: [.git])
        #expect(metadataOnly.detectedTools == [.git])
        #expect(metadataOnly.homeDirectory == s.home.path)
        #expect(metadataOnly.gitRoots == config.gitRoots)
        #expect(metadataOnly.keepCookieDomains == config.keepCookieDomains)
        #expect(metadataOnly.simulatorsApprovedForDeletion == config.simulatorsApprovedForDeletion)
        #expect(metadataOnly.appsApprovedForQuit == config.appsApprovedForQuit)
        #expect(metadataOnly.allowRestartToReclaimSwap)
        #expect(metadataOnly.staleNodeModulesThresholdDays == 90)
        #expect(metadataOnly.transcriptAgeThresholdDays == 120)
        #expect(metadataOnly.protectedRoots == CleanEnvironment.defaultProtectedRoots(homeDirectory: s.home.path))
        // This tests value projection only. A supplied tool ID is not an accepted adapter.
        try s.intact()
    }

    @Test("Two synchronous settings submissions invalidate before queued persistence runs")
    @MainActor
    func settingsSubmissionHasNoDiscoveryPhase() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let r = try await review(c)
        let token = try await c.confirm(binding: r.binding)
        let url = s.home.appendingPathComponent("config.json")
        let bridge = ExecutionPolicyBridge(coordinator: c, configURL: url,
                                           homeDirectory: s.home.path, detectedTools: [])
        var first = TidyConfig(); first.transcriptAgeThresholdDays = 60
        var second = first; second.transcriptAgeThresholdDays = 90
        let a = bridge.submit(config: first)
        #expect(c.policyAdmission() == .updating(revision: 2))
        let b = bridge.submit(config: second)
        #expect(c.policyAdmission() == .updating(revision: 3))
        #expect(!bridge.isExecutionEnabled && bridge.policyUpdatePending)
        // No await above: production MainActor persistence tasks cannot yet run.
        // The next main-actor statement is reachable without a discovery completion.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        await a.value; await b.value
        #expect(ConfigStore.load(from: url) == second)
        #expect(c.policyAdmission() == .ready(revision: 3))
        #expect(bridge.isExecutionEnabled && !bridge.policyUpdatePending)
        #expect(bridge.persistenceError == nil)
        let fresh = try await review(c)
        #expect(fresh.binding.policyRevision == 3)
        let denied = try #require(fresh.plan.reviewItems.first { $0.id == "deep.simulator.erase-all" })
        #expect(!denied.review.isSelectable)
        await expectConfirmationError(.unavailableSelection) {
            _ = try await c.setSelection(planID: fresh.binding.planID, selectedIDs: [denied.id])
        }
        try s.intact()
    }

    @Test("Older persisted update cannot reopen admission while a newer ticket is pending")
    func overlappingPolicyUpdates() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        let c = s.coordinator(); let old = try await review(c)
        let token = try await c.confirm(binding: old.binding)
        let first = try c.beginPolicyUpdate()
        let second = try c.beginPolicyUpdate()
        #expect(c.policyAdmission() == .updating(revision: 3))
        var firstConfig = TidyConfig()
        firstConfig.transcriptAgeThresholdDays = 60
        let configURL = s.home.appendingPathComponent("config.json")
        try ConfigStore.save(firstConfig, to: configURL)
        #expect(try await c.commitPolicyUpdate(first, environment: s.environment) == .superseded)
        // Deterministic interleaving: second persistence/commit has not happened.
        #expect(c.policyAdmission() == .updating(revision: 3))
        await expectConfirmationError(.stalePolicy) { _ = try await review(c) }
        #expect(await c.execute(token, currentPolicyRevision: 1).disposition == .stalePolicy)
        var secondConfig = TidyConfig()
        secondConfig.transcriptAgeThresholdDays = 90
        try ConfigStore.save(secondConfig, to: configURL)
        #expect(try await c.commitPolicyUpdate(second, environment: s.environment) == .applied(revision: 3))
        #expect(c.policyAdmission() == .ready(revision: 3))
        #expect(ConfigStore.load(from: configURL) == secondConfig)
        #expect(try await c.commitPolicyUpdate(first, environment: s.environment) == .superseded)
        #expect(c.policyAdmission() == .ready(revision: 3))
        let fresh = try await review(c)
        #expect(fresh.binding.policyRevision == 3)
        let freshToken = try await c.confirm(binding: fresh.binding)
        #expect(await c.execute(freshToken, currentPolicyRevision: 3).disposition == .noWork)
        try s.intact()
    }

    @Test("Corrupt mandatory ledger is not silently reset")
    func corruptLedger() async throws {
        let s = try ExecutionScratch(); defer { s.cleanup() }
        #expect(await s.coordinator().mutationAdmission() == .ready)
        let path = s.journal.appendingPathComponent("unfinished-effects.json")
        let corrupt = Data("{\"schema\":1,\"unfinished\":[".utf8)
        try corrupt.write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        let c = s.coordinator()
        #expect(await c.mutationAdmission() == .storageUnavailable)
        await expectConfirmationError(.storageUnavailable) { _ = try await review(c) }
        #expect(try Data(contentsOf: path) == corrupt)
        try s.intact()
    }
}
```

Fixture expected outputs are asserted above: actual denied erase-all row stays unselected; genuine empty selection mints and consumes token; supplied IDs do not change immutable registration; updated policy denies old hint/token; real changed/symlinked file fails capture; persisted unfinished record blocks regardless of phase/PID absence and lock release; corrupt bytes remain exact. All cleanup in tests removes only the freshly created UUID scratch root, never app support or ambient home. Add no injected valid capability to these tests.

## Exact app wiring and confirmation lifecycle

`AppExecutionServices` is `@Observable @MainActor final`, created once by `TidyApp` using `@State`. It owns one `let coordinator`, one or more discovery engines, one ExecutionPolicyBridge and the shared AppConfigStore. Load config once into a local value, capture `homeDirectory` once, and use `let detectedTools: Set<ToolchainID> = []` for this foundation's unknown discovery state. Derive the initial environment with `config.makePolicyEnvironment(homeDirectory: homeDirectory, detectedTools: detectedTools)`, construct coordinator with the journal's canonical app-support URL, then construct bridge with the **same** home/snapshot and AppConfigStore in that order. No detector, locator, tool-cache warm-up, background discovery Task or lazy discovery getter may run during service construction. Add `init(tier: Tier, services: AppExecutionServices)` to CleanView and `init(services: AppExecutionServices)` to CustomView. TidyApp passes the same instance to every Clean WindowGroup and Custom window. Delete per-view `ConfigStore.load()`, `CleanEnvironment` snapshot and coordinator construction; engine instances cannot imply separate coordinator instances.

Both view models receive `services`, store `RegisteredReview?` plus local display selection, and call `prepareReview` during load. Toggle/preset handlers compute requested eligible IDs through T01 `PlanSelection`, then await coordinator `setSelection`; replace the UI projection with its returned registration. Disable confirmation while this update is pending; never allow an old returned async response to overwrite a newer interaction (use a monotonically increasing UI request generation and accept only the latest). For invalid selection errors reload the held projection and show the reason; do not fabricate a successful selection.

When opening the confirmation dialog, freeze its displayed `ReviewBinding`. Confirm button sends that frozen binding to `confirm`, then calls `execute(token,currentPolicyRevision:)` with the shared current revision. Do not reconstruct binding from mutable current toggles inside the dialog action. Any toggle/config mutation dismisses the dialog; an already submitted operation is protected by coordinator checks. Catch ConfirmationError in both view models (add Custom `.failed(String)`); do not append RunLog as a successful run on confirmation failure. A RunReport admission denial can be logged as denial with its explicit disposition. Keep advanced memory confirmation separate and unavailable until accepted.

`AppConfigStore.config.didSet` must stop calling the current fire-and-forget save. Its exact app interface becomes `init(config: TidyConfig, bridge: ExecutionPolicyBridge)`, storing those dependencies; didSet calls only `bridge.submit(config: config)`. Do not compute an environment or discovery snapshot as a call argument: Swift evaluates arguments before entering submit and hence before its invalidation. AppExecutionServices creates the coordinator and bridge first, then this store from the initially loaded config. AppConfigStore does not own a second bridge. Services forwards bridge's `isExecutionEnabled`, `policyUpdatePending` and `persistenceError`; every review/confirm button and both view-model confirmation entry points require enabled and not pending. Show persistenceError visibly; no force-enable/retry-cleanup button. An explicit subsequent settings save may restore availability only after actual persistence and policy-update success, never by clearing a UI error.

### Pure policy projection; discovery remains a separate gated responsibility

The existing `TidyConfig.makeEnvironment` calls `ToolchainDetector.detect`, which calls `ToolLocator`; an uncached locator first tries `xcrun --find` and synchronously `waitUntilExit`, behind its own four-job semaphore rather than the shared runner budget. Therefore the earlier proposed didSet expression and eager initial environment derivation would block before invalidation/on launch. This corrects that **task-card mechanism**, not an already implemented T02 bridge. Moving the same discovery into a MainActor Task, into submit before beginPolicyUpdate, or behind a computed snapshot property does not fix it.

Add this method inside TidyConfig. Both inputs are explicit values, with no discovery-bearing default or callback. It is a pure value projection: no filesystem metadata, executable resolution, process/cache access, actor hop or asynchronous work. `defaultProtectedRoots` currently only concatenates strings; preserve that purity. The legacy helper may delegate its field mapping here, but T02 startup/settings paths never call that legacy helper.

```swift
public func makePolicyEnvironment(homeDirectory: String,
                                  detectedTools: Set<ToolchainID>) -> CleanEnvironment {
    CleanEnvironment(
        homeDirectory: homeDirectory,
        detectedTools: detectedTools,
        gitRoots: gitRoots,
        protectedRoots: CleanEnvironment.defaultProtectedRoots(homeDirectory: homeDirectory),
        keepCookieDomains: keepCookieDomains,
        simulatorsApprovedForDeletion: simulatorsApprovedForDeletion,
        staleNodeModulesThresholdDays: staleNodeModulesThresholdDays,
        transcriptAgeThresholdDays: transcriptAgeThresholdDays,
        appsApprovedForQuit: appsApprovedForQuit,
        allowRestartToReclaimSwap: allowRestartToReclaimSwap
    )
}
```

The bridge holds an immutable already-materialized metadata snapshot and derives each committed environment from the **same config value actually saved**. Submit accepts neither an independently supplied environment nor a resolver/probe closure. This prevents saving one config while installing another policy. Tool-presence metadata never grants executable identity, registry membership, local consent, ownership/quiescence or preflight success. Unknown/unavailable tools fail closed; `[]` means not discovered here, not a verified absence or successful inventory. Old name approvals/restart visibility remain inert under quarantine.

T02 deliberately performs no tool refresh: tool-dependent inventory remains unavailable even on explicit review until the separate discovery work is accepted. This is a foundation limitation, not removal of the product's complete inventory requirement or evidence that useful cleanup works. T08 must retain discovery functionality through explicit, bounded, off-main, shared-budget work; no auto-start during launch/settings. Before any future snapshot replacement can affect planning, it must be bound to a fresh coordinator invalidation/update and install coherently with the latest saved config. A late result from an older discovery/config revision must not overwrite newer state, revive old reviews or clear a pending/failed persistence update. Do not add such a refresh API or a parallel policy authority in this card. The legacy ScanViewModel/OnboardingViewModel and other locator paths still require their own T08 audit; this change does not certify them.

### Minimal throwing persistence and real production bridge

Replace only `ConfigStore.save` with this implementation and add the error enum in the same production file. Do not leave a swallowing overload callable from the app. Existing core save tests become `throws` and use `try`; search all `ConfigStore.save` call sites and make their propagation explicit. Default URL absence is an error, not a silently successful save. Full read/schema migration, preservation of corrupt/future configurations and import recovery remain T05; this change supplies the minimum T02 save-error boundary and does not claim full configuration migration correctness.

```swift
public enum ConfigSaveError: Error, Equatable, Sendable {
    case unavailableLocation, encodingFailed, directoryCreationFailed, writeFailed
}

// Replace the existing method inside ConfigStore:
public static func save(_ config: TidyConfig,
                        to url: URL? = ConfigStore.defaultURL) throws {
    guard let url else { throw ConfigSaveError.unavailableLocation }
    let data: Data
    do { data = try JSONEncoder().encode(config) }
    catch { throw ConfigSaveError.encodingFailed }
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch { throw ConfigSaveError.directoryCreationFailed }
    do { try data.write(to: url, options: .atomic) }
    catch { throw ConfigSaveError.writeFailed }
}
```

Create `ExecutionPolicyBridge.swift` with this complete production implementation. It accepts the real coordinator, storage URL and immutable home/tool metadata values, not an injected success/failure closure or alternate policy. The app bridge uses this exact type, so the deterministic regular-file-as-parent scratch test above checks production state, not a test reimplementation. Synchronous submit disables UI **and calls coordinator.beginPolicyUpdate before environment projection, any Task creation or await**; its only argument is the edited config value. Saves chain in edit order; the opaque ticket binds each completion, so a previous completion cannot reopen admission after a later submit. Only the latest edit controls visible pending/error/enabled state, but the coordinator's barrier is authoritative even if UI state is stale. T02 conservatively invalidates every config edit; T07 later separates presentation revisions. A failed save never reaches commitPolicyUpdate.

```swift
import Foundation
import Observation

@Observable @MainActor
public final class ExecutionPolicyBridge {
    public private(set) var isExecutionEnabled = true
    public private(set) var policyUpdatePending = false
    public private(set) var persistenceError: String?
    private let coordinator: ExecutionCoordinator
    private let configURL: URL?
    private let homeDirectory: String
    private let detectedTools: Set<ToolchainID> // metadata only, no lazy getter/refresh
    private var generation = UUID() // UI update identity, never execution authority
    private var pending: Task<Void, Never>?

    public init(coordinator: ExecutionCoordinator, configURL: URL?,
                homeDirectory: String, detectedTools: Set<ToolchainID>) {
        self.coordinator = coordinator
        self.configURL = configURL
        self.homeDirectory = homeDirectory
        self.detectedTools = detectedTools
    }

    @discardableResult
    public func submit(config: TidyConfig) -> Task<Void, Never> {
        isExecutionEnabled = false
        policyUpdatePending = true
        persistenceError = nil
        let next = UUID()
        generation = next
        let ticket: PolicyUpdateTicket
        do { ticket = try coordinator.beginPolicyUpdate() }
        catch {
            policyUpdatePending = false
            persistenceError = "Settings could not be applied. Cleanup remains disabled."
            return Task {}
        }
        let environment = config.makePolicyEnvironment(homeDirectory: homeDirectory,
                                                       detectedTools: detectedTools)
        let previous = pending
        let task = Task { [self] in
            await previous?.value
            do {
                try ConfigStore.save(config, to: configURL)
                let commit = try await coordinator.commitPolicyUpdate(ticket, environment: environment)
                if generation == next {
                    policyUpdatePending = false
                    if case .applied(let revision) = commit,
                       coordinator.policyAdmission() == .ready(revision: revision) {
                        persistenceError = nil
                        isExecutionEnabled = true
                    } else {
                        isExecutionEnabled = false
                        persistenceError = "A newer settings update is pending. Cleanup remains disabled."
                    }
                }
            } catch {
                if generation == next {
                    policyUpdatePending = false
                    isExecutionEnabled = false
                    persistenceError = "Settings could not be saved. Cleanup remains disabled. Fix the settings storage location and save again."
                }
            }
        }
        pending = task
        return task
    }
}
```

`beginPolicyUpdate` failure (including revision overflow) itself leaves the barrier unavailable; never make invalidation failure a ready state. Ticket construction is inaccessible to app callers, and commit is internal to the core production bridge; no UI reset/force-enable method exists. The bridge's returned task is a completion handle for app lifecycle/tests only; callers must not cancel it to revert policy. App shutdown drains pending persistence or retains disabled state; no cleanup is submitted until this bridge is enabled. This is minimal persistence failure propagation with synchronous invalidation, not T05's migration/backup/recovery implementation and not T07's full settings authority store.

### Deterministic no-probe wiring acceptance and responsiveness boundary

Before executing the new tests, independently inspect the real source call graph for the complete service-construction and didSet/submit paths (including default arguments and lazy properties). Required source evidence: the startup snapshot is a literal empty value, the only didSet call is `bridge.submit(config: config)`, the pure projection has exactly the field mapping above, and beginPolicyUpdate precedes that projection in submit. No path to `makeEnvironment`, `ToolchainDetector`, `ToolLocator`, Process, a scan or cache warm-up is permitted. Do not use a warm global locator cache as evidence of zero probes. Record the old proposed expression as the source-wiring RED and the revised production call graph as GREEN; a grep with no direct matches alone cannot prove transitive purity.

`purePolicyProjection`, `settingsSubmissionHasNoDiscoveryPhase` and the updated ConfigStore field test are complete deterministic RED inputs above: the new API initially does not exist; after implementation they use explicit scratch homes and metadata only. The two-submit test checks real synchronous barrier revisions before either persistence task can run, then real disk ordering/latest commit and continued registry denial. The existing failure test still proves invalidation before a failed save completes. No test starts an ambient executable, hangs a real xcrun, invents an accepted capability, replaces policy or claims a fake successful mutation. Projection values plus source-wiring inspection establish no discovery on this path; value assertions alone are not a probe-count test.

The app source acceptance must additionally trace TidyApp's one shared AppExecutionServices initialization and the actual AppConfigStore setter used by Settings, Clean and Custom. In the later app/UI harness, use loaded scratch config and scratch journal/config URLs only; construct the real services without requesting a scan/onboarding discovery, edit settings twice, and verify launch completion, immediate updating state, disabled confirmation across windows and a subsequent main-actor UI event without waiting for any discovery result. This is a required app-wiring gate, not satisfied by constructing only the core bridge; add complete app-harness test code at that gate before claiming it verified. No production probe injection or allow-all registry is needed because this path intentionally has no discovery dependency.

This correction removes the discovery-caused startup/pre-invalidation stall only. The shown save Task still inherits MainActor and calls synchronous ConfigStore.save; initial ConfigStore.load and mandatory journal setup also involve I/O. Their slow-storage latency and future lock-held real-effect boundedness are **not** established by these no-probe tests. A serialized off-main persistence/startup-I/O design needs separate reviewed T05 integration before claiming full launch/settings responsiveness; do not silently change persistence ordering or claim an app latency bound here.

## Ordered implementation / verification steps

- [ ] Review this card and T01 dependency interfaces before source changes. Confirm empty core reviews are a real no-op contract, never a cleanup success or adapter test bypass.
- [ ] Add the entire test file; run `cd TidyCore && swift test --filter ConfirmedExecutionTests` in the isolated worktree only after controller confirms baseline jobs are idle. Expected initial RED: absent ConfirmedPlan/ExecutionCoordinator/MutationAdmissionStore/resource types, not a host mutation.
- [ ] Add opaque registration/token contracts and implement negative/no-op lifecycle with explicit state. Run focused tests; capture behavioral RED/GREEN for unknown bindings, stale policy/review and replay. No test claims mutated anything.
- [ ] Add production no-follow identity capture and the minimal durable store with lock, initialized-state marker, atomic/synchronized bootstrap/intent writes, corrupt-file preservation. Run first-initialization, missing-initialized-ledger, zero-byte and unknown-schema tests as well as existing uncertainty tests; inspect owner-only modes. Disk-write failure must return storageUnavailable; never swallow it as ready or recreate a missing initialized ledger.
- [ ] Wire the one app-owned coordinator and frozen dialog binding through both surfaces, including config bridge and report availability. Internalize raw execution as denial-only. Search `rg 'execute\(plan:|ExecutionCoordinator\(' Tidy TidyCore/Sources` and review every match; app has exactly one coordinator construction and no raw execute caller. Core raw compatibility entry has no effect body.
- [ ] Add pure makePolicyEnvironment and migrate the existing ConfigStore field test before running the prescribed focused suite. Review `rg 'makeEnvironment|makePolicyEnvironment|ToolchainDetector|ToolLocator|submit\(config:' Tidy TidyCore/Sources TidyCore/Tests/TidyCoreTests/ConfigStoreTests.swift` plus transitive/default/lazy call paths against the no-probe wiring gate above. Record source-wiring RED/GREEN and run the supplied pure projection/two-submit tests. Bootstrap uses unknown metadata; no automatic/background discovery is introduced. Leave full T08 discovery/refresh and T05 app latency acceptance explicitly open.
- [ ] Replace ConfigStore.save with its throwing API, adjust existing successful-save tests and connect the exact ExecutionPolicyBridge and coordinator-owned synchronous barrier. Run `cd TidyCore && swift test --filter 'ConfirmedExecutionTests|ConfigStoreTests'`; the deterministic non-directory-parent test must observe `.updating` without an intervening await after submit, reject the old token before awaiting persistence completion, and retain disabled/error state. Run overlappingPolicyUpdates: a saved older ticket must leave the newer update pending until its own save/commit. Inspect final no-op admission and future dispatch contract to reject check-then-dispatch permits; UI disabling alone is not evidence. Full T05 migration and T03/T04 actual effect-race/boundedness acceptance are not asserted here.
- [ ] Compile-negative public API check: in a temporary external Swift client importing TidyCore (without `@testable`), independently verify `ConfirmedPlan()`, `ConfirmedPlan(coordinatorID: UUID(), nonce: UUID())`, reading an issued token's `nonce`, and `engine.execute(plan: plan, environment: environment)` fail for inaccessible API. Obtain module search flags from the local build, do not assert rejection based on missing import/module. The real no-op token tests demonstrate the public execute API remains usable with legitimately issued tokens; the coordinator source in another file can read internal immutable issuer/nonce without exposing them to external clients.
- [ ] Run `cd TidyCore && swift test --filter ConfirmedExecutionTests`, then controller-approved full suite after T01 host-effect audit. Expected focused GREEN for the supplied cases; record that positive mutation gates below are still open. Do not disable old quarantine tests to make this pass.
- [ ] Regenerate project if required; controller schedules `xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-build build CODE_SIGNING_ALLOWED=NO`. No signing/release changes. Build evidence is not device E2E.
- [ ] Independent source/diff review checks private immutable registry, no alternate coordinator ownership, no unsafe token initializer, no policy injection, actor reservation spanning awaits, ledger permanence, exact app call sites and all unresolved gates. No commit is authorized by this card.

## Mandatory unresolved integration gates (not completed by all-denied tests)

These are precise acceptance dependencies, not hidden implementation placeholders. Do not begin positive mutation tests without the reviewed production fixture and complete executable test code added at that integration entry gate.

| Gate | Prerequisite / fixture | Required observed result |
|---|---|---|
| Selected effects ≤ review ≤ discovery | Accepted in-scope `.M` adapter discovers three genuine disposable supported resource identities A/B/C through its production parser/planner; real selection is A/C; recorder at its effect-only transport | Exactly A then C, never B; later inventory D never appears; token records exact original identities; successful positive selection in both T01 surfaces |
| Mutation serialization across awaits | Same accepted adapter + T04 effect-only controllable transport whose first A submission remains in flight; two real reviews on one coordinator, distinct engines/windows | While A is suspended, second execute returns busy and zero second submissions; after adapter completion + durable finalization it can execute its unconsumed token; max simultaneous mutating submissions exactly 1, with at least one actual authorized submission |
| Per-item policy recheck | A/C accepted fixture; synchronous beginPolicyUpdate while C is preflighted but before its actual dispatch boundary; first update's save completion overlaps a second pending ticket | A only; C explicitly stale-policy/skipped, no C syscall/handshake release. Older commit cannot reopen newer pending admission. Instrument the real barrier-protected effect-start boundary and inverse ordering (already-started A drains). No async gap/returned permit is allowed between check and actual dispatch; verify lock handoff boundedness and UI responsiveness |
| Per-item identity/preflight | T03 anchored deletion + accepted manifest fixture; replace C inode/grow leaf/add child/start an owner after review | Only approved unchanged leaves; C/new child retained and reported; no broader rediscovery; stale identity test must reach accepted preflight, not stop at quarantine |
| Exact tool identifiers | Accepted Apple.M fixture with two actual provisioned disposable simulator identities or explicitly provisioned snapshots | Only selected UDID/exact snapshot IDs used; rename/new inventory does not expand effects; unsupported privilege/interruption contract remains denied |
| Two processes | T04 compiled disposable helper executable holds real journal lock while another process opens same directory | Second instance busy; abrupt first-process death frees lock but unfinished intent still blocks new mutation; no reliance on same-process-only descriptor test |
| Submission and surviving effects | T04 compiled child/adapter fixture through real launcher + handshake; crash before intent, after intent, after child creation, after handshake and with daemon job alive | No effect before durable identity/intent; ambiguity persisted as uncertainAndPossiblyRunning; PID reuse/boot change cannot clear; no mutation/retry until accepted positive reconciliation |
| App ownership and UI | T05 UI harness opens two Clean windows plus Custom with same AppExecutionServices | Same coordinator identity, exact frozen selection in confirmation, policy edits invalidate every dialog, busy shows as busy; real accepted selected/deselected parity verified |

The first narrow supported adapter is accepted in its already planned `.M` work unit, with explicit version/locality/ownership/preflight/completion contract and T03/T04 prerequisites; do not invent a tool ID or activate old broad commands. Completion of these gates is necessary to close T02 and restore useful supported cleanup. Until then report “T02 foundation implemented/verified; positive mutation and recovery integration incomplete,” not “sealed execution complete” or “cleanup works.”
