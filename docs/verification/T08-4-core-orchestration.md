# T08.4 core scan/planning orchestration verification

## Accepted scope

This phase consumes T08.1a/1b, T08.2, and T08.3. Its tracked implementation
scope is:

- `Engine/ScanEngine.swift`
- `Engine/CleanEngine.swift`
- `Catalog/CleanCatalog+{Extras,System,Xcode,DependencyCaches}.swift`
- exact core tests and `CoreOrchestrationTests.swift`
- this verification record

The user approved one narrow amendment on 2026-08-29: expose read-only
`effectiveSliceSeconds` and `effectiveUIBatchesPerSecond` in
`WorkSchedulerSnapshot`, populated only from the already-resolved acknowledged
policy. That adds only `Scanning/WorkScheduler.swift` and
`WorkSchedulerTests.swift` to the phase allowlist. It adds no policy,
admission, bridge/session, process, or effect authority.

## Authority and data flow

`CoreOrchestrationContext.make` accepts the caller's
`BridgeExplicitSessions`, valid `WorkSession`, and a correlation ID. It reads
revision, generation, observation epoch, filesystem/process caps, slice, and
presentation rate only from the facade snapshot. A supplied traversal limit
must use the acknowledged slice. The context is non-authoritative: it cannot
create a scheduler, bridge, session capability, process gate, or policy value.

The registered scan path begins one `ScanSessionRegistry` session with the
acknowledged revision/rate, starts registry-owned work, and publishes
cumulative bounded state only after rechecking the facade. Invalidating policy,
presentation revision, observation epoch, session cancellation, or a changed
slice/rate/process cap makes the retained context stale. Late work therefore
cannot publish through that context. Each handle retains at most one finite
latest `ScanReport`; it is not an app owner, index, queue, policy cache, or
monitor.

Filesystem work uses `HomeSurvey.walkBounded`,
`StaleNodeModulesScanner.findBounded`, `SizeScanner.diskUsageBounded`, or a
direct `BoundedTraversal`, always with the caller's same facade/session.
Command-backed work uses compiled T08.3 `ProcessRunner` declarations. Before a
command, the already-resolved revision/epoch/read-only cap is applied to the
one production process gate; an exact already-applied value is accepted only
when gate identity, revision, and cap agree.

## Partial, paused, unavailable, and terminal semantics

- The first bounded home result publishes before process probes begin.
- The registry owns terminal publication; registered work returns one
  completion and tests assert exactly one terminal.
- Cancellation at every orchestration checkpoint stops later launch and
  publication; the registry retains `.cancelled` with `.cancelled` coverage.
- Critical/paused policy rejects scan/context admission as `policyPaused`; it
  is never represented as complete or failed. Resumed policy requires a fresh
  acknowledged context.
- Parser, tool, bounded-result, overflow, and stale-policy failures are partial
  or unavailable evidence, never fabricated empty success.
- T08.2 cursors cannot be represented by the accepted `ScanSession` public
  schema. On slice expiry the engine invalidates its retained traversal cursor,
  returns partial `.sliceExpired`, and explicitly reports
  `continuationAvailable == false`. No token is leaked or replayable.
- Unclaimed-space candidates are suppressed and coverage becomes unavailable
  when a measured top-level entry crosses the reporting threshold without a
  complete bounded claim inventory. A small complete fixture can still prove
  unchanged ranking semantics; a potentially incomplete inventory is never
  reported as successful empty discovery.

## Catalog route inventory

The source-negative test pins every catalog file's `locate:`/`discover:` count
and assigns each route to this phase or a named later owner. Production planning
does not invoke generic sync-only `locate` closures on the explicit path.

| Route family | Owner and T08.4 treatment |
| --- | --- |
| Fixed paths and explicit memory descriptors | Pure construction / bounded O(1) inspection under the shared permit |
| Extras build outputs and stale node_modules | T08.4 bounded traversal helpers |
| APFS snapshot presence | T08.4 async `tmutil` declaration; failure unavailable |
| Approved simulator inventory | T08.4 async `simctl` declaration and strict decode |
| Flutter SDK cache | T08.4 async tool lookup plus permitted fixed-path inspection |
| Helper globs | T12 |
| Apple/Xcode effects | T15 |
| Android and remaining build/tool adapters | T16 |
| Browser adapters | T17 |
| Memory requests | T18 |
| Transcript/local-AI discovery | T19 |
| Git discovery/effects | T20 |

## Immutable effect scope

Planning still ends at `CapabilityRegistry` quarantine. Estimated bytes come
only from complete bounded measurements; partial/overflow measurement resets
the estimate to zero. No cleanup executor, mutation admission, confirmed plan,
journal, path guard, command mutation, or model/public `CleanItem` schema was
changed. No file was deleted, moved, cleaned, uploaded, pushed, released, or
deployed by this phase.

