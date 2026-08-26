# Headroom: Settings Registry and Adapter Contracts

Binding appendix to [the product design](2026-08-26-developer-headroom-design.md).
Date: 2026-08-26. Added after adversarial review. No implementation claims.

## 1. Registry semantics

Each entry has `id, valueType, defaultValue, allowedValues, resolutionClass, authorityEffect, presentationGroup`. UI labels are localized separately; stable IDs never change with renaming.

- **P (preference):** highest explicit global → profile → project → run value replaces the default. An absent override contributes no restriction.
- **R (restriction):** explicit disabled flags, exclusions and user hard limits combine restrictively. Built-in enabled/no-user-hard-limit does not veto a later preference.
- **A (authority):** local authorization ledger only, never imported or inherited from profile/run overrides.
- **H (hard constraint):** not editable; limits all preferences including Custom mode.

Authority effect: **none**, **invalidate** (increments policy revision; invalidates open plans), or **consent** (separate local acknowledgement/OS permission). Presentation changes alone do not invalidate plans.

All MiB/GiB use powers of 1024 and checked Int64 arithmetic. `null` means unset/unavailable, never zero. Integer ranges inclusive. Import limits: ≤1 MiB, nesting ≤16, ≤50 profiles, ≤1,000 entries/list, ≤4,096 characters/string; reject overflow/duplicate keys/invalid UTF-8. Unknown keys remain inert; no unknown key may gain authority.

## 2. Complete user-visible registry

Families expand to individual entries. Listed enum members are exhaustive; new members require defaults/migration tests. Sizes use binary values internally even if displayed in decimal units.

