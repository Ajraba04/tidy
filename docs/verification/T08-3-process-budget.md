# T08.3 sole process budget and async discovery verification

## Scope and ownership boundary

- `ProcessJobGate.shared` is the only production gate identity used by
  `ProcessRunner`. Its aggregate physical limit is immutable at two.
  Tests may construct isolated internal gates to prove queue behavior; no
  production caller constructs another gate.
- The gate owns one revisioned runtime read-only cap in the resolved range
  `0...2`. Updates are ordered by settings revision and observation epoch;
  duplicate, stale, late, missing-revision, and out-of-range observations
  reject. Callers cannot pass a cap when launching a command. The persisted
  preference remains unchanged at `1...2`.
- `ProcessRunner` compiles reviewed command shapes and direct-child needs into
  private built-in caller descriptors. Its public compatibility route accepts
  only the existing harmless, bounded direct-child fixtures. A caller cannot
  provide a gate, cap, caller ID, descendant claim, or mutation selector.
  Unknown command shapes, a claimed need above the compiled descriptor, and a
  nested launch reject before gate reservation or `ProcessSession` launch.
- `ProcessSession` still owns the T04 direct child, bounded stdout/stderr,
  deadline and signal decisions, consuming reap, and terminal lease release.
  The only session change is typed read-only/mutator admission through the same
  gate plus an internal exact retained-descriptor observation for regression
  evidence.
- Async `ToolLocator`, `ToolchainDetector`, `SimctlClient`, `SnapshotLister`,
  `ContainerSpaceInfo`, and `ProcessSurvey` discovery now reaches subprocesses
  only through compiled `ProcessRunner` entry points. `ToolLocator` has bounded
  actor-isolated result and in-flight caches and does not block a cooperative
  thread with a semaphore or synchronous process wait.
- No app/UI/bootstrap, package/PBX, `ExecutionPolicyBridge`, `WorkScheduler`,
  engine-orchestration, remote, cleanup, or release file was changed. The
  scheduler-to-gate handoff is an internal scalar configuration seam in this
  phase; adopting it from production engine/app orchestration remains with the
  later T08 orchestration phases.

## Test-first evidence

The new process-budget integration suite was written before the production
changes. Its first run was an observed compile RED for the missing shared gate
identity, revisioned cap update, typed reader/mutator accounting, descriptor
need rejection, nested-launch rejection, and retained-descriptor observation.
The implementation was then added and the same seven behavioral regressions
passed.

The regressions cover:

- one runner/gate identity and immutable aggregate cap two;
- accepted and stale `0/1/2` policy observations plus invalid-cap rejection;
- `2 -> 0` reader pause without revocation, `0 -> 1` eligible FIFO recovery,
  and unchanged mutator admission/release ownership;
- two readers delaying a future mutator, one reader coexisting with one
  mutator, and cap-one reader serialization;
- cancelled FIFO readers leaving no reservation or queue entry;
- unknown, forged-needs, and nested launches leaving the shared gate snapshot
  unchanged; and
- twenty direct-child cycles returning every session-owned descriptor and
  gate lease to zero.

An aggregate run initially exposed one test-only global shared-gate quiescence
assertion racing unrelated process-heavy suites. The regression now observes
the isolated gate and per-session descriptor ownership it creates; it does not
mistake another suite's valid shared-gate reservation for a leak.

The T04 standalone source manifest also initially failed because it omitted
already accepted T08.2 sources required by `WorkScheduler`. Its exact source
membership now includes `PolicyResolver`, `BoundedTraversal`, `ScanSession`,
and `WorkScheduler`; the compiled acceptance fixture exits successfully.

## Gate behavior

- A cap-zero reader remains queued and owns no physical slot. An eligible later
  mutator may use the aggregate budget, while queued readers retain their own
  FIFO order for recovery.
- Lowering the reader cap does not revoke a running reader. Raising the cap
  drains eligible work inside the gate actor.
- Reservation transfer occurs before a resumed waiter runs. Queued
  cancellation removes only that waiter's continuation and cannot leak or
  duplicate a permit.
