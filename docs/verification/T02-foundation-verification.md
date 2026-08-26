# T02 foundation verification — awaiting independent source review

Date: 2026-08-26. Worktree: `/private/tmp/tidy-headroom.wUbV9h`, branch `CAJ/developer-headroom`, source base `10f6901`. The approved app-entry documentation checkpoint is `1ad8ca8`; it contains no implementation source. Source is currently uncommitted and has not received its final independent review.

## Scope and limits

This checkpoint concerns real registered reviews, opaque one-use confirmation tokens, synchronous policy invalidation, fail-closed durable admission and shared app-model lifetimes. The production capability registry still denies every unaccepted mutation. No positive cleanup, per-item mutation boundary, child/daemon recovery, actual second process, positive native confirmation dialog or full T02/T05 acceptance is claimed.

All new T02 storage tests use fresh UUID-owned disposable roots. No normal Tidy launch, user cleanup, signing change, installation, publishing or remote Git write has been performed for this unit. The pre-existing full suite includes read-only host/tool probes. The host is an 8 GiB arm64 Mac on macOS 27 developer build 26A5406e with Xcode 27; it does not satisfy stable-OS, Intel or oldest-supported macOS 14 acceptance.

## Core evidence

Commands ran from `TidyCore`, with `--jobs 2`. Initial sandbox cache/manifest permission failures were followed by approved unsandboxed retries; these environment failures are not behavioral RED.

| Stage | Evidence |
|---|---|
| Missing API | `swift test --jobs 2 --filter ConfirmedExecutionTests` failed because the proposed coordinator/review/intent APIs did not yet exist. |
| Initial behavioral RED | `swift test --jobs 2 --filter 'ConfirmedExecutionTests\|ConfigStoreTests'`: 27 tests, 3 suites, 45 issues. Failures included actual bootstrap admission, throwing save and policy projection. |
| Real token branches | Subsequent runs reached genuine issued tokens: 40 then 24 issues included stale binding/policy, busy token consumption and uncertainty-after-confirmation. |
| Prescribed GREEN | Same focused filter: 27 tests, 3 suites passed, exit 0; 0.273 seconds test time. |
| Additional RED/GREEN | Relocated journal and legacy missing-disposition decoding failed first; after fixes, 32 tests, 3 suites passed, exit 0. |
| Ancestor-symlink RED/GREEN | Adding `CleanEngineTests` gave 44 tests, 4 suites. The new regression initially observed ready admission and bootstrap writes through a symlinked ancestor. Component-wise descriptor-relative opening/creation and anchored enumeration fixed both failures; 44/4 passed, exit 0, 0.310 seconds. |
| Public API boundary | Real imported-module clients cannot call raw `execute(plan:environment:)`, construct `ConfirmedPlan`, or read its nonce. Each fails with an access-control diagnostic. Legitimate coordinator confirmation/execution typechecks successfully. Raw execution had typechecked before internalization, establishing API visibility RED. |

The symlinked-temp fixture correction canonicalizes only the known existing temporary base with Darwin `realpath` before allocating a UUID directory. Foundation normalization had left `/var/folders/...` intact despite `/var` being a symlink. Production no-follow checks were not relaxed.

The raw engine entry is now internal and unconditional denial-only; latent mutation bodies were removed. Callback registration grants no capability. The journal has no reset/reconciliation API; any unfinished intent still blocks admission regardless of lock availability or process lifetime.

## App-model test isolation audit

The controller inspected the generated project, complete scheme, actual six-source test module, compiled SwiftFileList and generated `.xctestrun` before authorizing the first test run.

- Target: `TidyAppModelTests`, unhosted macOS unit-test bundle, local TidyCore dependency only.
- Exact sources: `ConfirmationLifecycleTests.swift`, `PlanSelectionModel.swift`, `CleanViewModel.swift`, `CustomViewModel.swift`, `AppExecutionServices.swift`, `AppConfigStore.swift`.
- Both generated configurations explicitly have empty `TEST_HOST` and `BUNDLE_LOADER`; no app target dependency or fixture resource phase exists.
- Generated test metadata lists only `TidyAppModelTests.xctest` as a dependent product. Its runner is Xcode's `Agents/xctest`, not Tidy or a fixture application.
- Services require explicit config, home, config URL and journal URL. The tests provide only scratch paths. Startup constructs a literal empty tool snapshot, pure policy projection, real coordinator/bridge/store and discovery engine; it does not load ambient settings, probe tools, launch commands or append an ambient run log.
- The separate manual review host retains its exact five-source membership. No services/VM/engine entry was added to that host.
- Shared `/private/tmp/tidy-headroom-build` is cache reuse only; jobs are serialized. A current successful `build-for-testing` is required before `test-without-building`. No broad clean is authorized.

