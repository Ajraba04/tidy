# T08.1a verification — scheduler core and exact-envelope resolution

Date: 2026-08-28  
Worktree: `/private/tmp/tidy-headroom.r1yE0o`  
Branch: `CAJ/developer-headroom`

## Scope

The checkpoint changed only the approved scheduler source, its focused tests, and this post-GREEN record. It adds no persistence integration, filesystem traversal, process execution, app wiring, background work, or mutation authority; those remain owned by T08.1b and later checkpoints.

## RED evidence

The exact initial focused test file was compiled before the implementation existed. Swift failed on the missing scheduler declarations, including `WorkScheduler`, `SchedulerPolicyController`, and their token/session types. This was the intended missing-production-contract RED rather than an assertion weakened to fit existing code.

## GREEN evidence

From `TidyCore`:

```text
swift test --disable-sandbox --jobs 2 --filter WorkSchedulerTests
33 tests passed in 13.002 seconds; exit 0
```

The focused suite covers production policy resolution, exact four-pair legacy compatibility (including explicit canonical defaults), synchronous admission closure, invalidating and presentation token ownership, observation epochs, bounded FIFO permits, aggregate caps, feature/slice/admission transitions, cancellation at every grant boundary, terminal reaping, bounded replay/tombstones, and the production-source negative manifest.

```text
swift test --disable-sandbox --jobs 2 --filter 'PolicyResolutionTests|PolicyDefaultsTests|SettingsProfilePersistenceTests|WorkSchedulerTests'
74 tests passed in 9.390 seconds; exit 0
```

```text
git diff --check
exit 0
```

Independent adversarial source review returned `Approved` after the final atomic preparation-ownership and exact-release fixes.

## Ordinary package-suite boundary

```text
swift test --disable-sandbox --jobs 2
503 tests across 55 suites; exit 1 with 19 issues
```

All 33 `WorkSchedulerTests` passed in that run. Failures were outside the T08.1a allowlist in existing host-dependent probes, notably `SystemToolSurveyTests` returning no process rows and `BoundedProcessRunnerTests` failing to prove child-process identity/observation under this sandbox. The run is recorded as failed, not GREEN, and no claim is made that T08.1a fixed or accepted those pre-existing environment-sensitive T04 boundaries.

SwiftPM also reported that user-level caches under `~/Library` were unavailable in the sandbox; package-local builds and the focused/regression suites completed successfully. During earlier rebuilds the package build directory exhausted the nearly full data volume; only generated `TidyCore/.build` output was cleaned before rerunning.

## Remaining gates

Durable `ExecutionPolicyBridge` handoff, bounded traversal adoption, the existing process-gate evolution, orchestration, app ownership/UI, physical cancellation acknowledgement, performance evidence, README, DMG construction, GitHub push, tag, and release remain open under T08.1b–T24.
