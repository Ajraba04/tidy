# Remediation continuation final review

Date: 2026-09-19

Baseline: `b4acfff2a78343884457b14ee5d9efba3df91e12`

Reviewed continuation commits:

- `47fe16a` — local ZIP/DMG checkpoint inspection
- `b171d85` — settings-shape, recovery-witness, and diagnostic privacy fixtures
- `dbf9c72` / `4fe419e` — store-bound fresh-default scan admission and external-image revalidation
- `6f78e05` / `abba5e4` — required-reason API inventory and frozen runtime-source refresh
- `76590e3` — consumed scan-grant and full-home-consent lifetime correction
- `be8e34d` — isolated production-scene runtime host and six native journeys
- `72c699b` — project, privacy, compiled-fixture, required-case, and aggregate CI gates
- `ab2d550` — read-only Darwin file-lease dependency investigation
- `3f576d9` — model aggregate floor aligned with the verified test inventory
- `fe90172` — scene teardown regression synchronized with an entry barrier
- `17ce90d` — cross-process fixture release signals published atomically
- `5bfd8ea` — atomic release regression required by the 701-case Core gate
- `530f665` — cancellation requested before scan-session publication is retained
- `ad90e30` — appearance fixtures and a single Settings scrolling surface
- `37a0d31` — current-host observation/performance driver and external harness
- `a64f4e8` — observed-case registration, compact AX fixture, and verifier isolation

Scope: retained whole-continuation review findings and dispositions. The earlier reviewed
checkpoint was `5bfd8eaaad4deb3b3b586ce6c4997e24ad8b1804`; subsequent changes listed here
are not covered by that approval. Resume baseline is `ca24965a0e91f5e433d3ec5c18c259ba07ce6c27`.
The resumed consolidated source review below is complete. Verification is partial:
the hidden-off capture passed, but the required compact native audit timed out (code -56).

## Verdicts

### Specification

**PASS at the source-review boundary for the contained continuation.** Final runtime
acceptance remains incomplete because the compact audit timed out. Earlier reviewed
changes implement the independently permitted read-only R05 unit, strengthen R06/R08/R12 evidence,
and add guarded R13 current-host production-scene evidence without crossing the approved mutation,
privacy, distribution, or release boundaries.

This is not approval of the full remediation program or a release verdict. The current advertised
application remains **NO-GO** and the full program remains **INCOMPLETE**. R02 still lacks supported
real Xcode producer ownership/exclusion proof; therefore positive R03/R04 effects and R05 mutation
reachability remain blocked. Every compiled catalog mutation remains denied and production bootstrap
continues to pass `detectedTools: []` into execution and scan environments.

### Quality

**PASS at the source-review boundary after the resumed corrections.** The hidden-off
fixture passed; compact accessibility remains unaccepted after the audit timeout. The fresh
default authority is bound to one settings actor, one generation, one use, exact canonical content,
and a revalidated disk image. Scope grants release captured identities after use. The runtime host is
selected only by its compile condition plus exact bundle identity, accepts no arbitrary path or
authority input, uses owned temporary roots, and removes automated fixtures through guarded cleanup.
The normal Release artifact is separately checked for absence of fixture-only markers.

Fresh aggregate verification remains an evidence prerequisite for the controller's completion
statement. Focused or earlier aggregate results cannot substitute for an aggregate run after the
final committed CI/source freeze.

## Findings and dispositions

### FR-01 — High — fresh-default provenance ignored external disk replacement

The first R05 implementation validated actor identity, generation, and token replay but did not bind
the bootstrap permit to the settings disk image. A second `SettingsStore` or external writer could
create valid, corrupt, or future settings after the absent-file load and before permit acquisition,
while canonical revision-zero policy still installed.

**Resolved in `4fe419e`.** The permit captures the exact `SettingsDiskImage`; acquisition reopens the
bounded settings path and requires the same directory/config/backup/lock/metadata identities and
bytes. The sole exception is the existing absent-parent to empty-parent transition caused by journal
bootstrap. Tests cover second-store publication, corrupt creation, atomic future-schema replacement,
byte preservation, replay, foreign actor, same-actor staleness, reservation, and generation
exhaustion. Focused evidence: Core 58/5 and app-model 17 selected tests passed.

### FR-02 — Important — runtime fixture cleanup and authorization oracle were not reliable

The provisional R13 host left each roughly 5,152-file fixture tree after termination, including setup
failure paths. Its recovery view also hardcoded the accessibility value `all-denied` even when the
visible registry calculation could report `authorization-changed`.

