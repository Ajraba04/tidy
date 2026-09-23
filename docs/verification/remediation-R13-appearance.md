# Production appearance verification — 2026-09-19

Status: corrected native matrix passed 4/4 (133.183 seconds), zero failures/skips; captured Settings and no-results layouts were visually checked in all four appearances.

The dedicated `TidyProductionRuntimeHost` applies four fixed presentation combinations to the actual production scenes: light/standard/normal motion, dark/standard/normal motion, light/increased contrast/reduced motion, and dark/increased contrast/reduced motion. Only the guarded runtime target recognizes these arguments; no preferences, permission, signing policy or system accessibility setting is changed.

`RuntimeTestAppearance` applies the chosen SwiftUI color scheme and environment. The installed SDK exposes contrast and Reduce Motion as public read-only getters with underscored writable environment keys. The disposable host uses those writable keys; the on-screen attestation reads the public getters actually delivered to the view. This is controlled view-environment coverage, not evidence of macOS setting delivery, animation timing, a supported production use of underscored APIs, or human VoiceOver acceptance. All declarations and call sites are guarded by `TIDY_RUNTIME_TEST_HOST`.

Each native journey validates actual environment values, synthetic storage isolation and live mutation denial; opens real Settings; verifies separate enabled/hittable editor and nonempty metadata endpoints; captures the window; enters 88 characters in search; closes with Command-W; and opens Safe Clean with the real disabled Clean Now button inside the window. Screenshots of Settings, long-search and Safe Clean are retained in the XCTest result bundle. Cleanup uses the existing host-side validated-root removal and verifies the root disappears.

The first 12 exported screenshots are retained at `/private/tmp/tidy-r13-appearance-images-20260919`, with the original result `/tmp/tidy-r13-appearance-20260919.xcresult`. Visual review found that the sibling profile workflow reserves most of the compact Settings window, compressing the registry scroll viewport to a fragment of one row. Metadata and the no-match explanation exist in AX but are visibly clipped. Therefore the initial functional passes do not establish layout acceptance. The regression now requires the metadata and no-match text rectangles to fit inside the actual scroll viewport. The focused RED run failed as intended: viewport height42.5 points versus metadata height130 points (`/tmp/tidy-r13-appearance-layout-red-20260919.xcresult`). Production Settings now owns the outer vertical ScrollView under its fixed header, while the extracted registry content keeps natural height and the existing standalone fixture wrapper remains intact. The corrected four-case result is `/tmp/tidy-r13-appearance-layout-green-20260919.xcresult`; 12 screenshots and their manifest are retained at `/private/tmp/tidy-r13-appearance-layout-green-images-20260919`. The eight corrected Settings/no-match images visibly show the formerly clipped content. Safe Clean remains disabled in all four cases.

No numerical contrast ratio or entire appearance/accessibility matrix is inferred from these checks. Pixel review, oldest-supported OS, host preference delivery, all workflow states and human assistive-technology evaluation remain separate evidence.


## Compact and automated accessibility continuation

The corrected Settings content also renders at an actual 480-by-520-point content size (480-by-552-point window frame). XCTest edge drags did not change the frame even though read-only AppKit inspection showed a resizable window with zero minimum-size constraints. Those gesture attempts are retained; they are not evidence that the product cannot resize. A fixed compile-scoped control now applies this one content size to the exact Settings window, with actual frame assertions. It accepts no supplied size or window identity.

The compact test adds physical metadata-height/row-height bounds, full metadata containment in the window and scroll viewport, and XCTest contrast/sufficient-description audits. The first audit identified an unnamed, window-sized AppKit hosting group, distinct from the labeled setting rows. Adding only a SwiftUI container label created a correctly labeled child but left that outer AppKit group unnamed. The current correction targets the public `NSWindow.contentView` accessibility label and preserves separate child elements. Its focused verification is pending; no audit finding is filtered out.

Retained compact evidence includes the initial missing-project-member build, a same-cache concurrent-build lock failure, the two unsuccessful drag attempts, geometry inspection, and the actual 480-point/audit failures. These are harness/functional failures with separate causes, not passing aggregate results. The successful fixed-size capture is `/tmp/tidy-r13-compact-fixed-input-20260919.xcresult`; the detailed AX tree is retained in `/private/tmp/tidy-r13-compact-ax-details/`. The unsuccessful SwiftUI-only label attempt is `/tmp/tidy-r13-compact-ax-labelled-20260919.xcresult`.

Native appearance cleanup now uses an XCTest teardown block registered before launch. An assertion with `continueAfterFailure = false` can bypass Swift `defer`; the retained AX failure demonstrates that XCTest teardown still invoked the exact host cleanup, waited for termination, and verified root removal. This does not promise cleanup after a process crash or unidentifiable fixture.


### Accessibility checkpoint before external measurements

