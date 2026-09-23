# Safety audit track — 9e1a500

Evidence: source inspection on 2026-09-17 at `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`. Scope: D02–D07/D14. No runtime tests launched by this track. Coordinator owns runtime results. `tracks/SafetyAuditRegressionTests.swift` contains seven scratch-only production-entry regression tests; it is an audit artifact, not a production patch. References below are relative to `TidyCore/Sources/TidyCore/` unless otherwise specified.

## Reachability boundary

`Execution/CapabilityRegistry.swift:13-17` accepts exactly `safe.xcode.derived-data` + `.deleteContents`. Public `ExecutionCoordinator` can execute it using a `.xcode` environment; existing `TidyCore/Tests/TidyCoreTests/DerivedDataExecutionTests.swift:68-116` uses that real route without a fake adapter. **The shipped UI cannot currently select it:** `Tidy/Execution/AppExecutionServices.swift:62-64,151-155` injects empty detectedTools at bootstrap and into retained bridge; `Tidy/Onboarding/OnboardingViewModel.swift:29-32` detects tools only for onboarding display; `Catalog/CleanCatalog+Xcode.swift:17` requires Xcode and `Engine/CleanEngine.swift:71-72,135-137` denies missing tool. Therefore findings below are **accepted-library/capability-enablement blockers**, not demonstrated current shipped-UI data loss. Do not repair tool detection before restoring quarantine or closing these defects. Full-program safety acceptance fails; current application usefulness verdict belongs to synthesis.

## Findings

### SAF-01 — Confirmation ignores reviewed root/descendant identities

- **Dimensions/severity/confidence:** D02/D03; High; high. Requirement: approved design S02/S03/S05 (`docs/superpowers/specs/2026-08-26-developer-headroom-design.md:31-34`). Public production API reachable; shipped UI unreachable as above.
- **Expected/observed:** confirmation binds exact reviewed identities and descendants. Coordinator captures root identities (`Execution/ExecutionCoordinator.swift:40-49,94-103`) but `validateSelection` (`:320-327`) checks only selectability, action and initial identity availability. Stored identities are never compared. Adapter opens current root and captures a new descendant tree after confirmation (`Execution/DerivedDataEffectAdapter.swift:52-53`), then deletes it (`:71-73`).
- **Minimal reproduction:** UUID scratch home/DerivedData/original; public prepare/select/confirm; create child, grow original, or move root away and recreate same path; execute old token. Regression tests: `postConfirmationChildSurvives`, `postConfirmationGrowthSurvives`, `replacedRootSurvives`. No race needed. Scope: newly created or replaced build output obtains authority it never had at review.
- **Root cause/correction:** execution-time capture substituted for reviewed authority. Core execution owner must first restore denial, then capture bounded review manifest, bind digest/root/exclusions to seal and durable intent, revalidate each reviewed leaf before effect. Depends on SAF-03/04.
- **Closure:** production-entry tests retain changed/new/replacement and outside witnesses; unchanged permitted-leaf positive control requires accepted proof. Re-quarantine is a valid immediate correction; regression tests should then assert explicit confirmation denial rather than require a token. Runtime reproduction results are coordinator-owned; last-check/unlink race separately SAF-03.

### SAF-02 — Parent selection bypasses protected children

- **Dimensions/severity/confidence:** D03/D04; High; high. Requirement: S06 and scope restrictions. Accepted public API reachable only as above.
- **Expected/observed:** protecting a child also protects it from parent cleanup. `Safety/PathGuard.swift:147-151` only checks candidate-inside-protected-root; ancestor-aware `relation` (`:6-24`) is not consumed by accepted adapter. Coordinator only guards target root (`ExecutionCoordinator.swift:241,248-251`); adapter captures/deletes with empty exclusions (`DerivedDataEffectAdapter.swift:53,73`). Planner also root-filters (`CleanEngine.swift:81-85`).
- **Minimal reproduction:** scratch DerivedData/protected-subtree/keep; environment.protectedRoots contains that subtree; select parent. `protectedDescendantSurvives` expects keep retained.
- **Correction/owner:** core safety owner projects protected canonical descendants into reviewed relative exclusions, binds exclusion digest and enforces it at every actual removal. Pinned/excluded path policy mapping requires policy-track integration.
- **Closure/regression:** protected nested file/directory, Unicode sibling, symlink alias and mount witness preserved through production coordinator, while an allowed sibling can execute with proof. No user data was touched; direct protectedRoots fixture avoids assumptions about UI settings mapping.

