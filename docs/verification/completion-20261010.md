# Local completion work — 10 October 2026

Baseline: `01dcf85e7f06abfd8d903d8e6401a49a83ffffdb`, reconciled audit branch,
continued on `CAJ/tidy-completion-20261010` in an isolated managed worktree.
The shared checkout remains on `main`. No publication or production cleanup.

## Execution plan

The user's current instruction is to continue until the app is complete. This
authorizes eligible implementation and validation, not invented acceptance of
unsupported capabilities. Exactly one GPT-6 Astra Medium adversarial plan review
was completed before implementation. Its corrections are incorporated here:

1. Reconcile the old T01–T24 checklist with current source and named tests before
   implementing missing consumers; distinguish source implementation, fresh
   verification, producer dependencies and external acceptance.
2. Run source/project/privacy checks, focused integration regressions, full Core
   with isolated process admission separate, and headless app-model checks.
   Correct failures from evidence and retain failed logs.
3. Fix independently implementable defects with focused regression evidence.
   Preserve mutation quarantine and the empty unattended allowlist.
4. Build and inspect synthetic native hosts. The earlier user deferral of GUI
   automation while using the laptop persists until scheduling is resolved.
   Native checks must include the latest compact audit failure (unnamed Touch Bar
   element), import progress/cancel/close/reopen and diagnostic save behaviour.
5. Build universal Release independently of GUI scheduling. Inspect local ZIP/DMG
   provenance, signatures, slices, resources, privacy manifest and parity. Keep
   reference hardware, human VoiceOver, real installation and release distinct.
6. Record final source hashes, toolchain, actual test counts, source/requirement
   mapping and precise remaining blockers; do not mark the full app complete
   while mandatory gates remain open.

## Initial current evidence

- Xcode 27.0 (27A266a), Swift 6.4, arm64, macOS 27.0.1 (26A434).
- XcodeGen 2.46.0 matches the repository pin.
- Approximately 191 GiB available before builds.
- Generated project membership: ten phases match, every test source included,
  disposable runtime composition isolated to the dedicated test host.
- Personal-data scanner/self-test, exact privacy source inventory/self-test,
  observation harness self-test and diff whitespace checks pass.
- The relevant Xcode release is unchanged from the producer-interface report.
  No new supported ownership/exclusion mechanism is evidenced; no lease probes
  are repeated and no adapter is enabled on synthetic evidence.

Verification logs and result bundles are retained under
`dist/verification/completion-20261010/`. Subsequent results belong to the exact
source manifest recorded there, not merely the baseline commit.

## Completion boundary

The September 20/22 source continuations supersede old labels that projects,
ranking, Build Prep, ecosystems and assistance are entirely absent. Their positive
mutation, physical, privacy-purpose and distribution gates remain separate.
The approved R02 DerivedData contract still requires complete producer-owned
association and exclusion; inactivity, advisory locks and another adapter are
not substitutes. Full-program and release status remain **INCOMPLETE / NO-GO**.

## Implemented local closure

| Requirement | Current production implementation | Fresh evidence |
| --- | --- | --- |
| Optional completed-report/index clearing (T07.3d) | Exact actor-issued file-size/store preview, one-use confirmation, stale identity/content rejection; clear reservation excludes scans, dormant continuation and confirmed execution; no settings/authority/journal reset | `OptionalRunHistoryTests`, `OptionalIndexClearingTests`, real unresolved-journal/local-ledger preservation model test, scan-start exclusion model test; native cancel/clear/reopen journey |
| Local reassociation guidance | Existing Local Consent pickers/ledger remain the owner; obsolete missing-feature text now points to Assistance | Settings source/copy tests; no duplicate authority store |
| Build Prep target volume (T13) | Home identity default; explicit approved root/volume selection; fresh exact-volume capacity; before/after identity and revocation checks; missing target remains unavailable | Four selection and five capacity tests; volume-specific policy and planner source review |
| Notification navigation (T21) | Persistent app-level window opener; exact budget and volume retained; no scan/effect on click; bounded newest-16 queue and yielded drain | Six injected-callback model tests; real OS notification delivery remains separate |
| Monitor reconciliation | No-op rescheduling preserves explicit measurement baseline; actual stop/disable resets pressure and page-out state | Original failing regression reproduced, then all 37 headroom-signal tests passed |
| Android legacy catalog | A child symlink escaping the declared system-image root is excluded | Deterministic owned-fixture RED/GREEN; catalog tests no longer inspect the user's real home |

