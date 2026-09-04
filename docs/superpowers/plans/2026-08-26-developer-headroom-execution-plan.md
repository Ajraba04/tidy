# Developer Headroom and Full Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task, or superpowers:subagent-driven-development when the user authorizes implementation delegation. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a customizable, low-overhead developer headroom manager with safe defaults, truthful evidence and comprehensive but bounded ecosystem coverage.

**Architecture:** Preserve the existing SwiftUI shell and local TidyCore package. Introduce a revisioned policy store, typed resource inventory, sealed execution selections and one execution coordinator, followed by shared resource budgeting, project-aware planning and compiled-in tool adapters.

**Tech Stack:** Swift, SwiftUI/Observation, Swift Testing, XCTest UI tests, Foundation, Dispatch, CoreServices/FSEvents, AppKit, native SQLite3; macOS 14+; x86_64 and arm64.

**Binding design:** [Product contract](../specs/2026-08-26-developer-headroom-design.md).
**Binding appendix:** [Settings registry, profiles and adapter contracts](../specs/2026-08-26-headroom-policy-and-adapter-contracts.md).
**Baseline:** `db4707f`, `v1.5.0`; working tree verified clean on 2026-08-26 before writing these documents.
**State:** Full execution authorized by the user's follow-up. Implementation is in progress on `CAJ/developer-headroom`; see [current evidence](../../verification/headroom-progress.md). Unchecked acceptance gates remain unproven.
**Independent review:** Accepted for program adoption after three passes; see [findings and final verdict](2026-08-26-developer-headroom-adversarial-review.md). Per-unit task cards and implementation verification remain mandatory.

## Global Constraints

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

Design requirements S01–S16 and every registry/default row apply to every task. Performance numbers are proposed acceptance gates, not existing benchmark results.

## 1. Delivery structure and dependency order

This is a program execution plan for multiple independently testable subsystems, not one large feature commit. The task contracts below define files, behavior, interfaces and acceptance. Implement one task at a time; take each listed RED/GREEN case through its own short test → implementation → test cycle rather than writing a whole subsystem before testing it.

Execution-entry gate: before each work unit, produce a narrow task card with the exact production signatures, complete failing test code, fixture inputs/outputs and proposed file edits, then review that card. The snippets here are illustrative contracts, NOT sufficient task acceptance. The 24 packages cover the full product; they are not represented as 24 small commits or copy-paste-complete implementations. T15–T20 expand into separately reviewable per-adapter inventory (.I) and mutation/denial (.M) units, as specified in the appendix.

| Stage | Tasks | Usable result | Depends on |
|---|---|---|---|
| A — Trust foundation | T01–T05 | Honest selectable plans, guarded execution, recovery, migrated settings | Existing app |
| B — Customization | T06–T07 | Complete policy controls, profiles/import preview, shared live settings | A |
| C — Low-impact engine | T08–T10 | Cancellable scans, bounded index and accurate headroom signals | A, policy types from B |
| D — Developer workflows | T11–T13 | Projects, working-set protection, ranked Build Prep | B, C |
| E — Bounded integrations | T14–T20 | Rescue and broad inventories with narrowly supported cleanup | D |

**Progress 2026-09-04:** Packages A, B and C (T01–T10) are implemented, independently reviewed per work unit and merged to `main` from `CAJ/developer-headroom`; the full core suite passed at the merged tree (623 tests in 63 suites, exit 0). Checked boxes below mark implementation and test evidence recorded in `docs/verification/` (per-unit files plus `headroom-progress.md`). Still open within that scope: physical-device acceptance (8 GiB Intel, macOS 14 smoke, VoiceOver/contrast on hardware — gated in T23), T07.3d dependency-bound data clearing, and the T22.3/T22.4 items dependency-bound to optional maintenance. T11–T24 have not been started.
| F — Assistance and acceptance | T21–T24 | Budgets, optional maintenance, device/performance evidence, handoff | E |

No later stage may reintroduce broad hidden tool actions to make a feature work. A blocked adapter remains visibly read-only; that is not an executor fallback. Stage A may temporarily have fewer cleanup capabilities than v1.5.0: unverified legacy effects are quarantined first, then restored individually after their acceptance gates.

## 2. Repository map and ownership

Existing paths are relative to repository root. New files are deliberately grouped by feature responsibility rather than a repository-wide reorganization.

| Responsibility | Existing files to evolve | New files |
|---|---|---|
| Plan visibility/selection | `Model/CleanPlan.swift`, `Model/CleanItem.swift`, `Clean/CleanPlanView.swift`, both Clean/Custom view models | `Model/ActionDescriptor.swift`, `Tidy/Clean/PlanSelectionModel.swift` |
| Execution authorization | `Engine/CleanEngine.swift`, `DefaultCustomActionExecutors.swift`, `Safety/PathGuard.swift` | `Execution/CapabilityRegistry.swift`, `ConfirmedPlan.swift`, `ExecutionCoordinator.swift`, `ResourcePreflight.swift`, `GuardedFileDeleter.swift` |
| Outcomes/recovery | `Model/RunReport.swift`, `Engine/RunLog.swift`, `Clean/CleanResultsView.swift` | `Execution/RunJournal.swift`, `Model/ResourceIdentity.swift` |
| Configuration | `Model/TidyConfig.swift`, `Engine/ConfigStore.swift`, `Settings/AppConfigStore.swift` | `Policy/SettingsEnvelope.swift`, `SettingsStore.swift`, `PolicyResolver.swift`, `PolicyValidator.swift`, `SettingsTransfer.swift` |
| Scanning | `Measure/HomeSurvey.swift`, `SizeScanner.swift`, `Engine/ScanEngine.swift`, `Exec/ProcessRunner.swift` | `Scanning/WorkScheduler.swift`, `ScanIndex.swift`, `ScanInvalidation.swift`, `ScanSession.swift` |
| Signals | `Measure/DiskStats.swift`, `MemoryStats.swift`, `SwapStats.swift`, `MenuBar/StatsRefresher.swift` | `Monitoring/SystemSnapshot.swift`, `SystemMonitor.swift`, `SignalHistory.swift` |
| Projects/planning | `Detect/GitRepoScanner.swift`, `GitRootDiscovery.swift`, catalog files | `Projects/ProjectInventory.swift`, `ActivityResolver.swift`, `Planning/CandidateRanker.swift`, `HeadroomPlanner.swift` |
| Integrations | `Exec/ToolLocator.swift`, `Model/CleanAction.swift`, `Model/ToolchainID.swift` | `Integrations/ToolAdapter.swift` and per-ecosystem files in T15–T20 |
| Assistance | Existing app scenes/settings | `Assistance/BudgetEvaluator.swift`, `MaintenanceRules.swift`, `Tidy/Headroom/*`, `Tidy/Projects/*`, `Tidy/Settings/*` |

Unless prefixed `Tidy/`, core paths in this table begin `TidyCore/Sources/TidyCore/`. Each task's Files block gives full repository-relative paths.

## 3. Execution discipline and test commands

Before implementation, read the current instructions, verify branch/worktree state and use an isolated `CAJ/` branch/worktree. Preserve unrelated changes. Record the baseline results again; the 2026-08-24 results (174 tests/35 suites and Debug build) are historical, not a current release gate.

For each task:

1. Write one named failing regression/contract test from the task.
2. Run its exact `swift test --filter` command and record the intended failure.
3. Implement the named behavior, including explicit unavailable/denied/error paths.
4. Run the focused suite, then the full core suite; run app build for app/API changes.
5. Inspect diff, requirements coverage and safety effects. Commit only that task's intentional file allowlist when execution authority includes commits. Never mass-stage.

Standard commands (repository root unless noted):

```sh
cd TidyCore
swift test
```

```sh
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-build \
  build CODE_SIGNING_ALLOWED=NO
```

UI tests are added in T05. Their run uses a dedicated test-only host with an injected fixture home and fake executors; never the user's configured home.

```sh
xcodebuild -project Tidy.xcodeproj -scheme TidyUITests \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-ui \
  test
```

XcodeGen is the project source of truth: modify `project.yml` and regenerate `Tidy.xcodeproj/project.pbxproj` together. Toolchain/signing/environment failures are reported separately from code failures. Do not weaken assertions to make a machine-dependent test green.

