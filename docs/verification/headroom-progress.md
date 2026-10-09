# Developer Headroom implementation evidence

Full scope: the approved [T01–T24 program](../superpowers/plans/2026-08-26-developer-headroom-execution-plan.md) and its binding design/registry. This ledger distinguishes implementation from tests, UI evidence and physical-device acceptance. Missing evidence means incomplete, not passed.


## Audit remediation working tree — 2026-10-09

This entry supersedes older completion claims for the current working tree. The
starting commit was `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a` in `/workspace/tidy`.
The user authorized implementation after the static audit. Their Linux restriction
on builds, app execution, dependency installation, generators, and tests remains in
force. **No Swift compilation, app launch, tests, project generation, packaging,
or release was performed for these changes.** Earlier passing test counts below
do not validate this patch. On 2026-10-10 the user authorized committing and pushing
this checkpoint for local continuation; see the
[local handover](local-handover-2026-10-10.md).

The publication check found `origin/main` at `9da3196`, 67 commits ahead of this
checkpoint's base, with overlapping remediation and additional product features.
The gaps below describe this branch only. Reconcile against current main before
using them as the repository's current backlog; this checkpoint does not supersede
the newer implementation or its evidence.

### Implemented source changes, awaiting native verification

| Finding | Current source change | Closure still required |
| --- | --- | --- |
| F01 | Bootstrap discovery supplies one tool set to onboarding, policy, and scanning. First explicit Scan saves ordinary defaults through the existing bridge. | Fresh-install and migrated-config macOS flows. Detection remains inventory evidence. |
| F02 | Reviews retain bounded manifests and identities; confirmation checks identities; effects compare current scope with the retained manifest. | Root/ancestor replacement and concurrent-writer tests. Production DerivedData is quarantined because no producer lease exists. |
| F03 | Intent/start/terminal/finish records, returned-effect completion proof, and a bounded reconciliation pass for known synchronous effects. Legacy incomplete records close with unknown outcomes, never replay. Process intents remain blocked. | Run/relaunch/crash/disk-full matrix. Recovery does not reconstruct per-leaf outcomes lost during a crash; those remain uncertain. |
| F04 | Capture bounds total entries, encoded bytes, depth, ancestor descriptors, and elapsed time. Effects check cancellation, policy changes, and deadline between leaves. | Actual memory/FD/latency measurements and interruption fixtures. A kernel syscall is not forcibly interrupted. |
| F05 | Mandatory cloud roots are unioned into environments, effective exclusions reach production environments, project traversal receives exclusions, and destructive parent-of-protected scopes are rejected. | All traversal/protection fixtures on macOS, including approved roots and filesystem aliases. |
| F06 | Shared observations reach the scheduler, power and thermal inputs remain distinct, critical state is held conservatively, and unknown observations retain restricted admission. | Pressure/power recovery, policy-handoff races, and real idle sampling checks. |
| F07 | Single-flight scan startup, separate running-partial presentation, service-owned cancellation, per-session result retention, and close/reopen subscription repair. Results publish before progress notifications. | Concurrent windows/rescan/cancel and terminal-delivery races. Retention is bounded to eight scan handles. |
| F08 | Monitor visibility belongs to individual consumers and is removed independently. | Real popover/window overlap and teardown. |
| F09 | Subscribe to normal pressure events; reject callbacks from stopped subscriptions; clear stale pressure when sampling stops. | Live normal-warning-critical-normal transitions. |
| F10 | Import uses no-follow, nonblocking descriptor open, regular-file validation, bounded reads off the UI actor, and stale-result cancellation with visible progress. | FIFO/symlink/provider tests. Cancellation cannot interrupt a kernel read already blocked on a regular file; it prevents applying the result. |
| F11 | Explicit test sources/resources reconciled in project.yml; CI includes app-model tests, the isolated process-cap test, both app architectures, and a semantic project-membership check. Local release no longer conditionally regenerates the project. | Execute the new CI gate, native targets, and deterministic regeneration comparison on macOS. |
| F12 | Optional history is bounded, path/message-redacted, serialized off the UI actor, and governed by acknowledged enable/retention/size settings. Mandatory recovery remains separate. | Retention/opt-out/relaunch/write-failure tests. Optional history rewriting is not crash-atomic and may lose optional records after interrupted writes. |
| F13 | README, onboarding, mode descriptions, and result accounting describe current inventory-only capabilities and measurement uncertainty. | Product/accessibility review and minimum-toolchain verification. |

