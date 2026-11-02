# Tidy 1.5.1 (2) update candidate — 11 October 2026

The owner authorized pushing Tidy, publishing its DMG and updating the installed
Mac app. This delivery is still pending the final source, native and CI gates.
The original main checkout is preserved; implementation continues on
`CAJ/tidy-completion-20261010`. The current pushed head is `2b7b1aa`, in draft
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

## 2b7b1aa hosted and local verification

Hosted run [38109504490](https://github.com/Ajraba04/tidy/actions/runs/38109504490)
passed Core 881, isolated process-cap 1, models 187 and presentation 2. Production
native executed 14 cases with four failures: owned compact Settings metadata
contrast, manual-fixture reopening, and two teardown control-window focus failures.
The tested PR merge commit was `6b92e84dc0f8dc04696fd195d1e5640261360185`;
its tree and branch head's tree both equal
`ea45c738bec88ebec04cef9f80ef5d1f21992ab2`. This is tree equivalence, not
exact-head binary provenance or a hosted pass.

The requested fresh canonical local run at `2b7b1aa` passed Core 881/112
(224.138 seconds), isolated process-cap 1, models 187 (76.461 seconds) and
presentation 2 (32.908 seconds). Production native executed 14 cases with ten
failures in 638.368 seconds. Its exit was 65; the failed aggregate remains retained
in `dist/verification/local-ci-2b7b1aa-20261011`.

A bounded unified-log investigation directly recorded XCTest generating Command
(key 55) and Q (key 12) while typing the literal Latin search query, followed by
normal AppKit termination and launchd exit `(0, 0, 0)`. The selected input source
was Arabic; ABC was already enabled. The keyboard-layout explanation is an
inference pending unchanged-case verification with ABC selected. No production
search code or input-injection workaround was introduced.

The compact contrast report named a four-field synthetic accessibility value,
while the view rendered seven metadata lines. A first experiment exposed all seven
strings in that value. Three affected model cases and the complete 187-model batch
passed, but the compact audit still failed on partly visible Build Prep metadata.
Its element image extended below Tidy's window into another app's content; this
failed evidence stays private and local.

The current repair preserves the VStack, semantic colors, spacing, seven
components and separate editor. It exposes a named metadata group with seven real
text children, removing the synthetic static-text trait, value and hint. Native
contracts require the group, seven nonempty children and exact component text;
all geometry assertions and the complete audit/classifier remain intact. Three
focused model cases pass. The first hierarchy check stopped before audit on a
native label/value test assumption; source review found the same P2 and it was
corrected using native static-text value with a label fallback. A bounded Astra
code review closed that finding at source level. The content-complete case then
reached the unchanged audit and failed on `buildPrep.primary.4` at
`(958, 577.8018, 88, 16)`, partly below the window `(942, 33, 480, 552)`.
The focused viewport probe failed with the original classifier and measured
captured/live `settings.content` identically at `(958, 254.5, 448, 314.5)`.
Its bottom is y=569; the offending Rule text starts y=577.8018. The complete
text rectangle is therefore outside the rendered viewport. No new exclusion was
used in that probe. The coordinator accepts one bounded correction only if exact
metadata identity/content and stable geometry establish full clipping, and the
same text is covered by a later successful full audit while wholly visible.
Any unresolved obligation or visible/intersecting contrast report must fail.
Otherwise this mandatory gate remains a precise publication/install blocker.

Both changed presentation cases passed in
`native-real-text-presentation-2.xcresult`; the current production hierarchy's
universal build passed in `release-real-text-build.log` with both architectures
and production-only binary composition. The bounded viewport proof implementation is compiled and ready for one focused
runtime attempt. It observes only materialized lazy rows, binds exact identities
and text across scrolling, validates stable snapshots, and requires a successful
full audit while each deferred group is wholly visible. Scroll movement uses the
measured geometry and fixed attempt/cap limits. A bounded Astra code review found
no actionable issue; no runtime pass is inferred. Project membership, personal-
data scan, exact privacy inventory, fixture composition and strict host/runner
signatures pass. The required final 14-case production native aggregate remains
pending. Desktop automation is held while the user is actively using the Mac;
Arabic was restored and verified at the last handoff.

With the already enabled ABC input source selected through the configured
Control-Space shortcut, the unchanged dark input case passed (42.282 seconds).
All three Window-menu focus journeys passed: diagnostic export (40.641 seconds),
manual review (48.350 seconds) and optional data (49.422 seconds). The five-case
batch retained its one compact audit failure. ABC selection is temporary;
Arabic was restored and verified before the coordinator's short profile turn.
Any subsequent temporary ABC selection must likewise be restored. The input-source route
is documented by [Apple](https://support.apple.com/en-gb/guide/mac-help/-mchlp1406/mac).
The focus helper retains hittability, app-exit and canonical-root cleanup checks.

Local toolchain is Xcode 27.0 / Swift 6.4 on arm64 macOS 27.0.1; hosted toolchain
is Xcode 16.2 / Swift 6.0.3 on macOS 14.8.9. These environments are not equivalent.

## Installation and publication

The installed app is still 0.1.0 (1). A complete private copy of its four app files
and three support-data files was verified before replacement; original bytes and
modes were rechecked unchanged before travel. The exact backup path and witness
are retained locally in `original-install-backup.json`; no backup content is
published here.

No 1.5.1 tag or release has been created and no installed bundle was replaced.
Earlier local packages predate these preservation fixes and must not be installed
or uploaded. The owner reported unavailable Actions allowance; the coordinator permits the
existing local package route after every required local gate passes and only in
the absence of a mandatory hosted protection gate. This does not turn failed
hosted evidence into a pass or authorize changing billing, protection or tests.
No package upload or installation proceeds while required native gates are red. Verify asset checksums/provenance, revalidate the backup and
originals, replace the bundle recoverably, then verify version and safe startup
with settings/history bytes preserved. Do not bypass Gatekeeper or add permissions.

The separately approved disposable SDK experiment stays outside this Mac update.
It has not run and does not qualify a production adapter.
