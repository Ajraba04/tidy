# T08.3 sole process budget and async discovery verification

## Consolidated post-review repair

The single independent phase review found three related defects. They were
handled in one corrective pass with new regressions before production edits:

- **Raw-launch authority:** the former internal `ProcessRequest`,
  `ProcessJobKind`, arbitrary gate initializer, and
  `ProcessSession.launch(request, gate:)` surface was removed. `ProcessRunner`
  now issues an opaque `AuthorizedLaunch` whose initializer is file-private to
  the compiled descriptor file. Production `ProcessSession.launch` accepts
  only that capability and selects `ProcessJobGate.shared` itself.
- **Test isolation:** T04 mechanism fixtures use an explicit
  `TidyCoreTesting` SPI with renamed `ProcessTestRequest` and
  `ProcessTestJobKind` types. Its private-purpose gate factory creates only
  test-isolated gates, and its raw launch rejects `ProcessJobGate.shared`.
  A real compiler-negative regression imports the built module with
  `@testable`, attempts the old mutation/custom-gate launch and direct
  `AuthorizedLaunch` construction, and verifies compilation fails with the
  file-private capability diagnostic.
- **Full paused-reader queue:** a queue at its retention limit cannot reject an
  otherwise eligible mutator merely because cap-zero readers occupy every
  queued position. The actor grants that mutator directly when physical
  capacity exists; active work remains bounded by two and queued retention by
  its configured limit.
- **Deterministic cancellation:** the FIFO regression now starts each waiter
  only after the prior queue increment is observed, cancels the known middle
  waiter, proves the oldest and then oldest-surviving grant order, and releases
  every granted lease.

No reviewer or agent was invoked for this corrective pass. The controller
performs direct verification; no repeat review is claimed.

## Scope and ownership boundary

- `ProcessJobGate.shared` is the only production gate identity used by
  `ProcessRunner`. Its aggregate physical limit is immutable at two.
  Tests may construct explicitly SPI-marked, purpose-tagged isolated gates to
  prove mechanism behavior; the production raw-launch path refuses them.
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
  Only the descriptor file can initialize its opaque launch capability.
- `ProcessSession` still owns the T04 direct child, bounded stdout/stderr,
  deadline and signal decisions, consuming reap, and terminal lease release.
  Production launch accepts no raw request or gate argument and always uses the
  runner-issued capability with the shared gate. The explicit test SPI cannot
  target that production identity. An internal exact retained-descriptor
  observation remains available for regression evidence.
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

Before the consolidated repair, two new behavioral regressions ran RED:

- an eligible mutator returned no reservation when two cap-zero readers filled
  the bounded queue; and
- an `@testable` importer successfully compiled a self-selected mutation
  request, new one-slot gate, and raw session launch, with compiler exit zero.

After the repair, the mutator is admitted and the importer fails to compile.
The compiler diagnostic also proves direct construction of
`ProcessRunner.AuthorizedLaunch` is inaccessible because its initializer is
file-private. The strengthened FIFO cancellation case was deterministic and
GREEN before and after the production change; it corrects the former test's
uncontrolled task-start ordering rather than masking a production failure.

The regressions cover:

- one runner/gate identity and immutable aggregate cap two;
- accepted and stale `0/1/2` policy observations plus invalid-cap rejection;
- `2 -> 0` reader pause without revocation, `0 -> 1` eligible FIFO recovery,
  and unchanged mutator admission/release ownership;
- two readers delaying a future mutator, one reader coexisting with one
  mutator, and cap-one reader serialization;
- cancelled FIFO readers leaving no reservation or queue entry;
- a full cap-zero reader queue preserving eligible mutator admission while
  retaining strict queue and physical bounds;
- unknown, forged-needs, and nested launches leaving the shared gate snapshot
  unchanged; and
- imported raw/custom-gate launch rejection, unforgeable authorized launch,
  and test-SPI rejection of the production gate; and
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
- If blocked readers have filled the bounded queue, an eligible mutator with
  physical capacity is granted immediately instead of being rejected by reader
  retention. No eligible queued waiter can exist at that point because every
  enqueue and release drains eligible work inside the actor.
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

Result after the consolidated repair: 10 tests in 1 serialized suite passed in
4.058 seconds. This includes the importer compiler-negative boundary probe,
test-SPI/shared-gate rejection, and full paused-reader queue admission.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter BoundedProcessRunnerTests
```

Result: 21 tests in 1 serialized suite passed in 24.913 seconds, including the T04 signal, reap,
timeout, fast-exit, bounded-output, cancellation-transfer, and direct-child
ownership cases.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 \
  --filter 'BoundedProcessRunnerTests|ProcessRunnerTests|ProcessBudgetIntegrationTests|ToolLocatorTests|ToolchainDetectorTests|ProcessSurveyTests|ContainerSpaceInfoTests|SnapshotListerTests|SimctlClientTests'
```

Result after the consolidated repair: 53 tests in 9 suites passed in 25.083
seconds.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter WorkSchedulerTests
```

Result: 34 tests in 1 suite passed in 4.981 seconds.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter SettingsProcessAcceptanceTests
```

Result: 3 test functions in 1 serialized suite passed, including 8
parameterized acceptance cases and the standalone source-manifest compiler,
in 14.895 seconds.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2
```

Final consolidated-repair full-core result: 545 tests in 58 suites passed in
48.490 seconds, exit
status zero. The run retained the existing diagnostic compiler/A2P artifacts
for descendant and process-ownership evidence; those messages were not test
failures. No current host-only full-core failure is known for this phase.

```sh
rg -n 'Process\s*\(|waitUntilExit|DispatchSemaphore|ProcessJobGate\s*\(' \
  TidyCore/Sources
```

Result: the only production-purpose gate construction is
`ProcessJobGate.shared = ProcessJobGate(limit: 2, purpose: .production)`.
The only other constructor call is inside the explicit SPI factory and uses
`purpose: .testing`; its initializer is private and production launch rejects
that purpose. There are no direct `Process`, `waitUntilExit`, or semaphore
matches.

`git diff --check` passed before staging. The staged allowlist and cached diff
are checked separately immediately before commit.

## Explicit non-claims

This phase does not claim a positive mutation adapter, accepted cleanup
authority, daemon-descendant containment, engine/app scheduler wiring, remote
delivery, cleanup execution, release, or deployment. It preserves the T04
direct-child boundary and leaves those later owners explicit.
