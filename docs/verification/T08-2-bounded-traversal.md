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
- The consolidated hardening pass recorded behavioral REDs for cursor replay
  (all eight concurrent calls resumed), post-permit expiry and revision drift
  (queued work still read `f0`), directory replacement and directory-content
  churn (both reported complete), selection-string overflow (the source was
  read), per-descendant expiry (both children were enqueued after the injected
  deadline), and slow owned-work cancellation (the registry terminalized while
  the task was still suspended). Metadata-failure injection first compiled RED
  because the source had no fallible allocation-metadata seam.
- The former one-node, pre-labelled million-breadth fixture was replaced by an
  on-demand virtual source that actually processes 4,113 entries. It reaches
  the configured 4,096-path queue, 512 hard-link identities, 64 page records,
  and eight top-N records while retaining only one generated directory page at
  a time.

No regression uses `Task.yield()` for ordering. Injected clocks, explicit batch
hooks, descriptor snapshots, and scheduler snapshots provide deterministic
control.

## Bounded behavior covered

- Blocking reads run on the dedicated utility `OperationQueue` only after the
  explicit bridge permit is accepted. Cancellation is checked between finite
  batches and before each descendant enqueue. The injected clock is also
  checked there; an expired slice stores only the bounded untouched suffix and
  unprocessed batch remainder for Continue.
- Queue, batch, depth, open-descriptor, hard-link identity, child-aggregate,
  result-record, top-N, breadth, path-string, protected-root, cursor, tombstone,
  and scan-slice retention are explicitly bounded. Byte and count arithmetic is
  checked.
- Top-N is a bounded heap and matches a complete bytes-descending,
  path-ascending oracle. A real filesystem fixture preserves allocated-byte and
  deterministic-order behavior, including hard-link de-duplication.
- Coverage reports missing, unreadable, protected, cross-volume, churn,
  overflow, breadth/depth, expiration, cursor, and cancellation reasons. A
  partial or contradictory terminal state cannot claim completeness. Failed
  allocation metadata reports unreadable instead of zero allocated bytes.
- Real directory enumeration binds the checked identity to an
  `O_NOFOLLOW` descriptor, compares `lstat` with `fstat`, enumerates through
  `fdopendir`, and identifies children with descriptor-relative `fstatat`.
  Bounded directory mutation watermarks are validated before Continue and
  before complete coverage is returned.
- Cursors are opaque store tokens, finite and single-use, and are bound to the
  work/logical session, root resource identity, scheduler/traversal generation,
  policy revision, expiry, and bounded pending-state digest. Replay, wrong
  session, expiry, generation/policy change, root replacement, churn, and
  unrepresentable remainder fail truthfully. Continue reserves the token before
  its first suspension and revalidates expiry plus scheduler generation and
  policy revision after permit acquisition.
- The session registry owns its work independently of observers. Subscribers
  have unique bounded streams; progress may coalesce/drop without changing the
  cumulative shared snapshot. One subscription can terminate without
  cancelling another or the work. Terminal state is retained before live
  streams finish and is available to a late subscriber. Zero subscribers retain
  no event backlog. Session cancellation signals the registry-owned task first,
  keeps work active while cancellation is slow, and emits its single retained
  cancelled terminal only after that task has ended.

## Focused commands

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2 \
  --filter 'BoundedTraversalTests|ScanSessionTests|HomeSurveyTests|SizeScannerTests|LargestItemsScannerTests|StaleNodeModulesScannerTests|UnclaimedSpaceScannerTests'
```

Final remediation result: 61 tests in 7 suites passed. This includes the
4,113-entry on-demand virtual traversal, a real filesystem fixture,
descriptor-bound replacement and metadata-failure cases, complete-sort top-N parity,
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
`/Users/abdulrahman/.cache/clang/ModuleCache`; the recorded remediation commands
therefore set `CLANG_MODULE_CACHE_PATH=/private/tmp/tidy-headroom-clang-cache`
and used SwiftPM's package sandbox override.

## Full-core observation

```sh
cd TidyCore
swift test --disable-sandbox --jobs 2
```

The remediation aggregate run executed 534 tests in 57 suites and exited 1
with 18 host/process-dependent issues, reported separately from T08.2:

- eight `SettingsProcessAcceptanceTests` child observations reported
  `.incomplete`;
- `ProcessSurvey` could not observe any top memory consumers in this host;
- `BoundedProcessRunnerTests` recorded nine issues across
  `descendantOutlivesCLIAndPipeDeadline`,
  `mutatingTimeoutLeavesActualChildRunning`,
  `realSurvivingChildKeepsReopenedCoordinatorBlocked`,
  `reusedPIDShapeCannotMatchActualIdentity`, and
  `inheritedPipeDeadlineIsNotCommandTimeout`, principally unavailable child
  identity/exit observations plus one host I/O error.

Every T08.2 traversal/session test, every adapter suite, and every
`WorkSchedulerTests` case passed within that aggregate run. Full-core GREEN is
not claimed.

Physical 50k-entry first-result, total-time, RSS, FD, and cancellation metrics
remain the separate gate assigned by the T08 design; CI timing here is not
claimed as that physical measurement.

## Source and whitespace gate

The final staged allowlist and `git diff --cached --check` were inspected before
the remediation commit. The remediation changed only both scanning primitives,
their two focused test files, and this verification file. No reviewer was
dispatched during the consolidated remediation; the controller performs direct
verification, and no subsequent reviewer loop is claimed.
