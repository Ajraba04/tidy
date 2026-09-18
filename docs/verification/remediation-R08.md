# R08 live settings, monitor ownership, and measurement truth

Date: 2026-09-17

## Implemented outcomes

- `SystemMonitor` now owns independent, idempotent scene leases and a separate explicit-work lease used by scans. Generation-bound scene transitions prevent a late appear task from resurrecting sampling after disappear or teardown.
- Memory-pressure events publish immediately to active subscribers without waiting for the five-second sampling interval or invoking another probe. Subscription generations reject callbacks from a stopped/replaced source, so a stale nominal event cannot clear a current critical state.
- Acknowledged settings revisions are applied through one app-owned binder. `SystemMonitor` rejects stale revision delivery, and selected-volume facts reject older measurement timestamps.
- `feature.headroom=false` stops repeating work and makes manual refresh return an explicit unavailable snapshot without invoking an OS probe.
- Headroom and menu surfaces consume acknowledged card and unit preferences. An explicitly empty `ui.cards` list remains empty. Binary output uses KiB/MiB/GiB labels; decimal output uses kB/MB/GB labels.
- Disk resource decoding rejects every missing or invalid capacity field instead of converting it to zero. A measured UUID and positive capacity resolve automatic Headroom targets; a mount path never becomes approval identity.
- Every registry row has tested production-consumer metadata. Unsupported R09-R11, incremental-index, authority, and presentation controls remain visible with exact unavailable reasons and cannot submit edits from the Settings surface.
- Optional completed-run history is independent of mandatory recovery. Its actor is confined to an owner-only directory and exact `runs.jsonl` name, serializes record/reconcile operations, bounds reads before allocation, rejects symlink/FIFO/directory/hard-link/oversized inputs, applies age and byte limits, and leaves recovery witnesses unchanged.
- The settings reference is generated deterministically from registry defaults, ranges, resolution/effect, allowed layers, and consumer metadata. A test byte-compares the committed `docs/settings-reference.md` with the renderer.
- Diagnostic rendering structurally excludes credentials, cookies, environment, argv, remotes, profile names, portable setting values, and personal path identity even when cosmetic redaction is off.

## Verification run

All commands used disposable build paths and at most two build jobs.

### Focused core behavior

Command used an isolated copy of `TidyCore` only because another active package was adding an intentionally red R02 test at the same time. `ResourceAuthorityTests.swift` was excluded from that disposable copy; no production source was excluded.

```text
swift test --package-path /tmp/tidy-r08-source \
  --scratch-path /tmp/tidy-r08-build/isolation --jobs 2 \
  --filter 'HeadroomSignalsTests|StatsTests|SettingsPresentationTests|OptionalRunHistoryTests|DiagnosticPrivacyTests'
```

Result: **53 tests passed, 0 failures**.

Covered outcomes include stale policy delivery, out-of-order scene transitions, explicit-work lifetime, disabled-feature zero probes, missing disk keys, binary/decimal labels, intentionally empty cards at the model layer, every registry row's consumer contract, committed settings-reference equality, optional-history age/byte/off behavior, unsafe optional-history storage denial, recovery witness preservation, and immutable diagnostic-renderer exclusions.

After the immediate memory-pressure path was added, the monitor suite was rerun incrementally:

```text
swift test --package-path /tmp/tidy-r08-source \
  --scratch-path /tmp/tidy-r08-build/isolation --jobs 2 \
  --filter 'HeadroomSignalsTests'
```

Result: **30 tests passed, 0 failures**, including immediate probe-free pressure publication and stale replaced-subscription callback rejection.

### App model integration

