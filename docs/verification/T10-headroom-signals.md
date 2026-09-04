# T10 headroom signals and UI verification

## Scope

New `TidyCore/Sources/TidyCore/Monitoring/{SystemSnapshot,SystemMonitor,SignalHistory}.swift`;
modified `Measure/{DiskStats,MemoryStats,SwapStats}.swift`,
`Detect/RestartReclaimSurvey.swift`; new `Tidy/Headroom/{HeadroomView,HeadroomViewModel}.swift`
and `Tidy/PrivacyInfo.xcprivacy`; rewired `Tidy/MenuBar/{StatsRefresher,MenuBarContentView}.swift`
onto the shared monitor; qualified wording in `Tidy/Scan/{ScanReportView,ScanSectionViews}.swift`
and `README.md`; tests in `TidyCoreTests/HeadroomSignalsTests.swift`, `StatsTests.swift`,
`MemoryAndSwapTests.swift` and `TidyAppModelTests/HeadroomViewModelTests.swift`.

## Contract compliance

- Observations are optional, timestamped, per-volume/system readings; no composite score
  exists anywhere. `HeadroomReadiness` is worded "target met", never buildability.
- Page-out rate is presented only as a pressure indicator; absolute
  "restart-only"/"swap never shrinks" claims were replaced with observed, qualified wording
  in the UI and README. Unavailable readings are `nil` plus a reason, never `0`.
- All system probes are injected (`SystemProbing` seam); `counterRate` returns nil on
  reset/negative delta/zero or non-finite elapsed; boot identity is consulted before any
  cumulative delta; page size is threaded by value.
- Monitoring disabled or all surfaces hidden ⇒ zero repeating timers/tasks, proven by
  injected instrumentation. Background sampling arms at launch only when the resolved
  policy enables it. Process polling never happens on the periodic path. History is
  opt-in, count- and age-bounded, and structurally cannot store process data.
- `PrivacyInfo.xcprivacy` declares Disk Space (E174.1) and System Boot Time (35F9.1),
  matching the APIs this phase calls. A pre-existing file-timestamp usage
  (`StaleNodeModulesScanner`/`TranscriptPruneScanner`, outside this phase) has no cleanly
  matching documented reason code and remains an open item for any distribution gate.

## Independent review and repair

One independent review ran after implementation. Findings, all repaired in one pass:
a retained-task leak/double-subscription on every window reopen (fixed with per-consumer
`SystemMonitor.subscribe()` streams deregistering via `onTermination`, plus a regression
test discarding six consumers and proving the survivor still receives broadcasts); an
unqualified "Only a restart can reclaim this" title; `?? 0`-as-unknown in
`RestartReclaimSurvey` (now optional + reason, including the `ScanEngine` call sites);
a duplicated immediate probe on open (timer loop now sleeps first); accounting comments;
launch-time arming. The `TidyUITests/HeadroomUITests.swift` file from the contract was
substituted with `TidyAppModelTests/HeadroomViewModelTests.swift` because no UI-test
target exists in the project; deviation disclosed, not hidden. `DiskStats`'s pre-existing
`?? 0` total-capacity fields were left unchanged (out-of-scope ripple) and remain known.

## Controller-run evidence (2026-08-29)

1. `swift test --disable-sandbox --jobs 2 --filter 'HeadroomSignalsTests|StatsTests'` — exit 0.
2. Full core: `swift test --disable-sandbox --jobs 2` — exit 0, 623 tests / 63 suites.
3. Isolated gate invocation (`TIDY_ISOLATED_GATE_TESTS=1 … --filter CoreOrchestrationTests`) — 14/14.
4. `xcodebuild test -scheme TidyAppModelTests` — exit 0, 126 cases passed, 0 failed.
5. Unsigned Debug app build (`CODE_SIGNING_ALLOWED=NO`) — BUILD SUCCEEDED.

No release, packaging, signing, upload, or real-user cleanup occurred.
