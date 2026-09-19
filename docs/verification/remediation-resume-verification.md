# Resumed remediation verification — 2026-09-19

Status: **verified partial checkpoint; required native audit NOT ACCEPTED**.
Current advertised application **NO-GO**; full program **INCOMPLETE**.

Resumed from `ca24965a0e91f5e433d3ec5c18c259ba07ce6c27` in the existing isolated
`codex/remediation-20260917` worktree. No change to main, producer requirements,
background authority, mutation quarantine, signing policy or publication authority.

## Changes and review

- Label both Settings content containers with ordinary SwiftUI semantics and remove
  the ineffective AppKit bridge. Child controls and metadata remain independent.
- Use primary text for metadata after the retained screenshot demonstrated gray-on-white
  contrast failure; retain the unfiltered native audit and existing model contract.
- Start the fixed hidden observation after XCTest launch, then await the actual hidden
  state with a five-second bound instead of assuming one yield completes hiding.
- Correct cycle JSON Boolean validation and make workflow traffic use its supplied
  artifact's Debug/Release configuration. Existing pure harness self-tests passed.
- Refresh direct API inventory/purposes and reconcile stale review/evidence headlines.

One consolidated Astra High code review found three substantive issues, all corrected.
Its source specification/quality verdicts are PASS for the contained partial scope;
that is not runtime or release approval. The earlier single plan review was not repeated.

## Single final verification pass

Command: `TIDY_VERIFICATION_OUTPUT=/private/tmp/tidy-resume-verification-2i64nn35 bash scripts/verification/verify.sh`.
Final script exit: **65**, at the production-native suite. No retry was run.

| Gate | Result |
| --- | --- |
| Project generation, source privacy controls, observer self-tests, API inventory | PASS |
| Core | 701 tests / 69 suites passed, 331.245 seconds |
| Separate process-cap fixture | 1 passed, 0.528 seconds |
| App models | 144 passed, 0 failed/skipped, 62.892 seconds |
| Presentation native | 2 passed, 0 failed/skipped, 20.135 seconds |
| Production native | 10 passed / 1 failed / 0 skipped, 349.036 seconds |
| Frozen build/verification inputs | All 241 hashes unchanged across verification |
| Aggregate normal Release stage | Not reached because the required native case failed |

The sole native failure is the compact accessibility audit. Geometry, metadata and
independent-control assertions completed, but XCTest returned accessibilityAudit code
-56, “Audit failed to complete in time”, before yielding an audit result. This is neither
a contrast pass nor evidence of a renewed description failure. The complete failed
result bundle and log are retained; no threshold/filter/skip was added to hide it.
The other four appearance cases and all six production-scene journeys passed.

Logs and result bundles are under `/private/tmp/tidy-resume-verification-2i64nn35/`.
Exact tracked source/verification hashes are in `remediation-resume-inputs.json`.
The older `remediation-core-inputs.json` remains the historical checkpoint it describes.

## Focused hidden-off result

The controller separately built the runtime host in Release, verified its compiled
fixture boundary, and ran exactly one complete externally observed 120-second capture.
Result: native 1/1 passed, 121 samples over 120.003 seconds; ready/final actual hidden
state and zero timers, leases and scan work; mutation denial retained; guarded fixture
cleanup verified. Source WIP and artifact hashes were unchanged during that capture.
Evidence: `/private/tmp/tidy-r13-observation-81azbpn5/`; detailed limits and metrics in
[hidden resume](remediation-R13-hidden-resume.md).

## Explicit remaining boundaries

The user's “don't overtest” instruction ended exploratory retries and longer captures.
The 600-second negative observation, 50k/20-cycle measurements and representative
workflow traffic remain unverified. Authorized background/paired-build gates still
require the real local authority workflow. Human VoiceOver, hardware/OS/reference
performance, exact privacy-purpose classification, supported producer exclusion and
positive effect/recovery delivery, and actual installation/upgrade/uninstall remain
open under the unchanged binding plan.

Final-source local packaging from `1782b4d` built and passed bounded inspection: both
architectures, strict ad-hoc signature, resources, runtime-marker exclusion, ZIP/DMG
parity and disposable copy/replace/remove witness. Stable artifacts are in
`dist/remediation-1782b4d/`; exact hashes and boundaries are in
[R14 package evidence](remediation-R14-resume.md). This success cannot turn the failed
native gate into release approval. No further tests followed the single aggregate.


## Subsequent focused continuation

The next resume made only test/fixture changes and ran the existing compact case three
times (diagnosis plus two bounded corrections), without repeating this aggregate or
packaging. It isolated off-window screenshot false positives and window occlusion;
the final case remains failed on the inactive verification window's native title.
This report's original counts and exit65 remain unchanged. See
[window-scope evidence](remediation-R13-audit-window-scope.md) for current status.
