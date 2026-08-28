# T08.1b scheduler-policy handoff verification

## Scope

- `TidyCore/Sources/TidyCore/Execution/ExecutionPolicyBridge.swift`
- `TidyAppModelTests/SharedSettingsWiringTests.swift`

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

The focused app-model command passed: 81 tests, 0 failures.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter WorkSchedulerTests
```

The scheduler-core filter passed: 33 tests, 0 failures. Its existing source
emitted only the prior redundant `#require` warnings in
`HostileProductionRegressionTests`.

```sh
git diff --check
```

The final whitespace/error-marker check passed with no output.
