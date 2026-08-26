# Tidy: Developer Headroom and Customization

Date: 2026-08-26
Status: Product contract for planning; not an implementation or release claim.
Baseline: `db4707f`, tag `v1.5.0`.

## 1. Product promise

Help developers on constrained Macs recover enough disk and workload headroom for their next task, while preserving useful caches, active projects, and local data.

Disk capacity and RAM/swap pressure are equal priorities. This is an explicit planning assumption following the user's approval of the combined direction. Tidy cannot guarantee build success, prevent all system contention, or manufacture physical RAM.

Full customizability means every supported policy has a visible, validated, persistable setting with reasonable defaults. It does not mean arbitrary commands, arbitrary deletion roots, weakened containment, hidden actions, or permission bypasses.

## 2. Approved scope and boundaries

- Native Swift/SwiftUI, macOS 14+, local TidyCore package, zero third-party runtime dependencies.
- Intel x86_64 and Apple Silicon arm64 supported; both require build and device evidence.
- No internet requests, telemetry, remote updates, repository fetches, model downloads, or remote package dependencies at runtime.
- Local IPC to an explicitly identified local tool service is allowed. No remote Docker contexts, TCP endpoints, SSH endpoints, or daemon auto-start during discovery.
- No repository deletion, database deletion, Docker volume deletion, local-model deletion, generic duplicate-file deletion, arbitrary scripts, or automatic force-quitting.
- No kernel tuning, swap-file manipulation, launch-agent disabling, privileged persistent helper, or changes to other tools' settings.
- No full-home scans on popover open or timers. No repository-supplied executable/config evaluation merely to discover a project.
- No change to signing, publishing, deployment, or remote Git state is authorized by this document.

Comprehensive coverage means inventory, ownership, consequences, supported actions, and honest read-only boundaries—not deletion support for every object.

## 3. Non-negotiable safety contract

S01. Every operation that can execute must appear in the confirmation review, including targetless commands and zero-byte memory actions.
S02. The executor accepts a sealed, current, confirmed selection, not a raw CleanPlan. Adding an item or expanding its targets requires new review.
S03. Only the selected canonical targets/identities and reviewed descendant batches may execute. Directory identity alone does not authorize future children or growth. No fresh wildcard discovery, snapshot relisting, `erase all`, or broad prune behind a narrow review.
S04. A single app-owned execution coordinator serializes all destructive runs across every window and engine instance. Persistent run state detects unfinished prior runs.
S05. Recheck current policy revision, resource identity, ownership, active-state evidence, protected descendants, and permissions immediately before each operation.
S06. Protect canonical system/iCloud/file-provider paths and their ancestors. Deleting a parent must not bypass a protected descendant. Do not follow symlinks or cross mount boundaries during deletion.
S07. Race-resistant file operations use anchored directory descriptors, no-follow traversal, and identity checks. If safe execution cannot be established, skip and explain. No claim of perfect atomicity over arbitrary concurrent filesystems.
S08. User exclusions may only narrow scope; they cannot remove mandatory protections. All import/export/profile/reset paths preserve this rule.
S09. Running or unknown-state resources are never recommended or unattended. For active project build artifacts, unknown ownership blocks deletion. Manual exceptions require explicit per-run acknowledgement only where the adapter contract permits them; mandatory protection remains absolute.
S10. Cache eligibility requires regeneratability evidence. A lockfile alone does not prove a dependency directory contains no user modifications.
S11. Failures, partial work, cancellations, skipped items, unavailable measurements, and uncertain outcomes are distinct states. Never invent zero or success.
S12. Cancellation stops scheduling immediately; do not force-kill an in-flight mutating tool. Wait for a bounded adapter-specific safe boundary, or record uncertain outcome and prohibit automatic retry.
S13. Only Tidy-owned read-only subprocesses may be terminated on timeout/cancel. Never signal user workload processes as an implementation detail of cleanup.
S14. The authorization/confirmation UI remains mandatory for manual cleanup. Opted-in automation has its own persisted, narrow standing authorization; it cannot silently promote a manual item to unattended.

S15. Before any Stage A release, quarantine EVERY legacy effect without an accepted local-only, exact-scope, ownership, preflight and interruption contract. This includes broad package-manager commands and Git remote prune/immediate gc/worktree prune/index.lock removal, not only simulator erase-all. The capability registry is enforced by the coordinator; UI visibility, old presets and custom executor registration cannot bypass it.