Contract snippets below define behavior and interfaces, not permission to bypass their surrounding acceptance criteria. Test fixtures must be local, injected and deterministic. No test calls a mutating host command.

## T01 — Make every action visible, selectable and honestly classified

**Files**
- Modify: `TidyCore/Sources/TidyCore/Model/{CleanPlan,CleanItem,CleanAction}.swift`
- Modify: `TidyCore/Sources/TidyCore/Catalog/CleanCatalog+{Helpers,Xcode,Memory}.swift`
- Modify: `Tidy/Clean/{CleanPlanView,CleanViewModel}.swift` and `Tidy/Custom/{CustomView,CustomViewModel}.swift`
- Create: `TidyCore/Sources/TidyCore/Model/ActionDescriptor.swift`
- Create: `TidyCore/Sources/TidyCore/Execution/CapabilityRegistry.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/{CleanEngine,DefaultCustomActionExecutors,GitHousekeeper}.swift`
- Create: `Tidy/Clean/PlanSelectionModel.swift`
- Test: `TidyCore/Tests/TidyCoreTests/PlanVisibilityTests.swift`

**Consumes:** current CleanItem, CleanAction, PlannedItem.
**Produces:** explicit review status independent of target count; shared selection model; stable selected action IDs.

```swift
public enum ReviewStatus: String, Codable, Sendable {
    case available, noWork, unavailable, blocked
}
public struct ActionDescriptor: Sendable {
    public let id: String
    public let status: ReviewStatus
    public let reason: String
    public let requiresPerRunOptIn: Bool
    public var isSelectable: Bool { status == .available }
}
```

- [x] RED: empty-target command remains a visible row; blocked/no-work rows show reasons; a zero-byte memory action is visible; all modes use the same rows/counts/selection.
- [x] Run `cd TidyCore && swift test --filter PlanVisibilityTests`; expect regression against target-count filtering.
- [x] Replace nonEmptyItems as the UI/execution predicate. Status is assigned by action-specific discovery, not inferred from bytes/targets. Plain missing paths are noWork; supported targetless commands can be available.
- [x] Add a default-deny capability registry at the EFFECT boundary. Every legacy item without an accepted exact-scope, ownership/activity, local-only, interruption and recovery contract is quarantined. Audit ALL catalog IDs now, including filesystem actions/custom executors; not just tool commands. Broad npm/brew/pod/uv/pnpm/deno/Go commands, remote prune, immediate Git gc, worktree prune and forced lock removal are unavailable. Registration, presets, handcrafted plans and UI bypass cannot grant capability.
- [x] Re-enable only individually accepted contracts through compiled-in registry changes and their adversarial tests. Production API exposes no “allow all”/test-bypass flag. Mutations remain blocked even if old UI calls raw execute before T02 lands.
- [x] Remove `deep.simulator.erase-all` as an executable capability. Legacy preset entry is preserved as unavailable, not remapped to another destructive action.
- [x] Make all tier plans individually deselectable. Cost/risk warnings appear in standard and Custom rows. Memory purge/restart are separate advanced confirmations, never automatically selected by Deep.
- [x] GREEN: review count equals selected executable count; accepted tool-only fixture plans are actionable; deselected/quarantined actions never invoke recording executors through any entry point. Full core test/build and intentional diff checkpoint.

Test seed (add in the named test file with `import Testing` and `@testable import TidyCore`):

```swift
@Test func targetlessOperationHasExplicitReviewState() {
    let action = ActionDescriptor(id: "tool.test", status: .available,
        reason: "Exact supported command", requiresPerRunOptIn: false)
    #expect(action.isSelectable)
}
```

## T02 — Seal selections and serialize execution across windows

**Files**
- Create: `TidyCore/Sources/TidyCore/Execution/{ConfirmedPlan,ExecutionCoordinator,ResourcePreflight}.swift`
- Create: `TidyCore/Sources/TidyCore/Model/ResourceIdentity.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/{CleanEngine,DefaultCustomActionExecutors}.swift`
- Modify: `Tidy/TidyApp.swift`, both Clean/Custom view models
- Test: `TidyCore/Tests/TidyCoreTests/ConfirmedExecutionTests.swift`

**Consumes:** T01 selection, canonical targets, current environment.
**Produces:** app-scoped ExecutionCoordinator; engine-issued confirmation token binding exact plan revision, selected IDs, resource identities and policy revision. Raw-plan execute becomes internal and unreachable from UI.

```swift
public struct ReviewBinding: Equatable, Sendable {
    public let planID: UUID
    public let planRevision: UInt64
    public let policyRevision: UInt64
    public let selectedIDs: Set<String>
    public func matches(_ other: Self) -> Bool { self == other }
}
// ConfirmedPlan has no public memberwise initializer.
// ExecutionCoordinator.confirm(binding:) throws -> ConfirmedPlan
// ExecutionCoordinator.execute(_:currentPolicyRevision:) async -> RunReport
// Only coordinator-held plans may be confirmed; tokens are single-use.
```

- [x] RED: forged/consumed/stale token; changed selection; changed settings; two windows; two engines; changed resource identity; unknown selected ID.
- [x] Run `cd TidyCore && swift test --filter ConfirmedExecutionTests`; expect missing contract failures.
- [x] Store registered plans privately in the coordinator; create single-use opaque tokens after matching full review binding. Recheck revision before each item, not just run start.
- [x] Capture exact snapshot identifiers at planning; delete those only. Capture simulator UDIDs, never names. No operation may rediscover a broader set at execution.
- [x] Share one coordinator from TidyApp. Actor reentrancy must not allow a second run across awaits: explicit running state rejects concurrent requests with a busy result. Detect another Tidy process using an advisory lock on the private journal directory. The durable uncertain-effect ledger overrides a free lock: Tidy process death never proves child/daemon completion.
- [x] Persist boot ID, child executable/start identity and adapter operation token before mutating submission. Use a start handshake where needed so no effect precedes durable intent. Crash in a submission ambiguity window yields uncertainAndPossiblyRunning, never an assumed unstarted effect.
- [x] GREEN: selected ≤ reviewed ≤ discovered invariant and single-run invariant hold under concurrent tasks. No raw plan call sites remain. Full tests/build and diff checkpoint.

```swift
@Test func policyChangeInvalidatesReview() {
    let id = UUID()
    let old = ReviewBinding(planID: id, planRevision: 1,
        policyRevision: 4, selectedIDs: ["cache"])
    let changed = ReviewBinding(planID: id, planRevision: 1,
        policyRevision: 5, selectedIDs: ["cache"])
    #expect(!old.matches(changed))
}
```

## T03 — Guard actual filesystem effects and partial results

**Files**
- Create: `TidyCore/Sources/TidyCore/Execution/GuardedFileDeleter.swift`
- Modify: `TidyCore/Sources/TidyCore/Safety/PathGuard.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/CleanEngine.swift`
- Modify: `TidyCore/Sources/TidyCore/Model/RunReport.swift`
- Test: `TidyCore/Tests/TidyCoreTests/GuardedDeletionTests.swift`

**Consumes:** selected ResourceIdentity, policy protections, coordinator lease.
**Produces:** per-target outcomes; checked allocated-byte observations; denied/partial status.

```swift
public enum EffectStatus: String, Codable, Sendable {
    case succeeded, partial, failed, skipped, cancelled, uncertain
}
public struct ByteObservation: Codable, Equatable, Sendable {
    public let bytes: Int64?
    public let explanation: String?
}
```

- [x] RED: descendant exclusion under a deletable parent; symlink swap; replaced directory inode; mounted child volume; same-prefix sibling; permission-denied child; removed target; hardlinks/clones; new children/growing files; cancellation/deadline during many-file deletion; cap exhaustion mid-batch; unchanged bytes after failed tool.
- [x] Run `cd TidyCore && swift test --filter GuardedDeletionTests`.
- [x] Anchor to validated directory file descriptors; walk children no-follow; refuse device/inode changes and protected ancestors/descendants. Use unlinkat-style relative operations for catalog-approved trees; refuse unsafe races, do not retry through a fresh path.
- [x] Bind the reviewed descendant manifest digest to confirmation. Each batch is ≤5,000 nodes/8 MiB. New/replaced/changed/grown nodes are skipped, newly created children remain intact, parent removed only if reviewed and empty. Never authorize a recursive delete solely by parent inode.
- [x] Manual caps limit reviewed allocated estimates and future scheduling, not guaranteed atomic actual bytes. Recheck metadata/budget before each leaf. Monotonic deadline prevents new dispatch at per-leaf boundaries; record syscall overruns. Unattended operations require producer-supported immutability/quiescence through effect; no such proof means unavailable.
- [x] Enforce catalog ownership constraints, not just “inside home.” DeleteContents propagates per-child errors; remove try? swallowing. Partial success counts only observed completed removals.
- [x] Separate apparent/allocated bytes and observed per-volume free-space delta. Shared APFS extents or unknown measurements cannot be added as proven reclaimed bytes. A command exit 0 is not a disk measurement.
- [x] GREEN: scratch sentinel outside selected roots remains intact under every adversarial test. Full tests/build and diff checkpoint.