### SAF-03 — Deletion lacks owner/quiescence evidence and producer exclusion

- **Dimensions/severity/confidence:** D04/D03/D07; High; high. Requirement: S05/S07 and appendix `docs/superpowers/specs/2026-08-26-headroom-policy-and-adapter-contracts.md:153-175` (complete owners, positive quiescence, five-second runtime validity).
- **Observed:** fixed path discovery only uses attributes (`Catalog/CleanCatalog+Helpers.swift:29-38`); coordinator gates only pair/count/path (`ExecutionCoordinator.swift:248-257`); adapter receives no owner, lease, expiry or manual acknowledgement (`DerivedDataEffectAdapter.swift:46-53`). Underlying primitive explicitly requires accepted producer exclusion/policy boundary (`GuardedFileDeleter.swift:493-496`), absent in adapter. Final stat (`:553-555`) and unlink (`:510-513`) are separate operations.
- **Minimal reproduction:** `missingOwnershipEvidenceWithholdsEffect` supplies only scratch path and tool-presence bit; no positive producer proof is supplied or representable, yet effect runs. Active-build disruption is a source-supported consequence, not a test against user workloads. Last-check/unlink concurrent replacement race is credible but not experimentally induced.
- **Correction/owner:** Apple adapter + core safety owner; retain inventory-only until supported versioned producer proof or separately warned permissible manual contract exists. Revalidate complete owners immediately; hold actual producer exclusion during check/unlink or withhold. Process absence is not proof.
- **Closure:** supported fresh-complete-owner positive integration fixture succeeds; unknown/shared/expired/new-active owner and unsupported version yield zero removals; deterministic lease/race fixture retains replacement witness. Blocks accepted cleanup and full program; current UI not established reachable.

### SAF-04 — Real effects bypass durable intent/terminal state and exhaust eight active slots

- **Dimensions/severity/confidence:** D05/D02; High; high source confidence. Requirements: S04/S16, T03.B/T04.C.
- **Expected/observed:** durable operation/manifest before effect, positive terminal reconciliation and bounded history after. Coordinator explicitly skips pending intent because reconciliation is absent (`ExecutionCoordinator.swift:222-237`), appends only planned/confirmed (`:238-239`), mutates (`:257`), returns completed (`:276-279`). Admission only checks unfinished ledger (`MutationAdmissionStore.swift:74-80`), which this path never populates. Journal caps active runs at eight (`RunJournal.swift:108-112`); only finished resolves a run (`:175`). Coordinator never finishes.
- **Minimal reproduction:** `realEffectIsDurablyRecorded` expects started/itemTerminal/finished after real scratch deletion; `nineSequentialRunsDoNotExhaustActiveSlots` repeats nine small scratch runs. Predicted result: missing phases and ninth storageUnavailable. Crash mid-unlink has no durable per-leaf progress; no real crash run by this track.
- **Root cause/authority contradiction:** adapter was enabled before integration gates; `docs/verification/headroom-progress.md:52-54` explicitly retains aggregate capture, ownership, persisted manifests and real recovery as unapproved. Existing `DerivedDataExecutionTests.swift:98-116` asserts the defective planned/confirmed-only sequence, so green evidence cannot close this requirement.
- **Correction/owner:** recovery/storage owner re-quarantines, implements durable exact reviewed manifest/operation intent, positive in-process file-effect completion/quiescence, bounded terminal resolution and no automatic replay. Do not merely append fake finished events around unrecorded effects.
- **Closure:** disposable helper crash/persistence-fault matrix at every durable/effect boundary; relaunch blocks until positive proof; 9+ completed runs retain bounded usable storage; corrupt/disk-full journal denies; optional history never clears unresolved state. No surviving mutating subprocess currently accepted, so subprocess-specific crash proof remains future integration gate.