S16. A timed-out/crashed run with potentially surviving child or daemon work enters `uncertainAndPossiblyRunning`. Persist child process start/boot/executable identity and adapter operation ID before submission. All new mutations stay blocked across relaunch until adapter-specific reconciliation proves quiescence. Fresh review, Tidy PID death, or disappearance of its file lock is insufficient. Unsupported reconciliation keeps that adapter unavailable.

### Recursive scope and resource limits

The authorization unit is an exact resource identity plus a reviewed descendant manifest for recursive filesystem work. A manifest binds volume, parent chain, inode/generation where supported, type, size and modification metadata. It is stored on disk in bounded batches (≤5,000 nodes and ≤8 MiB per batch). Larger trees require multiple reviewed batches; scan caps remain independent. No follow-up batch is silently added.

New descendants are left untouched; replaced/grown/changed entries are skipped; parent directories are removed only when they were reviewed and are empty after approved descendants complete. A directory with a new child is retained. No re-enumeration may expand authority.

Manual byte caps constrain reviewed allocated estimates and scheduling; they are NOT a guarantee of physical space freed or an atomic bound on a concurrently changing filesystem. Recheck metadata and remaining budget before each leaf effect. An exact hard effect bound requires adapter-proven immutability/quiescence held through the effect; without that proof, unattended execution is forbidden.

Time caps are monotonic scheduling deadlines. They stop dispatch at the next per-file/per-item safe boundary, never force-stop a mutating syscall or user workload. Record deadline overruns and uncertain state truthfully. A single uninterruptible syscall may exceed the deadline. This limitation must appear beside the setting, not only in technical documentation.

Remove broad simulator erase-all from executable catalog scope. Replace it with individual device actions only after per-device inventory/confirmation. Preserve old preset IDs as disabled entries with an explanation.

## 4. Customization model

### 4.1 Settings surfaces

- Features: Headroom, Build Prep, Project Inventory, Rescue, Ecosystems, Budgets, Notifications, History.
- Scope: approved roots, category/item enables, pinned projects, user exclusions, allowed local volumes.
- Cleanup policy: ages, minimum sizes, retention counts, regeneration-cost ceiling, per-run byte/item caps.
- Resource use: preset, scan workers, subprocess limit, scan scope/time limit, thermal/battery rules.
- Headroom: target per volume, warning/clear thresholds, profile-specific overrides.
- Experience: compact/detail mode, visible cards, ordering, units, refresh interval, badges, quiet hours.
- Data: bounded history/cache retention, local export/import, selective reset, clear local history/index.
- Automation: off, notify-only, or narrowly authorized cache maintenance; separate consent for each rule.

Every control displays its default, effective value, source, range, and consequence. Advanced settings are searchable. Simple users see presets and relevant controls; advanced users see all supported knobs. No unsupported/free-form command text field.

### 4.2 Precedence and conflict rules

For non-safety preferences: built-in default → saved global → explicitly activated session profile → project override → one-run override.

One-run overrides expire after the run. Profiles never activate based on mere app detection. The effective configuration is an immutable revisioned snapshot used by planning.

For safety restrictions: mandatory constraints intersect with every enabled explicit restriction. Exclusions union; immutable ceilings and explicit user hard limits take the strictest applicable limit. Ordinary built-in defaults do not remain permanent restrictions after override. For example, the 10 GiB default manual batch can be raised to 40 GiB; a separately configured 8 GiB global hard limit still caps that request at 8 GiB, and the immutable 100 GiB product ceiling always applies. A child layer cannot re-enable a disabled capability or relax an explicit protection inherited from another layer. Editing the owning layer is required to remove its user restriction.

Settings can change while a plan is open. Any execution-policy revision change invalidates confirmation, including policy resets and feature disables. Presentation-only edits use a separate preferences revision and do not invalidate a plan. Disabling a feature cancels its pending work; active mutating work drains safely before the feature is fully off.

Stable IDs are used for projects, profiles, categories, resources, and volumes. Names and PIDs are display data, never authorization identities.

### 4.3 Reasonable defaults

All numeric values below are initial product defaults/benchmarks, not assertions about universal Mac requirements. Use binary GiB/MiB internally and label consistently.

