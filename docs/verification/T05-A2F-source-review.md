# T05.A2F source review

Reviewed range: `20f2970..ab991f7`. Reviewer `t05a2f_source_review` read the complete2052-line generated package sequentially, plus one focused unchanged shared-FIFO lifetime check. No tests, builds, child launches, source writes or Git mutations by the reviewer.

## Initial verdict

Spec compliance: one scoped defect. Quality: Needs fixes. No Critical or Minor findings.

Important: `SettingsPublication.create()` could successfully create an inode with O_EXCL and then fail descriptor/named-file validation before its callers set `recoveryRequired`. A restrictive inherited permission mask is one concrete trigger. The actor must latch immediately after successful exclusive creation, before any throwing validation; unsuccessful open/EEXIST must remain non-latching. Retained partial files already block normal subsequent reads/retries, so this is a sticky-state/error-classification contract gap, not evidence of enabled cleanup or general data loss.

The remaining inspected transaction order, exact-image/revision/rollback checks, nonblocking readers, finite limits, shared checked-write extraction and fixture lifetimes passed the source review. A2P actual processes, A3 app cutover and supported-device acceptance remain separate.

## Remediation in progress

A fresh fixer owns only the publication file and settings tests. The regression will exercise bootstrap-lock and initialized pending-marker creation in a separately launched test process inheriting a restrictive mask. It must not change process-global umask inside parallel Swift tests, add a production test hook, weaken assertions, or claim the isolated permission test supplies A2P crash acceptance. The controller audits the actual fixture and launch command before RED. No corrected-source approval is claimed yet.

### Isolated runner discovery

The installed Xcode SwiftPM uses a loadable `TidyCoreTests.xctest` bundle, not a directly executable test file. Controller checked SwiftPM's [test runner argument construction](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Commands/SwiftTestCommand.swift), then verified the installed `swiftpm-testing-helper` with the actual bundle path and a single known pure test. That test passed1/1 in0.009s, exit0. The helper requires the installed XCTest/Testing framework and support-library paths in command-scoped DYLD_FRAMEWORK_PATH/DYLD_LIBRARY_PATH. Two earlier loader-only failures and a deliberate no-matching-tests exit69 are runner-discovery evidence, not regression RED or test coverage.

Build the regression normally, then launch only its filtered test through that helper in a fresh shell whose inherited umask is0400. The shell/test process exits after the run; no Swift test calls umask and the controller's environment, other tests, shared caches and production app are unchanged. HOME is not reassigned. The test must print/verify the actual creation mode and both bootstrap/marker arguments, not rely solely on the command or exit code.

### Actual regression RED

Controller audited the new parameterized method and all four helpers before execution: only canonical owned scratch is seeded/chmodded; probe descriptors close before exact-name unlink; no test calls umask, launches a child or installs a production hook. Normal `swift test --filter inheritedCreationMaskLatchesImmediatelyAfterExclusiveCreate --jobs 2` built in13.38s and passed one method/two cases in0.067s, printing actual0600 creation mode for both.

The separately launched installed helper, with umask0400 inherited before startup, printed actual0200 mode for both bootstrap-lock and initialized pending-marker cases. It failed with **four issues in0.027s, exit1**: each save returned unsafeLocation instead of writeFailed, and an immediately submitted invalid preference returned invalidChange instead of readOnlyRecovery. That second request occurs before reload and must be rejected from sticky actor state. Exact existing config/backup/metadata and zero-sized partial-inode preservation assertions otherwise passed. This is real post-create validation RED; no compiler/loader failure or synthetic syscall result is counted.

### Correction and GREEN

The fresh fixer moved recoveryRequired to immediately after the successful-open guard in create(), before descriptor/named-file validation, and removed the two delayed caller assignments. Failed open/EEXIST still returns before the latch. Controller inspected the complete three-hunk production delta.

Normal covering settings/execution/journal run:118 tests/four suites passed in4.673s (build4.15s), including the existing non-latching contention/pre-create failure checks. The identical isolated helper command then passed one method/two actual0200 cases in0.015s, exit0. No production hook, global test-process mask mutation, deadline relaxation or ignored assertion was added.

Controller post-correction full `swift test --jobs 2`:323 tests/42 suites passed in12.252s, build0.48s, exit0. Post-correction unsigned arm64 production app build reused `/private/tmp/tidy-headroom-build`, jobs2, and exited0 without output. No app launch. Independent re-review remains pending.