### SAF-05 — Accepted capture/effect lacks aggregate resource and cancellation bounds

- **Dimensions/severity/confidence:** D03/D05/D15/D18; Medium with current UI unreachable; high source confidence. Requirements: S12 and T03.B/T04 budget contract.
- **Observed:** `GuardedFileDeleter.swift:239-264` caps individual batches but retains every batch; `:265-307` recursively gathers/sorts every directory name and copies parent chains; `:314` flattens full entries. No total node/byte/depth bound or streaming manifest admission. Adapter `:64-75` processes all leaves without cancellation/deadline/policy/batch-byte check. Existing `LeafScheduleBudget` (`GuardedFileDeleter.swift:559-581`) is not used here.
- **Minimal scenario/impact:** large/deep scratch DerivedData or cancel before dispatch; source permits full capture and leaf scheduling regardless. This risks unbounded memory/FD/stack/work on constrained hosts. Physical exhaustion was deliberately not run.
- **Correction/owner/dependency:** filesystem execution owner adds total memory/durable admission caps, iterative bounded traversal, sealed chunks and explicit cancellation/deadline/policy checks at safe boundaries, retaining partial/uncertain state; depends on SAF-01/03/04.
- **Closure:** 50k/100k/churning/deep disposable fixtures, measured memory/FD bounds, cancellation latency and protected witnesses. Eight-GiB physical acceptance stays separate. Runtime bounds Not tested.

## Positive controls and limits

- **D02 Pass source boundary:** `ConfirmedPlan.swift:22-32` restricts token creation; coordinator validates identity/nonce/stored binding/policy (`ExecutionCoordinator.swift:154-198`); selection invalidates old tokens (`:116-136`). Raw engine execution is unconditional denial (`CleanEngine.swift:251-260`); custom executors cannot install authority.
- **D03 Partial:** anchored no-follow chain/local volume UUID+mount checks (`GuardedFileDeleter.swift:75-138,179-204`); unsupported/symlink nodes fail (`:292-300`); parent and leaf checks (`:524-555`). These are useful primitives, not reviewed/lease integration.
- **D05 Partial:** exclusive flock/durable bootstrap (`MutationAdmissionStore.swift:28-54,60-80`); existing unresolved intent blocks accepted adapter; retention protects unresolved journals (`RunJournal.swift:189-206`). Foundation tests do not close SAF-04.
- **D06 Partial:** fixed command/path/argv table (`ProcessRunner.swift:165-224`), fixed minimal environment (`:69-72`), shared gate (`:75-78,149-162`); testing launch requires isolated gate (`ProcessSession.swift:248-254`). Unknown commands including Git/Docker/shell are denied. Output must be complete (`ProcessRunner.swift:246-256`). No production mutating subprocess descriptor accepted. The two-command gate does not claim to count filesystem workers. Version-specific parser/daemon behavior and controlled traffic remain unproven.
- **D07 Pass intentional denial / Partial inventory:** every mutation except DerivedData denied, including Git remote prune/gc/lock removal, broad simulator/package prune, snapshots, memory quit/purge/restart, cookies and VMs. Denial does not satisfy promised inventory/mutation delivery.
- **D14 Partial source / Not tested traffic:** source searches found no URLSession/Network/socket-connect runtime path; Package.swift has no external packages and links sqlite3. This cannot prove zero child-process network/service effects; retain controlled traffic gate. This track collected no raw user data.
- **Cookie boundary:** `Browsers/ChromiumCookieCleaner.swift:66-69` always denies, leaving original DB/backups unchanged; SQL mutation/restore bodies removed. WAL/write/restore acceptance is Not applicable to current denied mutation and Blocked until accepted adapter for promised workflow. No Safari-cookie action. `CookieDomainSuggester.swift:23-41` opens SQLITE_OPEN_READONLY and reads host_key; `:45-54` uses explicit last-two-label heuristic, not PSL or deletion authority. No current app caller found. Future exact-domain/schema/WAL/locking/private validated backup/write verification/restore-failure tests mandatory.
- **Transcript memory:** mutation remains denied; scanner exclusion logic cannot itself confer delete authority. Scope-preserving quarantine is not useful cleanup completion.

