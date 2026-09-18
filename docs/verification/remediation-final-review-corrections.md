# Final-review correction batch

Date: 2026-09-18

Scope: the five implementation findings in `remediation-final-review.md`. This is focused
correction evidence for the partial remediation checkpoint. It does not change the current
application **NO-GO** verdict or the full Developer Headroom **INCOMPLETE** verdict.

## Corrected behavior

### Restart and FSEvents trust

- Cache trust is no longer inferred from equality with a process-local generation. An unreliable
  restart may collide numerically with a persisted generation, but it remains stale until a fresh,
  complete walk establishes a baseline under a live delivery stream.
- Cursor reuse requires both persisted and live device identities and exact equality. A missing
  identity, missing cursor, device mismatch, event-ID wrap, or unreliable history forces a fresh
  complete walk before cache reuse.
- Live delivery availability is distinct from retained-history reliability. A failed
  `FSEventStreamCreate`/`FSEventStreamStart` remains uncacheable even after a complete traversal,
  because later mutations could not be observed.
- A manual-Continue catch-up returns an opaque generation guard. `ScanEngine` consumes that guard
  before retaining another cursor or publishing terminal state. Events arriving after catch-up but
  during the continuation handoff therefore produce truthful partial `.churn`, not stale complete
  totals.
- Successful guard consumption retains the expected generations through terminal publication and
  into suspension. The suspension barrier rejects a newly retained cursor if an event lands after
  guard consumption but before idle teardown; that invalidation cannot be normalized into the next
  checkpoint.
- Final expected-generation validation, conservative index invalidation, cursor/generation capture,
  watch-admission closure, and pump cancellation execute in one `ScanInvalidation` actor turn after
  the flush. An event is therefore either validated as applied or left beyond the captured cursor
  for replay; no await can fold it into the new checkpoint.
- Cache status itself now flushes and drains the event pump before returning `.cached`, then
  rechecks delivery and generation trust. A matching cursor/device handshake is not treated as
  completed historical catch-up.

### Event-buffer memory bounds

- The C callback reads only the accepted prefix of the callback `NSArray`; it no longer bridges the
  entire array to `[String]` before applying the event cap.
- NSString UTF-8 length is checked before creating a Swift `String`. The limits are 4,096 bytes per
  path, 1 MiB per batch, 8 MiB across queued path payloads, 4,096 events per batch, and 64 pending
  batches.
- Any count or byte overflow collapses to one empty unreliable-history marker. Discarded path
  prefixes are not retained. Tests separately cross the per-path, per-batch, and total-pending
  byte boundaries.

### Terminal-partial idle and Continue

- A continuable terminal partial now enters a serialized dormant transition. It stops FSEvents,
  cancels the scan observation subscription, releases the explicit monitor lease, and leaves no
  scheduler permit or registry work active while awaiting the user's decision.
- Immediate Continue waits for that suspension barrier; it cannot install a second observation
  lease or restart a watch while teardown is still running.
- The app reserves one shared continuation transition synchronously before its first suspension or
  result await. Concurrent Continue calls therefore receive the same handle and create exactly one
  registry continuation session.
- Continue restarts the approved watch from the captured cursor and requires reliable device and
  history catch-up. A changed or unprovable gap discards the single-use traversal continuation and
  finishes the dormant scheduler session. The first indexed partial captures the active watch's
  live device UUID in its suspension checkpoint, so it can resume safely without requiring a prior
  complete cache commit.
- With indexing explicitly disabled there is no app-owned gap witness. Such a terminal partial is
  now published with `continuationAvailable=false`, releases its scheduler session, and does not
  offer a Continue action that can only fail.

This conservative index-disabled behavior is an honest limitation of the partial checkpoint. A
future fresh-scope restart or transient witness can restore a useful no-index Continue path, but
retained pre-gap totals are not accepted as safe evidence.

### Scene lease lifetime

- Headroom and menu view models now use a serialized scene-lease controller. Terminal disposal is
  ordered after every earlier visibility task, then removes both the active lease and its
  generation entry.
- Creating, showing, and destroying 100 pairs of view models returns active leases and generation
  bookkeeping to their exact baseline. The late-task resurrection protection remains in place
  without process-lifetime UUID tombstones.

### Verification enforcement

- `check-test-results.py` accepts repeatable required passing case names for Swift logs and Xcode
  result bundles. Missing names fail even when the aggregate count floor passes.
- Conservative aggregate floors are now 670 Core and 130 app-model tests. The verifier additionally
  requires the real 100k/parity case, scoped authorization, terminal-partial lifecycle and race
  cases, the two settings bootstrap/queue regressions, monitoring disposal, and scene-generation
  disposal. The native synthetic gate requires both accepted cases and a floor of two.

## Fresh focused evidence

All commands used the assigned retained caches and at most two jobs.

- Core scan/index/scope correction before the final consolidated timing-window pass:
  `swift test --scratch-path /tmp/tidy-r06-build --jobs 2 --no-parallel --filter
  'ScanInvalidationTests|ScanIndexTests|ScanScopeTests'` passed **58 tests in 3 suites**, zero
  failures. Log: `/tmp/tidy-final-review-continuation-guard.log`.
- Final catch-up/publication correction: focused ScanIndex/ScanScope execution passed **43 tests in
  2 suites**, zero failures. It includes the flush-delivered historical event, the post-consumption
  publication event, and Core handoff checks. Log:
  `/tmp/tidy-final-review-continuation-publication.log`.
- The final atomic-suspension interleaving rerun passed its **3 tests in 3 suites**, including an
  event injected at the former validation/checkpoint seam. Log:
  `/tmp/tidy-final-review-atomic-suspension-focused.log`.
- The final combined ScanInvalidation/ScanIndex/ScanScope rerun passed **60 tests in 3 suites**,
  zero failures. Log: `/tmp/tidy-final-review-core-final.log`.
- The separate explicit byte-budget rerun passed **16 ScanInvalidation tests**, zero failures. Log:
  `/tmp/tidy-final-review-byte-budgets.log`.
- App-model lifecycle correction: final focused `xcodebuild test` in `/tmp/tidy-r08-xcode` passed
  **5 tests**, zero failures: dormant partial teardown, first-indexed-partial Continue from a live
  device checkpoint, simultaneous Continue sharing, truthful index-disabled terminal state, and
  100 view-model generation disposal. Log:
  `/tmp/tidy-final-review-model-atomic-final.log`; result bundle under
  `/tmp/tidy-r08-xcode/Logs/Test/` at `2026.09.18_23-07-33-+0400`.
- Required-case parser controls passed against both focused artifacts. Exact matching rejected
  synthetic Swift and Xcode near-name suffixes; Python compilation and shell syntax checks also
  passed.

The coordinator owns the fresh final Core/model aggregates, application builds, universal Release
build, and final reviewer disposition after this batch. The earlier 685-test Core aggregate had one
unchanged process timing assertion fail under concurrent host build load; an immediate rerun of
that exact built test passed with the assertion unchanged. Neither run substitutes for the final
post-correction aggregate.

## Boundaries retained

- Catalog mutations remain compiled denied. This batch does not enable a producer, effect adapter,
  network route, daemon, permission, signing, publication, or release path.
- R02 real supported-producer proof remains open. R03/R04 and all R03C-dependent gates remain
  blocked.
- The existing real 100k fixture remains the current usefulness evidence: complete parity and 100%
  measured metadata-visit reduction on this 32 GiB M1 Max host. Reference-hardware latency,
  physical footprint, long-run idle cost, Intel/macOS 14, human accessibility, packaging, and
  distribution acceptance remain separate open gates.
