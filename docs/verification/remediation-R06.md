# R06/R07 scan, scheduler and index remediation evidence

Date: 2026-09-17

## Implemented production behavior

- Scan traversal now requires an opaque `AuthorizedScanScope`. The engine consumes the grant at
  the actual start boundary and rejects a replay, a foreign window owner, an expired grant, a
  changed policy revision or a different home environment. Continue retains the already-consumed
  grant only inside the same scheduler generation.
- Default Quick derives a finite set of exact cache/inventory roots. It does not use catalog
  `declaredRoot` safety containers such as `~/Library`, `~/Library/Developer`, `~/.claude` or
  `~/Library/Application Support/Claude`. Selected-project scope uses only acknowledged local
  project roots and refuses roots outside the acknowledged home volume boundary.
- User exclusions are combined with `CleanEnvironment.defaultProtectedRoots`; iCloud
  `Library/CloudStorage` and `Library/Mobile Documents` remain protected descendants even during
  an explicitly consented full-home scan.
- Full-home consent is a separate owner-bound token. Consent and its resulting scan grant both
  expire, are single-use, bind the acknowledged revision/home, and cannot be transferred to a
  second window.
- App scan ownership is global. A duplicate start attaches to the current generation, closing a
  view only detaches its subscription, and global Cancel retains ownership after every scan window
  closes. Running partial progress and terminal partial results are distinct UI states.
- Bounded traversal cursors are retained by the core scan handle. Manual Continue consumes each
  cursor once, preserves the original scope/revision/generation and converges over later bounded
  pages without restarting completed roots or expanding scope.
- While explicit work exists, AppExecutionServices holds a SystemMonitor explicit-work lease and
  forwards memory-pressure, thermal and Low Power Mode observations to the shared scheduler.
  Observation epochs are monotonic; stale samples are rejected. Critical state blocks new work
  and remains effective through the configured monotonic cooldown. The lease survives window
  closure and is released at terminal/cancel; hidden idle retains no scan lease.
- The app lazily opens its aggregate SQLite index only for explicit indexed scans. It applies the
  acknowledged `scan.cacheEnabled`, `scan.cacheMiB` and `scan.cacheExpiryHours` settings, recovers
  a corrupt app-owned database, binds roots to one live volume identity, starts FSEvents before
  traversal and stops the stream at terminal idle. A retained coordinator preserves generations
  across scans without leaving an FSEvents stream active.
- FSEvents catch-up now applies the stream's initial reliability/cursor handshake before a cache
  status read. Callback batches are capped at 4,096 events and the pending delivery queue at 64
  batches; overflow coalesces to an unreliable-history invalidation. `MustScanSubDirs`, dropped
  events, root changes, mount/unmount and event-ID wrap continue to invalidate conservatively.

