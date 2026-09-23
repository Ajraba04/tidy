# Traceability, project membership, CI and packaging — source track

**Evidence class:** static source/configuration inspection at `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`. Historical progress claims are cited as claims only; no test, build, release, package, device, or network observation was run by this track.

## Requirement-to-production map

| Requirement family | Design / task authority | Present production path | Status / closure criterion |
|---|---|---|---|
| Confirmation, sealing, quarantine | S01–S02, S15; T01–T02 | `ConfirmedPlan.swift`, `ExecutionCoordinator.swift`, `CapabilityRegistry.swift`, app clean/custom models | Partial. Only one accepted adapter; exercise every UI/forged/direct route at the actual effect boundary. |
| Filesystem containment/accounting | S03, S05–S08; T03 | `PathGuard.swift`, `GuardedFileDeleter.swift`, `ResourcePreflight.swift`, `SizeScanner.swift` | Partial. Use guarded disposable fixtures for replacement/mount/protected-descendant/hard-link cases and capture proof. |
| Recovery/process limits | S04, S11–S13, S16; T04/T08 | `RunJournal.swift`, `MutationAdmissionStore.swift`, `ProcessRunner.swift`, `ProcessSession.swift`, `ProcessJobGate.swift` | Partial. Death/daemon/full-disk/reconciliation proof with the accepted adapter is required. |
| Settings and authority separation | S08, S14; T05–T07/T22 | `SettingsStore.swift`, `SettingsTransfer.swift`, `SettingsWorkflow.swift`, `AppConfigStore.swift` | Partial. Current transfer/store source exists; data-clearing and standing authority are missing. |
| Scan/index/signals | T08–T10 | `ScanSession.swift`, `WorkScheduler.swift`, `ScanIndex.swift`, `SystemMonitor.swift`, `HeadroomView.swift` | Partial. Source and core tests exist; physical reference/device/performance gates remain open. |
| Working set/Build Prep | S09–S10; T11–T13 | no ProjectInventory/CandidateRanker/BuildPrep production module | Fail. Implement then prove uncertainty, ownership, marginal allocation and target-limited execution. |
| Rescue/ecosystem adapters | T14–T20 | legacy catalog/detectors only; no requested typed adapters or Ecosystem UI | Fail. Each inventory/mutation contract needs independent source, fixtures, denial and compatibility proof. |
| Assistance | T21–T22 | no BudgetEvaluator, NotificationPolicy/Broker, MaintenanceRules/Authorization | Fail. Implement default-off consent/hysteresis/revocation contracts and tests. |
| Performance/final handoff | T23–T24 | bounded primitives only; no benchmark/fault harness/settings reference/acceptance record | Fail. Create fixtures/evidence and close every acceptance gate. |

## D19 — actual test membership and CI enforcement

### Project generation and membership

`project.yml` names XcodeGen as the source of truth (`CONTRIBUTING.md:5-19`) and defines three targets: app, `TidyUITestHost`, and `TidyAppModelTests` (`project.yml:10-89`). The generated project names the same three native targets (`Tidy.xcodeproj/project.pbxproj:299-359,387-390`). There is no `TidyUITests` target despite multiple plan cards specifying `TidyUITests/*` (for example T20 at `execution-plan.md:682-689`, T21 at `707-713`, T22 at `731-737`).

The present app-model test target does compile all five on-disk app-model test files: its source phase lists `ConfirmationLifecycleTests`, `RunReportPresentationTests`, `SharedSettingsWiringTests`, `ScanOrchestrationWiringTests`, and `HeadroomViewModelTests` (`project.pbxproj:472-491`). The last two are omitted from `project.yml`'s `sources` list (`project.yml:55-76`) but present in the generated project. This is **generated-project drift**: a future XcodeGen regeneration can silently remove them from membership. It is not proof that the tests did not compile at this baseline.

The configured app-model suite is a unit-test bundle with no app host (`project.yml:77-88`; `project.pbxproj:589-594,626-631`). It compiles selected production view-model/service files rather than the complete app (`project.yml:62-74`). That is appropriate for app-model tests but cannot prove real scene/window/menu wiring.

