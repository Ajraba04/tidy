# R13 deterministic production cancellation resume

Date: 2026-09-19

Scope: repair and verify the production Scan Cancel race found by the final integrated verifier at
`5bfd8ea`. This checkpoint changes no scan authority, traversal limits, file counts, timeouts,
catalog capability, mutation path, or terminal presentation source.

## Root cause

`ScanViewModel.start` published `.running` before `AppExecutionServices.beginScan` returned, so the
production Cancel button was visible while the model's local `sessionID` was still nil. The old
`cancelScan` returned immediately in that state. On the current M1 Max the synthetic Full Home scan
could complete before XCTest's next accessibility query, producing `scan.phase.complete` instead of
a cancellable state. A related Rescan race retained the prior terminal `sessionID`; Cancel during the
new start could target the old generation and miss the new handle. Duplicate local start calls could
also reset a shared unbound pending flag.

The integrated failure is retained in
`/private/tmp/tidy-final-20260919-44u3mup6/production-native-ui.xcresult` and
`/tmp/tidy-final-20260919-5bfd8ea.log` around lines 3489-3634. A fresh focused reproduction at
`/tmp/tidy-r13-cancel-diagnosis2.xcresult` reached the same line-132 failure with the completed
production report visible.

## Product correction

Each local scan start or Continue now owns a UUID transition. While that transition is in flight,
duplicate local starts are ignored and Cancel records a request bound to that exact UUID. The old
local session is cleared before awaiting a new handle. Once the real handle returns, the model first
attaches its real registry session, then forwards the recorded Cancel to
`AppExecutionServices.cancelActiveScan`. Terminal UI still comes only from the real
`ScanSessionRegistry` stream. Failure paths clear only their matching transition and pending request.

Two app-model regressions use the real production services, scheduler, registry, and scan engine.
They occupy every resolved scheduler permit, pause the production start reservation, press Cancel
before local session publication, and require a retained real `.cancelled` terminal before releasing
any blocker or calling test teardown. One covers first start and one covers Rescan after a completed
old generation. Before blocker release both require registry active work zero, one new retained
cancelled terminal, zero scan explicit leases, and no index watch. After release and final disposal,
the scheduler must be `active=0`, `queued=0`, `liveSessions=0`.

Required behavioral RED: `/tmp/tidy-r13-cancel-model-red2.xcresult` failed the intended assertion
with `Pending Cancel did not reach the real registry terminal: running`. Final focused GREEN:
`/tmp/tidy-r13-cancel-model-green2.xcresult`, **2/2 passed** in 0.50 seconds total test duration.

## Native cancellation journey

The fixed compile-scoped `cancel-queued` scenario creates no supplied path, duration, worker count,
authority, or terminal result. It derives `effectiveWorkers`, opens one ordinary headroom explicit
session, and occupies exactly that many real scheduler permits. The production Full Home scan then
registers and queues behind those permits, making the real production Cancel action deterministic.

The native test requires:

- blocker readiness with every resolved permit active;
- real production Full Home consent and Cancel controls;
- `scan.phase.cancelled` from the production registry stream before blocker release;
- natural production lifetime cleanup after releasing only blocker-owned permits/session;
- service active scan nil, registry `sessions/active/retained = 1/0/1`, scheduler `0/0/0`, zero
  explicit leases, index watch false, and exact witness bytes unchanged;
- native Window-menu selection plus Command-W closes Scan, and reopening retains Cancelled.

`releaseAndAttest` does not call `disposeScanResourcesForTesting`; it bounded-waits for the production
lifetime owner and reports `failed natural-settle` if that owner does not reach the asserted state.
The final fixture cleanup button retains disposal only after all journey assertions.

Focused native GREEN: `/tmp/tidy-r13-cancel-native-green4.xcresult`, **1/1 passed** in 28.235
seconds. Final covering production-scene class:
`/tmp/tidy-r13-cancel-native-class-green.xcresult`, **6/6 passed**, zero failures/skips, 109.623
seconds for the test operation.

## Boundaries

This proves deterministic queued-start cancellation through the native production action and closes
the original timing race. It does not claim active-walker cancel latency, twenty-cycle FD/RSS
stability, 50k timing/physical-footprint acceptance, reference 8 GiB/Intel hardware, macOS 14,
human VoiceOver, or representative workflow traffic acceptance. Those remain separate R13 gates.
