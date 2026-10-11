# Developer Headroom implementation evidence

Full scope: the approved [T01–T24 program](../superpowers/plans/2026-08-26-developer-headroom-execution-plan.md) and its binding design/registry. This ledger distinguishes implementation from tests, UI evidence and physical-device acceptance. Missing evidence means incomplete, not passed.

## Reconciled audit checkpoint 10 October 2026

The Linux audit checkpoint `418ec00` was compared with main at `9da3196` and
selectively reconciled on `codex/audit-reconciled-20261010`. Main's newer scoped
scans, reviewed-resource persistence/recovery, Developer Workspace, assistance,
optional history, and verification tooling are retained. The additional source
fixes and disposition of all audit finding groups are in the
[local handover](local-handover-2026-10-10.md).

This reconciliation has source inspection and whitespace checks only. Its new
regression cases are unrun. No compilation, tests, app launch, generators,
packaging, or release ran in Linux. Previous passing results apply to their
recorded revisions, not this patch. Production mutations remain quarantined;
full-program and release acceptance remain incomplete. Later source checkpoints
on main, including the September 20 and 22 records linked in the handover, take
precedence over historical pending-feature claims below.

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
