# Manual Producer Operations Implementation Plan

> **For agentic workers:** Use the existing isolated worktree and subagent-driven development. The coordinator integrates and runs verification. Helpers do not start further plan reviews.

**Goal:** Deliver explicit, individually accepted manual producer operations without treating shared DerivedData exclusion as a prerequisite for unrelated adapters.

**Architecture:** Keep generic catalog effects quarantined. Add opaque manual-service reviews through the existing store-bound policy bridge and the same ExecutionCoordinator, installation admission lock and durable journal. Typed producer clients perform only fixed reviewed operations; compiled postcondition verifiers produce terminal receipts. No production capability becomes accepted merely because a fake producer passed tests.

**Tech Stack:** Swift/SwiftUI, existing TidyCore, native bounded POSIX process owner, macOS 14+, arm64/x86_64, no runtime packages or network dependencies.

## Current execution status

The frozen source now includes complete typed parsers, store-bound one-use
reviews and confirmed-operation consumption, schema-3 durable service intent,
owned native launch provenance, rejected-spawn and native/fixture terminal proof,
proof-publication recovery, durable obligation retirement, bounded queue and
terminal-read admission, approved read-only inventory, and app-owned manual
confirmation/execution/cancellation/quit-drain composition. Compiled production
acceptance remains denied. The Core aggregate passed 875 tests in 110 suites;
the app-model aggregate passed 174 tests with zero failures. Debug and universal
Release builds passed. Exact evidence and retained failures are recorded in
`docs/verification/completion-20261010.md`.

Tasks 1–3 and the native portion of Tasks 4–5 have implementation and local
fixture evidence. Their real SDK/app positive acceptance remains a Task 6 gate.
Docker has complete fake Unix-peer/HTTP/proof coverage but still lacks a qualified
production backend factory and dispatch; Tasks 4–5 therefore remain partial.
Task 6 still needs exact live-service authority and producer acceptance, the
remaining native/accessibility/privacy/physical/distribution evidence and final
capability-matrix acceptance. The unchecked source plan items below preserve the
original verification scope; they do not assert all production acceptance passed.

## Authority and exact contract change

The owner approved Choice 2 in `docs/verification/cleanup-contract-decision-20261010.md` on 10 October. This replaces the global shared-DerivedData dependency with per-adapter acceptance. It does not declare the historical R02 proof present, permit generic shared-cache unlinking, authorize live user tool/device effects, or authorize release. Unattended cleanup remains off and its allowlist empty. Existing repository/database/model/Docker-volume/broad-prune prohibitions remain.

The new contract distinguishes a service object from a frozen filesystem manifest. A container removal review explicitly authorizes the entire exact immutable container identity and its mutable contents at the moment the producer accepts removal. It must never claim stopped means immutable or promise frozen file contents. Every operation is initially unselected and requires a fresh consequence confirmation.

Exactly one GPT-6 Astra Medium adversarial review is required for this revised plan before implementation. Findings are consolidated once. Code review follows the implementation batch.

## Capability matrix

| Candidate | Exact manual scope | Required producer acceptance | Current activation |
| --- | --- | --- | --- |
| Apple simulator shutdown | One full UDID, matching runtime/device type, exact approved device set, available runtime, unpaired Booted device | Fixed supported simctl shutdown; owned normal exit; complete same-set post-inventory reports the reviewed identity Shutdown | Candidate only, pending implementation and authorized disposable-service acceptance |
| Docker stopped container removal | One canonical full 64-lowercase-hex container ID, Exited state, no mounts, no managed-stack ownership, explicit whole-container data-loss acknowledgement | One retained approved Unix-socket peer/daemon connection, force=false, v=false, link=false; complete correlated HTTP204 plus exact inspect NotFound | Candidate only, pending implementation and authorized disposable-service acceptance |
| Simulator deletion | Exact identity destructive operation | Separate deletion contract and explicit app/settings/data-loss review | Denied in this first batch |
| Docker image deletion | Exact immutable image ID with no parent pruning | Alias/platform/reference race and conditional scope contract not established | Denied |
| Shared DerivedData and other direct shared caches | Reviewed filesystem leaves | Existing producer ownership/exclusion contract | Denied |