| Stable ID | Type/default | Range/behavior | Class / effect |
|---|---|---|---|
| `feature.{headroom,buildPrep,projects,rescue,ecosystems,budgets,history}` | Bool / true | On-demand availability | R / invalidate |
| `feature.maintenance` | Bool / false | Enabling capability grants no rule authority | R / invalidate |
| `ecosystem.{apple,android,node,languages,homebrew,docker,ides,models,git,data}.inventory` | Bool / true | On-demand only | R / invalidate |
| `ecosystem.{same IDs}.manualActions` | Bool / false for new adapters | Legacy effects quarantined until accepted; explicit local enable afterward | R / invalidate |
| `item.<catalogID>.enabled` | Bool / true | Only accepted catalog IDs; cannot override quarantine | R / invalidate |
| `scope.projectRoots` | URL identity list / [] | Approved local dirs; no provider/network/system roots | A / consent |
| `scope.externalVolumes` | volume UUID list / [] | Exact local volumes; never path-only matching | A / consent |
| `scope.excludedRoots` | canonical URL list / [] | Union with mandatory exclusions | R / invalidate |
| `scope.pinnedProjects` | project ID set / [] | Imports cannot unpin | R / invalidate |
| `scope.currentProject` | project ID? / null | Explicit selection until cleared | P / invalidate |
| `browsers.keepCookieDomains` | domain list / [] | Validated exact domains; keep protection, never executable text | R / invalidate |
| `simulators.approvedDeletionUDIDs` | UUID list / [] | Local device association; each deletion still needs fresh review | A / consent |
| `tools.approvedExecutables` | executable identity list / [] | Canonical file/signature identity; path strings alone never authorize | A / consent |
| `docker.approvedEndpoints` | local socket identity list / [] | No TCP/SSH/remote endpoints | A / consent |
| `cleanup.inactiveDays` | Int / 60 | 7...365 | P / invalidate |
| `cleanup.transcriptDays` | Int / 45 | 7...365; memory directories always protected | P / invalidate |
| `cleanup.recentProtectionDays` | Int / 7 | 1...90; running/pinned always protected | P / invalidate |
| `cleanup.warmProjectCount` | Int / 5 | 0...50 | P / invalidate |
| `cleanup.minimumCandidateMiB` | Int / 100 | 1...102400 | P / invalidate |
| `cleanup.minimumItemMiB` | Int / 1 | 0...102400; unknown bytes never become eligible zero | P / invalidate |
| `cleanup.retainRecentArtifacts` | Int / 2 | 0...100 per mapped inactive project; not archives/models/databases | P / invalidate |
| `cleanup.costCeiling` | enum / low | low,medium,high; cannot relax protection | P / invalidate |
| `cleanup.requestedBatchGiB` | Int / 10 | 1...100 | P / invalidate |
| `cleanup.requestedBatchItems` | Int / 20 | 1...100 | P / invalidate |
| `cleanup.hardBatchGiB` | Int? / null | 1...100 when explicitly set | R / invalidate |
| `cleanup.hardBatchItems` | Int? / null | 1...100 when explicitly set | R / invalidate |
| `cleanup.manualInactiveAcknowledgementMinutes` | Int / 10 | 1...30; no unattended eligibility | P / invalidate |
| `scan.preset` | enum / eco | eco,balanced,custom | P / invalidate |
| `scan.requestedWorkers` | Int / 1 | 1...4; ≤logicalCPUCount and pressure ceiling | P / invalidate |
| `scan.readOnlyProcesses` | Int / 1 | 1...2; aggregate ≤2 command jobs including mutation | P / invalidate |
| `scan.defaultScope` | enum / quick | quick,selectedProjects; full-home is one-run request only | P / invalidate |
| `scan.sliceSeconds` | Int / 300 | 30...1800 | P / invalidate |
| `scan.uiBatchesPerSecond` | Int / 4 | 1...4 | P / none |
| `scan.onLowPower` | enum / pauseDiscretionary | pauseAll,pauseDiscretionary; ≤1 worker | R / invalidate |
| `scan.onSeriousThermal` | enum / pauseDiscretionary | pauseAll,pauseDiscretionary; ≤1 worker | R / invalidate |
| `scan.resumeAfterCriticalSeconds` | Int / 120 | 120...900 | P / invalidate |
| `scan.cacheEnabled` | Bool / true | App-owned cache, not background scan consent | P / invalidate |
| `scan.cacheMiB` | Int / 64 | 8...128 including WAL/temp files | P / invalidate |
| `scan.cacheExpiryHours` | Int / 24 | 1...48 | P / invalidate |
| `monitor.backgroundEnabled` | Bool / false | Monitoring, not cleanup | A / consent |
| `monitor.visibleIntervalSeconds` | Int / 5 | 2...60 | P / none |
| `monitor.hiddenIntervalSeconds` | Int / 60 | 60...900; ignored when background disabled | P / none |
| `monitor.rawHistoryEnabled` | Bool / false | Local bounded snapshots | P / none |
| `monitor.rawHistoryHours` | Int / 24 | 1...24; hard cap 5 MiB | P / none |
| `headroom.targetGiB` | Int? / null | null=min(20 GiB,10% capacity); explicit 1...min(1024,50% capacity) | P / invalidate |
| `headroom.warningGiB` | Int? / null | null=target; explicit ≥1, below clear | P / invalidate |
| `headroom.clearGiB` | Int? / null | null=warning+min(2 GiB,2% capacity); ≤capacity | P / invalidate |
| `headroom.volumeOverrides.<volumeID>` | record? / absent | target/warning/clear each inherit,automatic,fixedGiB(Int); selected-volume bounds as above | P / invalidate |
| `rescue.approvedApplications` | verified bundle identity list / [] | Per-instance revalidation; no PID/name-only consent | A / consent |
| `rescue.showAdvancedMemoryActions` | Bool / false | Separate purge/restart confirmation; never automation | P / invalidate |
| `rescue.quitTimeoutSeconds` | Int / 15 | 5...60; never force-quits | P / invalidate |
| `budget.<budgetID>.enabled` | Bool / false | All templates disabled; bound to approved volume identity | R / invalidate |
| `budget.<budgetID>.highGiB` | Int? / template below | 1...min(1024,50% volume capacity) | P / invalidate |
| `budget.<budgetID>.lowGiB` | Int? / 80% of high | ≥0 and <high in checked integer bytes | P / invalidate |
| `notifications.enabled` | Bool / false | OS consent required | A / consent |
| `notifications.pressureSustainSeconds` | Int / 60 | 30...600 | P / none |
| `notifications.recoverySeconds` | Int / 120 | 60...900 | P / none |
| `notifications.cooldownMinutes` | Int / 60 | 15...1440 | P / none |
| `notifications.quietHoursEnabled` | Bool / false | Local civil time, DST-aware | P / none |
| `notifications.quietStart` | HH:mm / 22:00 | 00:00...23:59 | P / none |
| `notifications.quietEnd` | HH:mm / 08:00 | Distinct from start; wraps midnight | P / none |
| `maintenance.mode` | enum / off | off,notifyOnly,authorizedCaches | A / consent |
| `maintenance.maxGiB` | Int / 1 | 1...5 plus explicit user hard cap | A / consent |
| `maintenance.maxItems` | Int / 5 | 1...20 | A / consent |
| `maintenance.deadlineSeconds` | Int / 60 | 30...120; scheduling deadline, not forced stop | A / consent |
| `maintenance.minimumAgeDays` | Int / 30 | 30...365 | A / consent |
| `maintenance.minimumIntervalHours` | Int / 24 | 24...168 | A / consent |
| `app.launchAtLogin` | Bool / false | macOS registration/consent separate | A / consent |
| `history.enabled` | Bool / true | Unfinished-effect ledger remains mandatory | P / none |
| `history.retentionDays` | Int / 30 | 1...90; never evict unfinished effects | P / none |
| `history.maxMiB` | Int / 10 | 1...50; reserve 1 MiB for unfinished ledger | P / none |
| `ui.density` | enum / compact | compact,detailed | P / none |
| `ui.units` | enum / binary | binary,decimal; correct GiB/GB label | P / none |
| `ui.cards` | ordered IDs / [disk,memoryPressure,swap,thermal,power] | Permutation/subset; unavailable visible card retains status | P / none |
| `ui.ecosystemOrder` | ordered IDs / registry order | Permutation of inventory ecosystem IDs; never eligibility/ranking | P / none |
| `monitor.suppressHiddenSampling` | Bool / false | Restricts separately authorized background monitoring | R / none |
| `ui.showBadges` | Bool / true | No fabricated health score | P / none |
| `ui.advancedSettings` | Bool / false | Search still finds advanced controls | P / none |
| `export.redactDiagnostics` | Bool / true | False still excludes credentials/cookies/env/argv/remotes | P / none |

