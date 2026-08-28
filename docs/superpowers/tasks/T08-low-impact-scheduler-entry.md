# T08 — Shared low-impact scheduler and cancellable scans

> **Status:** PREIMPLEMENTATION decomposition entry. This card authorizes no source edit. Each checkpoint below requires its own complete, independently approved task card, observed RED/GREEN cycle, verification record, and fresh adversarial source review.

## Binding outcome

T08 replaces per-caller filesystem fan-out with one app-lifetime scheduling authority, makes every T08-owned traversal cooperatively cancellable and bounded, evolves the already accepted T04 process gate instead of adding another semaphore, streams cumulative scan state through explicit sessions, and gives those sessions one multi-window app owner. It grants no mutation, background-scan, monitoring, index-freshness, or maintenance authority.

Hard limits remain:

- one aggregate filesystem-walk budget, resolved to `0...4` workers;
- one existing T04-derived command gate, at most two launched Tidy jobs total, including a future mutator;
- configured read-only process cap `1...2`, never additive to the total-two cap;
- bounded queues, traversal batches, cursors, subscribers, event buffers, results, strings, descriptor use, and top-N state;
- terminal/partial state is truthful: overflow, cancellation, unreadable work, churn, expiry, and missing pressure evidence never become complete success;
- opening the app, Scan view, Settings, or a window performs no scan, discovery process, repeating timer, or traversal.

## Dependency order

```text
T06 policy/revision owners       T04 process ownership/reaping
           │                                │
           ▼                                │
T08.1 scheduler policy/admission             │
           │                                │
           ▼                                ▼
T08.2 bounded traversal/session       T08.3 existing process gate
           └───────────────┬────────────────┘
                           ▼
              T08.4 core orchestration
                           │
                           ▼
              T08.5 app owner and UI
```

T08.1 → T08.2 → T08.4 → T08.5 is sequential. T08.3 depends on T04 and the T08.1 revision-bound policy snapshot and must finish before T08.4. Checkpoint numbering is binding.

## Production escape-route inventory

Every per-checkpoint card must repeat the current source audit and assign every match to an allowlisted conversion or an explicit later owner. A hidden exception keeps T08 source completion open.

| Route | Required owner/checkpoint |
|---|---|
| `SizeScanner` private task group and `diskUsage` enumerator | T08.2 shared scheduler/bounded traversal |
| `HomeSurvey.walk`, large-file retention, child aggregates, hard-link tracking | T08.2 bounded traversal/top-N/cursor |
| `LargestItemsScanner` directory listing | T08.2 bounded traversal |
| `StaleNodeModulesScanner` traversal | T08.2 bounded traversal |
| `UnclaimedSpaceScanner` catalog/location walks and follow-up surveys | T08.2 then T08.4 orchestration |
| `ScanEngine` task fan-out and all scan probes | T08.4 |
| `CleanEngine.makePlan`, every catalog `locate`/`discover`, and measurement | T08.4 shared scheduling; pure path construction is exempt and enumerated |
| `ToolLocator`, onboarding `ToolchainDetector`, Simctl and Snapshot discovery | T08.3 async declared process adoption or an explicit later gate that prevents full T08 completion |
| every direct `Foundation.Process`, `waitUntilExit`, `FileManager.enumerator`, and unbounded `contentsOfDirectory` in T08-owned paths | converted by T08.2/T08.3/T08.4 or explicitly deferred with evidence |
| `ProcessJobGate`, `ProcessSession`, `ProcessRunner` | T08.3 evolves the sole T04 production owner |
| `AppExecutionServices`, bootstrap, menu-bar session exposure, Scan view/model | T08.5 |

Add a source-negative regression that scans the exact production manifest for disallowed private pools, semaphores, default/unbounded streams, direct process waits, and unassigned traversal APIs. It uses an allowlist of proven pure/non-T08 paths; it must not weaken to a repository-wide substring count.

---

## T08.1 — Revision-bound scheduler policy and filesystem admission

### Scope and allowlist

Create only:

- `TidyCore/Sources/TidyCore/Scanning/WorkScheduler.swift`
- `TidyCore/Tests/TidyCoreTests/WorkSchedulerTests.swift`
- `docs/verification/T08-1-work-scheduler.md` after GREEN

No filesystem, process, engine, app, package, or PBX source changes.

### Contract