A successful command cannot assert freed physical bytes. Shutdown reports state only. Container removal reports its object result and separately observed strict-volume change only if a valid measurement exists.

## Task 1 — Typed review inputs and complete producer inventory

**Files:** new `TidyCore/Sources/TidyCore/Integrations/ManualServiceOperation.swift`; extend `AppleDeveloperAdapter.swift`, `DockerAdapter.swift`, `ToolAdapter.swift`; new `TidyCore/Tests/TidyCoreTests/ManualServiceOperationTests.swift`.

**Interfaces:** Define `ManualServiceAdapterID` with only `appleSimulatorShutdownV1` and `dockerStoppedContainerRemovalV1`; `ManualServiceObject` with distinct simulator/container associated bindings; `ManualProducerIdentity` holding exact executable identities, approved local set/socket, supported version and bounded producer identity. `ManualServiceReviewSummary` is display data. `ManualServiceReview` is opaque, has no public initializer, and carries a coordinator-issued UUID; display data cannot authorize effects.

- [ ] Add contract tests first: exact full IDs, duplicate UUIDs/IDs rejected, same name with different identity, unknown/transitional state, unavailable runtime, pair membership, unsupported version, changed toolchain/set/socket, container mounts/managed labels, oversized/malformed/truncated data.
- [ ] Extend parsing without changing existing inventory contracts: full device/runtime/pair responses, exact container inspect fields. A filtered/substr search or ordinary list row cannot prove absence or writable-data scope. Bound bytes, records, strings and JSON nesting through existing parsers.
- [ ] Bind Xcode/simctl identities and version separately from the parser-format version. Inspected candidate is Xcode27.0/27A266a, CoreSimulator1171.7; other versions remain unaccepted. Docker compatibility must be derived from the connected approved daemon's exact API/version record rather than guessed from CLI presence.
- [ ] Keep raw argv and mutable names/tags out of the public review request. Review expiration is at most 60 monotonic seconds; retain at most 32 pending summaries with bounded metadata. Cancellation and supersession remove the pending review.
- [ ] Coordinator runs focused contract tests and checks existing Apple/Docker inventory regressions.

## Task 2 — Store-bound manual policy and one-use review admission

**Files:** `Execution/ExecutionPolicyBridge.swift`, `Execution/ExecutionCoordinator.swift`, new `Execution/ManualServiceReview.swift`, corresponding Core tests.

**Interfaces:** A `BridgeManualServices` facade is minted only by the real bridge, bound to its coordinator and acknowledged settings generation. It exposes typed `prepare`, `confirm`, `cancelReview` methods; confirmation returns an opaque one-use `ConfirmedManualServiceOperation`. No caller-supplied effective policy, boolean authority or mutable allow-all registry is accepted.

- [ ] Test defaults/manualActions off, disabled feature/ecosystem, forged/wrong-coordinator/stale/consumed tokens, import/profile attempts, policy invalidation while queued, local consent revocation and two-window duplicate confirmation before implementation.
- [ ] Resolve acknowledged `feature.ecosystems`, exact ecosystem inventory/manualActions settings, and current local executable/root/socket consent in the bridge. Revalidate the same live authority and acknowledged generation before producer reads and dispatch. Portable preferences cannot create local grants.
- [ ] Register the typed review inside the existing coordinator; preserve the shared `.idle/.running` state, bounded review storage, progress stream and installation admission lock. An already-stopped simulator is visible no-work and performs zero mutation.
- [ ] Keep `CapabilityRegistry` default-deny for all legacy actions. No `.runTool` or `CustomActionExecutor` bypass is added.
- [ ] Coordinator runs policy/token tests and existing quarantine/hostile-import suites.

## Task 3 — Sealed mutation launch and durable service terminal proof

**Files:** `Exec/ProcessRunner.swift`, `Exec/ProcessSession.swift`, `Execution/EffectLifecycle.swift`, `MutationAdmissionStore.swift`, `RunJournal.swift`, `ReviewedManifestStore.swift`, `ExecutionCoordinator.swift`; new process/service lifecycle tests.

