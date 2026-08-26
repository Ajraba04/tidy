# T05.A2F settings publication foundation verification

Source started from BASE `71450c8`; review BASE is `20f2970`, whose only intervening change is the independently reviewed A2P documentation. Scope: explicit-URL durable settings publication and rollback foundation. Independent source review remains pending. This is not A.2P process/crash acceptance, A.3 app cutover, complete T05, or release acceptance.

## Implementation and boundaries

The settings actor now validates complete preferences, checked revision increments and bounded encoding before writes. It rechecks exact loaded images under a stable lock, publishes owner-only prepared-marker/candidate/exact-old backup artifacts in the specified P0–P5 order, and retains conservative recovery state on partial publication. Rollback is bound to an opaque store-issued preview and exact backup identity/bytes. Existing read-only migration, unsafe-file rejection and no-follow/nonblocking reads remain required.

The controller approved extracting the existing journal checked-write loop unchanged into internal `JournalCheckedWrite`, shared by both publishers. No separate persistence protocol or execution authority was introduced. The one A.1 staging-only unavailable-write test was migrated to successful save plus unissued-preview/recovery rejection, preserving its safety checks. Legacy ConfigStore, production app, policy bridge and effect paths are unchanged; this intermediate build is not a deployable migration release.

## Tests-first evidence

- Initial behavioral RED: 39 methods in two suites, 51 issues, 2.035s after declaration-only compiler scaffolding. Valid edits still returned unavailable and real fault/transaction assertions could not execute successfully.
- First GREEN: 39 methods/two suites, 0.932s, excluding initialized FIFOs until the controller's actual source/lifetime audit.
- After that audit, all seven initialized FIFO arguments passed in0.092s without rescue, preserving inode/mode/bytes and releasing the stable lock while stores remained alive.
- All five bootstrap and twelve publication faults execute real POSIX failures and assert the exact caught stage/errno, required preceding operations and forbidden later operations. EBADF faults are invalid-descriptor failures, not media-error claims; marker unlink uses actual owned-directory EACCES.
- Two self-review tests first failed with three issues: changed same-inode marker bytes could be deleted, and rejected admission erased an earlier real failure diagnostic. Exact marker-image revalidation and diagnostic retention fixed both.
- A third real-I/O regression failed with five issues: after successful bootstrap, actual marker-create EACCES did not latch the original actor. The correction retains the bootstrap recovery latch until full transaction success. Stable-lock acquisition also resets the diagnostic stage before authoritative rechecks; the O_EXCL-loser race branch was not deterministically forced, and no race-specific RED is claimed.
- Additional verification-only tests cover six whole-preference bounds before missing-directory creation and successful owner-only fresh-directory publication. They passed their first run; no behavioral RED is claimed for those additions.
- Final implementer focused/covering run: `swift test --filter 'SettingsMigrationTests|SettingsPublicationTests|ConfirmedExecutionTests|RunRecoveryTests' --jobs 2`, 117 methods/four suites passed in4.947s (build6.55s), no compiler warnings. Existing shared checked-write progress/EINTR and short-write tests remain unchanged.

## Controller verification

Initial full run: `swift test --jobs 2`, build0.49s; **322 tests/42 suites failed in11.313s with three issues**. Under full-suite concurrency, `independentHeldLockBlocksWithoutWritingThenExplicitRetrySucceeds` observed the holder watchdog fire and an unexpected successful update, and `independentBootstrapContenderCannotInitializeWinnersMetadata` missed its two-second entry deadline. Focused success is insufficient; scheduling/fixture investigation is in progress. The initial sandbox-only manifest error preceded the approved retry and is not source RED.

The unmodified repeat reproduced the same three failures in14.020s. Observation-only monotonic traces then showed a1.762s gap between actual holder lock acquisition and its resumed test continuation, followed by a0.47ms update attempt. Bootstrap task launch also waited1.653s before entering its body. That instrumented run passed322/42 in36.971s, demonstrating scheduling sensitivity rather than proving the fixtures robust.

The controller approved serializing only `SettingsPublicationTests`, preserving all parameterized cases, internal actor/thread/task contention,2s/5s deadlines and drain-before-cleanup assertions. The next normal parallel full run passed322/42 in18.842s (build14.82s): observed holder scheduling gap3.593ms and update attempt1.095ms. Temporary traces were then removed. This is bounded fixture workload scheduling; the legacy four-job/blocking-task process runner is unchanged and remains T04.B work. No global scheduler/storage hard-latency claim is made.

Clean controller rerun after removing all diagnostic prints: `swift test --jobs 2`, **322 tests/42 suites passed in23.054s**, build14.40s, exit0. All prescribed fault/FIFO cases remain selected. No compiler/test warning or error lines; `git diff --check` passed.

Unsigned production arm64 app build: `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO`, exit0 with no output. Existing derived data was reused. No app was launched. Independent source review remains pending.

## Independent review correction

Initial source review of20f2970..ab991f7 found one Important: a successful exclusive create could fail subsequent validation before recording sticky recovery state. A fresh fixer moved the latch immediately after successful open, before throwing validation; failed opens remain non-latching. The isolated inherited-mask regression observed actual0200 files and failed four assertions before correction, then passed both bootstrap/initialized cases afterward. Covering118/4 passed4.673s. See [source review](T05-A2F-source-review.md) for runner isolation, exact artifact preservation and error-classification evidence.

Controller post-correction full `swift test --jobs 2`:323 tests/42 suites passed12.252s, build0.48s, exit0. Fresh unsigned arm64 app build with the command above exited0 without output. Independent corrected-source re-review is pending; these runs do not establish A2P or app cutover.

## Remaining acceptance

Actual independent-process contention, bootstrap winner death, P1–P5 abrupt child exit and fault-free child reopen require A.2P after accepted T04.B. A.3 still owns atomic app cutover, off-main integration, policy noncommit, UI/import/in-flight lifetime acceptance. No physical power-loss, hostile-owner, blocked-filesystem hard latency, supported Intel/macOS14 or full-device acceptance follows from these tests. No push, tag, release, live migration or app launch was performed.