Minimum sizes/ages/retention may be overridden per accepted item with the same validation. Unknown item keys never create capabilities. Non-applicable fields display “not applicable.” Existing cookie keep-domains remain an empty preference list; simulator-delete approvals remain empty local UDID authority, old name approvals are preserved inert pending device reassociation. Old restart enablement migrates into visibility only, not consent.

Budget IDs: apple-derived-data, apple-simulators, android, docker, package-caches, models, ides, git, data, other. Templates: apple-derived-data 15 GiB, apple-simulators 25 GiB, docker 30 GiB, package-caches 10 GiB, models 50 GiB. Other budgets null/disabled. Invalid templates for a small selected volume remain disabled and request a smaller value; never silently clamp consent.

Per-item overrides use `item.<catalogID>.{inactiveDays,minimumItemMiB,retainRecentArtifacts}` with null/inherit defaults and the respective ranges above. Only cleanup/scope/headroom preferences may use project/run layers; UI, persistence, notification delivery and scanner-wide settings are global/profile only. Authority fields are machine-local only. Unsupported layer/key combinations are validation errors, not silently ignored.

Volume override IDs resolve only against the locally approved volume ledger; imports keep unmatched IDs inert. For the selected volume, resolve each global/profile/project/run layer in order: apply that layer's generic headroom field, then its matching volume override. Inherit leaves the lower value unchanged; automatic selects the volume-derived formula; fixedGiB selects a validated value. Then apply hard restrictions. No entry ever authorizes mounting or accessing a volume. Missing capacity makes automatic targets unavailable, not zero.

