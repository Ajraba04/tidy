# Scene-model lifecycle oracle validation

Date: 2026-09-19

## Finding and fix

The preserved aggregate failure in
`/private/tmp/tidy-final-20260919-44u3mup6/models.xcresult` recorded the final
lease and generation counts as `192` instead of baseline `0`. The original test
created each model, queued its visible transition, and immediately released it.
Its first baseline poll could therefore succeed before any queued transition
entered `SystemMonitor`; later transitions then made the final assertions fail.
This was a test-oracle race, not evidence of a production lifecycle defect.

The regression now retains 100 `HeadroomViewModel` and 100 `StatsRefresher`
instances, makes all visible, and waits up to the existing five-second bound for
exactly baseline plus 200 active leases and generation entries. It then releases
both arrays and waits for both counts to return to baseline. It uses the real
deinitializers and `MonitorSceneLeaseController.dispose()` path; it does not call
stop, reset, dispose, or cleanup methods from the test.

## Focused evidence

- `build-for-testing` succeeded with the shared model cache at
  `/tmp/tidy-r05-resume-xcode`, two build jobs, signing disabled, and the macOS
  arm64 destination.
- The single lifecycle case passed in ten separate `test-without-building`
  invocations, each with its own process, log, and result bundle at
  `/tmp/tidy-model-lifecycle-focused-01` through
  `/tmp/tidy-model-lifecycle-focused-10` (`.log` and `.xcresult`).
- The complete `HeadroomViewModelTests` suite passed: **11 tests, 0 failures**.
  Result bundle: `/tmp/tidy-model-lifecycle-headroom-suite.xcresult`.
- Independent final diff review found the exact plus-200 barrier sufficient to
  remove transient-baseline acceptance while preserving real deinit/dispose
  coverage and the five-second contract.

No production source changed. This focused evidence does not replace the final
aggregate verifier rerun.