Additional integrations: the aggregate index is constructed for explicit scans,
starts its event watch before traversal, and stops after terminal work. Monitoring
receives acknowledged settings changes; unchanged settings preserve raw history.
Headroom resolves the observed home volume and capacity, and distinguishes an
unavailable target from an unset preference. Bootstrap recovery offers retry and
revealing the settings directory without deleting damaged state.

Production mutation remains default-deny, including DerivedData. Internal fixture
coverage of the guarded adapter is not production acceptance and supplies no
runtime bypass. New tests cover ten completed journaled fixture runs, stale root
rejection, total manifest limits, multi-consumer visibility, history opt-out and
retention, FIFO/symlink imports, and first explicit scan configuration. They are
**written but unrun**.

Static checks performed: changed-call-path inspection, `git diff --check`, existence
of every `project.yml` path, and Python AST parsing of
`scripts/check-project-sources.py`. The membership checker itself invokes macOS
`plutil` and was not executed here. None of these checks establishes Swift
compilation or runtime correctness.

### Continuation: project inventory and scheduling stability

Read-only project marker inventory now runs within explicit Scan sessions when the
projects feature is enabled. It considers only approved roots, preserves mandatory
exclusions, caps retained projects at 256, and prunes recognized dependency/metadata
directories from recursive descent. Each root has a 30-second slice; the project
phase stops starting additional roots after its overall deadline or result cap.
Markers are metadata, not evaluated manifests. Git indirection files are displayed
as unresolved and are not followed. Nested projects, pins/current-project
protection, partial coverage, and observation time are visible in Scan.

`ActivityResolver` now expresses the complete-owner, five-second runtime evidence,
24-hour association, exact-resource/policy, held-lease, pin/running/recency rules.
It grants no execution authority. Production marker inventory always remains
unknown or pinned: it has no producer lease and cannot use a missing process as
positive proof. Git dirty/untracked/common-directory resolution, the complete
Projects workflow, and per-adapter evidence producers remain open T11 work.

The monitoring bridge also serializes and deduplicates applied observations, so an
unchanged sample does not advance the scheduler epoch and invalidate an active
scan. Regression cases for that boundary and project/ownership evidence were added
but **not run**. These additions do not change the native-verification limitation.

### Remaining program gates — do not mark complete

1. Run the foundation's core, app-model, isolated process, and app build gates on
   macOS, then resolve every failure before expanding mutation authority. Verify
   existing tests affected by changed scan ownership and default-deny capabilities.
2. T07.3d/T22.3: finish confirmed history/index clearing, local reassociation, and
   immediate privacy preference effects for every persisted store. Recovery retry
   currently preserves damaged settings; it does not automatically repair them.
3. T11–T13: finish project inventory beyond marker evidence and complete ownership/activity evidence, deterministic
   eligibility/ranking/overlap accounting, and the reviewed per-volume Build Prep UI
   and execution contract. Pins/recentness/cost/project controls still need their
   complete consumers; typed settings alone do not implement these workflows.
4. T14: instance-bound, explicitly confirmed graceful Pressure Rescue with refusal,
   timeout, and PID-reuse handling. Existing legacy termination remains denied.
5. T15–T20: independently accepted inventory and mutation/denial units for Apple,
   Android/Gradle/Flutter/Node, language managers/Homebrew, Docker/Colima, IDE/models/
   data, and Git/LFS/worktrees. No adapter receives blanket approval from this patch.