`TidyUITestHost` is an application target, not a test target (`project.yml:28-53`; `project.pbxproj:299-318`). Its scheme has a Run action (`project.yml:90-93`), and no XCTest UI test bundle exists. Therefore fixture-host acceptance is distinct from native UI automation and human UI acceptance.

`TidyCore/Package.swift:5-25` contains one SwiftPM test target, `TidyCoreTests`, so all Swift files under its declared test target may compile under `swift test`; this audit did not run it. The package excludes its C/Swift helper fixtures from direct source membership (`Package.swift:20-23`), which is expected helper handling, but demands review of the tests that compile/invoke them before using historical counts as acceptance.

### Scheme and CI matrix

Only `TidyAppModelTests.xcscheme` and `TidyUITestHost.xcscheme` are shared. The model scheme explicitly tests only the model bundle (`TidyAppModelTests.xcscheme:26-56`). There is no shared `Tidy` test scheme and no UI-test scheme. CI invokes `swift test` and an app **Debug build** only (`.github/workflows/ci.yml:32-39`); it never invokes `xcodebuild test -scheme TidyAppModelTests`, never launches the fixture host, never runs UI tests, never checks Release, architecture slices, project generation drift, localization, privacy plist, packaging, or static test membership.

The release workflow runs SwiftPM tests and a Release build (`.github/workflows/release.yml:23-30`), then ad-hoc signs or optionally notarizes, creates ZIP/DMG and publishes (`release.yml:52-127`). These operations are intentionally unrun by this audit. The published release path cannot be called verified from source.

### D19 findings and closure

| ID | Severity | Finding | Closure criterion |
|---|---|---|---|
| TRC-D19-01 | High | CI does not execute `TidyAppModelTests` or any UI suite. `ci.yml:32-39` supplies SwiftPM tests plus build only; the real app-model target/scheme exists but is unreferenced. | Add an explicit app-model `xcodebuild test`, establish a production-host/native-UI test target where appropriate, archive result bundles, and require both on PR/release CI. |
| TRC-D19-02 | Medium | `project.yml` excludes two existing model test files although generated `pbxproj` includes them. | Make YAML and generated project identical; CI should generate/compare in a disposable directory and fail drift. |
| TRC-D19-03 | High | TidyUITests referenced by T20–T22 plans do not exist or compile; fixture host is not a substitute. | Create and run the target against the real app/approved synthetic dependencies; record native UI proof separately from human accessibility. |

## D20 — packaging, compatibility, documentation and support

| Item | Source finding | Status / closure |
|---|---|---|
| Deployment/platform | macOS 14 is consistently configured in `project.yml:3-6,10-89`, `Package.swift:5-10`, and generated app configurations `project.pbxproj:706-736`. | Source Pass; oldest supported macOS runtime remains Blocked. |
| Architecture | No explicit app `ARCHS` setting appears in `project.yml` or target configs; CI runner is only `macos-14` (`ci.yml:9-10`). The design requires Intel and arm64 build/device evidence (`design:17-18`). | Partial. Build/inspect both slices and run both hardware gates. |
| Debug/Release parity | Both configurations hold bundle ID, version, hardened runtime, entitlements and deployment target (`project.pbxproj:690-737`); CI checks only Debug, release workflow checks Release. | Partial: source parity is not artifact parity. Build/inspect both; validate app resources/entitlements. |
| Entitlements/sandbox | Hardened runtime is enabled (`project.yml:21-26`; `project.pbxproj:695,720`); entitlement plist is empty (`Tidy/Tidy.entitlements:1-6`). README says sandbox disabled for home/tool access (`README.md:143-145`). | Partial. Inspect final codesign entitlements and least-privilege behavior. |
| Privacy manifest | Manifest declares no collection/tracking and DiskSpace/SystemBootTime reasons (`Tidy/PrivacyInfo.xcprivacy:5-45`). | Partial. Validate final bundle and current vendor reason mapping; source search does not establish zero network. |
| Localization | Project region list is Base/en only (`project.pbxproj:371-377`) and one `.xcstrings` resource is included (`project.pbxproj:257-264`). | Observed scope, not a defect: no additional locale is promised. State supported locales in release support material; any new locale requires plurals/long-text verification. |
| Unsigned install docs | README points users to unsigned instructions (`README.md:118-145`); `UNSIGNED_INSTALL.md:21-31` instructs recursive quarantine removal. The audit prompt prohibits invoking it, and its Gatekeeper/user-data/support implications need human/platform review. | Not tested. Verify signed and unsigned artifacts on supported OS without applying it to real user apps. |
| Release artifacts/provenance | Release creates ZIP/DMG with `ditto`/`hdiutil` but no checksums, SBOM, provenance or artifact verification (`release.yml:97-127`). | Partial/High readiness gap. Publish checksums/provenance and verify contents before release. |
| Cask | `packaging/tidy.rb:1-25` is explicitly a future template and carries `REPLACE_WITH_RELEASE_ZIP_SHA256`. | Not applicable to current distribution; do not present as a usable cask until released checksum/tap proof exists. |
| Local packaging script | `scripts/make-release.sh:21-49` optionally runs `xcodegen generate`, writes repository `DerivedData`/`dist`, ad-hoc signs and creates artifacts. | Not run. It can regenerate the audited project, so it must be exercised only from an isolated copy and compared against `project.yml`. |
| Documentation consistency | README's broad cleanup claims conflict with one accepted effect; product contract is cautious (`PRODUCT.md:7-22`) and design is a planning contract (`design:1-4`). | Fail (same root cause CVG-D01-01). Align docs/UI/registry or complete promised adapters. |

