# T09 incremental aggregate index verification

## Scope

New `TidyCore/Sources/TidyCore/Scanning/{ScanIndex,ScanInvalidation}.swift`; modified
`Engine/ScanEngine.swift` and `Measure/HomeSurvey.swift`; tests in
`TidyCoreTests/{ScanIndexTests,ScanInvalidationTests}.swift`; the settings acceptance
helper source list gained the two new files.

## Contract compliance

- One SQLite file (WAL, `auto_vacuum=INCREMENTAL` set before the header is initialized,
  integrity-checked on open, delete-and-reopen `recover()` as the only corruption
  response). Records key on volume UUID + stable root file identity + scanner version +
  policy fingerprint and persist aggregate totals/coverage/time only — never a file path.
  A partial scan can never replace a complete record. Aggregate and FSEvents cursor commit
  in ONE transaction with rollback on every failure path. Bounded eviction measures
  db+wal+shm together and early-returns under the cap.
- Generation/barrier protocol: a scan captures generation G before its baseline walk;
  events (and any history loss) increment generations before commits observe them; the
  event-delivery barrier drains to the flushed watermark (bounded, failing closed) before
  a commit compares G and publishes. Stale is derived at read time from the live
  generation. `InvalidationDecision.decide(historyReliable:)` is the single widening rule.
- Fail-closed guarantees: no active watch ⇒ `.unavailable(.watchInactive)`, never
  `.cached`; unreliable history is sticky for a watch's lifetime; wrap/drop/root-change/
  mount/unmount/must-rescan flags and a device-UUID mismatch all coarsen to unreliable;
  disabled mode creates no event stream and reports `.indexingDisabled`.
- `ScanEngine.runRegistered` consults the cache per root (home and Library separately)
  and skips the bounded walk on a complete `.cached` hit; cached data affects skipped
  measurement and display status only — it is never execution authority and never
  contributes plan targets or eligibility.
- The production `FSEventsScanEventSource` wraps the real C API (dispatch-queue delivery,
  `FSEventStreamFlushSync` hopped onto the stream's own queue). It is deliberately outside
  the deterministic suite; every protocol property is tested through the injectable
  `ScanEventSource` seam with fixture-only scratch roots.

## Independent review and repair

One independent review ran after implementation. Five blockers and three should-fixes
were repaired in one consolidated pass: the write-only cache (engine now reads before
walking, with an end-to-end second-scan-uses-cache test), the missing wrapped-IDs flag,
a pump task parked forever in `next()` on stop/restart (streams now resume parked waiters;
teardown awaits the pump), dead device-UUID plumbing (persisted on commit, threaded into
stream creation), fail-open freshness without a watch (now `.watchInactive`), a leakable
open transaction, the two-transaction cursor window, and the opaque root-identity
assumption (pinned by a dedicated test plus documentation). Known remaining item: the
barrier is a bounded yield-poll rather than an event-driven wait — safe (fails closed),
noted for a future pass. The coordinator is not yet constructed by the app; enabling
indexing end-to-end is composition-root wiring owned by a later app-phase task.

## Controller-run evidence (2026-08-29)

1. `swift test --disable-sandbox --jobs 2 --filter 'ScanIndexTests|ScanInvalidationTests'`
   — exit 0, 34 tests / 2 suites (after repairs; three FSEvents C-interop compile fixes,
   the auto_vacuum-before-WAL ordering fix, and the helper source-list addition were made
   by the controller during verification).
2. Full core: `swift test --disable-sandbox --jobs 2` — exit 0, 623 tests / 63 suites.
3. Isolated gate invocation — 14/14. App-model suite — 126/126, exit 0. Unsigned Debug
   app build — BUILD SUCCEEDED.

No release, packaging, signing, upload, or real-user cleanup occurred.