6. T21–T22: budgets, quiet notifications, independent standing maintenance authority,
   revocation, and exact bounded scheduling. Unattended mutation allowlist stays empty.
7. Privacy: substantiate FileTimestamp required-reason declarations against current
   platform guidance, verify exported diagnostics and backup behavior, and instrument
   local-only workflows. No new declaration was guessed during this Linux pass.
8. T23–T24: automated native UI coverage and manual keyboard/VoiceOver/contrast/text
   scaling checks; macOS 14 and current stable OS; Intel and Apple Silicon; physical
   8 GiB-device performance; fault injection; signed/unsigned packaging, signing,
   notarization, and release metadata. The cask checksum template is still unpublished.

The full program and the user's request to execute it fully remain incomplete.
This working tree is an unverified remediation candidate, not a release-ready app.

## Workspace and baseline

- Base application revision: `db4707f` (v1.5.0).
- Branch: `CAJ/developer-headroom`.
- Isolated worktree: `/private/tmp/tidy-headroom.wUbV9h`.
- Original checkout is preserved at `/Users/abdulrahman/Apps/tidy`.
- Local plan checkpoint: `67c9098`; no remote publication authorized or performed.
- Host observed 2026-08-26: arm64, 8 GiB RAM, 8 logical CPUs, macOS 27.0 (26A5406e), Xcode 27.0 (27A5237l).
- Baseline Swift tests: `swift test --jobs 2`, exit 0; 174 tests in 35 suites passed in 26.126 seconds after a 64.46-second build. Initial sandbox failure occurred before test execution; approved unsandboxed retry supplied this evidence.
- Baseline app build: unsigned Debug arm64 `xcodebuild`, exit 0, derived data `/private/tmp/tidy-headroom-build`, two jobs. Xcode 27 emitted its scheme supported-platform warning; the initial sandbox attempt failed during local package resolution and is not a code failure.

## Current execution instruction — 2026-08-26

The history-budget product decision is resolved: the user approved optional completed history having its own configurable cap, with separately bounded mandatory recovery storage. T04.A is implemented at `b6c585d`. The user directly resumed after the shared-helper correction question; the approved test-only extraction now preserves all assertions and production behavior. Focused92/3 and controller full297/41 pass; independent re-review approved T04.A through490ff5a with no remaining findings. No production defect was identified by the initial review.

The full program remains incomplete. The user authorized GitHub push, README update and a DMG release **after completion**, and explicitly rejected treating the partial foundation as the finished product. Release inspection was read-only; no push, tag, release or package publication occurred. Preserve the original checkout and continue on `CAJ/developer-headroom`.

Latest T04.A verification: `swift test --jobs 2`, 297 tests in 41 suites passed in 13.051 seconds, exit 0; unsigned production arm64 app build also exited0 with no output. The preceding253/40 run was the pre-T04.A baseline. Neither run establishes device or full-program acceptance.

T05.A2F and A2P are independently approved through63dc0f4 andd525f36. T05.A3 atomic app cutover is independently spec/quality Approved throughd82ba82 with no Critical/Important: appmodels29, focusedcore80/5, ordinary323/42, A2P3/eight, bounded21/1 and unsignedarm64 app build all pass. Complete coverage is partitioned so global child-owner assertions do not overlap. Legacy ConfigStore is gone; the app now uses one off-main actual store/coordinator, bounded durable edit ordering, shared scenes, explicit-only onboarding/scan, and truthful report projection. Native B UI/effect acceptance remains open.

T06.1 pure policy is independently Approved through83087b4; T06.2 typed persistence is independently Approved through40118ce; and T06.3 revision handoff is independently Approved through98cf0ba after three Important code findings and one remaining projection-parity finding were fixed. Final T06.3 focused core39/2, app-model37/37, ordinary362/46, bounded21/1, A2P3/1 and unsigned arm64 app build pass. One atomic store/bridge/app owner now provides strict base-bound deltas, presentation-only versus invalidating revision semantics, ordered failure reconciliation and shared durable/predicted compatibility projection. Full customization UI and policy consumption remain open.

