# R13 production-scene runtime composition and current-host native evidence

Date: 2026-09-19

Scope: safe production UI dependency injection and native runtime journeys on the current
32 GiB Apple M1 Max running macOS 27.0 (build 26A428). This is current-host diagnostic and
functional evidence. It is not reference-hardware, oldest-supported-OS, Intel, human VoiceOver,
distribution, signing, notarization, traffic, or release acceptance.

## Compile-scoped composition

`TidyProductionRuntimeHost` compiles the same `Tidy` app and production scene sources with the
target-only `TIDY_RUNTIME_TEST_HOST` condition. Its bundle identifier is
`io.github.ajraba04.Tidy.ProductionRuntimeVerification`, it is `SKIP_INSTALL`, and it has no
configured production entitlements or hardened-runtime requirement. The normal `Tidy` target has
no runtime-host compilation condition, launch-argument parser, synthetic path factory, fixture
control window, or cleanup action.

The dedicated target accepts only three fixed scenarios: acknowledged revision 1 settings,
fresh defaults with no settings file, and a fixed unsupported-schema settings document. It never
accepts a filesystem path, home, settings bytes, journal location, authority value, or capability
from an argument or environment variable. The normal target does not compile this selector.
The shared entry point also checks the exact bundle identifier on both sides of the compilation
condition: a runtime-verification bundle built without its flag receives no paths, and a normal
bundle accidentally built with the flag receives no paths. Either project-drift direction reaches
the storage-unavailable screen before consulting the real home.

Each launch calls `mkdtemp` directly under the canonical no-follow-safe temporary directory. The
fresh 0700 root contains separate synthetic `home`, settings, and journal locations. Home holds a
fixed exact-byte witness, a bounded 5,120-file Full Home fixture, and a small canonical Quick root.
All descendants are created inside the freshly owned root. Post-creation failures validate and
remove the exact root. UI tests opt into a fixed cleanup-on-termination behavior; the host disposes
monitor/scan resources, validates canonical temp prefix, randomized name prefix, owner, directory
type, and mode, removes its own root, and quits. The test then verifies disappearance. Twenty exact
owner-only roots left by earlier RED/diagnostic runs were validated and removed; zero remained.

Production bootstrap consumes the injected `AppStoragePaths` unchanged. The settings store reads
`paths.settings`; coordinator/admission storage reads `paths.journal`; the policy bridge, scope
authority, monitor volume, clean environment, and scan environment read `paths.home`. The native
tests read the attested actual paths and exact witness bytes. They do not accept a fixture label as
proof. Full Home uses the production consent dialog and the complete report contains the unique
synthetic fixture root. The fresh-default Quick scan reports the seeded canonical Quick root while
`config.json` remains absent before and after the scan.

`CapabilityRegistry` remains the fixed all-deny registry. Both visible and accessibility
authorization attestations compute the result from every catalog action. The Safe Clean production
window exposes a disabled `Clean Now`; no target condition changes coordinator, engine, settings,
scan, monitor, or effect authorization.

## Native result

Command:

```text
xcodebuild -quiet -project Tidy.xcodeproj \
  -scheme TidyProductionNativeUITests -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/tidy-r13-resume-xcode-final2 \
  -resultBundlePath /tmp/tidy-r13-resume-final2-native.xcresult \
  -jobs 2 test
```

Result: exit 0, **6/6 tests passed**, zero failures/skips, 105.791 seconds for the test
operation. `check-test-results.py` accepted the result bundle with minimum 6 and all six exact
required cases:

- acknowledged storage/home/settings/journal/witness, isolation, PID, and all-deny attestation;
- production Settings and Safe Clean, distinct row/editor/metadata AX endpoints, long search text,
  keyboard Command-W close/reopen, two simultaneous production windows, and disabled cleanup;
- production Full Home consent, complete scan, actual synthetic-root result, unchanged witness;
- production Full Home cancel, close, reopen, retained cancelled state, unchanged witness;
- store-bound fresh defaults, production Quick scan, actual Quick-root result, no settings write;
- unsupported-schema production recovery, exact original bytes preserved, no scan/cleanup controls.

The first new XCTest attempt built but timed out before assertions while enabling automation mode.
A later behavioral RED reached the production recovery screen because Foundation rewrote canonical
`/private/var` to the `/var` root symlink; the production no-follow loader correctly rejected it.
The composition now retains the POSIX-canonical spelling. Subsequent REDs caught AX identifier
clobbering, duplicate Touch Bar confirmation matches, automatic window tabbing, state restoration,
an oversized synthesized keyboard event, and sandbox-incompatible runner-side cleanup. None was
converted into a product authorization exception or host permission change.

## Build and isolation checks

- `xcodegen generate` followed by `python3 scripts/verification/check-project.py`: pass; 10 target
  phases match, all test files are included, and runtime composition is restricted to its host.
- Normal app build: `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug
  -destination 'platform=macOS,arch=arm64' -derivedDataPath
  /tmp/tidy-r13-resume-production-build -jobs 2 build CODE_SIGNING_ALLOWED=NO`: exit 0.
- Normal target build settings contain no `TIDY_RUNTIME_TEST_HOST`; the runtime host has
  `DEBUG TIDY_RUNTIME_TEST_HOST`.
- Recursive binary scans found each of `tidy-production-runtime-`,
  `runtime.fixture.cleanupAndQuit`, `--tidy-runtime-fresh-defaults`, and
  `RuntimeTestComposition` in the runtime host and none in the normal `Tidy.app`.
- `git diff --check`: pass before final documentation/commit preparation.

XCTest locally signs the runtime host and injects UI-testing entitlements, including test-manager
mach lookups and a read-only absolute-path exception. The project target itself configures no code
signing entitlements. Automatic window tabbing is disabled only in the runtime host so simultaneous
production windows remain independently observable. These facts make the host suitable for native
functional verification, not a distribution artifact or entitlements/hardened-runtime proof.

## Gates that remain open

- Human VoiceOver audio/navigation evaluation and the original AX blank-list endpoint on supported
  macOS releases.
- Physical 8 GiB Apple Silicon, 8 GiB Intel, and macOS 14 runtime evidence.
- Hidden/interactive RSS and CPU limits, physical footprint, 50k/100k reference timing, cancel
  latency instrumentation, twenty-cycle leak bounds, and paired background-build overhead.
- Controlled representative app/child traffic observation and complete privacy API/reason mapping.
- Production signing, hardened-runtime behavior, packaged install/upgrade/Gatekeeper, notarization,
  and release acceptance.

Model, source, build, and current-host native results do not close those gates.