```text
xcodebuild build-for-testing -project Tidy.xcodeproj \
  -scheme TidyAppModelTests -derivedDataPath /tmp/tidy-r08-xcode \
  -jobs 2 CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building -project Tidy.xcodeproj \
  -scheme TidyAppModelTests -derivedDataPath /tmp/tidy-r08-xcode \
  -only-testing:TidyAppModelTests/HeadroomViewModelTests \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testAcknowledgedPolicyObserverPublishesOnlyDurableRevisions \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testMeasuredVolumeIdentityAndCapacityResolveHeadroomWithoutPathApproval \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testVisibleHeadroomAppliesAcknowledgedFeatureDisableImmediately \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsRowsAreReachableSearchAdvancedAndAuthorityIsDeferred \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsRepresentativeGlobalControlsUseSharedStore \
  -jobs 2 CODE_SIGNING_ALLOWED=NO
```

Result: build-for-testing succeeded; **15 selected tests passed, 0 failures**.

This covers two simultaneous view-model leases, duplicate appear/disappear, discarded subscriber teardown, intentionally empty cards, durable-only policy observation, measured-volume resolution, live acknowledged feature disable, and truthful editable/unavailable Settings rows.

### Application compilation

```text
xcodebuild build -project Tidy.xcodeproj -scheme Tidy -configuration Debug \
  -derivedDataPath /tmp/tidy-r08-xcode -jobs 2 CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**. The build had already reached success when the coordinator requested a pause on new large builds due temporary disk pressure; no further large build was started.

### Earlier safe baseline

Before implementation, the focused policy/settings/monitor baseline ran 172 tests with 0 failures. That run included the existing historical schema-1 shapes, known schema-2 shapes, corrupt/future read-only recovery, byte preservation, import/reset authority preservation, and settings publication fault suites. Those migration tests were not changed by R08. This is baseline evidence, not a substitute for the controller's final aggregate rerun on the integrated branch.

## Exact remaining gates

- The app-owned `AppExecutionServices` file is joint R06/R08 integration and remains unstaged for the controller's combined commit and final integrated verification.
- The post-review revision-guard/history-error-reporting edits in that shared file and the Settings-window error label have compile evidence from the immediately preceding app build except for the final error-reporting-only adjustment; the controller's final Debug/Release rerun remains required.
- Actual diagnostic file export, including real temporary/backup file lifecycle, is not implemented. Only the pure metadata renderer and its immutable exclusion candidates are tested; `export.redactDiagnostics` remains visibly unavailable.
- Full released-shape migration/import/reset suites need the controller's final integrated aggregate rerun. No R08 source weakens their existing read-only recovery or byte-preservation behavior.
- Native SwiftUI two-window journeys, menu popover lifecycle, accessibility, VoiceOver, and actual background timer/command/scan-I/O observation remain runtime gates. The controller recorded a host XCTest bootstrap failure for native UI after two attempts; model tests do not replace that gate.
- Real missing-resource-key delivery on production filesystems, real two-volume/remount identity behavior, and supported-host privacy API declarations remain production/platform gates.
- Hidden-idle ten-minute CPU/RSS, interactive/scan physical footprint, constrained-host cancellation, 8 GiB Apple Silicon and Intel, macOS 14/current, and human accessibility acceptance remain R13 gates.
- R09-R11 settings stay intentionally unavailable until their project/ecosystem/assistance consumers and positive/negative acceptance fixtures land. The generated reference records those limitations and does not claim full-program completion.

## Resumed integration correction — history policy ordering

A controller review found that monitor configuration rejected stale settings, but queued history retention/completed-run writes still accepted an older policy. The history actor now requires an acknowledged revision on every mutating request, rejects older revisions without filesystem changes, and rejects conflicting policies with the same revision. The app passes its acknowledged revision and prevents stale completions from replacing newer history-error state.

Test-first evidence: `/tmp/tidy-history-revision-red.log` failed because the revision-bound API did not exist; after the change, `swift test --package-path TidyCore --scratch-path /tmp/tidy-controller-baseline --jobs 2 --no-parallel --filter OptionalRunHistoryTests` passed **5 tests**, including delayed-on-after-off, delayed-off-after-on, conflicting same-revision, unsafe storage, retention and recovery-witness cases. Log: `/tmp/tidy-history-revision-green.log`. Final app/aggregate verification remains required after joint integration.

## Post-review corrections

The bounded R08 source review found three gaps and the follow-up resolves them without touching the shared R06 scan/index implementation:

- The production dispatch memory-pressure source now subscribes to normal recovery as well as warning and critical. Tests assert the production mask and prove that a current subscription publishes critical then nominal immediately without another probe; stale replaced-subscription callbacks remain rejected.
- Applying an acknowledged Headroom disable now publishes an explicit unavailable snapshot to existing subscribers before repeating work is canceled. The regression requires that publication without a manual refresh and proves the OS probe count does not change.
- Optional history validates existing data against a fixed 50 MiB storage safety ceiling before applying a newly smaller retention cap. A file valid under 2 MiB is trimmed to its newest record under 1 MiB; disable combined with the lower cap removes only `runs.jsonl` and preserves a mandatory recovery witness. Symlink/FIFO/directory and sparse 50 MiB + 1 byte inputs remain rejected.

Test-first evidence recorded the expected failures before each correction: the production mask omitted `.normal`, disable produced no replacement snapshot/broadcast, and both cap-transition fixtures threw `.oversized`. The final focused command was:

```text
swift test --package-path TidyCore \
  --scratch-path /tmp/tidy-controller-baseline --jobs 2 --no-parallel \
  --filter 'HeadroomSignalsTests|OptionalRunHistoryTests'