T07 entry and T07.1b source cards are independently Approved. T07.1b pure profiles/restrictions is code-review Approved through `c1b7969`, including the recorded identity-boundary review fix. Final focused20/1, ordinary382/47, bounded21/1 and A2P3/1 pass. Profiles cannot weaken any current R family or contain authority, project or volume identity; factory/CRUD/diff/reset operations remain pure. Transfer, persistence, active selection and UI remain open.

T07.1a strict transfer is independently adversarial-review Approved. Final focused28/1, ordinary410/48, bounded21/1 and A2P3/1 pass. Import parsing is bounded and duplicate-key strict; classification fails closed; profile collision/inert ownership is explicit; merged candidates enforce exact project, aggregate, UTF-8, cross-layer, monotone and 1 MiB canonical-output bounds. Export excludes local authority/identity and weaker restrictions. Persistence, active selection and UI remain open.

T07.2a durable profile/import store is independently adversarial-review Approved. Final focused25/1, ordinary435/49, bounded21/1 and A2P3/1 pass. Schema2 active/inert state, exact base-bound document deltas, actor-issued single-use import previews, compatibility-projected candidate digests, hostile classification-only imports and complete-state rollback now live in the sole durable writer. T07.2 remains incomplete until 2b bridge/app handoff proves invalidation, selected-profile resolution, ordered replay, relaunch and two-window behavior.

T07.2b shared profile handoff is independently adversarial-review Approved at `1d772e8`. Final focused app-model39/39, profile25/25, transfer28/28, complete app-model57/57, full core exit0 and unsigned arm64 production build pass. One bounded 32-snapshot/32 MiB bridge now owns exact document/import retention, synchronous invalidation, lifecycle-bound single-use previews, selected-profile resolution and ordered two-window replay. T07.2 is complete; later T07 checkpoints are recorded below.

T07.3a registry-driven Settings UI is independently adversarial-review Approved at `7f8472b`. Final registry4/4, SharedSettings51/51, complete app-model69/69, ordinary core439/50, settings-process3/1, bounded-process21/1, fixture-host and unsigned production arm64 builds pass. Every current static/catalog/volume family has deliberate presentation metadata and localized copy; authority/read-only rows fail closed; supported edits use the one shared store; search, adaptive layout, accessibility metadata and zero-work-on-open contracts are covered. Its physical VoiceOver/contrast/macOS14/8GiB/Intel evidence remains open.

T07.3b profile, transfer and selective-reset workflows are independently adversarial-review Approved at `1c4a958`. Final workflow6/6, SessionProfile20/20, transfer28/28, persistence25/25, defaults4/4, resolution12/12 and SharedSettings74/74 pass; fixture-host and unsigned production arm64 builds also pass. The UI now exposes bounded profile lifecycle, portable export/import preview-confirmation, exact per-restriction reset consent, deterministic fixture states and revision-safe two-window replay through the shared store. The dated task-card amendment corrects one project-capability fixture without weakening assertions. T07.3d dependency-bound data clearing and physical VoiceOver/contrast/macOS14/8GiB/Intel evidence remain open.

T07.4 hostile production-bound regression is independently adversarial-review Approved at `2bfc605`. The exact hostile document traverses the real disk-backed store analyze/issue/commit/reopen/export pipeline, preserves the complete local config and preference graph, leaves imported profiles inactive, keeps safe unknowns inert and sensitive unknowns redacted, and remains rejected at the real coordinator, capability and engine quarantine boundaries with zero command/custom calls. Focused2/2, persistence25/25, coordinator28/28 and quarantine4/4 pass. Two aggregate 471-test runs each retained one unrelated bounded-process active-job interference failure; that exact test passes1/1 isolated, so aggregate full GREEN is deliberately unclaimed. Literal authority-ledger/accepted-adapter proof remains dependency-bound to T22.4.

## Merge checkpoint — 2026-09-04

