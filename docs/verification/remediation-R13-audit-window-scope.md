# Compact audit window-scope correction — 2026-09-19

Status: test-only corrections source-reviewed; final compact case remains **NOT ACCEPTED**.

## Evidence before correction

Resume baseline was `ecf76e7`, with only original untracked audits present and no active
runner. All 241 recorded source/verification inputs matched the previous checkpoint.
One unchanged Debug compact case ran against the existing built fixture, without rebuilding:
`/private/tmp/tidy-compact-resume-ecf76e7.{log,xcresult}`.

It completed the accessibility audit rather than repeating the earlier XCTest -56 timeout.
Its failure was `Contrast failed for Feature Projects`:

| Bounds | Geometry |
| --- | --- |
| Settings window | x414, y256, width480, height552; bottom808 |
| Settings scroll viewport | x430, y405.5, width448, height386.5; bottom792 |
| Reported Feature Projects element | x430, y848.8017578125, width106.5, height17.5 |

The element lies wholly below the window and viewport. Its saved element screenshot
contains the desktop behind the application, not Feature Projects text. The Settings
screenshot shows the earlier primary-metadata correction. This evidence establishes an
off-window contrast false positive; it does not establish why the previous audit timed out.

Exports are retained at `/private/tmp/tidy-compact-resume-ecf76e7-attachments/`:

- `B7C37617-EAC1-4B4F-B820-DA0A3392AA80.png`: captured off-window pixels.
- `1FB6C7A5-5218-4BE2-964C-FB6EC4ED7F13.png`: actual Settings window.
- `6BE68926-BF23-4A95-9298-84840309D4BF.txt`: complete issue description.
- `A0674DB4-05F6-4200-A244-F29440015523.txt`: element ancestry and bounds.

## Narrow classification policy