### Background execution modes

“Hidden idle” means no explicit scan, authorized maintenance, in-flight effect or bounded recovery probe. Background signal monitoring and maintenance are separate authorities.

| Mode while UI hidden | Permitted work |
|---|---|
| Idle; monitoring off; maintenance off | Zero repeating timers, subprocesses, filesystem streams or scan/index I/O |
| Explicit user scan still running | Only that scan, within its slice and scheduler budget; closing the window does not silently cancel it; menu offers Cancel |
| Background monitoring authorized | Bounded signals at configured interval, no process inventory/filesystem walks |
| Maintenance separately authorized | Only consented rule schedule and proven eligible effects; no generic scan/monitor authority; initial empty allowlist means no mutation |
| In-flight mutation draining | Finish/reconcile current effect within adapter boundaries; never start unrelated work |
| Unfinished effect after relaunch | One bounded reconciliation at launch or explicit Retry; no polling loop, no mutation until positive quiescence |

When UI is visible, only requested screens sample signals at the visible interval; opening the popover grants no scan, maintenance or mutation authority. A confirmed mutation may continue after its window closes; show menu progress/cancel, and drain safely on app quit or retain the uncertain ledger on abrupt termination.

At idle with monitoring off, close filesystem event streams. Maintenance scheduling, when separately authorized, does not authorize an idle filesystem event stream. On the next explicit/authorized scan, establish a fresh stream and catch up from its persisted cursor before treating any cached scope as fresh. Missing history invalidates the scope. Numeric idle performance gates apply to the first row; other rows must be measured and labelled separately.

Hard constraints: protected paths; one mutator; quarantine; no internet/arbitrary scripts; critical-pressure pause; ≤4 walk workers; ≤2 concurrent Tidy-launched command jobs TOTAL, including mutation; manual ≤100 GiB/100 items; automatic ≤5 GiB/20 items; credential exclusions; strict resource identities; import/profile/buffer bounds.

The scheduler grants one shared process permit to each launched command job. A mutating CLI occupies one of the two permits for its full lifetime, so at most one read-only command may coexist; if two readers already run, the mutator waits. No nested permit deadlock: adapters declare subprocess needs before dispatch. Descendant behavior needs its own bounded adapter contract; this is a command-job ceiling, not a claim to cap all OS processes or a daemon's internal workers.

## 3. Exact factory profile overrides

Policy overrides only: omitted keys inherit. Profiles may replace P preferences and add stricter R restrictions; they never grant A authority, change H constraints, enable maintenance/rescue, approve roots or remove inherited restrictions. Battery's pauseAll and suppressHiddenSampling=true are explicit additional R restrictions, not preferences that can weaken global protection.

| Profile ID | Target | Performance | Other overrides |
|---|---|---|---|
| `xcode` | 15 GiB | Eco 1 worker/1 process | cost low, 5 warm projects, apple first |
| `android` | 20 GiB | Eco 1/1 | cost low, 5 warm, android first |
| `flutter` | 20 GiB | Eco 1/1 | cost low, 5 warm, android then apple |
| `web` | 5 GiB | Eco 1/1 | cost low, 5 warm, node first |
| `localAI` | 30 GiB | Eco 1/1 | models first but read-only; no model process control |
| `battery` | Inherit | Eco 1/1 | pause all scans in LPM; no hidden polling; quick scope |

Ecosystem order is presentation only, never eligibility/ranking override. Invalid target for the selected volume makes readiness unavailable until corrected. Eco=1/1; Balanced=2/2; Custom=explicit stored counts. Preset changes preview expanded values; retained Custom values are not silently discarded. Stored profile identities are UUIDs; factory IDs above are stable template keys.

