# Settings accessibility row boundaries

Date: 2026-09-18

Baseline commit: `e6eee36b38e910990c6482951ffe367f12942724`

Scope: presentation-only `TidyUITestHost` Settings fixture on the current Apple Silicon host.

## Reproduction

A fixture built from a `git archive` of the baseline commit reproduced the Settings
accessibility corruption through the native macOS accessibility tree:

- The Feature Headroom title, checkbox, and metadata all exposed
  `settings.row.feature.headroom`.
- The metadata value repeated Default, Effective, Source, and Rule seven times.
- The same metadata node then absorbed Feature Build Prep and Feature Projects content.

This established a SwiftUI accessibility-tree boundary problem in
`RegistrySettingRow`, rather than a copy or settings-model problem.

## Change

Each registry row is now an accessibility container with its existing
`settings.row.<setting-id>` identifier and label. The interactive editor remains a
separate child with `settings.control.<setting-id>`. The metadata stack ignores its
individual text descendants and exposes one synthesized
`settings.metadata.<setting-id>` element with the existing label, value, and hint.
The visual layout, strings, and submission closure are unchanged.

## Native verification

The corrected fixture exposed separate native row containers for the three visible
rows. Native UI automation also resolved the named metadata nodes:

- `settings.row.feature.headroom` container containing
  `settings.control.feature.headroom` and `settings.metadata.feature.headroom`.
- `settings.row.feature.buildPrep` container containing
  `settings.metadata.feature.buildPrep`.
- `settings.row.feature.projects` container containing
  `settings.metadata.feature.projects`.

The visible Headroom metadata contained only its own Default, Effective, Source,
Rule, help, consequence, and availability details; it did not absorb either following
row. Activating the Headroom checkbox incremented `fixture.settings.submissions` from
0 to 1, confirming that container grouping did not consume editor interaction.

Verification used an isolated committed-source snapshot at
`/private/tmp/tidy-settings-ax-red.uRqFec/source` with separate derived-data paths and
two build jobs:

```text
xcodebuild -project Tidy.xcodeproj -scheme TidyUITestHost -configuration Debug \
  -derivedDataPath /private/tmp/tidy-settings-ax-red.uRqFec/DerivedData -jobs 2 \
  build CODE_SIGNING_ALLOWED=NO
Result: BUILD SUCCEEDED

xcodebuild -project Tidy.xcodeproj -scheme TidyNativeUITests -configuration Debug \
  -derivedDataPath /private/tmp/tidy-settings-ax-red.uRqFec/DerivedDataSigned -jobs 2 test
Result: 2 tests, 0 failures; TEST SUCCEEDED

xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -derivedDataPath /private/tmp/tidy-settings-ax-red.uRqFec/DerivedDataModel -jobs 2 test \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsAccessibilityFocusAndSemanticContrastContract \
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests/testSettingsAccessibilityTextLayoutRendersAtMinimumWidth
Result: 2 tests, 0 failures; TEST SUCCEEDED
```

The UI-test runner used Xcode's existing local ad-hoc signing behavior. No project
signing configuration, entitlements, permissions, or production authorization were
changed.

## Evidence boundary

This is native AX automation evidence for the presentation-only fixture. It does not
accept human VoiceOver output, the production R13 accessibility journey, other
appearance or hardware configurations, packaging, notarization, or release readiness.