**Resolved in `be8e34d`.** Fixture roots are registered immediately after `mkdtemp`, setup failures
remove only the validated owned root, native tests invoke host-side resource disposal/cleanup and
verify disappearance, and visible plus accessibility values share the same live registry result.
Earlier owned RED/diagnostic roots were revalidated and removed; the separately authorized manual
observation root was retained only through capture, then identity-checked and removed. Zero matching
fixture roots remained after capture.

### FR-03 — Important — successful scan authority retained path identities for app lifetime

`ScanScopeGrantLedger.consume` marked a grant consumed but retained the grant and every captured
root/ancestor identity forever. The adjacent full-home consent ledger also retained successful
consents until a later issue happened to reap them.

**Resolved in `76590e3`.** Successful grant consumption removes the entry under lock; registration
reaps expired abandoned grants; successful full-home authorization removes its consent before root
capture. Missing and consumed tokens still report `consumedConsent`; failed root capture consumes
the consent and cannot replay. Four focused regressions and the complete 15-test `ScanScopeTests`
suite passed. No speculative public API or hard-cap claim was added.

### FR-04 — Important — target misconfiguration could select real storage before UI attestation

Because the runtime host and normal application share `TidyApp.swift`, a missing runtime compilation
condition could compile the normal path-resolution branch in the verification bundle. Conversely,
leaking the condition to another bundle could expose fixture composition outside the intended host.

**Resolved in `be8e34d` and the final project gate.** The runtime branch requires the exact runtime
bundle identifier; the non-runtime branch refuses that identifier. Project verification requires the
runtime condition only on the dedicated host, its exact bundle identifier, and the production UI
suite's exact test host. The production target has no argument-selected path override. The compiled
fixture is checked before native launch, and the normal Release artifact is checked for absence of
fixture markers.

### FR-05 — Minor — evidence wording exceeded the exercised boundary

Review identified broad statements about all import work being blocked during bootstrap, every Safe
row being native-verified, and any write during the full admission interval being detected.

**Resolved in documentation.** The records now distinguish persistent import commit from analysis,
runtime registry denial from the visible disabled `Clean Now` assertion, and point-in-time disk-image
revalidation from a continuous external filesystem lease.

### FR-06 — Minor — predicted model aggregate floor was one test too high

The first final verifier run confirmed Core 700 and the isolated process-cap test, then stopped
because CI predicted 143 model cases while the complete suite contained 142. The discrepancy came
from counting the expanded revision-zero test as an addition even though it replaced the earlier
revision-zero/recovery test.

**Resolved in `3f576d9`.** The floor is 142, matching the verified inventory: baseline 137 plus five
net-new model cases. The failed gate was preserved as evidence; a fresh full verifier run from a new
empty evidence directory is required after the correction.

### FR-07 — Important — model lifecycle test accepted a transient zero before queued entries arrived

The corrected-floor rerun executed all 142 model cases but the scene teardown regression observed
192 retained lease/generation entries after first accepting a transient baseline. The original test
released each model immediately after queuing visibility and polled only global counts. That poll
could see zero before any queued transition entered `SystemMonitor`; late transitions then populated
the ledger after the test had already accepted its cleanup condition.

**Resolved in `fe90172`.** The test retains 100 Headroom and 100 menu models, requires the exact
baseline-plus-200 active/generation state, then releases both arrays and waits for the real
deinitializer/dispose path to return to baseline. It does not reset or stop the monitor. The named
case passed in ten separate processes and the full `HeadroomViewModelTests` suite passed 11/11. A
fresh aggregate rerun remains required after this test-only correction.

### FR-08 — Important — cross-process release signal exposed its final name before its byte

The next full Core run executed 700 cases but the `bootstrap-hold` settings process exited 126 while
waiting for `resume`. The retained artifact later contained the correct mode-0600 one-byte signal.
The harness created the final name with `O_CREAT | O_EXCL` before writing byte 82, so the strict child
could open the transient zero-byte inode and correctly reject it. The paired loser then timed out
because the parent aborted before publishing `retry`.

**Resolved in `17ce90d`.** The harness writes and validates an owned UUID staging file, closes it,
then publishes with same-directory `renameatx_np(..., RENAME_EXCL)`. Existing signals cannot be
replaced, failed staging is retained/removed only by its exact helper path, and reader validation was
not weakened. The no-replace test passed; the two-case contention method passed in five separate
processes; the complete process suite passed 4 tests/9 argument executions. The added regression
raises the final Core floor to 701 and is an exact required CI case.

### FR-09 — Important — visible Cancel could be a no-op before scan-session publication