**Interfaces:** Add a versioned `ManualServiceEffectBinding` as a distinct persisted service binding, retaining operation/run/plan/policy IDs, review digest, complete typed object and producer identity. Decode old filesystem/process records without reinterpretation. Add compiled service proof validation as a separate branch; retain every filesystem manifest requirement.

- [ ] Test real owned-scratch journal crash prefixes and faults before spawn, after spawn, before child identity persistence, after owned exit, before/after proof publication and before retirement. No fixture Boolean may clear an intent.
- [ ] Persist the exact binding and intent before any possible spawn. Persist child boot/PID/start/executable identity when captured. A crash in the capture window stays uncertain; do not pretend simctl/docker waits on the cooperative fixture start byte.
- [ ] Add private fixed producer declarations to the existing bounded launcher. Use pinned absolute executables and explicit environment; no inherited DYLD/SIMCTL/DOCKER/SSH/context variables, shell, arbitrary argv, daemon start or network fallback. Bind the selected local producer on every call.
- [ ] A mutation timeout/cancel never force-kills the producer. Preserve the owned reaper, process slot and durable intent until the compiled adapter proves terminal state. Cancellation before spawn is no-effect; after submission it stops later work and can remain uncertain.
- [ ] A compiled service verifier requires a matching owned normal child exit for simctl, or a complete correlated HTTP success/refusal response on the retained approved Unix connection for Docker, plus the adapter-specific complete exact-producer postcondition. It seals the operation/object/producer/receipt digest. Persist proof before itemTerminal and intent retirement. Only the matching verified proof can release that mutation's process slot.
- [ ] Recovery reconciles a valid persisted service proof and requires fresh review. Missing proof, lost reply, changed producer, incomplete postcondition or corruption stays blocked without replay. PID absence, reboot or a current reversible state alone cannot retire a pending daemon request.
- [ ] Coordinator runs bounded-process partitions separately, service lifecycle tests, and all existing filesystem recovery tests.

## Task 4 — Fixed Apple and Docker producer clients

**Files:** new `Integrations/AppleSimulatorOperation.swift`, `Integrations/DockerContainerOperation.swift`, `Integrations/LocalDockerHTTP.swift`; private launch declarations, bounded transport and tests in the files above.

- [ ] Apple client accepts only exact unpaired Booted UDID/runtime/type in the approved set, and uses one fixed shutdown command with explicit set/developer directory. Bind both the resolver and actual simctl. Full same-set post-inventory must be complete and exact. Never `all`, `booted`, `unavailable`, multi-ID, spawn, install or download.
- [ ] Docker uses a typed Unix HTTP client, not independent CLI reconnects for the effect. Retain one connected peer across final inspection, deletion and postcondition; validate socket identity, peer credentials and daemon/API identity. Reject redirects, reconnects, ambiguous framing, unbounded/chunked payloads outside the accepted parser, over-limit bodies and transport deadlines. Persist intent before any DELETE bytes. No request-resend after partial writes. Docker client binds the approved Unix socket, exact daemon identity/API/version and canonical inspect ID. Initial candidate is Exited, unmounted, unmanaged container only. Use exactly `DELETE /v<accepted-api>/containers/<full-id>?force=false&v=false&link=false`; never a name/prefix, prune, image removal, remote context, daemon auto-start or forced stop. A daemon conflict is refusal, not retry.
- [ ] Inject internal typed clients in tests only; production constructors remain fixed. Use real journal/artifact storage and fake bounded producer transcripts for semantic tests, plus owned subprocess fixtures for launch/reap proof. Fake producer success is not live adapter acceptance. Exercise the Docker HTTP framing and partial-write/response/deadline paths with an owned temporary Unix-socket server; do not contact a user daemon.
- [ ] Record command/API provenance, complete effect scope, all denial reasons and unresolved live acceptance in per-adapter integration documents.

## Task 5 — Explicit app review, progress, cancellation and recovery