## 4. Activity/ownership proof contract

An evidence record contains adapter ID/version, resource identity, recognized producer identities, evidence kind, observedAt, validity deadline, completeness, shared-owner set and revalidation method.

- Runtime evidence expires in 5 seconds and is reacquired immediately before mutation.
- Association/manifests expire after 24 hours or file/policy change.
- Historical inactivity defaults to 60 days but only ranks resources after ownership/runtime checks.
- `inactiveConfirmed` requires complete producer mapping and positive quiescence evidence for all owners, not absence of an observed process.
- Manual association + “inactive for this run” acknowledgement expires after 10 minutes by default. It may permit separately warned manual actions, never recommended/automatic actions or overriding running/pinned/mandatory protections.
- Unknown producer, denied access, incomplete enumeration, unsupported version, shared-owner uncertainty or pending invalidation means blocked/unknown.

| Resource | Required ownership/positive evidence | Shared/unknown treatment | Eligibility |
|---|---|---|---|
| App-owned cache/log | Documented versioned path, verified bundle, complete owner-instance check and adapter closed-state evidence | Unknown helpers block recommendation | Manual after fresh proof; unattended only with immutable object/lease proof |
| Mapped build output | Project metadata, recognized producers, pin/recency checks, complete supported build-session evidence | Universal IDE association is unavailable | Recommend only with proof; else explicit manual acknowledgement |
| Simulator | UDID/runtime and supported simctl state | Names never identify targets | Manually reviewed shutdown/delete, immediate recheck |
| Emulator | AVD identity + stable instance token via supported local interface | Missing token means read-only | Manual shutdown only |
| Package/global cache | Tool object/reference index, all consumer ownership, quiescence lease | Shared active or incomplete owner map blocks | Manual exact objects; no generic prune; initial unattended list empty |
| Docker | Pinned local endpoint, object ID/current references/state, stopped-container data warning | Pending jobs or unknown references block | Explicit manual only, no force |
| Git | Common dir/worktrees known, no operation/lock, hooks/config controlled | Unknown lock/common dir blocks | Local housekeeping only after acceptance |
| Models/environments/DB/VM | Bounded local metadata | Unknown stays unknown | Inventory/reveal only |

Positive fixture: a supported test adapter recognizes an immutable completed cache object, holds its producer-provided exclusion lease, has fresh complete owners and no pins/exclusions/recency; it becomes eligible. Negative pair: same bytes/age but one shared owner unobserved; recommendation and maintenance remain blocked.

A generic process scan cannot establish the positive proof. If no producer-supported proof exists, keep manual-with-acknowledgement or inventory-only; do not weaken evidence to populate recommendations.

## 5. Independent adapter work units

Split T15–T20 into `.I` inventory and `.M` mutation acceptance PER adapter file. Inventory can ship alone. Read-only .M units are engine denial tests, not deletion implementations.

Every .I produces `InventoryRecord(id, adapterID, ownerIDs, scopeID, kind, capability, allocatedBytes?, confidence, activity, observedAt, reason)`. Every .M consumes it and defines `EffectSpec(resourceIDs, descendantManifestDigest?, exactArgv?, endpointIdentity?, preflight, completionProbe)`. Resource text never supplies executable commands.

Before a .M: record supported parser/tool version, exact argv with typed identity slots, side-effect scope, network/hooks/plugins controls, ownership proof, denial conditions and quiescence/recovery probe. Undefined safe scope means inventoryOnly, not a guessed command.

