# R13 Current-Host Observation Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record bounded, truthful current-host runtime diagnostics for the isolated production-scene host without adding path or authority inputs to Tidy.

**Architecture:** A fixed-scenario runtime host emits one atomic ready attestation from its owned root. An external Python orchestrator validates and launches that exact bundle, samples process/system state, retains raw evidence in `/private/tmp`, and generates redacted summaries. UI actions remain in the production-native XCTest target.

**Tech Stack:** Swift 5 / SwiftUI / XCTest, Python 3 standard library, macOS `ps`, `lsof`, `footprint`, `nettop`, `xcodebuild`.

## Global Constraints

- The normal `Tidy` target must contain no scenario parser, synthetic path factory, observer control, or cleanup behavior.
- Runtime scenarios are fixed enums; the host accepts no path, duration, cap, settings payload, or authority input.
- Every fixture root is a canonical, owner-only UUID root under `/private/tmp` or canonical system temporary storage.
- No global preference, permission, security, signing, service, or network configuration changes.
- Results are current-host diagnostics and never substitute for reference hardware, human VoiceOver, supported OS, privacy-purpose, package, or release evidence.
- All builds use at most two jobs. Do not run build/GUI workloads during CPU/RSS observation windows.

---

### Task 1: Fixed readiness contract

**Files:**
- Modify: `Tidy/RuntimeVerification/RuntimeTestComposition.swift`
- Modify: `Tidy/TidyApp.swift`
- Test: `TidyProductionNativeUITests/ProductionSceneRuntimeUITests.swift`

**Interfaces:**
- Produces: fixed `hidden-off` and `hidden-no-authority` scenarios; one stdout root line; one atomic `state/runtime-ready.json`.
- Ready JSON fields: `schema`, `scenario`, `pid`, `settingsRevision`, `timerRunning`, `sceneLeases`, `explicitWorkLeases`, `scanSessions`, `scanActiveWork`, `allMutationsDenied`.

- [ ] **Step 1: Add failing native readiness assertions**

Launch each fixed scenario and require the exact scenario plus ready-state values. Do not poll by asking the app to probe; wait for the one ready artifact/AX projection.

- [ ] **Step 2: Run the two readiness cases and retain RED evidence**

Run with `xcodebuild ... -only-testing:TidyProductionNativeUITests/<case> -jobs 2 test` and preserve the result bundle.

- [ ] **Step 3: Implement fixed settings and atomic ready publication**

Use the existing owned runtime root. Write JSON to a UUID staging file, validate it, then publish with a no-replace atomic rename. Emit no repeating diagnostic task after readiness.

- [ ] **Step 4: Verify both cases and normal-artifact isolation**

Run the focused native cases, `check-project.py`, and the runtime/production binary marker checks.

### Task 2: External hidden-state observer

**Files:**
- Create: `scripts/verification/run-r13-observation.py`
- Create: `docs/verification/remediation-R13-current-host-diagnostics.md`
- Create after execution: `docs/verification/remediation-R13-current-host-diagnostics.json`

**Interfaces:**
- Consumes: validated runtime `.app`; fixed scenario name.
- Produces: UUID raw evidence directory, JSON summary, Markdown report.

- [ ] **Step 1: Implement pure validation and parser self-tests**

Cover runtime bundle identity, executable containment, ready JSON exact keys/types, PID/start matching, canonical fixture-root validation, `ps` time parsing, nettop-row parsing, and rejection of a normal Tidy bundle.

- [ ] **Step 2: Implement owned launch and event-driven readiness**

Launch the bundle executable directly with one fixed scenario flag, parse exactly one root line, wait for the atomic ready file, and verify its PID/scenario/internal state before sampling.

- [ ] **Step 3: Implement samplers and raw evidence**

Record fixed-interval `ps`, bounded `lsof`, recursive child PID snapshots, final `footprint`, and concurrent `nettop` output. Record command paths, timestamps, exits, and stderr without shell interpolation.

- [ ] **Step 4: Implement safe termination and cleanup**

Revalidate PID/start/executable before termination. Revalidate root prefix, no symlink, UID, directory type, and mode before removal. Retain on uncertainty.

- [ ] **Step 5: Run self-tests and the two fixed observations**

Run hidden-off for the fixed two-minute window and Headroom-enabled/background-authority-unavailable for the fixed ten-minute window without other UI/build load. Generate redacted summaries. Require both to keep the timer off and report the production authority unavailable.

### Task 3: Representative traffic and twenty cycles

**Files:**
- Modify: `TidyProductionNativeUITests/ProductionSceneRuntimeUITests.swift`
- Modify: `scripts/verification/run-r13-observation.py`
- Modify: `docs/verification/remediation-R13-current-host-diagnostics.md`

**Interfaces:**
- Consumes: production-native scheme and fixed queued-cancel scenario.
- Produces: twenty-cycle registry/lease/FD/RSS settling evidence and per-runtime-PID traffic logs.

- [ ] **Step 1: Add the deterministic queued-cancel fixture and one-cycle test**

Use runtime-only explicit sessions to occupy the resolved scheduler permits. Assert a real registry cancelled terminal, release blockers, then assert scan-owned state returns to baseline and close/reopen preserves cancellation.

- [ ] **Step 2: Add the twenty-cycle test**

Repeat start/cancel/settle against fresh generation state. Record initial/final FD and RSS through test-runner Darwin APIs and require zero worker/session/lease drift.

- [ ] **Step 3: Wrap native workflows with PID-aware traffic observation**

Follow only exact runtime bundle PIDs, start a new bounded nettop capture for each, sample children, and preserve gaps when a process exits before attachment.

- [ ] **Step 4: Run focused cycles, then the complete production-native suite**

Require every exact case, zero skips, fixture cleanup, and a successful loopback observer control. Do not claim universal zero network.

### Task 4: 50k scan and paired-build dependency

**Files:**
- Modify: `Tidy/RuntimeVerification/RuntimeTestComposition.swift`
- Modify: `TidyProductionNativeUITests/ProductionSceneRuntimeUITests.swift`
- Modify: `scripts/verification/run-r13-observation.py`
- Modify: `docs/verification/remediation-R13-current-host-diagnostics.md`

**Interfaces:**
- Produces: complete 50k useful/terminal monotonic timing, scan peak footprint/RSS, and UI/worker cancel timing. The paired-build mode reports its missing production authority dependency without launching work.

- [ ] **Step 1: Add fixed bounded 50k fixture and timing attestation**

Create exactly 50,000 zero-byte entries after a free-space guard. Record composition and allocated bytes. Emit request/first-useful/terminal/settled monotonic timestamps from runtime-only observation code.

- [ ] **Step 2: Run the complete 50k scan under external sampling**

Reject partial/incomplete coverage. Record useful and total duration, peak physical footprint, RSS, workers, FDs, and cleanup.

- [ ] **Step 3: Run five alternating build pairs**

Fail the paired-build mode before launch while `monitor.backgroundEnabled` has no accepted machine-local authority workflow. Do not substitute persisted authority, a compile-only override, or an off/off comparison. Five paired builds become feasible only after the production workflow can create the authorized background arm.

- [ ] **Step 4: Final verification and documentation**

Run script self-tests, project/privacy/personal-data gates, all exact native cases, and the repository verifier. State which current-host diagnostics meet thresholds and list every reference/human/platform gate that remains open.