`ScanViewModel` entered `.running` before `beginScan` returned a session identifier. If the user
selected Cancel during that interval, `cancelScan` returned without recording cancellation. The
fast production fixture could then complete before XCTest reached Cancel, which exposed the race
rather than providing deterministic cancellation evidence.

**Resolved in `530f665`.** Starts now carry an owner-bound request generation and retain a pending
cancel for exactly that generation. Rescan cannot target an old terminal session. The runtime
cancellation fixture saturates real scheduler permits, observes one real registry `.cancelled`
terminal, releases only its blocker resources, and waits for the production lifetime owner to
settle service/session/scheduler/lease/index state naturally before close/reopen assertions. The
focused model cases passed 2/2, the cancellation native case passed, and the complete six-case
production-scene class passed.

### FR-10 — Important — AX existence hid clipped Settings content and undescribed containers

At the original 900-by-552 Settings size, the registry surface received roughly 50 points of
height while its seven-line metadata required roughly 130 points. The row and metadata existed in
the accessibility tree, so existence-only checks passed even though visual review showed clipping
in every controlled appearance. The compact SDK accessibility audit then found undescribed AppKit
hosting and scroll-document containers that ordinary child-label assertions did not cover.

**Partially resolved at the `a64f4e8` checkpoint.** Settings now uses one outer vertical scroll
surface, and the compact fixture sets the real window content size through a fixed compile-scoped
AppKit control. It requires the metadata and editor inside both the window and scroll viewport,
requires physical metadata/row height, labels the search field, and runs the public contrast and
sufficient-description audit without filtering issues. The hosting-container and search findings
were corrected. The subsequent scroll-document-container RED remains open until its public AppKit
document-view label passes the same focused audit; the checkpoint is not acceptance.

### FR-11 — Important — hidden observation fixture persisted an impossible authority field

The first frozen Release hidden-off execution launched the exact runtime host but entered Settings
recovery before the observation coordinator. `seedObservationSettings` wrote
`monitor.backgroundEnabled` into persisted preferences. That setting has `.authority` resolution;
`PolicyValidator.validateStructure` rejects every persisted value, including `false`, with
`authorityIsLocal`. The product currently reports that the corresponding machine-local authority
workflow is unavailable, so persisted settings cannot honestly create an authorized background
state.

**Authority-field defect corrected in `3dd388a`.** Both fixed fixtures omit the portable
field and use actual production policy: feature off for 120 seconds, then feature enabled
without background authority for 600 seconds. No synthetic monitor grant is accepted.
The original failed run is retained under `/private/tmp/tidy-r13-observation-gytzmcuu`.
The corrected run `/private/tmp/tidy-r13-observation-u9jrbl5w` reaches the coordinator but
fails because the application did not become hidden. Neither run supplies performance
acceptance. Hidden lifecycle and successful capture remain pending.

## Specification trace

### R02 producer dependency

The read-only addendum correctly treats Darwin `F_SETLEASE` as a ruled-out lead rather than a
dependency exit. The installed release kernel denied acquisition to an ordinary unentitled probe;
published XNU requires a private file-lease entitlement and exposes neither complete producer/shared-
owner identity nor an unbreakable deep-subtree exclusion held across every unlink. R02 therefore
remains unavailable without weakening the approved contract or substituting a synthetic lease.

### R05 read-only fresh-install scan

- Only exact `.newDefaults` from the issuing `SettingsStore` can select `.freshDefaults` scheduler
  origin. Ordinary loaded revision-zero files and caller-forged values remain unavailable.
- The first persisted settings change closes admission and replaces revision zero only after durable
  save and scheduler commit. Save/conflict/cancellation paths do not apply edited policy.
- `ScanScopeAuthority` consumes only the scheduler-acknowledged scan envelope. Quick scope remains
  bounded to existing same-volume catalog roots; selected-project with no roots visits nothing;
  Full Home still requires owner-bound one-use consent.
- Bootstrap starts no traversal, process, monitor lease, timer, or index watcher. The native
  fresh-default journey keeps `config.json` absent before and after Quick scan.
- No tool discovery or cleanup authority was introduced. `CapabilityRegistry` remains fixed-deny.

### R08/R12 settings and privacy fixtures

- Supported schema-2 shapes are labeled supported historical shapes, not falsely labeled released
  builds. Future/corrupt downgrade fixtures preserve exact bytes and remain read-only.
- Import/selective reset preserves active profile, inert state, an independent authority witness,
  and a real unresolved mandatory recovery ledger. No fixture clears recovery to obtain admission.
