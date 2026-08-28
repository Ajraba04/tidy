# T08.2 bounded traversal and persistent scan-session verification

## Scope and ownership boundary

- Added `Scanning/BoundedTraversal.swift` and `Scanning/ScanSession.swift` with
  focused SwiftPM tests.
- Added bounded adapters only to `HomeSurvey`, `SizeScanner`,
  `LargestItemsScanner`, and the single-root portion of
  `StaleNodeModulesScanner`, together with their exact existing test files.
- Every bounded traversal is admitted through a caller-supplied
  `BridgeExplicitSessions` façade and `WorkSession`. The traversal owns only a
  bounded utility execution context for blocking filesystem calls; it does not
  construct or expose scheduler, controller, capability, or barrier authority.
- Existing synchronous engine-facing scanner paths remain unchanged. This
  phase does not claim that `ScanEngine` or another current production fan-out
  has adopted the new primitives. Multi-root stale-module fan-out, unclaimed
  space orchestration, and the engine conversion remain T08.4 work.
- No engine, process, bridge, scheduler, settings, app/UI, package, PBX,
  remote, cleanup, or release file was changed.

## Test-first evidence

Each production behavior was preceded by a focused regression and an observed
RED:

- The first traversal compile RED reported missing `BoundedTraversal`, limits,
  page, cursor, coverage, and deterministic-source types. After the declaration
  scaffold, the same test ran behaviorally RED with an empty path trace,
  incorrect unreadable/cancelled coverage, and zero metrics.
- The lower-level adapter compile RED reported all four bounded entry points as
  missing. Their first behavioral run exposed a symlink being retained as a
  zero-byte child aggregate; the traversal now skips symlinks before accounting
  and selection while the original synchronous APIs remain intact.
- An overlong raw-root regression initially returned `missing`, because
  canonicalization collapsed the nonexistent input. Raw root and protected-root
  strings are now bounded before canonicalization.
- Protected-root limit/reason and single-root stale-scanner regressions first
  failed to compile until the bounded API represented those constraints.
- The first session-registry compile RED reported the missing registry,
  subscription, snapshot, reporter, completion, and event types. The slow/full
  subscriber behavior then ran RED because test instrumentation counted a
  dropped progress event twice; bounded per-subscriber yield accounting fixed
  the high-water observation without adding an event backlog.
- Snapshot path bounds and terminal/coverage consistency each had their own
  compile RED before the corresponding registry error and validation behavior
  existed.
- The first aggregate full-core run exposed a traversal-test-only global file
  descriptor assertion that was sensitive to unrelated concurrent process
  suites. A per-source descriptor tracker replaced that global observation;
  twenty Continue and twenty cancellation cycles now prove traversal-owned
  descriptors and scheduler leases return to their own baselines.

No regression uses `Task.yield()` for ordering. Injected clocks, explicit batch
hooks, descriptor snapshots, and scheduler snapshots provide deterministic
control.

## Bounded behavior covered

- Blocking reads run on the dedicated utility `OperationQueue` only after the
  explicit bridge permit is accepted. Cancellation is checked between finite
  batches and before each descendant enqueue.
- Queue, batch, depth, open-descriptor, hard-link identity, child-aggregate,
  result-record, top-N, breadth, path-string, protected-root, cursor, tombstone,
  and scan-slice retention are explicitly bounded. Byte and count arithmetic is
  checked.
- Top-N is a bounded heap and matches a complete bytes-descending,
  path-ascending oracle. A real filesystem fixture preserves allocated-byte and
  deterministic-order behavior, including hard-link de-duplication.
- Coverage reports missing, unreadable, protected, cross-volume, churn,
  overflow, breadth/depth, expiration, cursor, and cancellation reasons. A
  partial or contradictory terminal state cannot claim completeness.
- Cursors are opaque store tokens, finite and single-use, and are bound to the
  work/logical session, root resource identity, scheduler/traversal generation,
  policy revision, expiry, and bounded pending-state digest. Replay, wrong
  session, expiry, generation/policy change, root replacement, churn, and
  unrepresentable remainder fail truthfully.
- The session registry owns its work independently of observers. Subscribers
  have unique bounded streams; progress may coalesce/drop without changing the
  cumulative shared snapshot. One subscription can terminate without
  cancelling another or the work. Terminal state is retained before live
  streams finish and is available to a late subscriber. Zero subscribers retain
  no event backlog.

## Focused commands

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 \
  --filter 'BoundedTraversalTests|ScanSessionTests|HomeSurveyTests|SizeScannerTests|LargestItemsScannerTests|StaleNodeModulesScannerTests|UnclaimedSpaceScannerTests'
```

Final result: 53 tests in 7 suites passed. This includes synthetic
million-entry breadth, a real filesystem fixture, complete-sort top-N parity,
cursor rejection/continuation cases, exact 1/2/3/4 batch-rate and
30/300/1800-second injected-clock cases, twenty Continue cycles, twenty
cancellation cycles, all four changed adapters, and the unchanged
`UnclaimedSpaceScanner` compatibility suite.

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 --filter WorkSchedulerTests
```

Final result: 34 tests in 1 suite passed. The scheduler façade and admission
contract remained green.

Direct sandboxed SwiftPM runs could not write the host compiler module cache at
`/Users/abdulrahman/.cache/clang/ModuleCache`; the recorded commands therefore
used SwiftPM's package sandbox override with the existing host cache access.

## Full-core observation

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2
```

The aggregate host run executed 526 tests in 57 suites and exited 1 with nine
process/host-dependent issues: eight `SettingsProcessAcceptanceTests` child
observations reported `.incomplete`, and
`BoundedProcessRunnerTests.existingPublicRunnerUsesAggregateReplacementGate`
reported its aggregate-runner observation. Every T08.2 traversal, session, and
changed-adapter test passed in that aggregate run. These process-suite results
are reported separately and are not represented as a full-core GREEN.

Physical 50k-entry first-result, total-time, RSS, FD, and cancellation metrics
remain the separate gate assigned by the T08 design; CI timing here is not
claimed as that physical measurement.

## Source and whitespace gate

The final staged allowlist and `git diff --cached --check` were inspected before
commit. No review agent was dispatched during implementation; the single
independent phase review remains with the controller after this phase, as
directed.
