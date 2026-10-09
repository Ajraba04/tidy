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