- Diagnostic primary/temporary/backup candidates exclude credentials, cookies, environment, argv,
  remotes, personal path identity, setting values, and profile names even with cosmetic redaction
  disabled. This tests the pure renderer only; no production diagnostic writer is claimed.

### R13 runtime and privacy evidence

- The dedicated host compiles real production scenes/services against a fresh synthetic home,
  settings file, and journal. Fixed scenarios cover acknowledged settings, absent settings, and a
  fixed unsupported schema; no supplied path, settings payload, or capability is accepted.
- Six current-host native journeys passed: storage/isolation attestation; Settings/Safe Clean AX and
  multi-window behavior; Full Home completion; cancel/close/reopen; fresh-default Quick scan; and
  future-settings recovery with preserved bytes and withheld controls.
- The 30-sample visible-window observation is diagnostic only. It records stable sampled RSS,
  physical footprint, no sampled children, and no `nettop` process rows after a loopback positive
  control. It does not close hidden/background duration, representative workflow traffic,
  short-lived child, scan-peak, reference-hardware, or performance gates.
- The frozen privacy inventory maps direct APIs to fields and purposes and now includes the runtime
  host's guarded `lstat`. Existing manifest values were not broadened to hide unresolved file-root,
  filesystem-locality, or volume-identity reasons.

### R14 package checkpoint

The recorded ZIP/DMG inspection is a valid immutable checkpoint for source `b4acfff`, including
checksums, architecture/resource parity, strict ad-hoc signature verification, empty entitlements,
and truthful absence of hardened runtime. It explicitly predates this continuation. It is not a final
package for the reviewed source and does not establish Gatekeeper, supported-OS install/upgrade/
uninstall, signing/notarization, publication, or distribution acceptance.

## Evidence boundaries and remaining gates

Source, unit/model, current-host native, build, and checkpoint package evidence do not replace:

- supported real Xcode producer/owner mapping and producer-held exclusion;
- positive effect lifecycle, recovery, cancellation, contention, and accepted adapter semantics;
- human VoiceOver evaluation and the original AX blank-list reproduction on supported macOS;
- 8 GiB Apple Silicon, 8 GiB Intel, macOS 14, and current stable supported-host evidence;
- reference performance, twenty active scan/cancel cycles, measured cancel latency, and build
  overhead;
- representative app-and-child traffic and final privacy-reason resolution;
- final immutable package provenance, production signature/entitlements/hardened-runtime inspection,
  install/upgrade/uninstall recovery witnesses, Gatekeeper path, notarization, or release.

No waiver, fake terminal record, cleanup acceptance, signing change, publication, or release is
approved by this review.


## Resumed consolidated review — 2026-09-19

One Astra High code reviewer inspected the delta after `5bfd8ea` through the resumed
working tree, including the final corrections. This was code review, not a repeat of
the already-completed plan review. Source specification and quality verdicts: **PASS
for the contained partial continuation**, with runtime and aggregate acceptance pending.
No additional substantive source defect remained after the following corrections:

- FR-12 (Important): fully visible Settings metadata used low-contrast secondary text.
  Retained green3 screenshot review supported changing only the metadata role to primary;
  the existing model contract was updated, and the native audit remains unfiltered.
- FR-13 (Important): active-cancel-20 validation treated `indexWatchActive` as an integer.
  It is now scenario-specifically Boolean; the existing pure self-test accepts a valid
  cycle document and rejects integer 0 for that field.
- FR-14 (Medium): workflow-traffic forced Debug while accepting a Release artifact.
  It now derives and validates the configuration from that exact artifact path.

The hidden-lifecycle correction starts via a fixed runtime-only button after XCTest
launch/path acquisition and waits at most five seconds for the actual hidden state.
It grants no authority and leaves fixed durations, policy/denial/work/cleanup checks intact.
The early-Cancel generation correction and the semantic Settings container labels were
accepted at source level. Retained earlier review findings above remain historical.

Following the user's “don't overtest” instruction, execution is limited to one focused
120-second hidden-off capture and one final aggregate. The 600-second negative capture,
50k/20-cycle measurements and representative traffic are left explicitly unverified;
no reference, authorized-background, physical peak, human or release gate is inferred.


Runtime disposition after the single final pass: the 120-second hidden-off capture passed.
The compact native audit returned XCTest code -56 (“Audit failed to complete in time”)
before yielding an accessibility result. It remains unaccepted; source review does not
turn that timeout into a pass. No retry follows the user's testing limit. Final counts
and packaging evidence are recorded in the resumed verification report.