## Test isolation

No tests run by this track. Inspected destructive tests allocate UUID scratch homes/targets/journals. Process C fixture writes only supplied scratch root; no shell/network/host cleanup. FIFO watchdog retains descriptors until drained.

Exclude `SimctlClientTests` (`TidyCore/Tests/TidyCoreTests/SystemToolSurveyTests.swift:55-88`) until disposable service/device identity and no undesired daemon startup established: it invokes real async host simctl list. `SimulatorPrunerTests.realDevicesNeverEligibleWithoutRealApproval` has stale host-listing comments but is inert because `Detect/SimctlClient.swift:82-84` returns []. Snapshot/process/disk/VM surveys read real host state nondestructively. CleanCatalogTests.everyLocatedFilesystemTargetFallsUnderDeclaredRoot reads real home path metadata; do not publish personal paths or label fixture-only.

Process compilers inherit HOME (`BoundedProcessRunnerTests.swift:8-12`, `SettingsProcessAcceptanceTests.swift:57-65`); SettingsProcess compiler lacks module-cache-path (`:164-169`). Coordinator should provision scratch HOME/cache paths or classify/skip ambient compiler cache writes. `ProcessBudgetIntegrationTests.swift:33-38` assumes package `.build/debug`; external --scratch-path alone breaks compile-negative evidence. Full suite needs serialization and honest shared-gate interference reporting.

## Approved adapter matrix

All appendix section 5 .I/.M units below remain incomplete typed adapter delivery; legacy path metadata is not versioned InventoryRecord/EffectSpec proof. Initial unattended allowlist is empty. All deny except unsafe DerivedData candidate.

| Adapter | Inventory | Mutation and closure |
|---|---|---|
| Apple/Xcode/SwiftPM/CocoaPods/simulators | Legacy path metadata; simctl JSON helper; incomplete producer/project mapping | DerivedData SAF-01–05; others deny. T15.I versioned identity/parser; T15.M exact UDID/owners/preflight/recovery; no all/unavailable |
| Android/Gradle/Flutter/AVDs | Legacy paths and async Flutter path; no stable AVD runtime token | Denied. T16 typed unknown state and supported instance protocol or keep denial |
| Node/Bun/Deno | Legacy caches, bounded stale node_modules/build paths | Denied. Lockfile never proves unmodified dependencies; exact output/owner manifest; no unattended node_modules |
| Rust/Python/Ruby/Go | Some pip/go legacy paths; no typed Cargo/venv/Conda/Gemfile/go.mod family | Denied. Separate inventory; venv/Conda read-only; shared/symlink/unknown blocks |
| Homebrew | Cache metadata; no supported mutation version | Broad cleanup/autoremove denied. Exact versioned effects or keep quarantine |
| Docker/Colima | No production pinned endpoint/object adapter found | No accepted command. Local pinned socket, remote zero calls, exact image/container IDs; separate writable-layer consent; no force/volume/prune |
| IDE | Legacy JetBrains/cache paths | Denied. Documented caches distinct from workspaceStorage/extensions; fresh owner proof |
| Models/environments | No typed model-alias/blob adapter | Unknown/model generic delete denied. Nonadditive inventory/reveal and permanent read-only tests |
| Databases/VMs | Legacy Claude VM paths, no typed database/VM family | Denied. Typed inventory/reveal and explicit denial regression |
| Git/worktrees | Bounded root/repo scanners; no accepted common-dir/hook-safe mutation | Helpers/catalog denied. Complete worktree/shared owner map, controlled hooks/config, exact local scope or quarantine |
| Browsers | Profile/domain helpers; most async catalog unavailable | Cookie/cache denied, no Safari cookie action. Exact domains/schema/WAL/backups/restore gates before enabling |
| Transcripts/logs/Trash | Fixed paths and transcript scanner | Denied. Memory protection, explicit personal-data loss, exact manifests/owners/recovery |
| Snapshots | Async listlocalsnapshots | Denied. Exact reviewed IDs/privileged contract; no fresh relist expansion |
| Memory | Explicit zero-byte/opaque-name rows, no process-instance adapter | All denied. Exact instance, graceful completion, separate advanced consent, truthful swap/RAM |

