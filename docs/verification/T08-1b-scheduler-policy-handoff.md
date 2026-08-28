# T08.1b scheduler-policy handoff verification

## Scope

- `TidyCore/Sources/TidyCore/Execution/ExecutionPolicyBridge.swift`
- `TidyAppModelTests/SharedSettingsWiringTests.swift`
- `TidyCore/Sources/TidyCore/Scanning/WorkScheduler.swift`
- `TidyCore/Tests/TidyCoreTests/WorkSchedulerTests.swift`

## Behavioral evidence

- A real `SettingsStore` invalidating global save closes the bridge-owned
  scheduler before its asynchronous prepare/save work begins. Existing façade
  sessions reject new grants with `admissionUpdating`; a queued grant does not
  execute until the exact durable saved envelope commits.
- A real external revision conflict and an actual publication replace failure
  both leave the façade unavailable; neither path reopens admission.
- Cancellation after admission cannot persist or commit a scheduler token:
  invalidating work remains unavailable, while the presentation token is
  discarded and existing admission remains usable.
- A cancellation observed only after `SettingsStore` has returned its durable
  envelope completes the exact scheduler/bridge acknowledgement instead of
  reporting a failed outcome with an invisible saved revision.
- Global and legacy scheduler candidates retain `activeProfileID` and inert
  imports. The acknowledgement handed to the scheduler is therefore the same
  durable envelope that `SettingsStore` saved.
- Each accepted non-presentation bridge handoff takes an internal,
  controller-capability-issued admission hold. An otherwise-open core barrier
  stays closed until the last such terminal handoff releases its own hold, so
  an already queued permit cannot run in the interval between serialized
  scheduler commits. The behavior is covered by deterministic queue events,
  not task-yield timing.
- A rate edit embedded in a multi-touch preferences document takes the closing
  invalidating path. Revision-zero defaults and recovery loads leave the
  façade unavailable; a positive loaded revision is installed before façade
  work starts.
- Only the exact, integer-tagged `scan.uiBatchesPerSecond` global delta uses
  the non-closing presentation prepare path. While controller and bridge
  presentation gates are blocked, a new session and an already queued grant
  remain admitted; the exact saved acknowledgement updates revision without
  changing scheduler generation. A wrong-tag rate delta is rejected before
  persistence.
- The public façade vends only explicit session begin, permit, cancel, finish,
  state, and snapshot operations. Controller/capability/prepared-token,
  discretionary-session, lease, and raw-release authority remain bridge
  internals.

## Commands

```sh
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/tidy-headroom-build \
  -jobs 2 test -only-testing:TidyAppModelTests/SharedSettingsWiringTests \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 CODE_SIGNING_ALLOWED=NO
```

The focused app-model command passed: 84 tests, 0 failures.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter WorkSchedulerTests
```

The scheduler-core filter passed: 34 tests, 0 failures. Its existing source
emitted only the prior redundant `#require` warnings in
`HostileProductionRegressionTests`.

```sh
git diff --check
```

The final whitespace/error-marker check passed with no output.