The FSEvents decisions follow Apple's documented requirements: monitoring begins before baseline
scanning, `MustScanSubDirs`/dropped history requires recursive rescan, root changes require a full
hierarchy rescan, and `FSEventStreamFlushSync` invokes callbacks for events that occurred before
the flush returns. Sources: [Using the File System Events API](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html),
[FSEventStreamFlushSync](https://developer.apple.com/documentation/coreservices/1445629-fseventstreamflushsync),
and [kFSEventStreamCreateFlagWatchRoot](https://developer.apple.com/documentation/coreservices/kfseventstreamcreateflagwatchroot).

## Fresh focused evidence

- `swift test --scratch-path /tmp/tidy-r06-build --jobs 2 --filter ScanScopeTests`
  passed 7 tests. The fixtures assert zero actual traversal-source metadata visits for an empty
  selected-project scope, exact Quick-root visits with unrelated Documents/credential-cache
  witnesses untouched, mandatory protected-descendant exclusion, grant owner/expiry/replay and
  root-identity replacement at engine start, and bounded Continue convergence.
- `swift test --scratch-path /tmp/tidy-r06-build --jobs 2 --filter
  'ScanObservationTests|ScanInvalidationTests|ScanIndexTests'` passed 37 tests in 3 suites. This
  includes monotonic critical cooldown/stale epoch rejection, constrained one-worker admission,
  bounded overflow invalidation, history loss, cursor/device identity, corruption/expiry/cap,
  incremental/fresh parity and the existing unchanged-fixture >=80% metadata-visit reduction.
- `swift build --scratch-path /tmp/tidy-r06-build --jobs 2` exited 0 after the production changes.
- `xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination
  'platform=macOS' -derivedDataPath /tmp/tidy-r06-xcode -jobs 2 build
  CODE_SIGNING_ALLOWED=NO` exited 0 for the integrated app before the final index queue/catch-up
  edits. Those later core edits compiled in the 37-test pass above.
- A focused `ScanOrchestrationWiringTests` run initially passed 8/10. The two failures exposed a
  real generation race: an old session's terminal cleanup stopped the replacement scan's shared
  observation/index resources. Cleanup is now guarded by the exact active session generation.
  The requested rerun was then interrupted by unrelated shared-tree R08 source replacement and
  later deferred when free disk fell near the controller's 5 GiB safety floor. It is not recorded
  as green here.

All fixtures wrote only under unique `/private/tmp/TidyR06*` or
`/private/tmp/T085ScanWiring-*` directories. No personal home, service, mutation adapter or remote
endpoint was used.

## Residual acceptance and release boundaries

- The physical UI Cancel <=100 ms and bounded-worker acknowledgement <=500 ms gates remain not
  measured. Unit/session cancellation evidence does not close them.
- Real critical memory pressure, serious thermal state, Low Power Mode, sleep/wake and stale
  provider behavior remain hardware/runtime acceptance. Injected scheduler observations prove the
  production handoff logic, not physical condition delivery timing.
- A fresh focused app-model rerun after the generation-race fix remains required. The app index is
  production-wired, but app-level real-FSEvents unchanged reuse and the 100k metadata reduction
  must still be recorded in a disposable fixture with raw artifacts. Existing core parity and
  reduction tests do not substitute for that app gate.
- Multiple-volume indexing is deliberately unavailable: a scan whose approved roots do not all
  resolve to the same live volume identity falls back to fresh traversal. External-volume consent
  and remount acceptance are not inferred from path equality.
- Physical footprint, FD/memory settling over twenty app cycles, Intel/Apple Silicon, macOS 14,
  VoiceOver and human UI gates remain untested here.
- Fresh-install scan admission and detected-tool restoration were intentionally left unchanged,
  as required by the dependency gates. Revision-zero settings still do not install scheduler
  authority, and app construction still supplies an empty detected-tools set.

R06 source behavior is implemented with the residual runtime gates above. R07 app integration is
implemented but remains incomplete until the focused app rerun and real scratch FSEvents/100k
artifacts are captured. Neither package is a full-program completion claim.

## Controller scope correction — cache aliases

Quick scope previously canonicalized known cache paths before issuing authority. Disposable fixtures proved that a leaf or ancestor symlink could authorize the fixture home, an unrelated directory, or an outside sibling. A moved cache ancestor replaced by a symlink could also preserve the leaf's opaque identity and pass the start check.

Quick candidates now keep their fixed lexical paths and use descriptor-relative no-follow capture. Grants retain typed volume/device/inode/generation/mode and ancestor identities, enforce the acknowledged home volume, and revalidate those identities at start. Root minimization no longer resolves aliases after validation. The four alias fixtures perform zero traversal metadata visits; the moved-ancestor case denies before traversal. No test traversed the actual home or system root.

RED: `/tmp/tidy-scope-alias-red.log`, 2 tests / 10 expected issues before the fix. GREEN: `swift test --package-path TidyCore --scratch-path /tmp/tidy-controller-baseline --jobs 2 --no-parallel --filter ScanScopeTests`, **9 tests passed**, `/tmp/tidy-scope-alias-green.log`. Physical mount/remount acceptance remains separate.