`CAJ/developer-headroom` was merged to `main` with a no-fast-forward merge; the merged tree is byte-identical to the tested branch tip `25e1f4d`. Verification at that tree: `swift test`, 623 tests in 63 suites passed, exit 0, and an unsigned Debug arm64 `xcodebuild build` of the app succeeded. This closes packages A–C (T01–T10) at implementation/test level only; the physical acceptance matrix below is unchanged and remains open. No push, tag, release or package publication has occurred.

## Work-package status

| Package | Status | Evidence / remaining gate |
|---|---|---|
| T01 Action review/quarantine | A scoped unit approved at `96fd35c`; B scoped default-denied checkpoint independently spec/quality approved at `48ee814`. Core175/37 passed before final bounded fix; covering6/6 and both final arm64 builds passed afterward. | Controller observed actual620×620-point native layout on all four shared surfaces, expanded Custom included; reviewer could not reopen temporary screenshot artifacts. AX endpoint navigation anomaly retained for T05/T23 reproduction; ordinary scrolling recovered. Old-filter regression proof was postimplementation. Positive accepted-action/T02/T04 and physical gates remain open; no full T01 acceptance. |
| T02 Sealed selection/coordinator | Bounded foundation independently spec/quality approved through `10616b3`; post-FIFO-fix full core204/38 and production arm64 build passed. Prior app models15/15 and production/manual-host builds passed. | Genuine RED/GREEN, public API-negative checks and isolated target audit recorded in T02-foundation-verification.md. FIFO admission regression caught and fixed during review. Positive mutation/recovery/UI integration remains unverified. Bootstrap tools remain unknown/empty; T08 discovery and T05 slow-storage latency remain open. |
| T03 Guarded filesystem effects | A scoped foundation independently spec/quality approved for `cefbbae..ec9dbc5`, with no remaining findings. Post-fix focused29/29, fullcore233/39 and unsigned arm64 app build passed; earlier compatibility3/3. | Evidence: T03-A-foundation-verification.md. B production integration remains unapproved: total capture resource bounds, real ownership/exclusion, persisted manifests, durable accounting and bounded policy/effect boundary required. No production primitive caller or accepted cleanup was added. |
| T04 Journal/process recovery | A independently approved through490ff5a. B independently spec/quality approved throughb770f3f, no findings: pure3/3, isolatedB21/1, nonB323/42 and unsigned arm64 app build pass. | See T04-A-foundation-verification.md, T04-A-source-review.md and T04-B-foundation-verification.md. B replaces actual runner, keeps sole signal/reap ownership, bounded streams and two shared slots; initial fixture readiness failure diagnosed/corrected without deadline relaxation. T02 JSON authority preserved; C/D real adapter dispatch/crash/recovery and UI acceptance remain gated. |
| T05 UI fixture host/migration | A.1/A.2F/A.2P accepted; A.3 atomic app cutover independently Approved throughd82ba82. App29, focusedcore80, complete partitioned package coverage and unsigned arm64 build pass. | Evidence: T05-A1-foundation-verification.md, T05-A2F-foundation-verification.md, T05-A2P-process-acceptance.md and T05-A3-atomic-app-cutover.md. Native B UI/dialog and first accepted adapter effect remain open; this is not full T05 acceptance. |
| T06 Policy/defaults | T06.1 pure core Approved through `83087b4`; T06.2 typed persistence Approved through `40118ce`; T06.3 revision handoff Approved through `98cf0ba`. Final T06.3 core39/2, app-model37/37, ordinary362/46, bounded21/1, A2P3/1 and unsigned arm64 build pass. | See T06-entry-review.md, T06-policy-customization-entry.md, T06-1-policy-core-verification.md, T06-2-policy-persistence.md and T06-3-policy-revision-handoff.md. Settings UI, profiles/transfer, scheduler/effect consumption and device evidence remain open; no full T06 product acceptance. |
| T07 Settings/profiles/transfer | Entry contract Approved; T07.1a strict transfer, T07.1b pure profile/restriction, T07.2a durable store, T07.2b shared handoff, T07.3a registry Settings foundation, T07.3b profile/transfer/reset workflows and T07.4 hostile production regression independently Approved. All currently dependency-free T07 work is complete. | See T07-1a-strict-transfer.md, T07-1b-profiles-restrictions.md, T07-2a-durable-import-store.md, T07-2b-shared-profile-handoff.md, T07-3a-registry-settings-ui.md, T07-3b-profile-transfer-workflows.md and T07-4-hostile-production-regression.md. T07.3d data clearing, T22.3 reassociation, T22.4 accepted-adapter regression and physical gates remain open; no full T07 acceptance. |
| T08 Low-impact scheduler | Complete: scheduler core, policy handoff, bounded traversal, process budget and core orchestration independently approved. | T08-1a-work-scheduler-core.md, T08-1b-scheduler-policy-handoff.md, T08-2-bounded-traversal.md, T08-3-process-budget.md, T08-4-core-orchestration.md. Physical gates remain with T23. |
| T09 Incremental index | Complete: incremental aggregate index approved at `25e1f4d`. | T09-incremental-index.md. Physical gates remain with T23. |
| T10 Headroom signals | Complete: truthful signals, shared monitor, privacy manifest approved at `76d589b`. | T10-headroom-signals.md. Physical gates remain with T23. |
| T11 Project inventory/activity | Pending | Ownership/protection, positive and negative fixtures |
| T12 Ranking/overlap | Pending | Determinism, eligibility, marginal bytes |
| T13 Build Prep | Pending | Per-volume target/cap/selection enforcement |
| T14 Pressure Rescue | Pending | Exact instance identity and graceful manual actions |
| T15 Apple | Pending | Separate inventory and accepted mutation units |
| T16 Android/Node | Pending | Separate per-adapter inventory and mutation/denial units |
| T17 Languages/Homebrew | Pending | Separate per-adapter inventory and mutation/denial units |
| T18 Docker/Colima | Pending | Pinned local endpoint and exact disposable fixtures |
| T19 IDE/models/data | Pending | Typed inventory and enforced read-only boundaries |
| T20 Git/ecosystem UI | Pending | Local-only scope, ownership and controls |
| T21 Budgets/notifications | Pending | Hysteresis, deduplication, consent |
| T22 Optional maintenance | Pending | Empty initial allowlist, separate standing authority |
| T23 Performance/reliability | Pending | Reference fixtures, physical gates and fault injection |
| T24 Full acceptance/handoff | Pending | Requirement-by-requirement audit and complete evidence |

