# T07.3a registry-driven Settings UI verification

Date: 2026-08-28

## Result

The bounded T07.3a foundation is implemented inside the approved allowlist. It adds an exhaustive presentation registry, localized Basic/Advanced Settings surfaces, shared-`AppConfigStore` editing, deterministic fixture-host coverage, zero-work-on-open source proof, and accessibility/performance contracts. Profile workflows, import/export UI, selective reset, publication, and release remain outside this checkpoint.

Final adversarial source review: **Approved** after two test-first correction rounds.

## TDD evidence

- Initial core RED: `swift test --package-path TidyCore --jobs 2 --filter SettingsPresentationTests` failed to compile on the missing `SettingsPresentation*` APIs.
- Initial app RED: the focused `TidyAppModelTests` build failed to compile on the missing Settings projection/control APIs.
- First review RED: focused compilation failed on the missing section-aware rows overload and `.notApplicable` API.
- Final review RED: focused compilation failed on the missing integer-draft, explicit empty-state, and accessibility projection APIs.
- No test was weakened. The existing dynamic-localization fixture was corrected to supply the newly binding-required consequence effect argument in addition to dynamic identity.

## Final automated verification

- `swift test --package-path TidyCore --jobs 2 --filter SettingsPresentationTests`
  - PASS: 4 tests, 1 suite, 0 failures (0.287 seconds).
- `xcodebuild ... test -only-testing:TidyAppModelTests/SharedSettingsWiringTests`
  - PASS: 51 tests, 0 failures (10.454 seconds in the final containing run).
- `xcodebuild ... -scheme TidyAppModelTests ... test`
  - PASS: 69 tests, 0 failures (10.392 seconds).
- `xcodebuild ... -scheme TidyUITestHost ... -jobs 2 build CODE_SIGNING_ALLOWED=NO`
  - PASS: `BUILD SUCCEEDED`.
- `xcodebuild ... -scheme Tidy ... -jobs 2 build CODE_SIGNING_ALLOWED=NO`
  - PASS: `BUILD SUCCEEDED`.
- `plutil -lint Tidy.xcodeproj/project.pbxproj`
  - PASS: OK.
- `python3 -m json.tool Tidy/Resources/Localizable.xcstrings`
  - PASS. Catalog has 128 static consequence effect placeholders and five dynamic positional identity/effect templates.
- `git diff --check`
  - PASS.

Compatibility partitions run during this checkpoint:

- `PolicyDefaultsTests`: 4/4 PASS.
- `PolicyResolutionTests`: 12/12 PASS. The card's `PolicyResolverTests` filter selected no tests; the actual suite name is `PolicyResolutionTests`.
- Ordinary core partition excluding process-heavy suites: 439 tests in 50 suites PASS.
- `SettingsProcessAcceptanceTests`: 3 tests in 1 suite PASS.
- `BoundedProcessRunnerTests`: 21 tests in 1 suite PASS (29.254 seconds).
- A combined full-core run had one timing-sensitive `BoundedProcessRunnerTests.existingPublicRunnerUsesAggregateReplacementGate` failure; that exact test and then its complete 21-test suite passed in isolation. Full-core combined GREEN is therefore not claimed.

## Integration correction

Replacing the legacy `SettingsView.swift` removed three type names still used by Onboarding. Because Onboarding is outside the card allowlist, minimal read-only compatibility views for those existing names remain in `SettingsView.swift`. They show already-stored values only and perform no discovery, process, persistence, or authority work. This was the only genuine card integration correction.

## Evidence boundary and remaining gates

Automated evidence proves source/unit projection behavior, deterministic rendering at 480 points and accessibility text size, semantic system color-role use, stable accessibility IDs/labels, focus ordering, exact registry coverage, fail-closed editing, and absence of on-open work triggers.

The following remain separate physical/manual acceptance gates and are not claimed here:

- VoiceOver reading/editing and Tab/Shift-Tab behavior on a physical Mac.
- Light/dark visual contrast inspection.
- macOS 14 compatibility run.
- Cold-open CPU/RSS/latency measurement on a physical 8 GiB low-spec Mac.
- Intel Mac verification.
- T07.3b profile CRUD/activation/diff/import/export/reset workflows.
- Signing, notarization, DMG creation, GitHub publication, or customer release.