```

Result: **40 tests passed, 0 failures** (33 monitor/headroom and 7 optional-history tests). Existing compiler warnings outside the changed behavior remain; no app build, app-model suite, hardware, native UI, export-file, migration, package, or release gate was claimed by this correction.

## Additional integration correction — volume ordering and monitor disposal

The app no longer orders measured-volume facts by `SystemSnapshot.observedAt`. The one app-owned volume observer assigns a strictly increasing `UInt64` epoch in stream-delivery order, and `AppConfigStore` rejects equal or older epochs. A newer missing-volume or remounted-volume observation therefore replaces stale UUID/capacity state even if wall time moves backward; a delayed older epoch cannot restore it.

`AppExecutionServices` now has an explicit, idempotent monitoring disposal path. Its ordinary deinitializer closes a small lock-protected Sendable lifetime gate and cancels the Sendable volume task synchronously, then schedules removal of the captured services-owned observer token on `MainActor` without capturing `self`. Scan/index generation resources and unrelated policy observers are not touched.

Test-first evidence used the existing `/tmp/tidy-r08-xcode` cache with two jobs. Before correction, the focused model run produced five assertions: the rollback fixture retained the stale 10 GiB target across newer missing/changed observations, and teardown left one monitor subscriber plus both policy observers registered. After correction:

```text
xcodebuild test -project Tidy.xcodeproj -scheme TidyAppModelTests \
  -derivedDataPath /tmp/tidy-r08-xcode -jobs 2 CODE_SIGNING_ALLOWED=NO \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testMonotonicVolumeEpochAcceptsNewerMissingAndRemountedObservations \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testExecutionServicesTeardownCancelsVolumeObservationAndOnlyItsPolicyObserver
```

Result: **2 tests passed, 0 failures**. This is focused app-model evidence. It does not close real remount/filesystem delivery, wall-clock-change runtime, native UI, hardware, export, migration, package, or release gates.

### Toolchain-compatible teardown follow-up

The initial disposal implementation used `isolated deinit`, which requires Swift 6.2 and is not compatible with the macOS 14 CI image's Swift 6.0 toolchain. The compatible implementation uses ordinary `deinit` plus the Sendable lifetime gate described above. Policy and volume callbacks check that gate before starting work and after suspension points, so a still-registered callback cannot install history/error state after disposal while main-actor token removal is pending. The explicit disposal path remains idempotent and removes its token synchronously.

Focused verification reran exactly the automatic-deinit and repeated-explicit-disposal cases in `/tmp/tidy-r08-xcode`: **2 tests passed, 0 failures**. The explicit test saves a later acknowledged policy after two disposal calls and proves the unrelated observer still fires while the disposed monitor revision does not change.