`WorkScheduler` is one injected/app-owned actor; a convenience shared production reference may exist only after T08.5 establishes the owner. It has no private per-session pool. It consumes one atomic snapshot derived from the real resolved `EffectivePolicy`, never recomputes `ScanBudget` arithmetic:

```swift
public enum DynamicScanObservation: Equatable, Sendable {
    case unknown
    case nominal
    case constrainedPowerOrSeriousPressure
    case criticalPressure
}

public struct SchedulerPolicySnapshot: Equatable, Sendable {
    public let revision: UInt64
    public let featureEnabled: Bool
    public let admission: ScanAdmission
    public let resolvedWalkWorkers: Int       // accepted 0...4
    public let resolvedReadOnlyProcesses: Int // runtime 0...2; persisted preference is 1...2
    public let sliceSeconds: Int              // accepted 30...1800
    public let uiBatchesPerSecond: Int        // accepted 1...4
    public let observation: DynamicScanObservation
}
```

Unknown observation is conservative until T10 exists: explicit user scans only, at most one walk worker, no discretionary admission. Critical admits no new scan work. Constrained/serious admits at most one. Feature disable cancels pending and active read-only scan work cooperatively; a presentation-only revision does not. Updates require monotonic revision plus exact policy identity; stale/late snapshots reject and cannot resurrect work.

Permit leases are nonforgeable, exact-release, FIFO, cancellation-safe, and session-bound. Queue/session cardinalities are finite and overflow rejects. Shrinking a cap does not revoke a running batch; it prevents new admission. Scan cancellation never signals, cancels, or releases a T04 mutator.

### Mandatory tests and gates

- Ten sessions never exceed the one effective aggregate cap.
- Unknown, critical, constrained, and nominal transitions are deterministic.
- Stale revision, late old policy, feature disable, and presentation-only edit behavior are exact.
- Queued cancellation grants no extra permit; acquire/cancel/release races end at zero.
- Cancelling session A leaves B intact; subscriber termination is not session cancellation.
- Queue overflow rejects; 20 cancel/finish cycles end with zero active/queued/sessions.
- No detached task, timer, process, thread, or I/O is launched by this checkpoint.

Run focused policy/scheduler tests, ordinary core tests, `git diff --check`, and independent review. Physical cancellation acknowledgement remains a named T23/T24 gate.

---

## T08.2 — Bounded traversal, cursor, cumulative events, and session registry core

### Scope and allowlist

May create `Scanning/{BoundedTraversal,ScanSession}.swift` and focused tests; may modify `Measure/{HomeSurvey,SizeScanner}.swift`, `Detect/{LargestItemsScanner,StaleNodeModulesScanner,UnclaimedSpaceScanner}.swift`, their exact tests, and create `docs/verification/T08-2-bounded-traversal.md`. No engine, process, app, package, or PBX edits.

### Traversal contract

Blocking enumeration runs only on a bounded dedicated utility executor after a T08.1 lease; never synchronously on MainActor or Swift's cooperative pool. It checks cancellation/deadline between finite batches and before every descendant enqueue. Bounds cover queued paths, entries/batch, depth, open descriptors, hard-link identities, child aggregates, strings, checked byte/count arithmetic, result queue, and top-N heap. Top-N retains at most N and orders deterministically by bytes then stable path.

Missing/unreadable/protected/cross-volume/churned/overflow work produces explicit coverage and reason. No truncated result is complete. Hard-link-bound overflow is incomplete rather than double-counted. Production does not retain every large file then sort.

### Continuation cursor

`TraversalCursor` is opaque, store-issued, single-use, session/root-bound, and finite. Its binding includes root resource identity, traversal generation, policy revision, bounded directory-relative position/descriptor stack, depth, remaining-work accounting, expiry, and digest. It never retains an unbounded `DirectoryEnumerator`. Cancel/finish/expiry closes all descriptors. Root replacement, generation change, churn beyond the representable watermark, replay, wrong session, or expired cursor rejects. If the remainder cannot fit the cursor/queue bounds, return incomplete with `continuationAvailable == false`.

### Subscriber/event contract

A `ScanSessionRegistry`/session actor owns work independent of observers. `subscribe(sessionID:)` returns a unique subscription ID plus its own bounded stream; subscribers never compete for one iterator. Each event contains session ID, monotonic sequence, policy revision, coverage, and a cumulative bounded snapshot/report. Progress may coalesce to the exact configured 1, 2, 3, or 4 batches/second, but a dropped progress event cannot corrupt state. Terminal cancelled/failed/partial/complete contains the final cumulative snapshot, is retained before stream finish, and is delivered exactly once to every live subscriber. Termination removes only that subscriber. Zero subscribers retain only bounded session/cursor/final state, never an event backlog.

