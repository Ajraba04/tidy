# T05.A1 read-only settings migration evidence

Scope: bounded historical settings reads, in-memory schema2 projection, conservative recovery results and explicit historical memory availability. This is not a deployable migration release or full T05 acceptance.

Source BASE: `a45d22c`; isolated worktree `/private/tmp/tidy-headroom.wUbV9h`, branch `CAJ/developer-headroom`. No live settings URL or app consumer was switched.

## Implemented boundary

- SettingsStore is an explicit-URL actor with no initializer I/O. Load never creates, repairs or rewrites files. Otherwise-valid persistence requests remain unavailable until A.2; recovery update/preview/rollback requests are denied.
- Typed bounded JSON decoding enforces 1 MiB, depth16, collection1000, strings4096 and profiles50 limits, duplicate decoded keys, UTF-8, numeric types/overflow, required historical fields and known schema shapes. Only the two later optional v1 memory preferences default when absent. Unknown v1 extras remain inert; unknown v2 envelope/config/preset extensions are recovery-only because this binary cannot preserve them.
- Component-wise no-follow local filesystem reads validate regular-file descriptors before bounded reads. Existing owned0755/0644 legacy data is read without chmod. FIFO/directory/symlink/unreadable/unsafe locations return recovery. Missing config beside backup/lock is not treated as a new installation.
- Missing historical memory observations decode as nil. Explicit zero remains measured; unknown/mixed/overflow totals are unavailable. Encoding explicit null prevents compatibility zero from becoming a measurement after reopening. T02 disposition and T03 typed effects/tool-exit semantics remain intact.
- Five exact fixture resources belong only to the test target. Only the approved historical-memory method in GuardedDeletionTests changed; no production filesystem-effect caller or capability was added.

## RED/GREEN evidence

All package commands use the existing cache and `--jobs 2`. Initial sandbox manifest/cache failure is environmental, not RED.

- Natural missing-API compile RED: absent SettingsStoreError.
- Declaration-only behavioral RED: 16 tests across two suites, 29 issues. Positive migration/default/schema2, recovery denial/reasons and historical/explicit memory cases failed. Invalid-input cases already passed the reject-all skeleton; they are not individually claimed as reproduced defects.
- First non-FIFO GREEN: 16 tests/two suites, 0.858 seconds.
- Root audited the real nonblocking regular-file validation order and UUID fixture/watchdog lifetime before the first FIFO test. First FIFO run passed without rescue; it is first-pass safety coverage, not a manufactured blocking regression.
- Missing config plus backup/lock: both arguments produced six genuine RED issues before the minimal auxiliary-presence guard; later GREEN preserves each file and denies edits.
- Final focused GREEN: 20 tests/two suites, all arguments, 0.815 seconds. FIFO rerun 0.027 seconds without rescue. Directory/unreadable and valid-state unavailable-write tests passed existing behavior on their first run.

## Controller verification

- Source writes paused before validation. Root inspected both new source files, all new tests and changed report/manifest/test-resource code; temporary mutations are scoped to UUID-owned fixtures, with unreadable-mode restoration and FIFO drainage before cleanup.
- `git diff --check`: exit0.
- `swift test --jobs 2` from TidyCore: exit0, **252 tests across 40 suites passed**, 14.694 seconds. No compiler/test warnings observed. This is correctness evidence, not a low-spec performance benchmark.
- `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO`: exit0, no output. Existing cache reused; no signing changes or launch.
- No normal app or manual fixture host launch. App-model/native UI tests were not rerun for this core-only unit.

## Remaining gates

- Independent source/spec review of `a45d22c..aa956b0` found one Important issue: the new memory aggregate delegated an empty report to the shared sum helper, yielding measured zero without observations. The narrow fix and evidence below await re-review; no A.1 approval claimed yet.
- Safe foreign-owner fixture was unavailable; owner checks have source evidence only. No privileged chown or foreign user data was used.
- A.2 must supply named-FD/single-link/locked exact-byte conflict checks, coherent publication/bootstrap, backups, explicit rollback, pending-stage recovery, revision overflow and real fault/process evidence. A.1 is a read-only projection, not write or execution permission.
- A.2/A.3 must cover a truly fresh install with an absent Tidy parent directory under Application Support. Current read-only load requires an existing parent; all current fixtures create one. No fallback reset is authorized.
- The app still uses legacy schema1 ConfigStore and numeric memory compatibility consumers. A.3 owns the atomic writer/startup/UI cutover; this intermediate build must not ship as recovery-safe.
- T05B accepted-action UI/shared-window/in-flight lifecycle, stable-OS accessibility reproduction, Intel/macOS14 and physical performance acceptance remain open.

Detailed chronological command evidence: `.superpowers/sdd/T05.A1-report.md`. The separate T04 history-budget decision remains pending and was not selected by this work.

## Empty-report follow-up

- A fresh fix agent added historical-empty and coordinator-style invalidToken/noWork reports. Genuine focused RED observed five nil expectations returning zero; the explicit-zero positive control passed. Historical round-trip coverage was added afterward and first executed in GREEN; no sixth RED failure is claimed.
- Only the new memory aggregate gained an empty-results guard returning nil. The shared accounting helper and all unrelated byte semantics remain unchanged.
- Covering command: `swift test --filter '(SettingsMigrationTests|missingLegacyMemoryDoesNotSilentlyBecomeMeasuredZero)(\.|\(|$)' --jobs 2`; exit0, **21 tests/two suites**, 0.411 seconds. All settings/FIFO/memory cases included; no warnings.
- Root inspected the exact two-file fix and report, then ran the full core suite again: `swift test --jobs 2`, exit0, **253 tests/40 suites**, 12.000 seconds, no warnings observed.
- Root repeated the exact unsigned arm64 production build above: exit0, no output. No launch or app-model/native UI run.
- `git diff --check` passed. These post-fix checks supersede the earlier 252-test build evidence for current source validation; independent re-review is still pending.