## Exhaustive catalog rows

Inventory column describes source capability, not current UI discovery. Empty detectedTools suppresses tool-required rows. Denied rows have **no accepted mutation tool version, owner proof, exact effect preflight or completion/recovery probe**. Action column is historical/intended metadata only, never permission. Future enablement requires every appendix :181-183 contract field and production negative tests; preserve denial meanwhile. Fixed-path identities are path metadata, not ownership proof.

| Catalog ID | Inventory code | Action metadata | Mutation | Source |
|---|---|---|---|---|
| `deep.android.avds` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Android.swift:12` |
| `deep.android.cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+Android.swift:23` |
| `deep.android.ndk` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+Android.swift:49` |
| `deep.android.sdk-temp` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+Android.swift:59` |
| `deep.android.system-images` | legacy locator; async unavailable unless explicit discovery | `.deletePath` | Denied | `Catalog/CleanCatalog+Android.swift:32` |
| `deep.deps.bubblewrap` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:64` |
| `deep.deps.cocoapods-repos` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:71` |
| `deep.deps.dart-server` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:56` |
| `deep.deps.go-clean-modcache` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:82` |
| `deep.deps.gradle-caches-full` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:10` |
| `deep.deps.gradle-wrapper` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:20` |
| `deep.deps.maven-repository` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:39` |
| `deep.deps.npm-npx` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:30` |
| `deep.deps.pub-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:47` |
| `deep.flutter.sdk-cache` | named bounded async discovery | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:104` |
| `deep.git.reflog-expire-all` | legacy locator; async unavailable unless explicit discovery | `.custom(.gitReflogExpireAggressive)` | Denied | `Catalog/CleanCatalog+Git.swift:21` |
| `deep.memory.purge-inactive` | explicit action row; no ownership evidence | `.custom(.purgeInactiveMemory)` | Denied | `Catalog/CleanCatalog+Memory.swift:18` |
| `deep.memory.quit-approved-apps` | explicit action row; no ownership evidence | `.custom(.quitMemoryHog)` | Denied | `Catalog/CleanCatalog+Memory.swift:32` |
| `deep.memory.restart-for-swap` | explicit action row; no ownership evidence | `.custom(.restartToReclaimSwap)` | Denied | `Catalog/CleanCatalog+Memory.swift:48` |
| `deep.simulator.delete-approved` | named bounded async discovery | `.custom(.simulatorPrune)` | Denied | `Catalog/CleanCatalog+Xcode.swift:141` |
| `deep.simulator.erase-all` | legacy locator; async unavailable unless explicit discovery | `.unavailable` | Denied | `Catalog/CleanCatalog+Xcode.swift:132` |
| `deep.system.apfs-snapshots` | named bounded async discovery | `.custom(.apfsSnapshots)` | Denied | `Catalog/CleanCatalog+System.swift:8` |
| `deep.system.claude-code-vm` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+System.swift:27` |
| `deep.system.claude-vm-bundles` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+System.swift:18` |
| `deep.xcode.archives` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:122` |
| `normal.chrome.cookies` | legacy locator; async unavailable unless explicit discovery | `.custom(.chromeCookies)` | Denied | `Catalog/CleanCatalog+Browsers.swift:52` |
| `normal.chrome.http-cache` | legacy locator; async unavailable unless explicit discovery | `.deleteContents` | Denied | `Catalog/CleanCatalog+Browsers.swift:14` |
| `normal.chrome.profile-caches` | legacy locator; async unavailable unless explicit discovery | `.deletePath` | Denied | `Catalog/CleanCatalog+Browsers.swift:29` |
| `normal.extras.build-outputs` | named bounded async discovery | `.deletePath` | Denied | `Catalog/CleanCatalog+Extras.swift:18` |
| `normal.extras.old-transcripts` | legacy locator; async unavailable unless explicit discovery | `.deletePath` | Denied | `Catalog/CleanCatalog+Extras.swift:37` |
| `normal.extras.stale-node-modules` | named bounded async discovery | `.deletePath` | Denied | `Catalog/CleanCatalog+Extras.swift:27` |
| `normal.git.housekeeping` | legacy locator; async unavailable unless explicit discovery | `.custom(.gitRepoGC)` | Denied | `Catalog/CleanCatalog+Git.swift:8` |
| `normal.safari.cache` | legacy locator; async unavailable | `.deleteContents` | Denied | `Catalog/CleanCatalog+Browsers.swift:72` |
| `normal.safari.favicon-cache` | legacy locator; async unavailable | `.deletePath` | Denied | `Catalog/CleanCatalog+Browsers.swift:90` |
| `normal.safari.legacy-cache` | legacy locator; async unavailable | `.deleteContents` | Denied | `Catalog/CleanCatalog+Browsers.swift:82` |
| `normal.safari.touch-icons` | legacy locator; async unavailable | `.deletePath` | Denied | `Catalog/CleanCatalog+Browsers.swift:95` |
| `normal.safari.webkit-cache` | legacy locator; async unavailable | `.deleteContents` | Denied | `Catalog/CleanCatalog+Browsers.swift:77` |
| `normal.safari.webkit-global` | legacy locator; async unavailable | `.deleteContents` | Denied | `Catalog/CleanCatalog+Browsers.swift:86` |
| `normal.trash.empty` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Extras.swift:8` |
| `safe.cache.bun-install-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:103` |
| `safe.cache.claude-desktop-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:59` |
| `safe.cache.claude-desktop-code-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:66` |
| `safe.cache.claude-desktop-gpu-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:73` |
| `safe.cache.deno-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:12` |
| `safe.cache.electron-builder-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:19` |
| `safe.cache.electron-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:18` |
| `safe.cache.go-build-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:21` |
| `safe.cache.helpd` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:45` |
| `safe.cache.homebrew-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:14` |
| `safe.cache.itmstransporter-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:16` |
| `safe.cache.jetbrains-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:22` |
| `safe.cache.mcp-repos` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:111` |
| `safe.cache.node-gyp` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:11` |
| `safe.cache.npm-cacache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:80` |
| `safe.cache.perplexity` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:52` |
| `safe.cache.pip-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:10` |
| `safe.cache.playwright-mcp-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:13` |
| `safe.cache.puccinialin` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:8` |
| `safe.cache.puppeteer` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:96` |
| `safe.cache.swiftpm-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:9` |
| `safe.cache.swiftpm-clones` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:38` |
| `safe.cache.typescript-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:17` |
| `safe.cache.uv-dir` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:88` |
| `safe.cache.xcode-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:15` |
| `safe.cache.yarn-cache` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:20` |
| `safe.flutter.tool-state` | path metadata helper | `.deletePath` | Denied | `Catalog/CleanCatalog+DependencyCaches.swift:95` |
| `safe.gradle.build-cache` | legacy locator; async unavailable unless explicit discovery | `.deletePath` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:210` |
| `safe.gradle.daemon-logs` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:219` |
| `safe.logs.claude` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:120` |
| `safe.logs.content-delivery` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:126` |
| `safe.logs.core-simulator` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:121` |
| `safe.logs.creative-cloud` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:124` |
| `safe.logs.diagnostic-reports` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:123` |
| `safe.logs.google` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:122` |
| `safe.logs.ngl` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:125` |
| `safe.simulator.core-simulator-caches` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:74` |
| `safe.simulator.core-simulator-temp` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:83` |
| `safe.simulator.delete-unavailable` | legacy locator; async unavailable unless explicit discovery | `.runTool` | Denied | `Catalog/CleanCatalog+Xcode.swift:110` |
| `safe.simulator.playground-devices` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:92` |
| `safe.simulator.xctest-devices` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:101` |
| `safe.system.cloudkit-cache` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:239` |
| `safe.system.qlmanage-reset` | legacy locator; async unavailable unless explicit discovery | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:247` |
| `safe.system.quicklook-thumbnails` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:231` |
| `safe.tool.brew-autoremove` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:159` |
| `safe.tool.brew-cleanup` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:151` |
| `safe.tool.deno-clean` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:191` |
| `safe.tool.npm-cache-clean` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:143` |
| `safe.tool.pip3-cache-purge` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:199` |
| `safe.tool.pnpm-store-prune` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:183` |
| `safe.tool.pod-cache-clean` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:167` |
| `safe.tool.uv-cache-prune` | estimate metadata only | `.runTool` | Denied | `Catalog/CleanCatalog+SafeCaches.swift:175` |
| `safe.xcode.coding-assistant` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:62` |
| `safe.xcode.derived-data` | path metadata helper | `.deleteContents` | **Fail: accepted API**, UI unavailable | `Catalog/CleanCatalog+Xcode.swift:14` |
| `safe.xcode.documentation-cache` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:24` |
| `safe.xcode.ios-device-support` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:33` |
| `safe.xcode.products` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:53` |
| `safe.xcode.watchos-device-support` | path metadata helper | `.deleteContents` | Denied | `Catalog/CleanCatalog+Xcode.swift:43` |