| Setting | Default | Allowed customization / immutable constraint |
|---|---|---|
| Master features | On-demand features available | Disable each independently; disabling never deletes user data |
| Monitoring | While UI visible only | Opt in to background signals; no background filesystem walk |
| Visible stats sampling | 5 seconds | 2–60 seconds; events preferred |
| Hidden stats sampling | None | Opt-in 60–900 seconds; no process inventory every tick |
| Pressure notification | Off | Warning persists 60 seconds; recovery 120 seconds; cooldown 60 minutes |
| Quiet hours | Off until configured | Local-time range, wrap midnight; suppress notifications, not safety |
| Login launch | Off | Explicit macOS login-item consent; denied is a supported state |
| Default quick scope | Approved catalog roots | Full-home scan requires a separate explicit request |
| Project roots | Empty | User-selected local folders; reject cloud/provider/network roots |
| External-volume scan | Off | Explicit volume UUID approval; no automatic remount matching by path |
| Performance preset | Eco | Balanced and Custom; safety pressure ceilings still apply |
| Concurrent walks | 1 | 1–4, also capped by CPU/pressure policy |
| Read-only subprocesses | 1 | 1–2; aggregate ≤2 concurrent Tidy-launched command jobs including the single mutator |
| Scan slice | 5 minutes | 30 seconds–30 minutes, then partial result with manual Continue |
| Enumeration UI batches | At most 4/second | 1–4/second; bounded queues |
| Serious thermal/LPM | One worker; no discretionary scans | More restrictive user choice allowed |
| Critical thermal/memory pressure | Pause scans | No override; resume after 120 seconds below critical |
| Disk target | min(20 GiB, 10% of volume capacity) | 1 GiB up to lesser of 1 TiB or 50% capacity; no success promise |
| Disk warning/clear | Below target / above target + min(2 GiB, 2% capacity) | Validated warning < clear ≤ volume capacity |
| Project inactivity | 60 days | 7–365 days; absence of reliable activity remains unknown |
| Transcript age | 45 days | 7–365 days; preserve memory directories |
| Active-project recency protection | 7 days | 1–90 days; running/pinned protection cannot be disabled |
| Warm-project count | 5 | 0–50; ties use stable ID |
| Default cost ceiling | Low | Low/medium/high; destructive resources still manual-only |
| Normal manual batch | 10 GiB or 20 items, whichever first | 1–100 GiB, 1–100 items; oversized indivisible action requires separate review |
| Rescue | All actions unselected | Per-instance manual selection, exact identities, graceful only |
| Memory purge/restart | Not recommended; separate advanced actions | Off by default, separate per-run confirmation; never Build Prep or automation |
| Budgets | Suggested, disabled | Per supported ecosystem/volume; high > low ≥ 0 |
| Budget suggestions | DerivedData 15 GiB; simulators 25; Docker 30; package caches 10; models 50 | Inactive templates, not automatic allocations or cleanup rules |
| Automation | Off | Notify-only first; cache maintenance requires rule-specific consent |
| Automated run limits | 1 GiB, 5 items, 60 seconds, once/day | May lower; may raise only to 5 GiB, 20 items, 120 seconds |
| Automated age floor | 30 days | 30–365 days, closed allowlist only |
| Scan cache | 64 MiB, aggregate entries, 24-hour expiry | Disable or 8–128 MiB; expiry 1–48 hours |
| Raw signal history | Off | Optional 24 hours, at most 5 MiB; no process argv |
| Run history | 30 days, 10 MiB | 1–90 days, 1–50 MiB; effective limit is smaller |
| Diagnostic export | Redacted, explicit | Home aliases, opaque project IDs; no credentials, cookies, env, argv, remotes |
| Settings import | Preview, inert | Schema/version checks, no authority transfer or automatic execution |

The permission/authorization ledger is separate from portable preferences. Imports cannot enable automation, grant quit rights, approve executable paths, approve volumes, register login items, or unpin mandatory protection. Paths are not portable defaults; imported roots need local resolution/confirmation. No machine-specific path/domain/name ships.

The complete stable-key registry, exact factory profile overrides, activity evidence matrix and adapter inventory/mutation split are binding in [Policy and adapter contracts](2026-08-26-headroom-policy-and-adapter-contracts.md). That appendix resolves values not expanded in the summary table.

### 4.4 Persistence and migration

One actor owns reads/writes, revision numbers, schema migration and import preview. App windows consume the same store, not independently loaded stale copies.

Migrate both historical schema-1 shapes (before and after memory fields) without losing valid fields. Missing optional values receive conservative defaults. Unknown future schema opens in read-only recovery; preserve original bytes. Corrupt files are preserved with an actionable error, not silently overwritten. Atomic writes with an owner-only backup; explicit rollback supported. Old run records lacking new measurement fields remain readable as unavailable, not zero.

## 5. User workflows

### Headroom