```swift
@Test func unavailableBytesRemainUnavailable() {
    let observation = ByteObservation(bytes: nil, explanation: "Permission denied")
    #expect(observation.bytes == nil)
    #expect(observation.explanation != nil)
}
```

## T04 — Durable outcomes, bounded process I/O and interruption semantics

**Files**
- Create: `TidyCore/Sources/TidyCore/Execution/RunJournal.swift`
- Modify: `TidyCore/Sources/TidyCore/Exec/ProcessRunner.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/{RunLog,MemoryReclaimer,SnapshotDeleter}.swift`
- Modify: `Tidy/Clean/CleanResultsView.swift`
- Test: `TidyCore/Tests/TidyCoreTests/{RunRecovery,BoundedProcessRunner}Tests.swift`

**Consumes:** T02 coordinator and T03 outcome types.
**Produces:** journal states planned → confirmed → started → per-item terminal → finished; interrupted/uncertain recovery.

- [x] RED: crash before/after effect; child surviving Tidy death; daemon job surviving CLI exit; PID reuse; submission ambiguity; full disk journal write; corrupt tail; oversized stdout/stderr; descendant holding pipe open; queued cancellation; mutating command timeout.
- [x] Run `cd TidyCore && swift test --filter 'RunRecoveryTests|BoundedProcessRunnerTests'`.
- [x] Append durable intent before effect; failure to persist intent blocks effect. On restart, unfinished potentially active effects enter uncertainAndPossiblyRunning and block ALL new mutations. Fresh inventory/review alone cannot clear this state. Only adapter-specific positive quiescence/completion evidence releases it; unsupported reconciliation keeps the capability unavailable. No “clear history”/reset button can discard this block.
- [x] Once quiescence is proven, require fresh inventory/review for any remaining work. Never auto-resume a destructive command. Completed IDs are not silently replayed. OS restart only helps when the adapter proves no persisted daemon job can survive/restart; do not use boot change as a universal shortcut.
- [x] Drain output concurrently with a 1 MiB retained cap per stream, continue draining/discarding after cap, mark truncated; max command duration is adapter-owned. Read-only child trees may be terminated/reaped; mutation timeout becomes uncertain, prevents subsequent work and cannot be labelled cancelled cleanly.
- [x] Replace free-form application-name AppleScript with injected app-layer graceful termination of verified NSRunningApplication identities. Keep the advanced restart request isolated, unselected and separately confirmed.
- [x] GREEN: no deadlock on oversized output or descendant pipe ownership; memory stays bounded; no unauthorized signals to user processes. Results show separate disk/RAM observations and per-item reasons. Full tests/build and diff checkpoint.

Contract code:

```swift
public enum RecoveryDecision: Equatable, Sendable {
    case blockMutations, requireFreshReview
    public static func forUnfinishedEffect(quiescenceProven: Bool) -> Self {
        quiescenceProven ? .requireFreshReview : .blockMutations
    }
}
@Test func unfinishedEffectsNeverAutoResume() {
    #expect(RecoveryDecision.forUnfinishedEffect(quiescenceProven: false) == .blockMutations)
}
```

## T05 — UI safety harness and schema-preserving migration

**Files**
- Create: `TidyCore/Sources/TidyCore/Policy/{SettingsEnvelope,SettingsStore}.swift`
- Modify: `TidyCore/Sources/TidyCore/Model/TidyConfig.swift` and `Engine/ConfigStore.swift`
- Modify: `Tidy/Settings/AppConfigStore.swift` and `Tidy/TidyApp.swift`
- Create: `TidyUITests/PlanSafetyUITests.swift` and `TidyUITestHost/TestHostApp.swift`
- Modify: `project.yml`, generated `Tidy.xcodeproj/project.pbxproj`
- Test: `TidyCore/Tests/TidyCoreTests/SettingsMigrationTests.swift`
- Create fixtures: `TidyCore/Tests/TidyCoreTests/Fixtures/Config/{v1-original,v1-memory,corrupt,v999}.json`
- Modify: `TidyCore/Package.swift` to copy only test fixtures into test resources

**Consumes:** current schema-1 shapes and old run records, T02 coordinator.
**Produces:** schema-2 envelope, recoverable load result, monotonic revisions and a separate safe test host.