The updated protection gate intentionally denies a parent containing a protected
descendant before capturing a manifest. Two old fixture expectations were corrected
to assert this stronger boundary; the review-time retention test uses an unrelated
protected sibling. No quarantine, ownership or test-count requirement was weakened.

## Headless and package results

- `core-final.log`: **782 tests / 91 suites**, runner success, 193.536 seconds.
  The process-global gate remains outside the ordinary invocation and passes
  separately: **1 test**, 0.380 seconds, `isolated-process-cap.log`.
- `models-final.xcresult`: **166 tests, zero failures**, 86.617 seconds.
  Required-case validators pass for Core, models and isolated admission.
- Normal Debug app build and universal **arm64 + x86_64 Release** build pass.
- Generated project, personal-data, exact privacy inventory and whitespace checks
  pass. Required-case gates now include the new workflows.
- The ZIP/DMG in `dist/verification/completion-20261010/packages/` have matching
  app manifests, strict ad-hoc signature validation, both slices, version 1.5.0
  build 1 and inspected privacy resources. The readonly DMG inspection and
  disposable copy/replace/remove rehearsal passed with its state witness intact.
  These are verification artifacts, not a publication or actual user installation.
- Exact source hashes, dirty patch, toolchain and package checksums are retained
  in the evidence directory. Earlier failing logs are preserved.

## Native audit diagnosis and honest boundary

The user explicitly authorized isolated GUI tests during this continuation.
The compact audit reproduced the historical AppKit Touch Bar problem on
MacBookPro18,2 / macOS 27.0.1. Its AX frame (80,0,685,30) is outside the stable
Settings window (942,33,480,552), and its screenshot contains menu-bar pixels.
Restoring key-window focus and ending text editing did not remove the platform
surface. Those experimental fixture changes were reverted.

A separately source-reviewed, exact-host/OS/container-limited false-positive
classifier revealed another description issue on the labelled system child
`emoji & symbols`. Rather than expanding exclusions, the experimental classifier
was also reverted. The original compact audit remains required and failing;
`verify.sh` still requires it. No overall automated-accessibility pass is claimed.
Raw evidence: `compact-initial.xcresult`, `compact-focus*.xcresult`,
`native-focused*.xcresult` and their exported attachment directories.

