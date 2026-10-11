# Tidy 1.5.1 (2) update candidate — 11 October 2026

The owner authorized pushing Tidy, publishing its DMG and updating the installed
Mac app. This delivery is still pending the final source, native and CI gates.
The original main checkout is preserved; implementation continues on
`CAJ/tidy-completion-20261010`. The previous pushed head is `01713a6`, in draft
[PR 1](https://github.com/Ajraba04/tidy/pull/1).

## Upgrade preservation

Startup no longer applies default history retention to migrated revision-zero,
absent or malformed settings. History maintenance and completed-run recording
require a genuine positive bridge acknowledgement, matching current app state
and the exact settings actor/disk image. The read check does not reload settings,
adopt external values, invalidate previews or latch recovery.

The first global edit materializes existing legacy preferences only when the
stored typed document is absent. Store, bridge prediction and optimistic app
replay agree, while raw compare-and-swap and strict decoding remain intact.
Completed terminal reports survive owner cancellation and presentation-save
races. Validation retries are limited to eight attempts; exhausted retries show
a persistent not-stored warning without changing existing history.

The relaunch model fixture now disposes and joins the former service's monitoring
readers before starting a replacement service. This models process exit rather
than two simultaneous service instances. Its original profile and units assertions
remain; the new instance must also report a normal loaded disposition.

## Current evidence

All logs below are retained under `dist/verification/release-1.5.1-20261011`.

| Check | Result | Evidence |
| --- | --- | --- |
| Final Core | 881 tests in 112 suites passed, 169.877 seconds | `core-final-full.log` |
| Isolated process cap | 1 test passed, 0.511 seconds; relevant source unchanged | `isolated-process-cap.log` |
| Final focused app regressions | 14 tests passed | `maintenance-final-focused-green.xcresult` |
| Prior complete model batch | 184 tests, two assertions failed in one relaunch case; focused lifecycle correction then passed | `models-final-full.xcresult`, `document-relaunch-lifecycle-green.xcresult` |
| Final complete models | 187 tests passed, 72.137 seconds | `models-final-187.xcresult` |
| Final universal Release | Passed; final source universal build | `release-final-prepare.log` |
| Native signed preparation | Fresh host/runner exist and strict signatures pass; fixture composition passes | `native-clean-build.log`, `native-ready-build.log` |
| Native runtime before restored login | No UI acceptance: automation mode initialization timed out | `production-native-bootstrap-repaired.xcresult` |
| Native runtime after restored login | 1 isolated initialization test passed after sign-out/in | `native-restored-session.xcresult` |

The earlier compact accessibility failure remains required, not excluded. Human
VoiceOver, reference hardware, privacy-purpose/distribution and positive producer
acceptance remain separate unfinished evidence. Production manual providers and
catalog mutations remain denied; unattended cleanup stays off.

The maintenance validation race was reproduced before its bounded retry fix.
Four focused assertions failed before implementation; the final 14 focused and
187 aggregate model tests pass. The final uncommitted source review reports no
actionable regressions. The complete native suite, including the compact audit,
is still unverified for this candidate.

## Installation and publication

The installed app is still 0.1.0 (1). A complete private copy of its four app files
and three support-data files was verified before replacement; original bytes and
modes were rechecked unchanged before travel. The exact backup path and witness
are retained locally in `original-install-backup.json`; no backup content is
published here.

No 1.5.1 tag or release has been created and no installed bundle was replaced.
Earlier local packages predate these preservation fixes and must not be installed
or uploaded. Publish only through the existing required release workflow after
exact-head CI passes. Verify asset checksums/provenance, revalidate the backup and
originals, replace the bundle recoverably, then verify version and safe startup
with settings/history bytes preserved. Do not bypass Gatekeeper or add permissions.

The separately approved disposable SDK experiment stays outside this Mac update.
It has not run and does not qualify a production adapter.