- [x] RED: old JSON missing memory fields loses no roots/presets/domains; future version untouched; malformed file preserved; failed write leaves old file; two-window revisions agree; old reports decode unavailable memory.
- [x] Run `cd TidyCore && swift test --filter SettingsMigrationTests`.
- [x] Decode version before payload. Missing file alone means new defaults; existing invalid/future file means read-only recovery. Owner-only atomic backup/write, single writer actor; never silently reset corrupt state.
- [x] Create a separate UI fixture host target depending on shared app views and injected protocols. Exclude its files/resources from production target; use no production default paths and no real executor even when launch arguments are malformed.
- [x] UI RED/GREEN: targetless action visible; deselection prevents recording invocation; unknown settings import never runs; closing one window does not orphan a hidden second execution; policy update invalidates confirmation.
- [x] Run UI command from `3, full core suite/build, and inspect production app bundle for absence of fixture host/test hooks.

```swift
public enum SettingsLoadDisposition: Equatable, Sendable {
    case newDefaults, migrated, loaded, recoveryReadOnly
}
// SettingsStore.load() async -> SettingsLoadDisposition
// SettingsStore.update(expectedRevision: UInt64, change: SettingsChange) async throws
// SettingsChange is an enum of validated edits, never an arbitrary closure.
```

## T06 — Effective policy, defaults and full customization

**Files**
- Create: `TidyCore/Sources/TidyCore/Policy/{PolicyResolver,PolicyValidator,PolicyDefaults}.swift`
- Create: `TidyCore/Sources/TidyCore/Policy/{FeatureSettings,ScanSettings,CleanupSettings,ExperienceSettings}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/{PolicyResolution,PolicyDefaults,PolicyValidation}Tests.swift`

**Consumes:** migrated settings/revisions from T05.
**Produces:** EffectivePolicy snapshot with per-field source/reason, validated settings and restrictions.

- [x] RED: global/profile/project/run precedence; deny beats enable; exclusion union; strictest cap; invalid age/range; NaN/overflow; missing volume capacity; unknown feature ID; every design-default row has a test.
- [x] Run `cd TidyCore && swift test --filter 'PolicyResolutionTests|PolicyDefaultsTests|PolicyValidationTests'`.
- [x] Implement every stable-key row in the binding appendix, including types/defaults/ranges, presentation settings and exact factory overrides. Defaults live in one registry; UI/serialization do not duplicate values. A registry row missing coverage blocks this task.
- [x] Resolve P preferences by replacement, R explicit restrictions by intersection, A authorities from a separate ledger, H ceilings immutably. The default 10 GiB is NOT a permanent cap. Requested 40 GiB works unless an explicit 8 GiB hard cap applies. Custom cannot remove protected paths/critical pause.
- [x] Persist two different volume-UUID headroom override records and verify both after relaunch. Test generic versus volume-specific overrides at every layer, inherit/automatic/fixed values, unavailable capacity and unmatched imported volume IDs. Factory profiles may carry P and stricter R only; Battery never changes A/H.
- [x] Validate numeric inputs before conversion/multiplication; clamp only temporary display values, reject invalid persisted edits with field-specific errors. Missing capacity prevents capacity-derived target calculation.
- [x] GREEN: table-driven snapshot of default/effective/source for every setting; disabled feature has no scheduled work; caps cannot be exceeded by profile activation. Full tests/build and diff checkpoint.

```swift
public enum PolicyMath {
    public static func manualLimitGiB(requested: Int?, userHardCaps: [Int]) -> Int {
        ([requested ?? 10, 100] + userHardCaps).min()!
    }
    public static func exclusions(_ layers: [Set<String>]) -> Set<String> {
        layers.reduce(into: Set<String>()) { $0.formUnion($1) }
    }
}
@Test func profileCannotRaiseSafetyCap() {
    #expect(PolicyMath.manualLimitGiB(requested: 40, userHardCaps: []) == 40)
    #expect(PolicyMath.manualLimitGiB(requested: 40, userHardCaps: [8]) == 8)
    #expect(PolicyMath.exclusions([["pinned"], ["private"]]) == ["pinned", "private"])
}
```

## T07 — Settings UX, profiles, inert import/export and resets

**Files**
- Create: `TidyCore/Sources/TidyCore/Policy/{SettingsTransfer,SessionProfile}.swift`
- Create: `Tidy/Settings/{FeatureSettingsView,ScanSettingsView,CleanupSettingsView,ExperienceSettingsView,ProfileSettingsView,SettingsTransferView}.swift`
- Modify: `Tidy/Settings/{SettingsView,AppConfigStore}.swift` and `Tidy/Custom/CustomView.swift`
- Test: `TidyCore/Tests/TidyCoreTests/SettingsTransferTests.swift`; `TidyUITests/CustomizationUITests.swift`

**Consumes:** T06 registry and effective policy.
**Produces:** searchable basic/advanced settings, named profile CRUD, diff preview, portable preferences without machine authority.

- [x] RED: imported rule cannot enable maintenance; imported roots/executable paths/volume IDs remain unresolved; unknown IDs retained disabled; duplicate profile names use stable IDs; selective reset respects pins/protections.
- [x] Run `cd TidyCore && swift test --filter SettingsTransferTests`.
- [x] Export portable preference values only; omit authorization ledger. Parse import into an inert preview; explicitly confirm each local root, compare every changed setting and save atomically after validation. Cancel makes no writes.
- [x] Provide factory Xcode/Android/Flutter/Web/Local AI/Battery profiles from design; clone, edit, rename, export, delete, reset; no automatic profile activation. Deleting active profile falls back visibly to global policy and invalidates plans.
- [x] Controls show default/effective/source, range and consequence. Keyboard navigation, VoiceOver labels, text scaling and contrast must work. History/index clearing has scoped confirmation, never a broad application-support directory wipe.
- [x] GREEN: all design controls reachable and persisted; relaunch round trip; two windows synchronized; import/reset can't bypass safety. Core/UI suites/build and diff checkpoint.

Required production regression: serialize a hostile import containing `maintenance.mode=authorizedCaches`, executable/root approvals and model-deletion IDs; pass those bytes through SettingsTransfer's real preview/commit path. Assert the local authorization ledger is byte-identical, unknown capabilities remain inert, the real coordinator rejects the forged operation and the recording effect client sees zero calls. Comparing a constant named “imported consent” is not this test.

## T08 — Shared low-impact scheduler and cancellable scans

**Files**
- Create: `TidyCore/Sources/TidyCore/Scanning/{WorkScheduler,ScanSession}.swift`
- Modify: `TidyCore/Sources/TidyCore/Measure/{HomeSurvey,SizeScanner}.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/ScanEngine.swift` and `Exec/ProcessRunner.swift`
- Modify: `Tidy/Scan/{ScanViewModel,ScanView}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/ScanSchedulingTests.swift`

**Consumes:** EffectivePolicy, injected clock/pressure inputs.
**Produces:** shared bounded worker permits; AsyncStream<ScanEvent>; cancellation by session ID.

- [x] RED: ten scans cannot each claim a private worker pool; queued waiter cancellation releases no extra permit; no work after cancel; slow synchronous enumerator cooperates; separate UI session close doesn't cancel other session incorrectly.
- [x] Run `cd TidyCore && swift test --filter ScanSchedulingTests`.
- [x] Route all filesystem traversals, catalog locate work and process discovery through one budget. Replace unbounded task fanout; move blocking work off the main actor and avoid exhausting Swift's cooperative pool.
- [x] Use one shared ceiling of two concurrent launched command jobs including the mutator; configured read-only ceiling is 1...2 but never additive. Test two readers delay a mutator and one mutator leaves at most one reader slot. Reserve declared adapter needs before dispatch and reject undeclared nested launches; unknown descendant bounds keep the adapter unavailable.
- [x] Check cancellation between bounded enumeration batches; cap queued paths/results; stream ≤4 UI batches/second; top-N ranking uses bounded heaps, not all large files retained.
- [x] Scan time slice returns partial coverage with Continue. Critical pressure pauses discovery; serious/LPM applies one-worker ceiling. Already-started mutation semantics stay with T04, not scanner cancellation.
- [x] GREEN: worker count never exceeds effective cap; 20 cancel/resume cycles return FDs/permits; fixture cancellation and first-result latency meet design section 7. Core/UI tests/build and diff checkpoint.

```swift
public struct ScanBudget: Equatable, Sendable {
    public let requestedWorkers: Int
    public let criticalPressure: Bool
    public let constrainedPower: Bool
    public var effectiveWorkers: Int {
        criticalPressure ? 0 : min(max(1, requestedWorkers), constrainedPower ? 1 : 4)
    }
}
@Test func criticalPressurePausesEvenCustomMode() {
    #expect(ScanBudget(requestedWorkers: 4, criticalPressure: true,
        constrainedPower: false).effectiveWorkers == 0)
}
```

## T09 — Incremental aggregate index without stale authority

**Files**
- Create: `TidyCore/Sources/TidyCore/Scanning/{ScanIndex,ScanInvalidation}.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/ScanEngine.swift` and `Measure/HomeSurvey.swift`
- Test: `TidyCore/Tests/TidyCoreTests/{ScanIndex,ScanInvalidation}Tests.swift`

**Consumes:** bounded scan records, scoped approved roots, policy revision.
**Produces:** native SQLite aggregate cache with freshness/coverage, FSEvents invalidation and bounded eviction.

- [x] RED: deeply changed child with unchanged root mtime; dropped/coalesced events; moved root; unmounted/replaced volume; app absent during changes; policy/protected-root change; crash during update.
- [x] Run `cd TidyCore && swift test --filter 'ScanIndexTests|ScanInvalidationTests'`.
- [x] Key records by volume UUID, stable root identity, scanner version and policy fingerprint; persist aggregate totals/coverage/time, not all file paths. SQLite transaction per completed batch; partial scans never replace complete records.
- [x] Start scoped FSEvents before baseline traversal; invalidate affected roots, replay a persisted cursor on resume, invalidate fully on loss/root change/wrap/unavailable history. Parent mtime alone never proves validity.
- [x] Maintain a per-root generation. A scan captures generation G; any event affecting its root increments generation before processing scan commits. Drain through an event-delivery barrier before publication; publish aggregate/coverage/generation/processed cursor in ONE transaction only when current generation still equals G. Otherwise retain stale status and reschedule bounded work.
- [x] Test modification to an already-scanned descendant while the baseline is finishing, invalidation immediately before commit, crash before/after cursor persistence, and dropped events during the barrier. “Fresh” means event-consistent through the recorded watermark, never execution authority or an atomic filesystem snapshot.
- [x] When indexing is off, no event stream remains. On expiry/corruption/budget eviction display cached/stale/unavailable explicitly and use fresh scan when requested. Cached bytes/eligibility can never authorize execution.
- [x] GREEN: reference fresh traversal equals incremental results after every fixture event sequence; unchanged 100k-entry case reduces metadata visits ≥80%; cache remains ≤ configured cap including WAL/shm/temporary files. Full tests/build and diff checkpoint.

```swift
public enum InvalidationDecision: Equatable, Sendable {
    case affectedRoot, allApprovedRoots
    public static func decide(historyReliable: Bool) -> Self {
        historyReliable ? .affectedRoot : .allApprovedRoots
    }
}
@Test func lostHistoryCannotReuseCachedAuthority() {
    #expect(InvalidationDecision.decide(historyReliable: false) == .allApprovedRoots)
}
```

## T10 — Truthful headroom signals and UI

**Files**
- Create: `TidyCore/Sources/TidyCore/Monitoring/{SystemSnapshot,SystemMonitor,SignalHistory}.swift`
- Modify: `TidyCore/Sources/TidyCore/Measure/{DiskStats,MemoryStats,SwapStats}.swift`
- Modify: `TidyCore/Sources/TidyCore/Detect/RestartReclaimSurvey.swift`
- Create: `Tidy/Headroom/{HeadroomView,HeadroomViewModel}.swift`
- Modify: `Tidy/MenuBar/{StatsRefresher,MenuBarContentView}.swift`, `Tidy/Scan/ScanSectionViews.swift`, `Tidy/TidyApp.swift`
- Create: `Tidy/PrivacyInfo.xcprivacy`
- Test: `TidyCore/Tests/TidyCoreTests/HeadroomSignalsTests.swift`; `TidyUITests/HeadroomUITests.swift`

**Consumes:** T06 preferences, T08 budget inputs, injected system probes.
**Produces:** optional timestamped per-volume/system observations, not a composite score.

- [x] RED: API denial; unsupported signal; wake resets cumulative counters; negative delta; zero elapsed time; nondefault page size; changed boot identity; hidden window produces no timer when monitoring disabled.
- [x] Run `cd TidyCore && swift test --filter HeadroomSignalsTests`.
- [x] Use Dispatch memory-pressure events, ProcessInfo thermal/power notifications, bounded VM/swap syscalls and per-volume capacity queries. Page-out rate is a pressure indicator, not labelled exact SSD writes or proof swap must be cleared.
- [x] Poll processes only on explicit request or selected visible rescue screen, not every stats tick. History is opt-in, bounded and stores no process argv.
- [x] Label available capacity types separately; readiness is “target met,” not guaranteed buildability. Replace absolute “swap never shrinks”/restart-only claims throughout README and UI with observed, qualified wording.
- [x] Verify Apple required-reason API usage against current documentation and add the applicable manifest reasons; validate plist and bundled resource. No invented reason code.
- [x] GREEN: deterministic signals, empty/error states and low-resource UI pass; hidden-off instrumentation records zero repeating tasks. Full tests/build and diff checkpoint.

```swift
public func counterRate(before: UInt64, after: UInt64, seconds: Double) -> Double? {
    guard seconds.isFinite, seconds > 0, after >= before else { return nil }
    return Double(after - before) / seconds
}
@Test func resetCounterIsNotNegativePressure() {
    #expect(counterRate(before: 10, after: 2, seconds: 5) == nil)
}
```

## T11 — Project inventory with explicit uncertainty

**Files**
- Create: `TidyCore/Sources/TidyCore/Projects/{ProjectInventory,ActivityResolver}.swift`
- Modify: `TidyCore/Sources/TidyCore/Detect/{GitRepoScanner,GitRootDiscovery,StaleNodeModulesScanner}.swift`
- Create: `Tidy/Projects/{ProjectsView,ProjectDetailView,ProjectsViewModel}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/ProjectInventoryTests.swift`

**Consumes:** user-approved roots, bounded scanner and system snapshot.
**Produces:** project IDs/ownership, declared toolchains, activity evidence, pinned state, per-resource confidence.

- [ ] RED: Git worktree `.git` file, nested repo, monorepo, unreadable manifest, malicious symlink, huge manifest, invalid encoding, repo named like a CLI option, no reliable activity evidence.
- [ ] Run `cd TidyCore && swift test --filter ProjectInventoryTests`.
- [ ] Parse manifests/lockfile names as data with 1 MiB input limit, bounded nesting/depth and no evaluation. Never run gradlew/npm scripts/python project code, fetch remotes, or read credentials.
- [ ] Resolve local Git metadata using bounded safe read-only operations with optional locks disabled, no external diff/pager/hooks; do not alter index. Preserve uncommitted/untracked status as protection evidence.
- [ ] Implement the binding appendix's ownership evidence matrix BEFORE ranker eligibility: recognized producers, 5-second runtime freshness, 24-hour association freshness, completeness/shared owners, producer quiescence, exact revalidation and manual-ack expiry. User pins/current selection protect; absence of IDE association stays unknown.
- [ ] Add paired positive/negative eligibility fixtures: supported immutable completed object with held producer lease becomes eligible; same-age shared object with one unobserved owner stays blocked. Manual “inactive for this run” acknowledgement never becomes recommendation/maintenance proof.
- [ ] GREEN: zero network/project-script execution; unknown remains protected; root removal cancels scans and deletes only Tidy's corresponding cached metadata after confirmation. Full tests/UI build and diff checkpoint.

```swift
public enum ActivityEvidence: String, Codable, Sendable {
    case running, pinned, recent, inactiveConfirmed, unknown
    public var blocksRecommendation: Bool { self != .inactiveConfirmed }
}
@Test func unknownDoesNotMeanIdle() {
    #expect(ActivityEvidence.unknown.blocksRecommendation)
}
```

## T12 — Candidate eligibility, cost ranking and overlap accounting

**Files**
- Create: `TidyCore/Sources/TidyCore/Planning/{CleanupCandidate,CandidateRanker,OverlapLedger}.swift`
- Modify: `TidyCore/Sources/TidyCore/Catalog/CleanCatalog+Helpers.swift`
- Test: `TidyCore/Tests/TidyCoreTests/CandidateRankerTests.swift`

**Consumes:** typed resources, working-set evidence, EffectivePolicy.
**Produces:** explained eligible/blocked candidates with cost/confidence and marginal bytes.

- [ ] RED: active/unknown resource excluded; current global cache blocked; same path across catalogs; parent-child overlap; hardlink reuse; APFS shared allocation unknown; tie stability; invalid negative sizes.
- [ ] Run `cd TidyCore && swift test --filter CandidateRankerTests`.
- [ ] Apply safety eligibility before ranking. Use lexicographic cost → inactivity confidence → reclaim estimate → stable ID rather than an opaque weighted “AI score.”
- [ ] Keep pinned/recent/running resources out. A lockfile does not make edited node_modules/venv disposable. Dependency directories stay explicit/manual-risk actions, never recommended automatically.
- [ ] Build a canonical overlap ledger keyed by volume/resource identity. Choose one covering action, never add nested estimates twice; shared/unknown extent estimates remain non-additive.
- [ ] GREEN: deterministic golden ordering, displayed reasoning and unique marginal bytes across every fixture. Full tests/build and diff checkpoint.

```swift
public struct CandidateOrder: Comparable, Equatable, Sendable {
    public let cost: Int
    public let confidence: Int
    public let bytes: Int64
    public let id: String
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.cost != rhs.cost { return lhs.cost < rhs.cost }
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
        return lhs.id < rhs.id
    }
}
```

## T13 — Build Prep and target-limited execution

**Files**
- Create: `TidyCore/Sources/TidyCore/Planning/HeadroomPlanner.swift`
- Create: `Tidy/Headroom/{BuildPrepView,BuildPrepViewModel}.swift`
- Modify: `TidyCore/Sources/TidyCore/Execution/ExecutionCoordinator.swift`
- Test: `TidyCore/Tests/TidyCoreTests/BuildPrepTests.swift`; `TidyUITests/BuildPrepUITests.swift`

**Consumes:** ranked candidates, selected profile/project/volume, policy caps and strict available bytes.
**Produces:** exact capped reviewed plan; target-met/insufficient/unavailable result; no automatic new selection.

- [ ] RED: already enough space; no eligible bytes; external volume won't free system volume; missing measurements; one oversized indivisible candidate; user deselection; concurrent disk growth; cap reached before target.
- [ ] Run `cd TidyCore && swift test --filter BuildPrepTests`.
- [ ] Compute deficit from the requested volume's strict current capacity, not a cross-volume sum. Purgeable/important-use estimates are separate context.
- [ ] Select known marginal bytes up to cap; any indivisible operation exceeding the remaining cap is excluded, with a separate explicit manual-plan option. Do not split tool operations whose scope cannot be constrained.
- [ ] Execute only confirmed candidates serially; remeasure target volume after each. Stop at target, cap, cancel or uncertain effect. No re-ranking that adds unreviewed items.
- [ ] GREEN: exact “need/selected/protected/not enough” UI and no-op behavior; caps and target stop verified with fake changing capacity. Full tests/UI/build and diff checkpoint.

```swift
public func headroomDeficit(target: Int64, available: Int64?) -> Int64? {
    guard target >= 0, let available, available >= 0 else { return nil }
    return max(0, target - available)
}
@Test func missingCapacityCannotPromiseReadiness() {
    #expect(headroomDeficit(target: 20, available: nil) == nil)
    #expect(headroomDeficit(target: 20, available: 25) == 0)
}
```

## T14 — Graceful, instance-bound Pressure Rescue

**Files**
- Create: `TidyCore/Sources/TidyCore/Rescue/{WorkloadIdentity,RescuePlanner}.swift`
- Create: `Tidy/Rescue/{RescueView,ApplicationTerminator}.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/MemoryReclaimer.swift` and `Detect/ProcessSurvey.swift`
- Test: `TidyCore/Tests/TidyCoreTests/RescuePlannerTests.swift`; `TidyUITests/RescueUITests.swift`

**Consumes:** fresh workload identity and user-selected instances, T02 confirmation and T10 signals.
**Produces:** graceful termination requests and observed, qualified before/after effects.

- [ ] RED: same-name apps, reused PID, changed bundle path, app refuses quit, app already exited, user cancelled prompt, critical pressure without consent.
- [ ] Run `cd TidyCore && swift test --filter RescuePlannerTests`.
- [ ] Identify app by bundle URL/identifier plus PID/start identity; request AppKit termination in injected app layer. Confirm exit without force; timeout means refused/uncertain, not succeeded.
- [ ] Initially support exact simulator shutdown through T15, not deletion; Android emulator shutdown through T16 only when stable identity is verified. General dev-server/Gradle/container stop remains suggestion-only.
- [ ] Attribute memory carefully: show observed system delta as noisy, never guaranteed per-app reclaim; no subtraction across unrelated measurement windows.
- [ ] GREEN: no process signals/arbitrary AppleScript; all actions initially unchecked; no automation route; no automatic launch/restart of target apps. Full tests/UI/build and diff checkpoint.

```swift
public struct ProcessInstance: Equatable, Sendable {
    public let pid: Int32
    public let startedAtTicks: UInt64
    public let executable: String
}
@Test func pidReuseDoesNotTransferConsent() {
    #expect(ProcessInstance(pid: 42, startedAtTicks: 1, executable: "/fixture/app")
        != ProcessInstance(pid: 42, startedAtTicks: 2, executable: "/fixture/app"))
}
```

## T15 — Adapter boundary and Apple developer inventory

**Files**
- Create: `TidyCore/Sources/TidyCore/Integrations/{ToolAdapter,AppleDeveloperAdapter}.swift`
- Modify: `TidyCore/Sources/TidyCore/Detect/SimctlClient.swift` and `Engine/SimulatorPruner.swift`
- Modify: `TidyCore/Sources/TidyCore/Catalog/CleanCatalog+{Xcode,DependencyCaches}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/AppleDeveloperAdapterTests.swift`
- Create: `docs/integrations/apple-developer.md`

**Consumes:** policy, exact local tool identity, T11 projects, T12 candidate model.
**Produces:** reusable adapter contract and versioned Apple fixtures.

Execute as T15.I (adapter interfaces/parser/inventory) then T15.M (exact effect preflight/completion/denial). Apply the appendix's concrete fixture/argv matrix. Repeat this separation for EACH adapter in T16–T20; no single task may mix parser acceptance and unreviewed mutation enablement.

```swift
public enum AdapterCapability: String, Codable, Sendable {
    case inventoryOnly, exactResourceMutation
}
public protocol LocalToolProbe: Sendable {
    func version(executable: URL) async throws -> String
    func read(executable: URL, arguments: [String]) async throws -> Data
}
// Mutations never go through LocalToolProbe; they require the coordinator lease.
```

- [ ] RED: malformed/version-changed JSON; renamed device; same name/different UDID; deleted device; active simulator; unknown Xcode mapping; archive dSYM importance.
- [ ] Run `cd TidyCore && swift test --filter AppleDeveloperAdapterTests`.
- [ ] Inventory via validated `xcrun simctl list -j`; map DerivedData using bounded local metadata, not guessed names. Include SwiftPM/CocoaPods/device-support/runtimes with confidence.
- [ ] Exact shutdown/delete uses reviewed UDID and preflight state. No `erase all` or `delete unavailable` batch commands. Runtime and archive removal requires separate explicit consequence review and proven ownership.
- [ ] Record detected version/output fixture/allowed argv/local scope in integration doc. New versions fail read-only until fixture compatibility passes; executable overrides require explicit local approval and identity validation, never ambient PATH.
- [ ] GREEN: unsupported versions remain visible read-only; scratch simulator integration test only with explicitly created disposable device; no real user's devices. Full tests/build and diff checkpoint.

## T16 — Android, Gradle, Flutter and Node resources

**Files**
- Create: `TidyCore/Sources/TidyCore/Integrations/{AndroidDeveloperAdapter,NodeDeveloperAdapter}.swift`
- Modify: `TidyCore/Sources/TidyCore/Catalog/CleanCatalog+{Android,SafeCaches,DependencyCaches,Extras}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/{AndroidDeveloperAdapter,NodeDeveloperAdapter}Tests.swift`
- Create: `docs/integrations/{android-flutter,node}.md`

**Consumes/produces:** T15 adapter contract, T11 project identities → typed resource inventory and exact cache actions.

- [ ] RED: active Gradle version; SDK referenced by active project; symlinked cache; custom cache location; edited node_modules; no lockfile; malformed AVD metadata; device instance changed.
- [ ] Run `cd TidyCore && swift test --filter 'AndroidDeveloperAdapterTests|NodeDeveloperAdapterTests'`.
- [ ] Inventory manifests and known local SDK/AVD/cache metadata without running gradlew/npm scripts. No `gradle --stop` per-PID promise: it affects a whole version. Suggest supported manual operations with full scope; do not execute wrappers.
- [ ] Preserve useful shared package caches. Exact regeneratable inactive build outputs become candidates; node_modules remains manual-risk only. SDK/NDK/AVD data is never deleted solely due age.
- [ ] Add version-scoped parser fixtures and commands for each supported native tool. Emulator shutdown only if instance identity can be revalidated through a bounded local interface; otherwise report-only.
- [ ] GREEN: no script execution/network, no active-project deletion, per-tool disable and per-project exclusions apply. Full tests/build and diff checkpoint.

Required production regression: create a fixture project with package.json, lockfile and an edited node_modules file; discover through NodeDeveloperAdapter, pass records through CandidateRanker and request Build Prep plus standing authorization. Assert the dependency record is manual-risk, neither flow selects it, the coordinator denies unattended execution and the edited bytes remain unchanged. A local boolean comparison is not this test.

## T17 — Rust, Python, Ruby, Go and Homebrew

**Files**
- Create: `TidyCore/Sources/TidyCore/Integrations/{LanguageCacheAdapter,HomebrewAdapter}.swift`
- Modify: `TidyCore/Sources/TidyCore/Model/ToolchainID.swift` and `Exec/ToolLocator.swift`
- Test: `TidyCore/Tests/TidyCoreTests/{LanguageCacheAdapter,HomebrewAdapter}Tests.swift`
- Create: `docs/integrations/{language-caches,homebrew}.md`

- [ ] RED: Cargo target override/shared target; venv containing local data; Conda environment; custom GOPATH; Bundler local path; unavailable tool; Homebrew auto-update environment; owner permission denial.
- [ ] Run `cd TidyCore && swift test --filter 'LanguageCacheAdapterTests|HomebrewAdapterTests'`.
- [ ] Inventory known Cargo/pip/uv/Conda/Bundler/Go/Brew locations and explicitly approved overrides. Do not evaluate project configuration files or run Python/Ruby imports.
- [ ] Classify virtual environments/installed toolchains as report-only; explicit inactive build output and known download caches may become candidates. Broad `brew cleanup`/`go clean -modcache` stays disabled unless complete command scope is representable and authorized.
- [ ] Disable auto-update/network behaviors in permitted tool calls; otherwise use filesystem inventory only. Document compatibility fixtures and unsupported fallback per ecosystem.
- [ ] GREEN: global caches shared by active projects blocked, no environment deletion, owner-only scoped mutation. Full tests/build and diff checkpoint.

Required production regression: LanguageCacheAdapter discovers fixture pyvenv.cfg/Conda metadata containing a user data file; submit its actual record to the generic mutation entry point. Assert inventoryOnly, capability rejection, zero executor calls and unchanged fixture bytes.

## T18 — Local Docker/Colima inventory and constrained operations

**Files**
- Create: `TidyCore/Sources/TidyCore/Integrations/{DockerAdapter,LocalEndpointGuard}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/{DockerAdapter,LocalEndpointGuard}Tests.swift`
- Create: `docs/integrations/docker-colima.md`

- [ ] RED: DOCKER_HOST/DOCKER_CONTEXT overrides; SSH/TCP context; malicious Unix socket symlink; context switching after review; stopped container with writable-layer data; shared image layers; daemon absent; Colima disk image.
- [ ] Run `cd TidyCore && swift test --filter 'DockerAdapterTests|LocalEndpointGuardTests'`.
- [ ] Resolve effective context before any daemon call. Only explicitly approved local Unix sockets/recognized local desktop context may be queried; scrub inherited overrides and bind explicit endpoint per invocation.
- [ ] Inventory images/containers/cache/volumes and VM logical vs host allocated size. No daemon start, no VM disk-file removal, no `system prune`/`builder prune`/`volume prune`.
- [ ] Support exact unused image IDs without force and exact stopped container IDs only after data-loss warning, identity/state/reference revalidation and per-run consent. Volumes/build-cache bulk prune remain report-only.
- [ ] GREEN: fixture remote endpoints produce zero calls; scope switch invalidates token; disposable local container/image tests use explicit fixture IDs. Full tests/build and diff checkpoint.

```swift
public func permitsLocalEndpoint(_ endpoint: String) -> Bool {
    endpoint.hasPrefix("unix://") && !endpoint.contains("\n")
}
// This syntax prefilter is not authorization: follow with approved socket
// identity/ownership/context checks and bind that exact identity in the plan.
@Test func remoteDockerIsNotLocalInventory() {
    #expect(!permitsLocalEndpoint("ssh://server"))
    #expect(!permitsLocalEndpoint("tcp://127.0.0.1:2375"))
}
```

## T19 — IDE caches, local AI and data-directory reporting

**Files**
- Create: `TidyCore/Sources/TidyCore/Integrations/{IDECacheAdapter,LocalModelAdapter,DataDirectoryAdapter}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/{IDECacheAdapter,LocalModelAdapter,DataDirectoryAdapter}Tests.swift`
- Create: `docs/integrations/{ide-caches,local-models,data-directories}.md`

- [ ] RED: IDE open with unknown project; VS Code workspaceStorage containing persistent state; extension settings; model aliases sharing blobs; symlinked model store; database folder disguised as cache.
- [ ] Run `cd TidyCore && swift test --filter 'IDECacheAdapterTests|LocalModelAdapterTests|DataDirectoryAdapterTests'`.
- [ ] Classify verified disposable IDE caches/logs using version-specific allowlists; owner must be stopped and state certain before deletion. No extension/version/workspaceStorage removal.
- [ ] Ollama/Hugging Face/MLX inventory uses local bounded metadata and allocated sizes only, no daemon start or model hashing/download. Shared blobs are not summed independently.
- [ ] Recognized DB and VM directories produce read-only resource rows with Reveal in Finder. No generic filesystem delete path is supplied for these resources.
- [ ] GREEN: readonly capability enforced in engine, not merely disabled UI; every disable/exclusion/profile setting applies. Full tests/build and diff checkpoint.

Required production regression: LocalModelAdapter discovers two aliases sharing one fixture blob; verify non-additive allocated bytes, then submit a forged generic delete using the discovered ID directly to the coordinator without UI mediation. CapabilityRegistry must reject it, the recording client must see zero effects and both aliases/blob must survive. Repeat for a DataDirectoryAdapter database and VM record.

## T20 — Git/LFS/worktrees and comprehensive ecosystem controls

**Files**
- Create: `TidyCore/Sources/TidyCore/Integrations/GitStorageAdapter.swift`
- Modify: `TidyCore/Sources/TidyCore/Engine/GitHousekeeper.swift` and `Catalog/CleanCatalog+Git.swift`
- Create: `Tidy/Ecosystems/{EcosystemView,EcosystemDetailView}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/GitStorageAdapterTests.swift`; `TidyUITests/EcosystemUITests.swift`
- Create: `docs/integrations/git-storage.md`

- [ ] RED: active Git operation/lock; worktree common dir outside approved root; dirty or bare repo; repo hooks/config with external commands; LFS blobs with unknown references.
- [ ] Run `cd TidyCore && swift test --filter GitStorageAdapterTests`.
- [ ] Inventory shared Git storage without double-counting; no remote checks. Do not remove `index.lock` merely because it looks old. Unknown lock owner means blocked.
- [ ] Audit existing gc/reflog commands for hooks/config, worktree scope and live operations; only fixed reviewed commands with controlled side effects remain executable. Reflog expiry is separate advanced opt-in; no repository/worktree/LFS deletion.
- [ ] Add one ecosystem settings/detail surface: enable inventory vs enable supported manual actions, per-item ages/caps, status/reasons, compatibility, local executable approval, and reset.
- [ ] GREEN: all design section 5 ecosystem rows have inventory coverage and correct mutation/read-only boundaries; user settings are consistent across Scan/Build Prep/Custom. Full tests/UI/build and diff checkpoint.

```swift
public func gitMaintenanceAllowed(lockOwnerKnownAbsent: Bool, active: Bool) -> Bool {
    lockOwnerKnownAbsent && !active
}
@Test func unknownGitLockDoesNotGetDeleted() {
    #expect(!gitMaintenanceAllowed(lockOwnerKnownAbsent: false, active: false))
}
```

## T21 — Budgets, hysteresis and quiet notifications

**Files**
- Create: `TidyCore/Sources/TidyCore/Assistance/{BudgetEvaluator,NotificationPolicy}.swift`
- Create: `Tidy/Budgets/{BudgetsView,NotificationBroker}.swift`
- Test: `TidyCore/Tests/TidyCoreTests/BudgetEvaluatorTests.swift`; `TidyUITests/BudgetUITests.swift`

- [ ] RED: disabled template; high ≤ low; unknown allocation; overlapping budgets; timezone/DST/wrapped quiet hours; permission denial; wake notification flood; repeated pressure event.
- [ ] Run `cd TidyCore && swift test --filter BudgetEvaluatorTests`.
- [ ] Implement off-by-default budget templates and per-volume thresholds from design. Evaluate only known measurements, with stable alert state/hysteresis and cooldown.
- [ ] Request OS notification permission only when enabled. Quiet hours suppress delivery, not safety decisions; persist dedup state without retaining process data.
- [ ] Notification opens review/inventory; never executes a plan. Missing data keeps warning unknown, not cleared.
- [ ] GREEN: fake-clock transition table and UI permission states pass; no duplicate notification on wake; no action from notification click except navigation. Full tests/build and diff checkpoint.

```swift
public func budgetAlert(used: Int64?, high: Int64, low: Int64, wasAlerting: Bool) -> Bool? {
    guard high > low, low >= 0, let used, used >= 0 else { return nil }
    return wasAlerting ? used > low : used >= high
}
@Test func missingMeasurementDoesNotClearAlert() {
    #expect(budgetAlert(used: nil, high: 100, low: 80, wasAlerting: true) == nil)
}
```

## T22 — Optional, tightly bounded cache maintenance

**Files**
- Create: `TidyCore/Sources/TidyCore/Assistance/{MaintenanceRules,MaintenanceAuthorization}.swift`
- Create: `Tidy/Settings/MaintenanceSettingsView.swift`
- Test: `TidyCore/Tests/TidyCoreTests/MaintenanceRulesTests.swift`; `TidyUITests/MaintenanceConsentUITests.swift`

- [ ] RED: import/profile enables rule; disabled master feature; expired/revoked authority; wrong volume; active/unknown owner; stale estimate; cap exceeded by one target; login invocation without consent; missing journal.
- [ ] Run `cd TidyCore && swift test --filter MaintenanceRulesTests`.
- [ ] Ship off, notify-only offered first, initial unattended allowlist EMPTY. Store authorization separately from settings, binding exact accepted capability IDs, roots/volumes, byte/item bounds, monotonic scheduling deadline, inactivity floor and rule version.
- [ ] Additions to the initially empty closed allowlist must be derived from adapters proven by T15–T20, never all Safe-tier entries. Allow only individually measured regeneratable filesystem caches; no tools, browsers, project outputs, devices, apps, snapshots, models, data directories or restart.
- [ ] Skip without fresh identity/size/activity AND adapter-supported immutable/quiescent scope held through effect. Bound reviewed descendant batches and check remaining cap/deadline before every leaf. Never force-stop a mutating syscall; report overrun. If none qualify, report no work. Clock rollback cannot increase frequency allowance.
- [ ] Route standing-authorized plans through the same coordinator/journal and all immutable protections; rule or policy change invalidates authorization until reviewed. No automatic recovery replay.
- [ ] GREEN: default app has zero background cleanup; user can revoke all rules immediately; no login helper is required unless explicitly enabled. Full tests/UI/build and diff checkpoint.

```swift
public func maintenanceEligible(allowlisted: Bool, activeStateKnownIdle: Bool,
    hasFreshConsent: Bool, withinCaps: Bool) -> Bool {
    allowlisted && activeStateKnownIdle && hasFreshConsent && withinCaps
}
@Test func unknownActivityBlocksMaintenance() {
    #expect(!maintenanceEligible(allowlisted: true, activeStateKnownIdle: false,
        hasFreshConsent: true, withinCaps: true))
}
```

## T23 — Performance harness, chaos cases and device acceptance

**Files**
- Create: `TidyCore/Tests/TidyCoreTests/{PerformanceBudget,FaultInjection}Tests.swift`
- Create: `scripts/benchmark-headroom.sh`
- Create: `docs/verification/headroom-benchmark-protocol.md` and per-device evidence reports
- Modify: `.github/workflows/ci.yml` and `project.yml`

- [ ] RED: instrumentation detects an idle unauthorized hidden timer, worker leak, unbounded output, index cap overflow, wrong-volume accounting and a missed cancellation. Test every background-mode row from the appendix separately; explicit in-flight work must not be misreported as hidden idle.
- [ ] Run `cd TidyCore && swift test --filter 'PerformanceBudgetTests|FaultInjectionTests'`.
- [ ] Add fixture generator inside test target: 50k quick-root entries and 100k nested entries, bounded small files, known counts, deterministic mutation schedule, scratch path sentinel. No real home scan in CI.
- [ ] Document hardware/OS/power/thermal state, dataset, baseline, five paired runs, median wall time/CPU/footprint/metadata calls/FD counts. Measure cold/warm scans and representative Xcode/Android builds using disposable sample projects.
- [ ] CI builds both architectures and runs deterministic correctness/UI tests; noisy performance thresholds run on controlled physical reference machines, not uncalibrated shared CI.
- [ ] Run all design section 7 gates on 8 GiB Apple Silicon and 8 GiB Intel; oldest supported OS smoke and current OS. Record unavailable hardware as incomplete gate, not a simulated pass.
- [ ] GREEN: every numeric gate has attached measured evidence; no background mode ships if build overhead gate fails. No production data cleanup used for benchmarking.

```swift
@Test func workerBudgetHasNoUnboundedOption() {
    for workers in -2...12 {
        let budget = ScanBudget(requestedWorkers: workers,
            criticalPressure: false, constrainedPower: false)
        #expect((1...4).contains(budget.effectiveWorkers))
    }
}
```

## T24 — Final hardening, documentation and release handoff

**Files**
- Modify: `README.md`, `CONTRIBUTING.md`, `docs/UNSIGNED_INSTALL.md`
- Create: `docs/verification/headroom-acceptance.md` and `docs/settings-reference.md`
- Modify: `.github/workflows/release.yml` only if separately authorized for implementation; no release dispatch

- [ ] Verify all S01–S16 adversarial cases and traceability below. REPEAT the full catalog audit already required in T01; no legacy direct route, hidden command, stale authorization or unbounded scanner.
- [ ] Generate settings reference from tested registry; compare every default/range/source against design. Test migrations from all released shapes plus user downgrade/future-version recovery.
- [ ] Audit privacy: zero outbound calls in instrumented workflows; no tool-triggered downloads/hooks/remote context use; exports redacted; manifest reasons current; credentials never logged.
- [ ] Run full core/UI/build/static gates. Review unsigned and optional signed app behavior separately; build success does not prove TCC permissions, quit support or notarization.
- [ ] Assemble exact evidence: implemented, tested, hardware verified, packaged, uploaded, released. Only implementation/test states may be marked here; publishing requires fresh authority.
- [ ] Hand off remaining unsupported adapters and missing hardware gates explicitly. Do not call the complete suite ready if any required safety/performance test remains unresolved.

## 4. Requirements traceability

| Requirement | Tasks | Acceptance evidence |
|---|---|---|
| Full customization, defaults, precedence | T05–T07 | Default registry coverage, layered conflict tests, persistence/UI round trips |
| Import/export/reset without authority transfer | T05–T07, T22 | Malicious/future/corrupt import, revoked rules, reset UI |
| Plan/execute parity and per-item selection | T01–T02, T05 | UI selected IDs equal invoked IDs; targetless regression |
| Filesystem/command scope safety | T02–T04, T15–T20 | Race/symlink/ancestor exclusion/command fixture tests |
| Readiness and swap/thermal truth | T10, T13 | Unknown/reset counters, source labels, copy review |
| Working-set protection/project inventory | T11–T12 | Active/unknown/shared-cache protection and worktree fixtures |
| Ranking and target-limited Build Prep | T12–T13 | Overlap/volume/cap/stop/no-expansion tests |
| Graceful workload relief | T14–T16 | PID/UDID reuse, refusal and manual selection tests |
| Comprehensive ecosystems | T15–T20 | One documented capability/compatibility matrix per ecosystem |
| Budgets, profiles, quiet assistance | T07, T21–T22 | Threshold/quiet-hour/revocation/default-off tests |
| High performance | T08–T10, T23 | Bounded work, incremental parity, reference-device metrics |
| Reliability and recovery | T02–T05, T09, T23 | Crash/journal/corrupt config/event-loss/timeout tests |
| No network/no overreach | T11, T15–T20, T22, T24 | Controlled executables, IPC boundary, readonly forbidden resources |
| Per-volume and truthful results | T03–T04, T10, T13 | Unknown/partial/observed-capacity/clone/hardlink cases |
| Accessibility and low-complexity UI | T05, T07, T10–T14, T20–T21 | Keyboard, VoiceOver, scale, empty/denied/partial states |
| Release boundaries and device proof | T23–T24 | Architecture builds and physical-device evidence |

## 5. Rollout and stopping rules

- A and B are valuable independent releases only after T01's complete default-deny legacy audit, not just visibility fixes. Do not wait for every ecosystem to quarantine current hazards.
- Feature capability flags are local, default-off for newly introduced mutation adapters until their tests and compatibility contract pass.
- Read-only integrations may ship before mutations; label capability and unsupported tool versions explicitly.
- No blanket “all features enabled” preset. New settings migrate conservatively; presets cannot silently select newly added dangerous capabilities.
- If performance budgets fail, ship the previous bounded scan path and keep incremental/background behavior disabled; do not weaken correctness to hit speed targets.
- If a planned source/version cannot support narrow scope, preserve inventory and explanation rather than broadening mutation authority.
- Re-review whenever a task introduces a new effect type, changes protected-root semantics or adds standing authorization.

## 6. Planning self-review and independent review

Self-review checklist:

- [x] Every feature in design section 5 maps to a task.
- [x] Every defaults-table row maps to T06 registry coverage and T07 UI.
- [x] Every destructive adapter is required to obey S01–S16, including legacy actions.
- [x] No unknown signal may be represented as zero or inactive.
- [x] Performance targets distinguish measured evidence from desired gates.
- [x] Safety/defaults are binding; unspecified adapter mutations remain unavailable until separately accepted, not implementation discretion.
- [x] Independent adversarial reviewer checks scope, contracts, safety bypasses, performance, migration, feasibility, test quality and dependency order.

These checks cover the plan's requirements, not implemented behavior. Review outcome and disposition are recorded in the [adversarial-review document](2026-08-26-developer-headroom-adversarial-review.md). This plan authorizes no implementation by itself; user direction is required to begin execution.
