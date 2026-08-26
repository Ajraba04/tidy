# Developer Headroom implementation evidence

Full scope: the approved [T01–T24 program](../superpowers/plans/2026-08-26-developer-headroom-execution-plan.md) and its binding design/registry. This ledger distinguishes implementation from tests, UI evidence and physical-device acceptance. Missing evidence means incomplete, not passed.

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

The history-budget product decision is resolved: the user approved optional completed history having its own configurable cap, with separately bounded mandatory recovery storage. T04.A is implemented at `b6c585d`. The user directly resumed after the shared-helper correction question; the approved test-only extraction now preserves all assertions and production behavior. Focused92/3 and controller full297/41 pass; independent re-review is pending. No production defect was identified by the initial review.

The full program remains incomplete. The user authorized GitHub push, README update and a DMG release **after completion**, and explicitly rejected treating the partial foundation as the finished product. Release inspection was read-only; no push, tag, release or package publication occurred. Preserve the original checkout and continue on `CAJ/developer-headroom`.

Latest T04.A verification: `swift test --jobs 2`, 297 tests in 41 suites passed in 13.051 seconds, exit 0; unsigned production arm64 app build also exited0 with no output. The preceding253/40 run was the pre-T04.A baseline. Neither run establishes device or full-program acceptance.

## Work-package status

| Package | Status | Evidence / remaining gate |
|---|---|---|
| T01 Action review/quarantine | A scoped unit approved at `96fd35c`; B scoped default-denied checkpoint independently spec/quality approved at `48ee814`. Core175/37 passed before final bounded fix; covering6/6 and both final arm64 builds passed afterward. | Controller observed actual620×620-point native layout on all four shared surfaces, expanded Custom included; reviewer could not reopen temporary screenshot artifacts. AX endpoint navigation anomaly retained for T05/T23 reproduction; ordinary scrolling recovered. Old-filter regression proof was postimplementation. Positive accepted-action/T02/T04 and physical gates remain open; no full T01 acceptance. |
| T02 Sealed selection/coordinator | Bounded foundation independently spec/quality approved through `10616b3`; post-FIFO-fix full core204/38 and production arm64 build passed. Prior app models15/15 and production/manual-host builds passed. | Genuine RED/GREEN, public API-negative checks and isolated target audit recorded in T02-foundation-verification.md. FIFO admission regression caught and fixed during review. Positive mutation/recovery/UI integration remains unverified. Bootstrap tools remain unknown/empty; T08 discovery and T05 slow-storage latency remain open. |
| T03 Guarded filesystem effects | A scoped foundation independently spec/quality approved for `cefbbae..ec9dbc5`, with no remaining findings. Post-fix focused29/29, fullcore233/39 and unsigned arm64 app build passed; earlier compatibility3/3. | Evidence: T03-A-foundation-verification.md. B production integration remains unapproved: total capture resource bounds, real ownership/exclusion, persisted manifests, durable accounting and bounded policy/effect boundary required. No production primitive caller or accepted cleanup was added. |
| T04 Journal/process recovery | A implemented at b6c585d; approved shared FIFO test helper extracted and verified focused92/3 plus full297/41. Independent re-review pending. | See T04-A-foundation-verification.md and T04-A-source-review.md. B launcher/FD/identity entry contract independently READY, source assignment awaits A approval. T02 JSON authority preserved; C/D real adapter dispatch/crash/recovery and UI acceptance remain gated. |
| T05 UI fixture host/migration | A.1 independently spec/quality approved for a45d22c..599ed45, no remaining findings. Empty-report issue fixed with genuine RED; post-fix focused21/2, controller fullcore253/40 and unsigned arm64 build passed. | Evidence: T05-A1-foundation-verification.md. A.2F still requires T04 shared I/O; A.2P/A.3/B remain gated, including truly absent fresh-install parent handling. App retains legacy writer/UI until atomic A.3 cutover; intermediate build is not a deployable migration release. |
| T06 Policy/defaults | Pure-entry documentation independently spec/quality READY after four Important corrections; no source implemented | See T06-entry-review.md and T06-policy-customization-entry.md. Registry fixture91 literal rows→133 unique entries/patterns; merged validation, scan admission, restriction provenance and selected-volume bounds specified. Source/prerequisite approval, storage/app integration and all execution/device evidence remain open. |
| T07 Settings/profiles/transfer | Pending | Persistence, settings reachability, authority-free import |
| T08 Low-impact scheduler | Pending | Shared worker/process budgets, cancellation |
| T09 Incremental index | Pending | Event-publication races, parity and metadata savings |
| T10 Headroom signals | Pending | Truthful unknown states, idle work, privacy manifest |
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