Apple describes the audit as screen-limited and documents an issue handler for confirmed
false positives in [Perform accessibility audits for your app](https://developer.apple.com/videos/play/wwdc2023/10035/).
The prior blanket-unfiltered handler was the coordinator's verification choice, not a
separate prohibition in the binding R13 product plan. This correction supersedes that
handler only for geometry that cannot contain the app's displayed pixels.

Only an exact contrast issue may be classified as an off-window false positive, and only
with a present element, valid finite positive raw rectangles, a nonempty valid set of
all present app windows containing the subject window, and strict disjointness from
**every** app window. The app-window geometry must remain unchanged during and after
the audit. All exclusions retain the full issue, geometry and hierarchy as attachments
and print an explicit diagnostic.

Description, combined/unknown-type, nil/invalid geometry, visible, partially visible,
edge-touching, and findings visible in another app window still fail. Neither labels
nor known setting IDs are allowlisted. Embedded assertions in the existing compact case
exercise the actual classifier's positive and negative boundaries; no new test case,
retry, delay, timeout or production behavior was introduced.

One bounded Astra High source review caught and corrected two gaps: the first draft
considered only the subject window, and rectangle validation needed raw dimensions to
reject negative rectangles. The final single-file delta passed source review. The
controller's focused run remains the runtime acceptance step.

## Scope and unchanged evidence

The initial handler correction changed only the native test. The subsequent layout
correction also changes `RuntimeTestAppearance.swift`, entirely within the existing
`TIDY_RUNTIME_TEST_HOST` compilation guard.
The previous Core, model, appearance and scene results remain historical evidence for
their unchanged code; the previous aggregate exit65 is not rewritten as a successful
end-to-end invocation. The inspected `1782b4d` packages remain the previously recorded source checkpoint;
no distributed behavior was changed by these two test-only files. No full-suite, long-duration or package rebuild is required for this
test-only correction under the user's “don't overtest” instruction.

Human accessibility, supported hardware/OS, producer/effect dependencies, privacy-purpose,
long performance captures and distribution acceptance remain separate open gates.


## Corrected-handler result and fixture occlusion

The first corrected run (`/private/tmp/tidy-compact-window-scope-20260919.xcresult`)
exercised the classifier assertions and retained three off-all-window contrast findings
as explicit false-positive attachments. It then correctly failed on
`runtime.control.title`, frame (574,312,253.5,23), inside the runtime control window
(554,260,620,572) but covered by Settings (414,256,480,552).

The saved element image shows the Settings section picker (“Features / Scan / Cleanup”),
not “Production runtime verification”, the element named by the audit. This is a second
concrete fixture problem: overlapping test windows cause screen pixels to disagree with
AX ownership. Evidence is in `/private/tmp/tidy-compact-window-scope-attachments/`,
especially `E1D5E2C6-4512-42A7-AE16-5D1E07309092.png` and
`42D353BC-FA8F-4CAB-83A9-131D32121AE8.txt`.

The next correction is confined to the existing compile-scoped appearance host and its
compact test: arrange the two existing windows side by side inside the display's usable
bounds, preserving their sizes, and assert non-overlap before auditing. No occlusion
filter is added. One final focused run is permitted after this correction; further
failures will be retained without another test loop.


## Final bounded result

Source review accepted the non-overlapping arrangement without additional audit
exceptions. The final focused command rebuilt only the affected fixture/test targets
in the retained Debug cache and ran the existing compact case once:
`/private/tmp/tidy-compact-separated-windows-20260919.{log,xcresult}`.
Result: **exit65; 1 test, 1 failure, 0 skips, 25.979 seconds**. No further run followed.

The embedded classifier assertions and Settings geometry, child controls and window
arrangement passed. Both app windows were fully on-screen, size-preserved and disjoint:
Settings (942,33,480,552), control (306,33,620,572). Three wholly off-all-window contrast
reports were retained as classified false-positive attachments.

The unsuppressed failure was the visible native title-bar text
“Tidy Production Runtime Verification”, frame (388,39.689453125,242,17.310546875),
in the inactive auxiliary window. The captured image contains that light-gray title on
white, not desktop pixels or an overlapping scene. The handler correctly did not
classify it as off-window. The Settings audit therefore still fails; the later Clean
audit was not reached, so its new arrangement path is source-reviewed but not runtime
verified. No overall accessibility acceptance is inferred.

Failure exports: `/private/tmp/tidy-compact-separated-failure/`, including
`83CE62B5-5C2A-4128-89E3-7B227AA5C5AC.png` and
`3A44BCC5-4CCD-4186-90BF-02D00A545A1F.txt`.
The next design boundary is separating auxiliary verification controls from the scene
under audit while retaining the existing synthetic-root attestations and cleanup.
No extra ignore rule, title-bar workaround, retry or full suite was added at this limit.

Three focused runs were made in this continuation: unchanged diagnosis, corrected
handler, and corrected arrangement. Core/models/other native cases, long captures and
packaging were not repeated. The earlier aggregate failure and all three focused
failures remain historical evidence. Current product NO-GO/full program INCOMPLETE
remain unchanged.

All 239 other recorded inputs remained unchanged. The two final tested inputs were:

- `Tidy/RuntimeVerification/RuntimeTestAppearance.swift`: `3d12d40d63a8b6eb7e51a08a2381d7fe25b129ec993a61025e2ef9f84a4521ab`
- `TidyProductionNativeUITests/ProductionAppearanceRuntimeUITests.swift`: `9a7d21d830fad4bd74aea39d3b85a0f01140de9635d8ecc055de79b29dc7d89c`


## 2026-09-20 hide/restore correction and user GUI deferral

The earlier arbitrary retry limit was not treated as a permission blocker. The failed
side-by-side workaround was removed. The test-host-only control is now physically hidden
with NSWindow.orderOut during audit and restored through a guarded Runtime Verification
menu, including independent XCTest teardown restoration before fixture cleanup.
Source review and fixture build passed.

The single run at `dist/verification/compact-20260920-4gc9hwff/isolated-audit.xcresult`
finished before the user's GUI deferral:1 test/1 failure,29.891s. It verified that only
Settings remained in the app window list, and menu restoration plus guarded cleanup
completed after failure. The remaining issue was an unnamed Touch Bar element at
(80,0,685,30); no description exclusion was added. Clean's audit was not reached.

The user then instructed: “defer repetitive GUI checks for when am not using the laptop;
focus on the code side”. No GUI runner remained active, and no further GUI run followed.
The compact audit and diagnostic save-dialog checks are queued for a later available
session. Headless code work continued in [R08 diagnostic export](remediation-R08-diagnostic-export.md).
