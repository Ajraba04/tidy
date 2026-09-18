# Remediation integration record

The implementation branch started at `9e1a500`. It covers R01 containment, R02 reviewed-resource foundations, R06/R07 scan/index corrections, R08 live policy/measurement/history, R12 verification enforcement, and R13/R14 evidence/documentation/packaging preparation. It is not full-program or release acceptance. See [dependency closures](remediation-dependency-blocks.md) and [headroom acceptance](headroom-acceptance.md).

## Workspace continuity

During verification on 2026-09-18, the entire original Desktop/AJR directory moved into iCloud Desktop. The original Git history and uncommitted work survived. A new local isolated clone at `/Users/mac/Developer/tidy-remediation-20260918` was created from the moved repository, with exact index/worktree patches and untracked files preserved. All 389 source files matched SHA-256 against the moved worktree, and `git fsck --connectivity-only` passed. The iCloud copies were left unchanged. No remote push, tag or publication occurred.

The recovery preservation manifest and patches are `/private/tmp/tidy-workspace-move-preservation-20260918`. Historical commands in package reports retain their original paths; current verification uses the recovered local clone.

## Shared application integration

`AppExecutionServices.swift` integrates the independently owned R06/R08 work: one serialized scan transition, generation-owned observation/index resources, retained terminal results, acknowledged cache policy, expiring scoped grants, monitor scene/work leases, monotonic volume observations, and revision-bound confined optional history. Its ordinary deinitializer closes monitoring callbacks and cancels/removes only its own bindings; it does not require Swift 6.2 isolated-deinitializer syntax.

Fresh focused source evidence before the combined integration commit:

- Scan/index core foundation: 79 tests, followed by 39 invalidation/index tests after real FSEvents corrections.
- Scan app models: 14 passed, zero skipped, including simultaneous starts, replacement teardown, retained results, closed-window global cancellation and the real 100k index gate.
- R08 monitoring/history corrections: 40 tests passed (33 monitor + 7 history).
- Recovered-path monitoring lifetime compatibility: 2 model tests passed.
- Scope alias correction: 9 tests passed, including four hostile cache aliases and moved-ancestor denial.

Real app/FSEvents fixture: 500 directories, 100,000 files, 49,152 allocated bytes, fresh metadata visits 100,502, unchanged visits 0, complete content parity, zero catch-up retries. The 100% measured reduction exceeds the 80% correctness gate on this M1 Max fixture. This is not reference-hardware latency, physical footprint or whole-app idle performance evidence.

Final full core/model/architecture checks and whole-branch review are recorded below once complete. Earlier failures remain in the package reports and must not be erased by focused passes.

## Shared-settings full-model integration correction

The first recovered full-model run on 2026-09-18 executed 132 tests and left two
`SharedSettingsWiringTests` cases failing. The failures had independent causes:

- A positive-revision app bootstrap returned while the bridge's asynchronous initial scheduler
  installation could still own admission. An immediate legacy setter could therefore receive and
  discard `.unavailable` before entering the tested replace/sync failure path. App bootstrap now
  awaits that initial installation before publishing its editable shared services.
- `PolicyDefaults.rows` rebuilt the complete immutable static setting registry on every lookup.
  Document validation and optimistic replay multiply those lookups across the bounded 32-snapshot
  queue, allowing the real I/O suspension to cross its five-second deadlock watchdog. The registry
  is now initialized once as immutable process state; queue bounds, retention, and the watchdog are
  unchanged.

Fresh focused evidence using `/tmp/tidy-r08-xcode`, `-jobs 2`, and the macOS arm64 destination:

- The two formerly failing tests passed together: 2 tests, 0 failures, 6.902 seconds
  (`/tmp/tidy-focused-two-green.log`).
- The replace/post-rename failure regression passed 20 fresh-process repetitions with zero
  failures (`/tmp/tidy-focused-replace-20x.log`).
- Seven settings/bootstrap/queue integration regressions passed with zero failures in 6.220
  seconds, including both formerly failing cases, the 32-snapshot overflow path, schema-1 and
  schema-2 bootstrap, and revision-zero/recovery scheduler admission
  (`/tmp/tidy-settings-integration-green.log`). The authority/queue case completed in 3.574
  seconds with its original finite watchdog and exact rejection assertions intact.
- Focused Core policy/default/transfer verification passed 32 tests across 2 suites in 42.906
  seconds (`/tmp/tidy-core-policy-cache.log`). The exhaustive portable-classifier registry test
  completed in 8.040 seconds.

These focused passes close the two observed integration failures. They do not replace the required
fresh whole-suite model/Core reruns or release acceptance.

## Review-correction aggregate checkpoint

The intermediate review-correction Core run executed 685 tests across 69 suites in 321.892 seconds, with one failure: `BoundedProcessRunnerTests.descendantOutlivesCLIAndPipeDeadline` observed 1.721064083 seconds against its unchanged 1-second timed-segment limit. Other development builds were active on the host; this is a possible scheduling contributor, not proven causation. The same built test binary reran that exact case with `--skip-build` and passed without source or limit changes (2.424 seconds total including the separate descendant-completion wait). Logs: `/tmp/tidy-remediation-core-reviewed.log`, `/tmp/tidy-remediation-process-timing-rerun.log`. The failed aggregate remains failed evidence. It also predates the final continuation-handoff guard and strengthened byte-budget assertions, so a new final aggregate is required.

The next Core checkpoint passed **687 tests across 69 suites** in 205.220 seconds (`/tmp/tidy-remediation-core-accepted.log`), including the unchanged process timing assertion. The count/skip checker passed. This checkpoint precedes the reviewer's consolidated final catch-up/continuation-pause findings and is not the final accepted-source aggregate.

The first complete verifier pass on `6d707f0` passed **689 Core tests / 69 suites** in 166.805 seconds and the separate isolated process-cap case. Full model execution then produced **137 total, 136 passed, 1 failed, 0 skipped**: `HeadroomViewModelTests.testReadinessReflectsAvailableBytesAgainstTarget` failed two assertions after its unchanged 2-second wait found no snapshot. The real FSEvents/100k case passed in 21.476 seconds. The verifier correctly stopped before native/Release. This exposed a possible initial subscription/broadcast ordering gap and is being corrected; no timeout or assertion was relaxed. Preserved artifacts are `/tmp/tidy-remediation-before-snapshot-replay/` (including the failed model result bundle and the entire verifier log).

Commit `ce89f22` closes that initial-state race by registering a subscriber and replaying the monitor's latest observed snapshot in one actor turn. It starts no probe or timer and preserves the measurement timestamp. A deterministic publication-before-subscription regression failed before the fix and passed afterward; all 34 `HeadroomSignalsTests` and all 11 `HeadroomViewModelTests` passed with the original readiness watchdog and assertions. The bounded reviewer approved the correction. The complete verifier is rerunning on these inputs.

Final post-replay results: **690 Core / 69 suites**, isolated-cap **1**, app models **137**, synthetic native UI **2**, all passed. Universal Release built both architectures. [Final verification](remediation-final-verification.md) records exact timings, cache fixture visits, input hashes, the artifact-stage CLI correction and preserved failure boundaries.