Show per-volume available space, separately labelled important-usage/purgeable estimates, memory pressure, swap use/change, thermal state and low power status. Unsupported or denied signals display unavailable. No aggregate health score.

Rename “only a restart can reclaim this” to factual VM/swap observations; do not claim that macOS swapfiles universally never shrink. Restart is an optional system request, not a guaranteed reclaim amount.

### Build Prep

User chooses project/profile and target volume. Readiness means “configured headroom met,” not “build will succeed.” Recommendation order is deterministic: eligibility, low rebuild cost, reliable inactivity, confidence, marginal allocated bytes, stable ID.

Only fresh, nonoverlapping, eligible candidates count. Global dependency caches used by an active project are protected or blocked when ownership is uncertain. Resource metadata never supplies executable commands.

At execution, remeasure the relevant volume after each completed item; stop once the target is met or the selected cap is reached. Do not add new candidates without another review. Report insufficient headroom when there is not enough eligible space. Unknown estimates are not counted as zero-cost solutions.

### Project inventory and working set

Read manifest/lockfile metadata with byte limits; discover repositories including worktrees and nested repos without executing project wrappers. Record local remote configuration only as optional presence; never check server existence.

Activity uses user pins, explicit current-project selection, recent Tidy observations and available local app/process evidence. macOS does not provide universal reliable “current IDE project” information. Treat absent evidence as unknown rather than inactive.

`inactiveConfirmed` requires complete, fresh adapter-specific ownership evidence, not the absence of an observed process. A user's “not working on this project” acknowledgement is a separate, expiring manual override and never creates unattended eligibility. The binding evidence matrix defines recognized producers, freshness, shared-resource treatment and positive/negative examples before the ranker is implemented.

Do not read file contents merely to determine last use. Access times are not authoritative. Do not hash dependency trees to find duplication. Shared objects/clones and ambiguous paths have non-additive/unknown reclaim estimates.

### Pressure Rescue

Group workloads by verified app bundle URL/identifier plus process instance start identity; device UDID; or local service identity. Display each exact action and whole-command scope. Refuse PID reuse and identity changes.

First actions: graceful app quit, individual simulator shutdown, supported emulator shutdown. No automated rescue. General dev-server kill, broad Gradle stop, and container-stack stop are suggestions until their identity/scope can be established reliably.

### Ecosystems

Inventory is comprehensive, mutations conservative:

| Ecosystem | Inventory | Permitted first mutations |
|---|---|---|
| Xcode/SwiftPM/CocoaPods | DerivedData mapping, archives, device support, simulators/runtimes, caches | Inactive mapped build outputs; explicit exact devices; archives remain separate high-risk review |
| Android/Gradle/Flutter | SDK/NDK images, AVDs, build output, caches, pub/Flutter SDK | Inactive proven build outputs and known tool caches; no broad active SDK removal |
| Node/Bun/Deno | Download caches, stores, node_modules, build artifacts | Known caches; inactive outputs; dependency directories only with explicit risk acknowledgement, never auto |
| Rust/Python/Ruby/Go | target, Cargo, pip/uv, venv/Conda, Bundler, module caches | Inactive build outputs and verified download caches; environments report-only initially |
| Homebrew | Download cache, installed/outdated versions, tool-owned cleanup scope | Local cache files proven safe; broad cleanup commands only if scope can be exactly represented |
| Docker/Colima | Local daemon/context, images, stopped containers, build cache, volumes, VM allocation | Individually identified unused images/containers only if supported without force; no broad prune or volumes |
| JetBrains/VS Code | IDE versions, known caches/logs, extension data | Verified disposable caches/logs only while owner is stopped; no workspaceStorage/settings/extensions |
| Ollama/HF/MLX | Local model files/shared blobs, download cache, age/confidence | Report/reveal only; model deletion and shared blob pruning excluded |
| Git/LFS/worktrees | Ownership, object sizes, worktree links, local status | Existing reviewed housekeeping only after scope/activity checks; no repo/worktree/LFS deletion |
| Databases/VMs | Recognized local data directories, sizes and ownership | Report/reveal only; never infer disposable database or VM data |

Unsupported tool version, unreadable index, missing daemon, scope change, or parser failure produces unavailable/read-only, not guessed commands. Each mutation needs an adapter-specific compatibility contract and disposable integration fixture.

### Budgets, profiles and assistance

Budgets evaluate known allocations per volume, with hysteresis and notifications; missing data cannot clear an alert. Overlapping category budgets are informational and never add shared bytes twice.