Total source-expanded catalog rows: **97**. Verify count against coordinator runtime inventory if generated.

## Coordinator-executed regression evidence

On 2026-09-17 the coordinating auditor reported execution of the seven tests in `tracks/SafetyAuditRegressionTests.swift` in an isolated package fixture: **7 tests failed with 10 expected regression issues; all outside witnesses survived**. The ninth sequential run returned `storageUnavailable`. This upgrades SAF-01/02/04 and missing-proof deletion in SAF-03 from source-only to **production integration failure**. It does not establish current shipped-UI reachability, a concurrent last-syscall race, real host activity loss, crash recovery behavior or physical resource bounds. The authoritative command, exit status, timestamp, isolated package path and log belong in the coordinator's evidence manifest. No source implementation changed during these probes.

Observed regression mapping:

| Regression | Required observation | Reported observation | Finding |
|---|---|---|---|
| postConfirmationChildSurvives | New child retained | Assertion failed after accepted delete; outside witness retained | SAF-01 |
| postConfirmationGrowthSurvives | Grown leaf retained | Assertion failed; outside witness retained | SAF-01 |
| replacedRootSurvives | Replacement root child retained | Assertion failed; moved original/outside witnesses retained | SAF-01 |
| protectedDescendantSurvives | Protected child retained | Assertion failed; outside witness retained | SAF-02 |
| missingOwnershipEvidenceWithholdsEffect | Unknown-owner payload retained | Assertion failed; outside witness retained | SAF-03 |
| realEffectIsDurablyRecorded | started, itemTerminal, finished recorded | Three missing-phase assertions failed | SAF-04 |
| nineSequentialRunsDoNotExhaustActiveSlots | Ninth run completes successfully | storageUnavailable; success assertion failed | SAF-04 |