**Files:** new `Tidy/Developer/ManualServiceReviewModel.swift` and `ManualServiceReviewView.swift`; extend `DeveloperWorkspaceModel.swift`, `DeveloperWorkspaceView.swift`, `AppExecutionServices.swift`, project source declarations and model/native tests.

- [ ] Add initially unselected review actions on exact inventory rows. Show object ID, producer/set/endpoint, observed state, consequences, acceptance status and expiration. Do not show a working Execute button for unaccepted producers.
- [ ] Confirmation uses the bridge's sealed token and app-owned task; windows subscribe but cannot duplicate dispatch or abandon journal ownership when closed. Existing global progress/cancel/quit drain and explicit recovery routes remain the owner.
- [ ] Model tests cover close/reopen, double-click, cancellation, stale policy/consent, refusal/uncertainty, no-work and preserved optional-history/recovery boundaries. Native fixtures use injected service transcripts only.
- [ ] Regenerate project membership, settings/capability docs and privacy inventory, then coordinator runs Core/model/native/build gates proportional to the final source batch.

## Task 6 — Acceptance and exact remaining authority

- [ ] Preserve source/static/unit/build/native-synthetic evidence separately. Keep current compact accessibility and first-useful-output performance failures open until independently resolved; do not soften thresholds.
- [ ] Prepare an exact disposable-service fixture procedure from current installed inventories, naming resources to create/use/remove and retained outside witnesses. This preparation must be complete before asking the owner for live tool/device-effect authority, which the redesign decision explicitly did not grant.
- [ ] Do not activate either production adapter until its supported-version contract and required disposable producer evidence are accepted. Unaccepted candidates remain clearly unavailable.
- [ ] Reinspect packages at the final source checkpoint; no push, publication or release waiver. The owner must separately approve any changed delivered capability manifest.

## Scope completeness

This plan implements the manual producer-operation architecture and the first two candidate adapters. It does not silently turn their unavailable live acceptance into success, restore simulator deletion or Docker image deletion, or represent the full original catalog as complete. Subsequent adapters require independent concrete contracts; unsupported surfaces stay truthful and read-only. The approved redesign removes one universal prerequisite, not all safety or acceptance requirements.

## Consolidated adversarial review — binding implementation corrections

The required single GPT-6 Astra Medium review completed on 10 October. The
following table is the authoritative clarification of Tasks 1–6; no second plan
review is requested.

### Submission and proof state table

| Observed boundary | Allowed disposition | Required proof | Admission/resource handling |
| --- | --- | --- | --- |
| Review cancelled/expired before durable intent | Cancelled/unavailable; no effect | No submission object exists | Drop one-use review |
| Intent publication fails | Storage unavailable; zero submission | Owned code has not invoked spawn/write | Preserve storage failure; no spawn/write |
| Launcher fails before a child can exist, or HTTP transport has written zero request bytes | Failed/cancelled without effect | Sealed launcher/transport never-submitted receipt bound to binding digest | Durable no-submission proof then retire |
| Apple command nonzero, mismatched child, missing/truncated inventory or timeout | Uncertain | No terminal proof | Retain intent; never treat exit code as no-effect refusal |
| Docker complete same-connection documented 409 conflict or exact-object 404 after DELETE | Refused/no work | Strict correlated response on already validated supported route/producer; no reconnect | Durable compiled refusal receipt then retire |
| Apple owned normal exit plus complete exact matching Shutdown postcondition | Succeeded | Compiled Apple receipt bound to complete reviewed service binding and owned child | Persist proof, itemTerminal, retire, release matching slot |
| Docker complete 204 plus exact-object inspect 404 on the retained validated connection | Succeeded | Compiled HTTP request/response/postcondition receipt | Persist proof, itemTerminal, retire, close connection/release service ownership |
| Partial request write, lost reply, unexpected HTTP/server response, connection close before postcondition, changed producer | Uncertain | No terminal proof | No reconnect/retry; preserve intent and bounded diagnostic |
| Crash after proof publication but before terminal event | Recoverable only by validated immutable proof-artifact lookup by operation ID | Exactly one valid proof matching the full persisted service-binding digest | Append missing terminal event once, then existing retirement order |
| Crash without durable proof | Blocked, no replay | No PID/reboot/current-state shortcut | Explicit recovery remains blocked; producer-specific future evidence only |