| Unit | Concrete minimum fixture | Expected record/effect |
|---|---|---|
| Apple.I | simctl JSON `{"devices":{"runtime.fixture":[{"udid":"11111111-1111-1111-1111-111111111111","name":"Fixture","state":"Shutdown","isAvailable":true}]}}` | One exact device identity |
| Apple.M | Same UDID becomes Booted before delete | Block delete; shutdown argv `["simctl","shutdown",UDID]`; delete argv `["simctl","delete",UDID]`; never all/unavailable |
| Android.I | AVD ini + project manifest; runtime token missing | Unknown-state device/resource rows |
| Android.M | Unsupported emulator identity protocol | Deny; no guessed adb/kill; supported identity + completion fixture required to enable |
| Node.I | package.json/lockfile + edited node_modules file + inactive output | Dependency manual-risk distinct from output |
| Node.M | Reviewed output manifest gets a new child | Approved unchanged leaves only; no unattended node_modules |
| Languages.I | Cargo target, pyvenv.cfg, Conda metadata, Gemfile.lock, go.mod as separate roots | Separate typed records; venv/Conda read-only; no scripts |
| Languages.M | Shared symlinked target/cache; missing owner | Block; proven file manifests only |
| Homebrew.I | Cache files + unsupported installed version | Cache report, mutation quarantined |
| Homebrew.M | Broad cleanup without exact effects | Deny; no brew cleanup fallback |
| Docker.I | Approved `unix:///fixture/docker.sock` vs `ssh://fixture` | Only pinned local endpoint queried; remote zero calls |
| Docker.M | 64-hex image ID acquires reference; stopped container has writable data | Image argv `["--host",endpoint,"image","rm",imageID]`; container argv `["--host",endpoint,"container","rm",containerID]` only separate consent; no force/volume/prune |
| IDE.I | Cache, workspaceStorage, extensions | Only documented Cache potentially disposable |
| IDE.M | Owner starts after review | Skip; no newly discovered directory target |
| Models.I | Two aliases share blob | Non-additive bytes, no mutation capability |
| Models.M | Forged generic delete against model ID | Coordinator denies; zero effects |
| Data.I | PostgreSQL markers and VM disk | Read-only data rows |
| Data.M | Forged generic delete against data ID | Coordinator denies; zero effects |
| Git.I | Worktree file, external common dir, live index.lock | Shared/unknown blocks; no lock removal |
| Git.M | Broad prune/gc with uncontrolled hooks/common-dir effects | Quarantine until local exact contract; never remote prune/forced lock removal |

CLIs require both exact argv and version-specific completion evidence. Host integration tests use explicitly provisioned disposable resources; no ambient home/daemon defaults.

## 6. Production-bound testing and implementation-entry gate

The program plan's small policy snippets illustrate contracts; they cannot satisfy a task's RED/GREEN gate by themselves. Tests must call production parser/import/planner/coordinator/adapter entry points and observe a recording effect boundary.

Test support owns scratch homes, fixture clocks, controllable probes and recording tool/filesystem clients. It contains NO alternate ranker, resolver, parser, capability policy or eligibility implementation. Production constructors accept these narrow dependencies.

Mandatory end-to-end tests:

1. Deserialize an import requesting authorized maintenance/model deletion; commit inert preview. Persisted authorization bytes unchanged, coordinator denies execution, zero executor calls.
2. Discover edited node_modules through the real NodeDeveloperAdapter; real ranker excludes it from Build Prep and coordinator denies standing authorization.
3. Discover shared model blob through LocalModelAdapter; forged generic delete rejected by capability registry even without UI.
4. Runtime evidence expires/changes after review; real preflight skips effect. Unrelated safe selection proceeds only if run is not globally uncertain.
5. Child/daemon survives simulated app death; relaunched coordinator reads uncertainAndPossiblyRunning and rejects every mutation until positive quiescence proof.

Before implementing each work unit, produce a narrow task card with concrete production signatures, fixture inputs/outputs and complete failing test code. The card is reviewed independently. No tautological assertion, illustrative-only interface or unsupported mutation contract passes. This is a deliberate program-to-task gate: the 24 work packages are NOT claimed to be copy-paste-complete implementation scripts for the entire product.