## Closure sequence

1. Reconcile `project.yml` with `Tidy.xcodeproj`, add missing `Tidy` and UI test coverage to CI, and record result bundles.
2. Treat current catalog rows as inventory/quarantined until one-row-at-a-time accepted adapter contracts and production fixtures exist; update README before offering broad mutation claims.
3. Build/inspect Debug and Release arm64/x86_64 artifacts in an external DerivedData path; verify manifest/entitlements/localization/package contents.
4. Run human keyboard/VoiceOver/contrast/long-text journeys and reproduce the retained AX blank-list condition; source identifiers are supporting evidence only.
5. Complete T11–T24 and then rerun the full traceability ledger. Neither source inventory nor historical green counts establishes program completion.

## Exhaustive production-directory, persistence, permission and background-entry inventory

This is an exhaustive inventory of production source directories at this revision; tests and fixture-host source are separately identified. A named source file is an implementation seam, never proof that it ran.

| Area | Complete source membership | Effects / persistence / permission / background significance |
|---|---|---|
| Core Browsers | `Browsers/ChromiumCookieCleaner.swift`, `CookieDomainSuggester.swift` | Local browser inventory/cleaner seam; cookie mutation remains registry-denied. |
| Core Catalog | all `Catalog/CleanCatalog*.swift` (12 extension files plus root) | Defines legacy rows/actions; only DerivedData action pair is allowlisted. |
| Core Detect | `Detect/{ContainerSpaceInfo,GitRepoScanner,GitRootDiscovery,LargestItemsScanner,LaunchAgentsSurvey,ProcessSurvey,RestartReclaimSurvey,SimctlClient,SnapshotLister,StaleNodeModulesScanner,ToolchainDetector,TranscriptPruneScanner,UnclaimedSpaceScanner}.swift` | Discovery only; no T11–T20 typed adapter modules. |
| Core Engine | `Engine/{CleanEngine,DefaultCustomActionExecutors,GitHousekeeper,MemoryReclaimer,RunLog,ScanEngine,SimulatorPruner,SnapshotDeleter}.swift` | Plan creation and legacy effect seams; custom effects are denied except sole adapter route. `RunLog` is optional run-history model, distinct from durable admission. |
| Core Exec | `Exec/{CleanupCommandRunner,ProcessIdentity,ProcessJobGate,ProcessRunner,ProcessSession,ToolLocator}.swift` | Process execution/identity/gating. There is no `BoundedProcessRunner.swift`; the test is named `BoundedProcessRunnerTests.swift`. |
| Core Execution | `Execution/{CapabilityRegistry,ConfirmedPlan,DerivedDataEffectAdapter,ExecutionCoordinator,ExecutionPolicyBridge,GuardedFileDeleter,JournalPOSIXIO,JournalStorage,MutationAdmissionStore,PolicyInvalidationBarrier,ResourcePreflight,RunJournal}.swift` | Confirmation, one allowed effect, journal/admission storage and preflight. There is no `RunRecovery.swift`; recovery behavior is represented by `RunJournal`, `JournalStorage`, `MutationAdmissionStore`, coordinator and tests. |
| Core Measure | `Measure/{ByteFormat,DiskStats,HomeSurvey,MemoryStats,PathDisplay,SizeScanner,SwapStats}.swift` | Local measurements and size accounting. |
| Core Model | all `Model/*.swift` (15 files) | Codable/domain state: action, plan, config, report, identities and environment. |
| Core Monitoring | `Monitoring/{SignalHistory,SystemMonitor,SystemSnapshot}.swift` | Signal sampling/history; any physical background behavior needs runtime evidence. |
| Core Policy | `Policy/{CleanupSettings,ExperienceSettings,FeatureSettings,PolicyDefaults,PolicyResolver,PolicyValidator,ScanSettings,SessionProfile,SettingsEnvelope,SettingsPresentation,SettingsPublication,SettingsStore,SettingsTransfer,SettingsWorkflow,StrictJSON}.swift` | Sole typed policy/store/transfer subsystem. `SettingsStore` is the durable preferences path; imports are intended inert. |
| Core Safety | `Safety/{AppRunningCheck,PathGuard,PermissionBroker}.swift` | Activity checks, containment and permission abstraction. No TCC consent observation was run. |
| Core Scanning | `Scanning/{BoundedTraversal,ScanIndex,ScanInvalidation,ScanSession,WorkScheduler}.swift` | Shared scan scheduling and index persistence; no physical FSEvents/sleep proof in this track. |
| App Clean/Custom | all `Tidy/Clean/*.swift`, `Tidy/Custom/*.swift` | Plan/review/results and individual Custom selection/presets. |
| App execution | `Tidy/Execution/AppExecutionServices.swift` | Shared app bootstrap, coordinator and scan route. It constructs scan environments with `detectedTools: []` at lines 64 and 152. |
| App Headroom/Menu/Onboarding/Scan | all Swift files under those four directories | Present user surfaces, timers/model projection and local tool-detection onboarding. Onboarding alone calls `ToolchainDetector.detect()` (`OnboardingViewModel.swift:29-32`). |
| App Settings | `Tidy/Settings/{AppConfigStore,SettingsView}.swift` | Shared settings bridge and registry/profile/transfer/reset UI. |
| App root/resources | `Tidy/TidyApp.swift`, `Tidy/PrivacyInfo.xcprivacy`, `Tidy/Tidy.entitlements`, `Tidy/Resources/Localizable.xcstrings`, Assets | Scenes/resources/configuration; entitlement plist is empty. |
| Test-only host | `TidyUITestHost/TestHostApp.swift` | Fixture application, not compiled into the Tidy application source phase or a UI test bundle. |

### Sole accepted adapter is unavailable in the shipped scan/clean path

`CapabilityRegistry` allowlists only the DerivedData `deleteContents` pair (`TidyCore/Sources/TidyCore/Execution/CapabilityRegistry.swift:12-16`), and `DerivedDataEffectAdapter` additionally requires the Xcode DerivedData item/path (`DerivedDataEffectAdapter.swift:18-48`). However, `AppExecutionServices` constructs `CleanEnvironment` with `detectedTools: []` (`Tidy/Execution/AppExecutionServices.swift:64-66,152-154`), while `CleanEngine` marks tool-gated items unavailable when their toolchain is absent (`TidyCore/Sources/TidyCore/Engine/CleanEngine.swift:68-78`). This makes the sole accepted adapter unavailable in the shipped app route described here. The onboarding model detects tools separately (`Tidy/Onboarding/OnboardingViewModel.swift:29-32`), but this source audit found no transfer of that set into `AppExecutionServices` clean/scan environments.

**Status:** source-confirmed current reachability gap, not a historical claim. **Closure:** connect an approved, current tool-detection result to the shared production environment; add an app-level regression that proves DerivedData becomes available only when Xcode is actually detected and remains unavailable otherwise; then run fixture-host and real-app confirmation/effect tests.