The public AppKit content-view label correction passed its original audit finding: the next retained run identified `settings.search` instead. An explicit Search settings accessibility label corrected that field. The next run (`/tmp/tidy-r13-compact-ax-search-20260919.xcresult`) reached an unnamed scroll-document container, with frame445-by884.6 points, which remains under diagnosis. This checkpoint is intentionally **not** compact-audit acceptance: the ordinary verifier requires the new compact case and cannot pass until this remaining finding is resolved. Independent hidden-monitor measurements may use a frozen checkpoint without opening Settings; their exact artifact and source are recorded separately.


The first scroll-document correction adds a named semantic content group plus a public NSScrollView document-label bridge. The focused run `/tmp/tidy-r13-compact-ax-scroll-20260919.xcresult` still reports an unnamed `Other` container at the scroll-document bounds. This reviewed source checkpoint is retained for exact independent-observer provenance; the compact audit remains RED and its remaining container is under diagnosis. The audit is not filtered, and final verification must still run and pass the exact compact case.


### Bounded compact accessibility diagnosis continuation

A fresh public XCTest hierarchy trace is retained at `/tmp/tidy-r13-compact-public-trace-20260919.xcresult` and `/tmp/tidy-r13-compact-public-trace-20260919.log`. It reproduced the description failure in 17.708 seconds and showed the exact path `ScrollView` → `Other` labelled `Settings content` → same-frame unnamed `Other` → independently exposed setting rows, checkbox and metadata. This established that the remaining element was inside the labelled outer SwiftUI content container. The temporary trace instrumentation was removed after capture.

The first bounded hypothesis removed the outer semantic wrapper while retaining the AppKit document bridge. `/tmp/tidy-r13-compact-ax-green2-20260919.xcresult` remained RED, one test with one failure in 18.614 seconds. Its failure attachment showed two same-frame unnamed `Other` elements, contradicting the claim that the public AppKit bridge labelled the exposed scroll document.

Source inspection matched those two elements to the two intentional nested `LazyVStack` containers: the production settings content and `RegistrySettingsContent`. The second and final bounded hypothesis labels both containers with SwiftUI `.contain` semantics and removes the ineffective AppKit bridge. `/tmp/tidy-r13-compact-ax-green3-20260919.xcresult` advanced past the unnamed-container finding. Its failure path shows both `Settings content` and `Settings registry` labels, followed by the independently exposed `settings.row.feature.headroom` group and `settings.metadata.feature.headroom` static text.

The compact case remains RED: one test with one failure in 16.859 seconds. The unfiltered audit now reports `Contrast failed` for `settings.metadata.feature.headroom`, frame 445 by 162 points, with the detail `Contrast failed for Default: On. Effective: On. Source: Built-in. Rule: On or off`. All pre-audit physical containment checks and the separate enabled/hittable checkbox and metadata queries completed before that finding. Teardown still invoked fixture cleanup and waited for the runtime host to terminate. Per the two-hypothesis bound, no contrast patch or further GUI run was attempted; this newly exposed contrast finding remains a separate unresolved accessibility seam for review.


### Consolidated review correction

The reviewer inspected the retained green3 failure screenshot (`/tmp/tidy-review-contrast-element.png`): fully visible metadata is gray on white. The controller changed only `SettingsVisualContract.metadataRole` from secondary to primary text, retaining headline/body hierarchy and all semantic endpoints. The existing model contract assertion now requires that role. No further exploratory compact run was made; the unchanged unfiltered compact case will run once in final aggregate verification. Until that result, compact acceptance remains pending.


### Single final aggregate outcome

The resumed final verifier ran the unchanged compact audit once from the corrected
source. Its pre-audit compact geometry, metadata and independent-checkbox assertions
completed, but XCTest returned `com.apple.xcode.xctest.accessibilityAudit` code -56,
“Audit failed to complete in time”, on the Settings audit before producing any issue
result. Test duration was 45.166 seconds including teardown. The unfiltered audit
therefore remains **NOT ACCEPTED**: neither a contrast pass nor an unnamed-container
regression is inferred from a tool timeout. Per the user's “don't overtest” instruction,
no retry or additional audit run follows.

Evidence: `/private/tmp/tidy-resume-verification-2i64nn35/production-native-ui.log`
and its `production-native-ui.xcresult` bundle. Earlier green3 description progress
and contrast failure remain historical evidence; the screenshot-supported primary
text correction is source-reviewed but still lacks a completed final native audit.


### Later bounded continuation

The subsequent resume diagnosed two audit-fixture defects and introduced a reviewed,
strict geometry classification only for exact contrast issues wholly outside every
app window. All findings are retained. Description/visible/partially visible findings
remain failures. The fixture also arranges windows without overlap. This explicitly
supersedes the earlier blanket-unfiltered handler policy; it does not weaken visible
contrast acceptance. The final focused case still fails on the inactive auxiliary
window's native title and never reaches Clean's audit. See
[window-scope evidence](remediation-R13-audit-window-scope.md). No further test loop ran.