## Physical acceptance matrix

| Required environment | Availability | Verification |
|---|---|---|
| 8 GiB Apple Silicon | Current host | Not yet measured |
| 8 GiB Intel | Not established | Not run; required gate remains open |
| macOS 14 oldest-supported smoke | Not established | Not run; required gate remains open |
| Current host OS | macOS 27.0 developer build | Toolchain evidence only, not stable-OS release acceptance |

No user data cleanup is permitted as test setup. All effects must use disposable fixtures. Publishing, signing changes and remote Git writes require separate authority. The goal remains active until the full contract is implemented and verified; an incomplete device matrix is not full completion.

## Reliability follow-up

- T05/T23: reproduce the native AX endpoint/blank-list observation recorded in T01-B-manual-verification.md on supported stable macOS with ordinary scrolling, keyboard and AX navigation. Subsequent ordinary scrolling recovered and content was inspectable; cause remains undiagnosed. Do not claim comprehensive scrolling/accessibility robustness from the scoped layout pass.
- T05/T08: synchronous ConfigStore save/load, initial journal I/O and legacy tool-detection paths remain latency risks; the T02 pure projection correction does not certify those paths.
- T23/T24: final T02 model tests passed15/15 but Xcode27 emitted an IDEFoundation diagnostics-setup warning about setRunnablePIDWithDiagnostics lacking a completion handler. Preserve alongside the earlier scheme warning; stable-OS/toolchain verification remains open.