### Mandatory tests and gates

- Slow deterministic enumerator runs off-main and stops between batches with no later work.
- Million-entry synthetic input respects queue/batch/depth/FD/hard-link/event/top-N high-water bounds; a smaller real fixture verifies FileManager behavior.
- Heap equals full-sort oracle; complete fixtures preserve existing numeric parity.
- Partial→Continue has no duplicates/missing records; single-use/replay/expiry/cancel/root-replacement/churn/max-breadth/max-depth tests are exact.
- Two subscribers receive identical cumulative terminal state; slow/full-buffer subscriber cannot corrupt state; cancelling one subscription leaves the other/session alive.
- Rates 1/2/3/4 and slices 30/300/1800 use an injected clock, not sleeps.
- Twenty cancel and twenty Continue cycles restore FDs and scheduler leases to baseline.

Physical 50k-entry first-result/total/RSS/FD/cancellation metrics remain separate gates; CI timing is diagnostic only.

---

## T08.3 — Sole process gate, revisioned cap, and async discovery adoption

### Scope and allowlist

May modify the existing `Exec/{ProcessJobGate,ProcessSession,ProcessRunner}.swift`; the exact async discovery owners identified by the source audit (`ToolLocator`, `ToolchainDetector`, Simctl/Snapshot helpers and their callers/tests); T04 standalone manifests if exact source membership changes; and create `ProcessBudgetIntegrationTests.swift` plus `docs/verification/T08-3-process-budget.md`. No second gate/semaphore/wrapper actor and no app edits.

### Contract

`ProcessJobGate.shared` (or an injected reference to that same identity) remains the sole production T04 gate with immutable aggregate cap two. One revisioned policy owner applies the resolved runtime read-only cap `0...2` (the persisted preference remains `1...2`); callers cannot choose a cap per invocation. Zero admits no new or queued read-only reservation and does not block, cancel, signal, or release a T04 mutator. Shrinking the cap does not revoke an already-running reader; session/policy cancellation owns cooperative termination where required. Stale/late cap updates reject.

Declared subprocess needs are internal, nonforgeable compiled descriptors keyed to a reviewed built-in caller/adapter ID. Arbitrary callers cannot self-certify `descendantsBounded`. Unknown/undeclared descendant behavior, nested launch, or need greater than the compiled descriptor rejects before reservation, pipes, PID, or recorder activity. `WorkScheduler` may observe/configure the gate but never owns, wraps, queues, or releases its permits.

`ProcessSession` keeps existing T04 direct-child identity, bounded output, timeout, signal ownership, consuming reap, and terminal release semantics. Two readers delay a future mutator; one mutator leaves at most one reader slot; read-only cap one serializes readers. Positive accepted-adapter mutation coexistence remains deferred until the first T15–T20 adapter path exists.

### Mandatory tests and gates

- Exact one production gate identity across `ProcessRunner` and scheduler observation.
- Conflicting caller limits are impossible; stale `0/1/2` cap updates and forged needs reject.
- Paused/critical `2 → 0` grants no new or queued reader, `0 → 1` recovery resumes eligible FIFO work, and mutator admission/ownership is unchanged throughout.
- Two-reader/mutator, one-mutator/one-reader, cap-one serialization, FIFO cancellation, nested/undeclared rejection, and 20-cycle FD/lease recovery.
- Every converted discovery uses bounded async `ProcessRunner`; source audit lists every remaining direct `Process`/`waitUntilExit` route and its later owner.
- All T04 bounded-process, A2P/source-manifest, signal/reap/timeout/fast-exit tests rerun serialized from unrelated process-heavy suites.

No mutation authority or daemon-descendant guarantee is claimed.

---

## T08.4 — Core scan/planning orchestration through shared owners

### Scope and allowlist

May modify `Engine/{ScanEngine,CleanEngine}.swift`, exact catalog `locate`/`discover` owners identified by the inventory, core scan/planning tests, and create `docs/verification/T08-4-core-orchestration.md`. It consumes T08.1–T08.3; it may not create a pool, gate, policy cache, app owner, index, monitor, or effect path.

### Contract