Profiles: Xcode, Android, Flutter, Web, Local AI, Battery. All can be cloned, edited, reset or disabled. Profiles alter Tidy policy only; they do not change system, IDE, Docker, Gradle or build settings. Factory profile targets are suggestions and never override a user's lower hard cap.

Automation starts with notify-only. Optional unattended maintenance has a separate closed allowlist of individually proven regeneratable, inactive filesystem caches. No generic command actions. Evidence and authorization are checked at every run. Notifications require OS consent and deduplication; revocation/quiet hours/timezone changes are supported.

The initial unattended allowlist is empty. An adapter may enter it only after proving a quiescent/immutable effect scope, bounded scheduling and recovery in its separate mutation acceptance task. Until then the feature supports budgets and notify-only rules and must not be marketed as automatic cleaning.

## 6. Architecture

Retain thin SwiftUI + TidyCore separation. New responsibilities:

- Policy: effective settings, precedence, validation and reasons.
- Inventory: typed resource identity, ownership, confidence, per-volume measurements.
- Planning: eligibility, ranking, target goal, overlap accounting and selection.
- Execution: sealed review contract, coordinator, per-adapter preflight, journal and outcomes.
- Monitoring: event-driven signals and bounded snapshots; no cleanup side effects.
- Scanning: shared budget scheduler, incremental aggregate index, scoped invalidation.
- Integrations: compiled-in adapters, fixed commands, local-only scope.

Use native actors/AsyncStream, Foundation/Dispatch, SQLite3, CoreServices and AppKit where necessary. Keep system UI APIs in the app layer behind injected protocols.

## 7. Performance and reliability acceptance

Targets are release gates to measure, not achieved claims:

- Hidden idle, monitoring and maintenance off: zero repeating timers, zero subprocesses and zero scan I/O. Explicit user work, separately authorized maintenance, draining and bounded reconciliation are distinct modes in the binding appendix, not idle-work exceptions hidden from measurement.
- Optional hidden monitoring: mean Tidy CPU <0.5% of one core over 10 minutes; resident memory ≤60 MiB after settling.
- Interactive steady state ≤100 MiB; scan peak physical footprint ≤150 MiB on the reference 8 GiB Mac.
- Quick known-root scan: first useful result ≤1 second, total ≤10 seconds for the declared 50k-entry fixture; full scan uses comparative rather than universal time promises.
- Cancellation: UI responds ≤100 ms; no new scan/tool work after cancellation; bounded scan workers acknowledge within 500 ms on local fixture.
- During a repeatable build, background Tidy work adds ≤3% median wall time over five paired runs; otherwise background scanning remains disabled.
- Incremental scan: ≥80% fewer file metadata visits than cold scan for an unchanged 100k-entry fixture; correctness equal to a fresh reference walk.
- After 20 scan/cancel cycles: no leaked workers/FDs, memory returns within 10 MiB of settled baseline.
- Test slow/unreadable/missing roots, millions of tiny files via bounded fixtures, churn, low disk, sleep/wake, event loss, app restart and config corruption.
- Full-suite release gate: 8 GiB Apple Silicon physical Mac and 8 GiB Intel physical Mac on supported OS; oldest macOS 14 smoke plus current OS, core tests and app UI flows. Unavailable hardware means explicitly incomplete acceptance.

No production cleanup is performed to validate the plan. Destructive integration tests use disposable scratch trees, repositories, devices and containers created for the test; no ambient home defaults.

## 8. Evidence sources and corrections

These sources constrain implementation; recheck installed tool versions before executing the plan.

- Apple: [memory-pressure events](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure) provide signal-driven monitoring.
- Apple: [thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum) supports throttling/pause policy.
- Apple: [Low Power Mode](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled) is an input, not a system setting Tidy changes.
- Apple: [FSEvents guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html): lost/coalesced events and root changes require invalidation/rescan; parent mtime alone is not a cache-validity proof.
- Apple: [volume capacity API](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey) requires an appropriate privacy-manifest declaration.
- Docker: [system prune](https://docs.docker.com/reference/cli/docker/system/prune/) has broad scope. Tidy must not hide it behind individually reviewed rows.
- Gradle: [daemon commands](https://docs.gradle.org/current/userguide/command_line_interface.html) operate across a version, not merely a selected idle project. Do not call a project wrapper during discovery or present broad stop as per-PID rescue.

## 9. Delivery boundary

The execution plan maps this entire contract to gated releases. Phase completion is distinct from full-suite acceptance. This planning turn produces documents and adversarial review only; it does not authorize implementation, commits, tagging, publishing or cleanup.