- With aggregate cap two, two readers occupy both slots; after one completes,
  the waiting mutator can coexist with the remaining reader. With reader cap
  one, a second reader stays queued while one mutator can still occupy the
  other physical slot.
- `WorkScheduler` snapshots are used only as revisioned observations in the
  integration regression. The gate remains the policy and permit owner; the
  scheduler does not wrap, queue, acquire, or release process permits.

## Discovery conversion and deferred synchronous inventory

The final production-source audit found no direct `Foundation.Process`
construction, `waitUntilExit`, or `DispatchSemaphore` in `TidyCore/Sources`.
The exact remaining synchronous call routes are intentionally subprocess-free
and have these later owners:

- `CleanCatalog+Xcode -> SimctlClient.listDevicesSync` is deprecated and
  fail-closed. T08.4 owns async catalog/engine adoption.
- `CleanCatalog+System -> SnapshotLister.hasLocalSnapshotsSync` is deprecated
  and fail-closed. T08.4 owns async catalog/engine adoption.
- `CleanCatalog+DependencyCaches -> ToolLocator.locate("flutter")` uses only
  fixed filesystem candidates. T08.4 owns async catalog orchestration.
- `TidyConfig.makeEnvironment`, `OnboardingViewModel`, and the existing
  `ScanEngineTests` fixture call synchronous `ToolchainDetector.detect`, which
  now checks fixed filesystem candidates only. App onboarding adoption is
  T08.5; app edits were forbidden in this phase.
- `CleanupCommandRunner -> ToolLocator.locate` uses only fixed filesystem
  candidates. A positive accepted-adapter mutation path and its compiled
  mutation descriptor remain owned by the first applicable T15-T20 adapter
  phase.

The existing `ScanEngine` async fan-out already calls `ContainerSpaceInfo`,
`SnapshotLister`, `SimctlClient`, and `ProcessSurvey`; those helpers now share
the bounded runner. Reshaping that fan-out remains T08.4 and was not performed
here.

## Verification commands and results

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter ProcessBudgetIntegrationTests
```

Result: 7 tests in 1 serialized suite passed.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter BoundedProcessRunnerTests
```

Result: 21 tests in 1 serialized suite passed, including the T04 signal, reap,
timeout, fast-exit, bounded-output, cancellation-transfer, and direct-child
ownership cases.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 \
  --filter 'BoundedProcessRunnerTests|ProcessRunnerTests|ProcessBudgetIntegrationTests|ToolLocatorTests|ToolchainDetectorTests|ProcessSurveyTests|ContainerSpaceInfoTests|SnapshotListerTests|SimctlClientTests'
```

Result: 50 tests in 9 suites passed.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter WorkSchedulerTests
```

Result: 34 tests in 1 suite passed.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter SettingsProcessAcceptanceTests
```

Result: 3 test functions in 1 serialized suite passed, including 8
parameterized acceptance cases and the standalone source-manifest compiler.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2
```

Final full-core result: 542 tests in 58 suites passed in 49.265 seconds, exit
status zero. The run retained the existing diagnostic compiler/A2P artifacts
for descendant and process-ownership evidence; those messages were not test
failures. No current host-only full-core failure is known for this phase.

```sh
rg -n 'Process\s*\(|waitUntilExit|DispatchSemaphore|ProcessJobGate\s*\(' \
  TidyCore/Sources
```

Result: the only gate construction is
`ProcessJobGate.shared = ProcessJobGate(limit: 2)`; there are no direct
`Process`, `waitUntilExit`, or semaphore matches.

`git diff --check` passed before staging. The staged allowlist and cached diff
are checked separately immediately before commit.

## Explicit non-claims

This phase does not claim a positive mutation adapter, accepted cleanup
authority, daemon-descendant containment, engine/app scheduler wiring, remote
delivery, cleanup execution, release, or deployment. It preserves the T04
direct-child boundary and leaves those later owners explicit.
