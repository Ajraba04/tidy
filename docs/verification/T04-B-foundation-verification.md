# T04.B bounded process mechanism verification

Source BASE4b4ce2a, sole writer `t04b_implement`, isolated CAJ/developer-headroom worktree. Independent spec/quality review approved the scoped mechanism throughb770f3f with no remaining findings. This replaces the actual public ProcessRunner mechanism; it grants no cleanup capability, accepted adapter, terminal reconciliation or app-crash recovery authority.

## Controller entry audit

Controller read all four actual production files, complete BoundedProcessRunnerTests and checked-in C fixture before authorizing any child test. Inspected: sole passive waitid(WNOWAIT) observer followed by exact-child consuming waitpid under the same ownership lock as the only SIGTERM site; nil identity cannot signal; post-spawn ownership is returned rather than thrown away. Every pipe original is normalized above stdio and marked CLOEXEC; checked spawn file actions plus CLOEXEC_DEFAULT exclude extra descriptors. Parent reads/control are nonblocking, control has descriptor-local SIGPIPE protection, and read FDs close only in Dispatch cancellation handlers. Stream callbacks have four-read/64KiB work and1MiB retention bounds. Retained session/supervisor and gate accounting outlive collection or abandonment; read-only release requires actual reap/local closure, mutation remains held.

Fixture audit: owned canonical UUID roots only; original HOME is passed unchanged, TMPDIR is scoped to owned scratch. Actual fixture modes never signal another process. Ordinary run-root removal requires direct-child reaping plus registered known-descendant NOTE_EXIT; ambiguous/unregistered ownership preserves artifacts. Compiler/public/Foundation roots remain retained. Compiler bounded output is saved under build; failed artifact writes preserve both root and actual retained supervisor. No app or user cleanup is used as a fixture.

Existing async discovery callers check succeeded before parsing. Legacy MemoryReclaimer/SimulatorPruner/SnapshotDeleter/GitHousekeeper entrypoints remain fixed-denied. SystemCleanupCommandRunner itself is still a public command transport, not intrinsically denied. Synchronous Foundation Process in ToolLocator/SimctlClient/SnapshotLister remains T08 work; absence of an explicit wait-any/SIGCHLD handler in project source is not universal Foundation compatibility proof.

## Execution evidence

Initial selected pure-mapper compile failed naturally for missing new B APIs after an approved sandbox retry. No test/fixture ran; this is compiler RED, not behavioral failure. Three pure gate/mapper tests then passed0.074s, build20.45s. Mechanical Swift-import corrections expand the installed compound PID-path-capacity macro and unqualify kevent function calls; no ownership change.

Controller approved both Foundation-first/POSIX-first cases in one parameterized assertion body before the first actual child run. `swift test --jobs 2 --filter BoundedProcessRunnerTests`:21 tests/one suite failed with one issue in32.386s, build5.39s. The mutation-timeout test collected uncertainty at0.2s before its alive marker existed; later full identity check, done marker and actual reap passed. All other cases passed.

Diagnostic-only focused run reproduced the same assertion failure: launch returned0.003528s, collect0.215808s with alive/done both false, uncertainty, zero signals/reaps; done was observed1.923769s with actual raw0 reaped once and zero signals. Root read the retained log. This diagnoses the test's readiness assumption, not the precise OS cause of executable entry delay. The approved correction keeps collect first,0.2s deadline and all original assertions; only waits for the existing bounded alive marker after returned uncertainty, before checking post-timeout liveness. Added zero-signal assertions at timeout and after actual normal reap. Temporary prints removed; no production behavior changed.

Focused regression passed1/1 in2.365s (build5.93s). Complete isolated B suite passed21 tests/one suite in40.272s (build0.42s), exit0. Both Foundation launch orders and all original/supplement cases ran, including3MiB per-stream flood with1MiB retention, inherited descendant pipes, actual surviving mutation/abandonment, queued cancellation,25 transfer races, aggregate public gate, actual identity-less reaping and truthful UTF8/output/exit mapping.

## Controller package verification

Complete package coverage is intentionally partitioned: B's global gate-count assertions require its prescribed isolated run; all other package tests run separately rather than changing those assertions or omitting tests. `swift test --jobs 2 --skip BoundedProcessRunnerTests`:323 tests/42 suites passed12.397s, build0.67s, exit0. Combined with isolated B,344 methods/43 suites were covered. This is not a claim of one default-parallel full-suite run. The unchanged legacy ProcessRunner tests and real read-only discovery consumers passed against the replacement. No warnings/error/recorded-issue lines in either successful log.

Unsigned production arm64 app build: `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO`, exit0 without output. Existing derived data reused; no app launch.

Independent reviewer `t04b_source_review` read the complete3ecb4b4..b770f3f package and B contracts, then focused unchanged checks on discovery consumers and quarantined legacy helpers. **Spec compliant; task quality Approved**, no Critical/Important/Minor findings requiring correction. No reviewer tests/builds/launches/mutations. This closes B's scoped mechanism gate only and permits the separately reviewed A2P source assignment; device/effect/recovery/T08 boundaries remain unchanged.

## Boundaries

Current-host tests cannot establish macOS14/Intel device acceptance, hard syscall latency, all-runtime Foundation coexistence, or accepted effect recovery. No push, tag, signing change, DMG, release, live migration or real cleanup has occurred.