`ScanEngine` produces/feeds a registered session rather than assembling an unbounded one-shot report. Every traversal/survey/stale-node/unclaimed-space/catalog-locate/measurement job acquires the same filesystem scheduler. Every command-backed probe uses the one T08.3 gate and compiled declaration. Pure path construction is explicitly inventoried and exempt. `CleanEngine.makePlan` receives the same scheduler; planning cancellation cannot alter sealed-review or mutation semantics.

First cumulative partial state may publish before slow probes finish. Slice expiry is partial with a valid single-use Continue cursor or explicitly unavailable continuation. Critical is paused, not complete/failed. Serious/constrained runs at one. Parser/tool failure becomes unavailable evidence, not empty success. Events bind session and policy revision; late work cannot overwrite a newer generation.

### Mandatory tests and gates

- Real scan fixture observes aggregate filesystem/process high-water within caps.
- Two scans plus one planning request share one walk budget.
- First useful snapshot precedes blocked probes; terminal is exactly once.
- Cancel at every orchestration stage launches/publishes nothing later except terminal cancellation.
- Actual production rate/slice/policy transitions match the T08.1 snapshot.
- Complete fixture matches legacy reference semantics where unchanged.
- Exhaustive locate/discover/process/traversal source-negative audit has no unassigned escape.
- Full relevant core and T04 partitions pass; existing sealed execution remains unchanged.

---

## T08.5 — App-lifetime owner, policy handoff, multi-window UI

### Scope and allowlist

May modify the exact definitions of `AppExecutionServices`, app bootstrap (`TidyApp`/service construction), menu-bar/global scan-status owner, `Scan/{ScanViewModel,ScanView,ScanReportView}.swift`, fixture host/app-model tests, exact localization and PBX memberships, and create `docs/verification/T08-5-app-scan-lifecycle.md`. The checkpoint card must name exact files after source inspection; broad folder edits are forbidden.

### Contract

`AppExecutionServices` owns exactly one scheduler and one `ScanSessionRegistry` after bootstrap, without starting work. It atomically projects the acknowledged effective policy revision into T08.1/T08.3. Until T10 provides live observations, production observation is `.unknown`: explicit-only, one worker. Feature disable cancels read-only scan work; presentation-only edits preserve it.

Run creates or attaches to one explicit session. A view model stores only session/subscription IDs and cumulative bounded presentation. Two windows subscribe independently to the same session. Closing/deinit detaches the subscription only. Explicit Cancel targets one session ID and remains available through the global/menu owner after its window closes. Continue consumes the issued cursor. Rescan after terminal creates a new generation; late old events are ignored.

MainActor performs bounded state publication only. No `onAppear`, `.task`, Settings setter, bootstrap, timer, or view construction starts discovery. Partial, paused, Continue-unavailable, cancelled, failed, and complete are distinct accessible states.

### Mandatory tests and gates

- Two windows share one registry/session and receive identical terminal state without duplicate work.
- Close/detach isolation, menu/global Cancel, rescan generation, stale-event rejection, and 20 attach/detach/cancel cycles.
- Bootstrap/view/settings-open instrumentation proves zero traversals, processes, scan timers, and hidden-idle work.
- MainActor heartbeat stays responsive while a real slow bounded enumerator blocks off-main.
- UI receives configured cumulative updates only; stable accessible Run/Continue/Cancel identifiers, labels, focus, text scaling and contrast fixtures.
- Full app-model/core partitions and unsigned arm64 build pass; exact PBX/production-fixture separation is inspected.

---

## Completion and nonclaims

Scoped T08 source completion requires all five independently approved checkpoints and a final source audit assigning every T08-owned escape route. It proves bounded/cancellable production ownership on tested fixtures only.

Full product/release acceptance additionally requires named physical evidence on 8 GiB Apple Silicon and Intel, oldest-supported macOS 14 and current OS: first useful result, total fixture time, UI/worker cancellation, peak RSS, 20-cycle RSS/FD return, and accessibility/window/menu behavior. Deterministic tests cannot close those gates.

T09 owns incremental cache, FSEvents freshness and ≥80% metadata-visit savings. T10 owns real pressure/power/thermal observation. The first accepted T15–T20 adapter plus later hostile gate owns positive real mutator/read-only coexistence. T08 authorizes no background scanning, so build-impact testing remains disabled rather than implying such authority exists. Until all product gates close, README/release language must not call Tidy universally battery-neutral, leak-free, or validated on all low-spec Macs.