## Direct command evidence

Commands are listed in execution order. RED results are intentional TDD
observations, not completion gates.

1. Baseline:

   `swift test --disable-sandbox --jobs 2 --filter 'ScanEngineTests|CleanEngineTests|PlanVisibilityTests|DeclaredRootEnforcementTests'`

   Result: exit 0; 25 tests / 4 suites passed.

2. Source-manifest RED:

   `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.productionRouteManifestIsSealed'`

   Result: exit 1; 10 expected owned escape findings.

3. Legacy-boundary RED:

   `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.legacyCallsAreSafeNoOpBoundaries'`

   Result: exit 1; 4 expected issues proving legacy work still launches.

4. Snapshot projection GREEN:

   `swift test --disable-sandbox --jobs 2 --filter 'WorkSchedulerTests.snapshotProjectsOnlyAcknowledgedSliceAndPresentationRate'`

   Result: exit 0; initial nil, acknowledged install, presentation-only rate,
   invalidating slice, constrained one-worker, critical pause, and nominal
   resume assertions passed.

5. Explicit planning GREEN:

   `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.explicitPlanningUsesSharedPolicy'`

   Result: exit 0; one test passed.

6. Registered scan GREEN:

   `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.registeredScanPublishesBeforeProcessAndTerminatesOnce'`

   Result: exit 0; one test passed.

7. Bounded catalog RED then GREEN:

   `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.boundedCatalogDiscoveryDoesNotPresentTruncatedTargets'`

   RED result: exit 1; target and byte estimate were incorrectly presented.
   GREEN result: exit 0 after async bounded dispatch.

8. Shared aggregate walk budget GREEN:

   `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.scansAndPlanningShareOneWalkBudget'`

   Result: exit 0; active 1 and queued at least 2 observed.

9. Cancellation stages GREEN:

   `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.cancellationStopsLaterStagesAndPublication'`

   Result: exit 0; all three stages passed.

10. Actual process high-water GREEN:

    `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests.registeredScanUsesSharedProcessCap'`

    Result: exit 0; harmless compiled process fixtures observed active reader
    high-water above zero, no greater than acknowledged cap or physical two,
    and zero active at terminal.

11. Consolidated pre-seal audit:

    `swift test --disable-sandbox --jobs 2 --filter 'CoreOrchestrationTests'`

    Result: exit 1; every additive behavior passed. Only the intentional four
    legacy-boundary issues and ten owned source escapes remain pending explicit
    compatibility authorization.

## Controller final verification (2026-08-29)

The user explicitly approved Option A on 2026-08-29: legacy `ScanEngine.run`
and the 3-argument `CleanEngine.makePlan` become temporary no-op boundaries
(rows retained, zero discovery/measurement/traversal/process launch) until
T08.5 rewires the app to the explicit orchestration path. The boundary was
sealed and every command below was run directly by the controller.

1. Focused orchestration suite:

   `swift test --disable-sandbox --jobs 2 --filter CoreOrchestrationTests`

   Result: exit 0; 14 tests / 1 suite passed, including the legacy-boundary
   and source-manifest tests.

2. Shared-process-cap test isolation. The
   `registeredScanUsesSharedProcessCap` test observes the one shared physical
   `ProcessJobGate`, whose policy revision and reader counts other suites churn
   when the whole target runs in one process, so it is gated behind
   `TIDY_ISOLATED_GATE_TESTS=1` and runs as a dedicated invocation:

   `TIDY_ISOLATED_GATE_TESTS=1 swift test --disable-sandbox --filter CoreOrchestrationTests`

   Result: exit 0; 14/14 including the cap test (high-water above zero, no
   greater than the acknowledged cap or physical two, zero active at terminal).
   In plain full-suite runs the test records as skipped.

3. `SettingsProcessAcceptanceTests` regression found and fixed: the suite
   compiles a hardcoded source list into a standalone helper binary, and the
   new `Execution/DerivedDataEffectAdapter.swift` (referenced by listed
   sources) was missing from that list, failing the helper compile with
   `.incomplete`. The file was added to the list.

   `swift test --disable-sandbox --filter SettingsProcessAcceptanceTests`

   Result: exit 0; 3 tests / 8 parameter cases passed.

4. Full core suite:

   `swift test --disable-sandbox --jobs 2`

   Result: exit 0; 564 tests / 60 suites passed. One earlier full run recorded
   a single interference failure in
   `SettingsMigrationTests.independentBootstrapContenderCannotInitializeWinnersMetadata`
   (multi-process bootstrap contention; 46/46 green in isolation), the same
   pre-existing full-suite interference class as the known
   `BoundedProcessRunnerTests` aggregate flake.