A 404 is accepted only after a successful version/daemon/inspect exchange on the
same supported API route and same retained connection, with a strict Docker
error object identifying the exact full object ID. A generic HTML/proxy/unknown
route 404 is uncertainty, not absence. Duplicate/conflicting proof artifacts,
unknown schemas and binding substitution fail closed.

### Cancellation and terminal-verification ownership

The app-owned operation retains response collection, owned reaping, admission
lock and bounded terminal verification independently of the initiating view/task.
Cancellation prevents submission when possible and prevents later operations;
it does not abandon an in-flight response. Use a separate bounded terminal
collection deadline. On unresolved expiry retain only the durable uncertainty
and bounded ownership records; close HTTP descriptors and stop buffering without
asserting daemon completion. A still-unreaped owned child remains under the
existing sole reaper.

A process reservation represents both a physical child and an unresolved
mutation obligation today. Separate those concepts: after the mutating direct
child is consuming-reaped, retain the mutation obligation/admission but allow its
bounded postcondition reads through an explicit terminal-verification lane under
the same physical two-process maximum. That lane is limited to the current sealed
operation's exact read-only probes; it is not general inventory, cannot grant a
new mutation, and does not wait forever on a user read-only cap of zero. Test a
cap-zero transition, another occupied physical slot, cancellation and deadline.
HTTP service ownership is a distinct bounded connection/request resource, not a
fictional process child.

### Persisted schema

Introduce a new service-intent schema version instead of changing the meaning of
schema-1 legacy process or schema-2 filesystem bytes. Store the complete typed
binding and digest; proof archives bind the same digest plus the producer
receipt. Historical validation dispatches by an explicit compiled verifier ID;
filesystem proofs still require their original manifest and association. Add
bounded immutable proof discovery for the proof-publication/event gap, rejecting
multiple conflicting artifacts. Test interruption at every publication/retirement
boundary with the actual store and reopened coordinator.

### Docker provider and HTTP constraints

An arbitrary approved local socket is not an accepted local Docker provider.
Production activation additionally requires a named, versioned provider contract
that binds the connected peer (macOS peer credentials/PID and executable identity)
to the explicitly accepted local backend arrangement. Revalidate the socket around
connect; retain one peer; bind daemon ID and negotiated API/version. Self-reported
JSON plus socket locality alone never activates a provider. Until installed
provider evidence establishes this arrangement, production Docker construction
must deny while owned fake Unix-socket tests remain possible internally.

HTTP has one request outstanding at a time, no redirects/reconnects/pipelining,
maximum 16 KiB headers / 64 header fields / 2 MiB body, strict HTTP/1.1 status,
exact finite Content-Length, and no ambiguous duplicate lengths or unsupported
transfer encoding. Header/body deadlines and partial writes are tracked. Only
fixed GET version/info/exact inspect and the fixed one-ID DELETE are represented
by the type system. Initial container acceptance requires `State.Status=exited`,
`Running=false`, `Paused=false`, `Restarting=false`, empty `Mounts`, no nonempty
volume-driver or volume declarations, and no Compose/Swarm/stack/orchestrator
ownership labels (`com.docker.compose.*`, `com.docker.stack.*`,
`com.docker.swarm.*`, `io.kubernetes.*`). Unknown required fields deny. Final
inspection does not claim a lock; the user's whole-container consequence review
and the producer's nonforce running-state refusal define the scope.

### Simulator provider and activation

Capture/revalidate the actual simctl executable, selected developer directory,
explicit device set, supported runtime/device type and complete pair inventory.
Qualifying its shutdown normal-exit/postcondition semantics and pairing behavior
is part of disposable producer acceptance, not a consequence of parsing JSON.
A post-spawn mismatch remains uncertain. Neither public tokens nor a successful
fake provider may bypass a compiled adapter/provider/version acceptance record.
Test production composition rejection directly. Live fixture preparation names
all setup/use/cleanup commands and outside witnesses before any owner request.