`xcodebuild -help` accepted all three timeout options. The generated test metadata defaults to disabled timeouts/600 seconds, so every behavioral invocation explicitly overrides it with `-test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 60`. A timeout is a test failure; any hung-run scratch root must be retained for inspection.

## App-model RED and current work

The first build-for-testing failed on missing app-service API and the now-throwing legacy save call. After safe interface scaffolding, build-for-testing succeeded. Neither compile result establishes lifecycle correctness.

The first actual behavioral run completed normally: 13 tests, 22 failures, no unexpected failures, exit 65, 1.127 seconds. It reproduced missing setter invalidation, missing successful review installation, immutable capture lost during automatic dismissal, an old dismissal clearing a new presentation, a static observable generation and stale/out-of-order/reopened request lifetimes. This was not a runner, signing or timeout failure.

Result bundle: `/private/tmp/tidy-headroom-build/Logs/Test/Test-TidyAppModelTests-2026.08.26_14-50-32-+0400.xcresult` (local temporary artifact; retention is not guaranteed).

Two additional tests first failed on reusable direct take and replacement retaining the old safe projection instead of the real deep review: 2 tests, 5 failures, exit 65. After implementation, the complete 15-test bundle passed. A composition refactor then put the lifecycle algorithm in one app-internal `AppReviewSession`, with thin concrete Clean/Custom VMs; all 15 passed again. Its source remains excluded from the manual host.

The descriptor follow-up removed URL-based volume lookup, which had reopened the namespace after no-follow capture. `fgetattrlist` now reads and validates `ATTR_VOL_UUID` from the retained leaf descriptor without a path fallback. The covering 44-test core run passed after that change, using actual local APFS capture/change/symlink cases. Unsupported filesystems remain unverified and fail closed. Missing default settings location now constructs no fallback service and displays unavailable scene content; that nil-path UI is source/build verified only, not natively observed.

## Controller final verification

All following runs used final paused source after shared-session extraction, retained-descriptor volume capture, nil-path handling and results text corrections. Heavy jobs ran sequentially.

| Check | Exact command / result |
|---|---|
| Full core | From `TidyCore`: `swift test --jobs 2`; exit 0, **203 tests / 38 suites passed**, 9.549 seconds test time. This is a test-run duration, not a low-spec performance benchmark. |
| Production app | `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO`; exit 0, no output. No launch. |
| Manual host | Same build command with `-scheme TidyUITestHost`; exit 0, no output. No launch. |
| Current app-model bundle | Same command with `-scheme TidyAppModelTests` and `build-for-testing`; exit 0, no output. |
| Final model tests | Same model scheme/destination/path/jobs with `test-without-building -only-testing:TidyAppModelTests/ConfirmationLifecycleTests -test-timeouts-enabled YES -default-test-execution-time-allowance 30 -maximum-test-execution-time-allowance 60 CODE_SIGNING_ALLOWED=NO`; exit 0. |
| Result summary | `xcrun xcresulttool get test-results summary --path /private/tmp/tidy-headroom-build/Logs/Test/Test-TidyAppModelTests-2026.08.26_15-00-24-+0400.xcresult`; approved cache-access retry exit 0: **15 passed, 0 failed, 0 skipped, 0 expected failures**, no test runtime warnings. |
| Isolation/whitespace | Production SwiftFileList excludes test/host sources; bundle listing contains no fixture resources. Exact marker/test-string scan across the app bundle, including debug dylib, returned no matches (rg exit 1). `git diff --check` exit 0. Manual host source SHA-256 remains `8f563a98737d673d828e488f98f597dc466901049a807f65d35665b95bff12a8`. |

The final test command emitted an Xcode IDEFoundation warning: `setRunnablePIDWithDiagnostics:logSection:andCompletionHandler:` was called without a completion handler and blocked for diagnostics setup. Tests completed successfully, but output is not pristine. This is retained for T23/T24 toolchain/stable-OS review alongside the prior scheme warning; no claim that changing app source fixes it. `xcresulttool` initially hit a sandbox report-cache permission error, then succeeded with approved access.

Independent source/spec review is still required before this scoped foundation is approved. No positive cleanup or complete T02 acceptance follows from these results.

## Required follow-up

- Independent spec and quality review of the complete source range.
- T03/T04 accepted-adapter dispatch, retained manifests, mutation serialization, cancellation and durable recovery integration.
- T05 positive native dialog ordering, shared-window active-run lifecycle and historical settings/UI integration.
- T08 bounded explicit tool discovery; the empty bootstrap snapshot is unknown, not verified absence or complete inventory.
- Physical arm64/Intel, macOS 14 and supported stable-OS acceptance, including the retained T01.B scrolling anomaly.

The detailed chronological implementation log remains `.superpowers/sdd/T02-report.md`. This tracked record deliberately separates tested foundation behavior from unimplemented or unverified acceptance gates.