Apple documents [issue handlers for demonstrated false positives](https://developer.apple.com/videos/play/wwdc2023/10035/),
but that permission alone does not validate this app. Human VoiceOver and the
supported/reference-host matrix remain unperformed. The other native journeys
are recorded separately from this failed audit.

The pending product decision is documented in
[cleanup contract decision](cleanup-contract-decision-20261010.md). No proposed
contract change is applied without the user's answer.

`native-final.xcresult` passes **11 tests, zero failures**, 233.025 seconds:
four appearance variants and seven production-scene journeys, including optional
data review/cancel/clear/reopen and diagnostic-panel cancellation. The compact
accessibility case was deliberately excluded from this invocation after its
retained focused failure; the required full native gate is therefore **not green**.
This does not prove a successful diagnostic Save or actual OS notification click.

A coordination message from another chat requested preserving the strict
contract while the owner is unavailable. It supplies no owner approval for the
proposed redesign; the decision remains unresolved and the existing contract
continues to govern this work.

## Owner-approved next stage

The owner subsequently answered **“Authorize the manual per-adapter redesign.”**
The [decision record](cleanup-contract-decision-20261010.md) now authorizes that
engineering stage, with per-operation acceptance and no immediate mutation enablement.
The prior coordination note and pending status above are historical.

Diagnostic Save now has fresh native evidence: `diagnostic-save.xcresult` passed
one real-panel test that wrote metadata into synthetic home, verified absence of
the home path in exported bytes, and checked mode 0600. Synthetic presentation
`native-ui.xcresult` passed both required tests.

The first external-observer 50k attempt failed with “scan produced no useful progress”;
its evidence is retained at `/private/tmp/tidy-r13-observation-performance-50k-glk2bxyh`.
This is unresolved current-host harness/product evidence, not a performance pass.


## Manual-service continuation and corrected observer evidence

The first failing observer attempts above remain retained. Subsequent source
work corrected the fixture's obsolete useful-row matcher and exposed cumulative
partial scoped-scan results before a traversal batch completes. The progress
callback carries actual visited counts and results, observes cancellation/scope
validity, and adds no timer or extra filesystem reads. Focused progress tests
passed; the Core batch then passed **798 tests / 94 suites**, 205.920 seconds.
This full invocation preceded the later service review/journal/transport work.

Frozen current-host observation passed at
`/private/tmp/tidy-r13-observation-performance-50k-2rekvt0d/summary.json`:
first useful result **0.167557 seconds**, complete settling **6.338 seconds**,
50,539 entries, sampled descriptors 7–7, maximum RSS 128,592 KiB, no sampled
network rows or child PIDs, and a verified loopback observer positive control.
This is Debug synthetic-fixture evidence on this host; reference hardware and
other global physical acceptance remain separate.

The hidden-off observation passed at
`/private/tmp/tidy-r13-observation-mg6t4_ix/summary.json`: at least 120 seconds,
actual hidden state, local authority **denied**, zero timer rescheduling, scene
or explicit leases, scans and work; all catalog effects denied. The harness now
recognizes denied as the implemented local-ledger negative state and still rejects
granted/unknown. Both observations retain their exact WIP and artifact hashes.
They do not cover source edits made after those frozen captures.

Typed manual inputs, complete bounded parsers, store-bound one-use reviews and
schema-3 service intent are implemented. Confirmation still consumes and denies
unaccepted production providers. The fresh coordinator expiry regression passes.
The focused review/journal/transport plus existing filesystem recovery batch
passed **69 tests / 6 suites**, 9.564 seconds.

The same-process fake Unix peer protocol passed **13 tests / 2 suites**, 1.406
seconds (`docker-protocol-green.log`, parameterized cases included). A separate
compiled-receipt/recovery invocation passed **12 tests / 2 suites**, 1.538 seconds
(`docker-proof-green.log`): success, documented refusal and exact already-absent
proofs survive reopening after proof publication before the terminal event.
The proof archive contains hashes/categories and omits producer error text.
An independent Astra code review found no actionable issue in that path.
No real Docker daemon was contacted and no production provider was accepted.

The packages recorded above belong to the earlier source checkpoint. Later scan
and service changes require a fresh build/package inspection before delivery.


## Simulator read and review UI checkpoint

The process-budget transfer and pinned simulator client passed a focused
**32 tests / 3 suites**, 25.011 seconds (`service-client-green.log`). The
subsequent manual adapter/recovery batch passed **109 tests / 12 suites**, 11.779
seconds (`manual-batch-green.log`). Both include the owned cooperative fixture
only; no actual simctl shutdown was invoked.

Source review identified an internal reservation-release shortcut; it is fixed
with private reservation fields, constrained pre-spawn rollback and a gate-issued
transfer acknowledgement. Source review also identified unbounded queue waiting
for manual reads and an unchecked root marker probe in the chooser. Deadline
admission now spans queue wait and child execution, and chooser probes run off the
UI actor using a verified root descriptor and no-follow marker access.

The first combined deadline/root run failed three issues among **136 tests / 14
suites** (`manual-deadline-root-green.log`); this is retained as failure evidence.
Two root positives exposed Foundation's legitimate `/tmp` spelling versus its
`/private/tmp` filesystem path. The fix first verifies the complete stored
approval, then walks the verified realpath spelling without following components.
Negative root/ancestor/marker alias cases remain denied. The third issue was a
fixture race between consuming reap and asynchronous budget release; its original
700ms operation and total two-second bounds remain unchanged. The focused repair
passed **16 tests / 3 suites**, 1.612 seconds
(`manual-deadline-root-repair.log`). ProcessRunner subsequently adopted the new
bounded launch seam; final batch verification must include that call-site change.

Manual Operations now displays complete typed candidate identity, scope,
consequences, availability and review lifetime. Choices start unselected and
unacknowledged. Explicit inventory shares the real scheduler and local consent;
stale results are rejected. The UI has no dispatch implementation yet and cannot
enable execution from a description or checkbox. The real facade retains owner
binding for review cancellation. Model evidence:
`manual-model-green.xcresult`, **4 tests, zero failures**, including late-read
cancellation, duplicate preparation and a real actor/bridge cancel/reopen journey.
The normal Debug build also passed (`manual-app-build.log`).

The isolated production-scene native journey passed **1 test, zero failures**,
17.120 seconds (`manual-native-ui.xcresult`). It inspected only a compile-scoped
synthetic description, exercised/reset choices and preserved the outside witness.
The fixture binary composition check passed before its GUI launch. This does not
establish a production manual effect, fresh native producer inventory, or the
historically failing compact accessibility gate.

The exact live-service preparation is recorded in
[manual producer acceptance preparation](manual-producer-acceptance-preparation-20261010.md).
Native invocation/owned-launch provenance, service child persistence, the actual
simulator proof/dispatch path and live fixture authority remain separate work.


## Owned child and sealed fixture proof checkpoint

The native invocation description and owned cooperative launch passed **19 tests /
4 suites**, 1.605 seconds (`manual-launch-green.log`). The only launcher in that
checkpoint is fixed `/bin/cat` on an isolated gate. Native shutdown metadata is
digest-bound but cannot itself launch a producer or activate a capability.

Captured service child identity now uses a separate schema-3 transition. Source
review found that raw journal/store tuples could still bypass owned capture; two
real regressions reproduced **7 issues** (`manual-child-forgery-red.log`). The
replacement non-Codable receipt has a file-private constructor, is minted only
after opaque launch validation, and binds the exact submission/journal/store.
Both raw capture routes reject and submission requires all child fields absent.
The six capture regressions and sealed client/legacy recovery batch then passed
**65 tests / 7 suites**, 9.607 seconds (`manual-owned-capture-green.log`).

The simulator receipt now accepts only the opaque owned launch and binds its
origin, invocation digest, actual child/session identity, run/operation and full
service context. A raw session plus caller-provided IDs is no longer accepted.
Fresh complete fixture postcondition data and owned normal reap are both required.
The compiled fixture proof uses the explicit
`tidy.manual-service.simulator-owned-fixture.v1` identity, reconstructs its fixed
cat invocation, matches the durably captured child, and cannot be renamed to a
native verifier. Proof publication/reopening/idempotent recovery and the matching
Docker/filesystem recovery batch passed **67 tests / 7 suites**, 11.015 seconds
(`manual-simulator-proof-green.log`). Independent source review found no actionable
issue in this frozen batch. No native SDK proof or production budget release is
claimed; fixture cleanup remains guarded by isolated-test provenance.

Full app-model verification passed **170 tests, zero failures**, 62.708 seconds
(`manual-model-full.xcresult`). Required-case validators passed for the focused
Core, model and native results. The verifier now requires the new ownership,
queued-deadline, recovery and native manual-review cases and retains the compact
accessibility case unchanged.

An independent task has since reserved the desktop for its native acceptance
queue, with Masoon's current simulator turn active. No further GUI or live
producer run is started during that reservation. Source/build/owned-cat checks
continue; earlier Tidy native tests above already finished.


### Resumed native submission, proof and retirement checkpoint

Local execution resumed after the coordinated pause. Shell execution and the
existing worktree were revalidated; the last committed revision remains
`a09bc5d`. Available space at restart was 112 GiB. The pending pre-pause batch
completed: **47 tests / 7 suites**, 27.471 seconds
(`manual-native-hook-green.log`).

The one-shot native submission hook is separate from repeatable validators and
commits durable submission immediately before the sole `posix_spawn`. Its sealed
no-spawn receipt can arise only from a returned durable permit followed by an
observed rejected spawn. Generic errors, cancellation, duplicate attempts and
PID absence do not create that proof. The compiled rejected-spawn archive
reconstructs the full invocation digest, preserves native/fixture verifier
identity and requires the submitted intent to contain no captured child tuple.
A real fixed absent-executable fixture tests proof publication before terminal
publication, followed by reopened recovery without replay.

Independent review found a pre-submission cancellation race after the final
validator. The session now checks task cancellation immediately before the
hook, and the hook checks both task and shared app cancellation before advancing
its attempt count. A bounded fixed-cat validator pause exercises both origins.
The first combined compile caught a test-only stale outcome case name; the
correct `.launched` case repaired it, with the failed log retained as
`manual-native-proof-compile-red.log`.

The accepted-native client has no injected reader. Native and fixture receipts
are separate types. Native terminal verification retains the owned session,
requires a consuming-owned normal reap and the full stored child tuple, and uses
one finite terminal lease for fresh resolver/version probes bracketing complete
devices/runtimes/pairs responses. It reconstructs the exact native declaration
and requires the same reviewed identity to be Shutdown. Ordinary inventory and
cooperative clients cannot create native evidence. Native producer acceptance
remains denied, so no real SDK effect or native positive acceptance is claimed.
The intended missing-API RED is retained in `manual-native-client-red.log`.
The resulting combined batch passed **35 tests / 9 suites**, 4.307 seconds
(`manual-native-proof-green.log`).

`RunJournal.finishManualService` mints an opaque transient retirement receipt only
after matching proof publication, terminal publication, run completion and
intent retirement have succeeded. The process gate requires that receipt's
explicit native verifier, exact owned child/session and matching lease/obligation,
with no active or queued verification reads, before one-use closure. Fixture,
Docker and rejected-spawn evidence cannot close a production process obligation.
Publication-failure fixtures prove that terminal/finished write failures return
no closure receipt, while durable reopening can reconcile without reconstructing
that transient capability. The RED is retained in `manual-retirement-red.log`.
The combined retirement batch passed **36 tests / 10 suites**, 4.795 seconds
(`manual-retirement-green.log`); its test-count validator passed. Independent
source reviews of the no-spawn, native client/proof and retirement/cancellation
batches reported no remaining actionable findings.

The coordinated desktop GUI slot was briefly granted and explicitly released:
this Core checkpoint required no GUI run. No live simulator or Docker effects,
shared device changes, CoTeam VM/daemon access, Git push, merge or release occurred.
Confirmed execution and app-owned dispatch integration are the next source batch;
full Core/build/model checks must follow that batch before a final source claim.


### Confirmed execution and app-owned dispatch verification

The confirmed ledger is bounded to 32 records and retains the original review
expiry. Foreign ownership attempts do not consume another owner's record;
owned attempts are one-use even on stale policy, digest mismatch, expiry or live
consent revocation. The real bridge reloads acknowledged policy and local scope
before the same coordinator reserves state/admission and dispatches. Exact
already-Shutdown inventory returns no work without creating an intent.

Independent source review found and corrected two disabled-path defects: recursive
policy-barrier acquisition inside its own commit closure, and native mutation
queue admission without a finite deadline/app-cancellation wakeup. Barrier
closures now inspect only the already-validated policy's authority epoch/revision.
The sealed hook's original absolute deadline bounds gate admission; a bounded
shared cancellation observer removes only its unsubmitted waiter. Callback
invocation occurs outside the token lock and registration is removed after
admission. Fixed queue fixtures retain both outside slots while verifying expiry
and app cancellation, then publish the sealed no-submission proof. Their intended
missing-API RED is retained in `manual-mutation-admission-red.log`.

The app reserves the exact review task synchronously before awaiting confirmation,
joins only the same review/digest, excludes competing scan/catalog/optional-clear
work, retains ownership across window dismissal, and includes manual work in
shared cancellation/progress and bounded quit draining. The model merely observes
that retained task. Execute remains hidden for denied producers and cannot be
enabled by candidate data, a checkbox, portable settings or a prepared summary.
No working production effect is claimed.

The first 174-test model aggregate recorded two assertions in one new contention
test (`manual-dispatch-model-full.xcresult`): its second same-owner review correctly
superseded the first, returning unknownReview. The fixture now uses distinct
window owners, preserving both registrations while testing busy admission. The
focused eight-test repair passed (`manual-dispatch-model-repair.xcresult`), then
the complete **174-test aggregate passed with zero failures**
(`manual-dispatch-model-final.xcresult`). The model RED compile is retained in
`manual-app-dispatch-red.log`.

The full current Core aggregate passed **875 tests / 110 suites**, 216.270 seconds
(`manual-core-full.log`), and the process-global cap fixture passed separately:
**1 test**, 0.380 seconds (`manual-isolated-process-cap.log`). Required-case and
count validators passed. Normal Debug and universal arm64/x86_64 Release builds
passed (`manual-final-debug.log`, `manual-final-release.log`); both slices,
production composition and the privacy resource were checked. Project membership,
personal-data scanning, current-source privacy inventory and whitespace checks
passed. The final independent source review reported the two findings resolved
and no new actionable P0/P1/P2 findings in this integrated execution batch.

The exclusive desktop slot has been granted for one existing synthetic manual
review fixture journey. Its result is still pending at this source checkpoint.
Real SDK effects, real Docker effects/provider acceptance, the unchanged compact
accessibility failure, human/reference-hardware acceptance and release remain open.


### Latest GUI resource checkpoint

The final isolated runtime host built successfully, and its fixture composition
check passed. The first test invocation used CODE_SIGNING_ALLOWED=NO and its
host/runner resource signatures were invalid; that owned invocation was stopped
before any test result. Rebuilding through the earlier successful ad-hoc fixture
route (CODE_SIGN_IDENTITY=-, CODE_SIGNING_ALLOWED=YES) passed, and strict deep
signature checks passed for the host and runner. The subsequent single-test
invocation was interrupted at the owner's coordinated urgent GUI release request,
before any test result. The exact scoped fixture-process check found no running
host/runner from that build. Both interrupted invocations ended with code75;
no latest-source native UI pass is claimed. Logs and result containers are retained
as `manual-final-native-ui*` and `manual-final-native-signed-build.log`.
The GUI lease is explicitly released, and no further retry is authorized by the
current resource queue. Original data/services and other tasks' devices were
preserved. The earlier 17.120-second synthetic journey remains historical evidence.


### Local source/package and SDK preparation checkpoint

The verified Core/App batch was committed locally as
`89ca2ec97d679bf74cafb997a4d03a94c83f1087`. No push or merge occurred.
Fresh packages live in `dist/verification/completion-20261010/manual-final-packages/`:
version1.5.0/build1, strict ad-hoc signatures, both architectures, matching six-file
app payloads in ZIP and readonly DMG. The owned copy/replace/remove rehearsal
preserved its outside witness. `inspection.json` records source and checksums.
No app was launched or installed into the user's Applications; no notarization,
publication or real install acceptance is claimed.

The separate SDK semantics preparation has10 pure/local-file tests passing,
with dataless, anchored-directory and staging-name substitution failures retained.
Its independent source reviews report those P2 findings resolved; no production
code changed. The owner approved the exact disposable experiment after inspecting
its preparation. Execution still waits for the shared native/device lease and
fresh outside-witness revalidation. Production provider activation and actual
Tidy positive-effect acceptance remain separate; the experiment creates no Tidy
receipt, proof or bridge/journal qualification.
