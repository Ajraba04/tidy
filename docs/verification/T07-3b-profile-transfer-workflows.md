# T07.3b Profile, transfer and reset workflows — verification

Date: 2026-08-28

## Automated evidence

- `swift test --jobs 2 --filter SettingsWorkflowTests`: 6 tests passed.
- Relevant core compatibility partitions passed: `SessionProfileTests` (20),
  `SettingsTransferTests` (28), `SettingsProfilePersistenceTests` (25),
  `PolicyDefaultsTests` (4), and `PolicyResolutionTests` (12).
- `xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -destination
  'platform=macOS,arch=arm64' -parallel-testing-enabled NO -jobs 2 test
  -only-testing:TidyAppModelTests/SharedSettingsWiringTests
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO`: 74 tests passed,
  zero failures.
- `xcodebuild -project Tidy.xcodeproj -scheme TidyUITestHost -destination
  'platform=macOS,arch=arm64' -parallelizeTargets -jobs 2 build
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO`: succeeded.
- The equivalent `Tidy` scheme build succeeded.
- `plutil -lint Tidy.xcodeproj/project.pbxproj`, localization JSON parsing, and
  `git diff --check` passed. No project-file edit was required.

The automated suite covers profile lifecycle and monotone updates, two-window
revision conflicts/replay, portable transfer taxonomy and issued-token
accounting, bounded file reads, generation-safe cancellation, exact
per-restriction reset consent, immutable reset exclusions, descriptor coverage
and whole-surface submission lock, localization, accessibility metadata,
deterministic fixture rendering, and zero work on open.

## Test-integrity amendment

The task card records the dated correction from project-invalid
`scan.requestedWorkers` to project-capable `cleanup.inactiveDays` in the
immutable-project reset fixture. Assertions and expected behavior were not
weakened.

## Deliberately unclaimed physical/manual gates

Still pending separate physical/manual verification: VoiceOver and keyboard
dialog focus; real `NSOpenPanel`/`NSSavePanel` security scope on macOS 14;
light/dark contrast inspection; 8 GiB cold-open and worst-case 1 MiB/50-profile
CPU, RSS, latency and cancellation measurements; and Intel validation. T22.3,
T07.3d, T22.4, packaging, signing, notarization, DMG and release remain out of
scope.
