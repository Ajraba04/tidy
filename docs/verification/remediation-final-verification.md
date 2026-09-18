# Final local remediation checkpoint — 2026-09-18

Status: **verified partial checkpoint; application NO-GO, full program INCOMPLETE**.

Reviewed application/Core/test source: `ce89f22` on `codex/remediation-20260917` (includes the consolidated correction `6d707f0` and native Settings AX fix `4ef9956`). Later changes are verification-script corrections and evidence records. The source/spec reviewer approved the correction delta and the snapshot-replay follow-up. All mutation catalog entries remain denied.

## Fresh results

| Gate | Result |
| --- | --- |
| Core aggregate | 690 tests, 69 suites passed; 166.356 seconds |
| Isolated process-cap fixture | 1 passed; 0.377 seconds |
| App models | 137 passed, 0 failed, 0 skipped; 63.890 seconds |
| Synthetic native UI | 2 passed, 0 failed, 0 skipped; 19.491 seconds |
| Universal Release | Build succeeded; arm64 and x86_64 independently verified |
| Generated project | All 7 source/resource phases match; all model test files included |
| Privacy source gate | Seeded negative/clean controls and repository source scan passed |
| Privacy manifest | Built Release plist syntax passed |
| Input stability | All 174 Core/package/settings-reference hashes unchanged through verification |
| Required tests | Exact named Core/model/native cases passed; accepted floors raised to 690/137/2 |

The Core aggregate permits only the named isolated process-global case to skip; that case passed in its separate process. No model or native skips were accepted. Input hashes are in `remediation-core-inputs.json`.

The real app-owned FSEvents fixture ran 100,000 files under 500 directories. Fresh and unchanged scans were complete and had equal results; actual metadata visits dropped from 100,502 to 0 (100% reduction), with zero catch-up/fresh retries. The test took 21.502 seconds including fixture/setup work. This is correctness/cache-usefulness evidence on the current M1 Max 32 GiB host, not a reference-machine scan-latency or physical-footprint measurement.

## Invocation and artifacts

The sequential invocation was:

```sh
TIDY_VERIFICATION_OUTPUT=/tmp/tidy-remediation-final-verification \
  bash scripts/verification/verify.sh
```

Dedicated existing build caches were reused; the test suites themselves reran. Logs and result bundles:

- `/tmp/tidy-remediation-final-verification/core.log`
- `/tmp/tidy-remediation-final-verification/isolated-process-cap.log`
- `/tmp/tidy-remediation-final-verification/models.xcresult`
- `/tmp/tidy-remediation-final-verification/native-ui.xcresult`
- `/tmp/tidy-remediation-final-verification/release.log`
- `/tmp/tidy-remediation-final-verification/final-gates.log`
- `/tmp/tidy-remediation-final-verification.log`

The sequential script passed all tests and built Release, then exited at the existing multi-architecture `lipo -verify_arch` invocation. The installed tool rejected that invocation. Each architecture succeeds when verified individually. The verifier, local package helper and release workflow now use separate required checks. Both positive checks and a negative x86_64 check against an arm64-only test executable passed; the corrected remaining artifact checks and all exact test-result gates were then rerun successfully. The original script failure remains in the raw log; this record does not mislabel it as a clean end-to-end script exit. Shell syntax and release-workflow YAML checks passed. No remote CI was dispatched.

The Release application is `/tmp/tidy-final-release/Build/Products/Release/Tidy.app`, version 1.5.0, build 1. Executable SHA-256:

```text
24ceb69087e430d1a7ed48ec1df94bd1e24b1605778d5de52389a0e6e2481d16
```

This is an executable checksum, not acceptance of a signed/notarized distributable package. No release was published and no host security/permission policy was changed.

## Preserved failures and recovery

An intermediate 685-test Core run failed one unchanged timing assertion; the same binary's focused case and later full aggregates passed without relaxing it. A subsequent complete verifier run passed 689 Core tests but failed 1 of 137 model tests because initial snapshot publication could precede subscription. `ce89f22` fixes that ordering by replaying the latest observed state during registration. Deterministic RED/green, the full affected monitor/model suites, and the fresh aggregates above verify the correction. The failed verifier artifacts remain under `/tmp/tidy-remediation-before-snapshot-replay/`.

Earlier native runner-startup failures remain historical evidence. The later complete synthetic native suite passed, including the Settings accessibility row/editor/metadata and submission checks; it does not replace a human VoiceOver session or production native journeys.

The restored isolated Desktop worktree was fast-forwarded after all 389 pre-move file hashes matched the preserved snapshot. Its older tracked WIP is retained in Git stash `3325e977f674f2201c4680c1a5c07f50d978fcdb`; the old untracked dependency record and source/patch backups remain in `/private/tmp/tidy-workspace-move-preservation-20260918/`. Main stays at `9e1a500` with its pre-existing untracked audit/migration inputs preserved.

## Remaining scope

See `headroom-acceptance.md` and `remediation-dependency-blocks.md`. R02 lacks accepted real producer ownership/exclusion proof; production effects, recovery and dependent program work remain open. Index-disabled terminal partial scans truthfully offer no Continue. R09–R11 breadth, production native journeys, human accessibility, reference hardware/OS and physical measurements, complete privacy/network evidence, and packaging/install/upgrade/uninstall/distribution acceptance remain unfulfilled. Passing source/build/fixture gates does not close those requirements.
