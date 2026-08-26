# T04.A journal foundation verification

Source BASE: `142f90a`. Scope: durable journal and mandatory admission persistence only. Independent source review is pending; this is not full T04 or release acceptance.

## Implemented scope

- One bounded scanner and checked publisher serve mandatory and diagnostic storage; ambiguous staging is preserved and blocks admission.
- Checksummed, bounded journal replay enforces state transitions and supports only confirmed no-effect completion. No positive-effect proof or ledger-clearing API was added.
- Optional completed history has its own configurable allowance. Eight active diagnostic slots and the mandatory ledger remain separately bounded and are not history-evicted.
- Nonblocking/no-follow leaf readers validate regular-file type, ownership, permissions, link count and named/descriptor identity before reading.

## Test evidence — 2026-08-26

The implementer recorded natural missing-API compilation failure separately from genuine behavioral RED. Initial non-FIFO execution failed 42 methods with 79 issues. A later exact-child-association regression failed with three issues before its correction.

Final focused command: `swift test --filter 'RunRecoveryTests|ConfirmedExecutionTests' --jobs 2` — exit 0, 72 methods in 2 suites (44 journal, 28 unchanged admission/coordinator), 3.784 seconds. The diagnostic FIFO test passed after the controller audited its reader and watchdog lifetime, without watchdog rescue. No blocking defect was manufactured.

Controller full suite: `swift test --jobs 2` — exit 0, 297 tests in 41 suites, 13.051 seconds. Build 0.38 seconds; no compiler/test warnings. `git diff --check` also passed.

Controller unsigned arm64 production app build: `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO` — exit 0 with no output. No app was launched and no release artifact was published.

## Remaining boundaries

## Shared FIFO test-support correction — 2026-08-26

The user directly resumed after the narrow shared-helper approval request. The tracked shared-FIFO amendment supersedes the plan's separate-copy instruction. One package-test-internal FIFOReadWatchdog now serves ConfirmedExecutionTests, RunRecoveryTests and SettingsMigrationTests; all assertions and caller catch/drain/cleanup ordering are unchanged. No production source changed.

Fresh pre-refactor full baseline:297 tests/41 suites, exit0,10.986s. Controller inspected the actual extracted helper and all three caller diffs before approving FIFO execution. Focused post-refactor:92 tests/3 suites, exit0,3.562s (build9.15s). Controller post-refactor full suite:297 tests/41 suites, exit0,12.808s (build0.60s). No compiler/test warnings in the successful runs; sandbox-only manifest failures preceded approved retries. `git diff --check` passed. Prior unsigned production build evidence applies to unchanged production source; no new app build or launch was needed for this test-only extraction. Independent re-review remains pending at this checkpoint.

## Remaining full-program boundaries

Real subprocess ownership/recovery, supported positive effects and terminal proofs, aggregate manifest/proof reservations, joint optional report accounting, persisted-settings/app integration, Intel and macOS 14 device verification, physical interruption testing and the rest of T01–T24 remain open. Fault injection does not establish power-loss durability or a hard syscall latency guarantee. The user requested README/GitHub/DMG delivery after the full program is finished, not a foundation-only preview.
