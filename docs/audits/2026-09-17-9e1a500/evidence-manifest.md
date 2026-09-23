# Evidence manifest

Baseline `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`,2026-09-17. Source/configuration and static findings are in tracks/*.md with exact file/line pointers. This manifest links command vectors, working directories,UTC start/end,monotonic elapsed times,exit codes and retained outputs. JSON arrays are exact command arguments, not shell strings. Reproduce in an isolated checkout with inspected fixtures; do not blindly run real-service tests.

## Executed commands

|Evidence/run|Class|Exit|UTC start → end|Artifacts|
|---|---|---|---|---|
|E05 model119|app-model|0|2026-09-17T15:26:30.657796+00:00 → 2026-09-17T15:27:46.022745+00:00|[arguments/provenance](evidence/app-model-tests.json), [output](evidence/app-model-tests.log)|
|E08 slices/plists/signatures|build/artifact inspection;not packaged install|0|2026-09-17T15:37:44.085399+00:00 → 2026-09-17T15:37:46.852356+00:00|[arguments/provenance](evidence/artifact-inspection.json), [output](evidence/artifact-inspection.log)|
|E01 host/Git/toolchain baseline|source/configuration|0|2026-09-17T15:07:58.942672+00:00 → 2026-09-17T15:08:00.001345+00:00|[arguments/provenance](evidence/baseline.json), [output](evidence/baseline.log)|
|Failed sample:process already exited,no hang established|source/configuration|255|2026-09-17T15:25:55.972280+00:00 → 2026-09-17T15:25:56.014020+00:00|[arguments/provenance](evidence/core-hang-sample.json), [output](evidence/core-hang-sample.log)|
|E04 baseline selected620;3ambient tests omitted|unit + scratch production integration|0|2026-09-17T15:28:37.716591+00:00 → 2026-09-17T15:31:25.643497+00:00|[arguments/provenance](evidence/core-local-layout.json), [output](evidence/core-local-layout.log)|
|E03 baseline selected619; external-layout failure|unit + scratch production integration|1|2026-09-17T15:08:46.680912+00:00 → 2026-09-17T15:14:21.420777+00:00|[arguments/provenance](evidence/core-safe.json), [output](evidence/core-safe.log)|
|E08 arm64Debug|build/artifact inspection;not packaged install|0|2026-09-17T15:08:47.832104+00:00 → 2026-09-17T15:09:17.596750+00:00|[arguments/provenance](evidence/debug-build.json), [output](evidence/debug-build.log)|
|E09 existing safe native fixture|build/artifact inspection;not packaged install|0|2026-09-17T15:27:57.994736+00:00 → 2026-09-17T15:28:41.834683+00:00|[arguments/provenance](evidence/fixture-host-build.json), [output](evidence/fixture-host-build.log)|
|Evidence isolation worktree|source/configuration|0|2026-09-17T15:10:28.398389+00:00 → 2026-09-17T15:10:28.540763+00:00|[arguments/provenance](evidence/fixture-worktree.json), [output](evidence/fixture-worktree.log)|
|E12 isolated XcodeGen2.46.0|source/configuration|0|2026-09-17T15:45:05.541499+00:00 → 2026-09-17T15:45:05.599500+00:00|[arguments/provenance](evidence/generated-project-existing-directory.json), [output](evidence/generated-project-existing-directory.log)|
|Failed preparation:destination absent|source/configuration|1|2026-09-17T15:44:56.242445+00:00 → 2026-09-17T15:44:56.346498+00:00|[arguments/provenance](evidence/generated-project.json), [output](evidence/generated-project.log)|
|E12 machine source/resource comparison|source/configuration|0|2026-09-17T15:45:26.547527+00:00 → 2026-09-17T15:45:26.623048+00:00|[arguments/provenance](evidence/generation-membership-verified.json), [output](evidence/generation-membership-verified.log)|
|Failed dependent read:generated file absent|source/configuration|1|2026-09-17T15:44:56.396425+00:00 → 2026-09-17T15:44:56.461409+00:00|[arguments/provenance](evidence/generation-membership.json), [output](evidence/generation-membership.log)|
|E08 x86_64Release cross-build|build/artifact inspection;not packaged install|0|2026-09-17T15:27:42.528764+00:00 → 2026-09-17T15:29:13.059010+00:00|[arguments/provenance](evidence/intel-build.json), [output](evidence/intel-build.log)|
|E11 standalone driver link|build/artifact inspection;not packaged install|0|2026-09-17T15:31:34.991835+00:00 → 2026-09-17T15:31:40.500011+00:00|[arguments/provenance](evidence/monitor-build.json), [output](evidence/monitor-build.log)|
|E11 live monitor component|performance measurement (component)|0|2026-09-17T15:31:40.540181+00:00 → 2026-09-17T15:42:44.062981+00:00|[arguments/provenance](evidence/monitor-measurement.json), [output](evidence/monitor-measurement.log)|
|E07 expectedRED2|production integration (audit-only tests)|1|2026-09-17T15:27:41.424906+00:00 → 2026-09-17T15:27:52.234835+00:00|[arguments/provenance](evidence/policy-regressions.json), [output](evidence/policy-regressions.log)|
|E09 storage-injected production app fixture|build/artifact inspection;not packaged install|0|2026-09-17T15:37:20.601491+00:00 → 2026-09-17T15:38:23.125326+00:00|[arguments/provenance](evidence/production-fixture-build.json), [output](evidence/production-fixture-build.log)|
|E08 arm64Release|build/artifact inspection;not packaged install|0|2026-09-17T15:10:28.576112+00:00 → 2026-09-17T15:13:37.040202+00:00|[arguments/provenance](evidence/release-build.json), [output](evidence/release-build.log)|
|E06 expectedRED7/10issues|production integration (audit-only tests)|1|2026-09-17T15:26:12.967252+00:00 → 2026-09-17T15:27:11.866635+00:00|[arguments/provenance](evidence/safety-regressions.json), [output](evidence/safety-regressions.log)|
|Invalid measurement:zero selected tests,no evidence|performance measurement (component)|0|2026-09-17T15:33:48.864999+00:00 → 2026-09-17T15:33:52.421386+00:00|[arguments/provenance](evidence/scan-measurement-no-tests.json), [output](evidence/scan-measurement-no-tests.log)|
|E10 partial large scans/immediate cancellation|performance measurement (component)|0|2026-09-17T15:34:05.270360+00:00 → 2026-09-17T15:34:29.663081+00:00|[arguments/provenance](evidence/scan-measurement.json), [output](evidence/scan-measurement.log)|
|E01 real schemes/targets|source/configuration|0|2026-09-17T15:08:00.038722+00:00 → 2026-09-17T15:08:43.900876+00:00|[arguments/provenance](evidence/schemes.json), [output](evidence/schemes.log)|
|E12 syntax/personal-pattern checks|source/configuration|0|2026-09-17T15:37:46.902191+00:00 → 2026-09-17T15:37:47.038111+00:00|[arguments/provenance](evidence/static-checks.json), [output](evidence/static-checks.log)|

## Reproduction and selection

Run SwiftPM from `TidyCore` with bounded `--jobs 2 --no-parallel`; exact commands are JSON records. Full safe baseline selection is `--skip SimctlClientTests` plus audit-only test exclusions in the detached worktree. Original package has623 tests;3 async Simctl tests query real CoreSimulator service and were withheld. Initial external-scratch run also excluded the stale-comment synchronous simulator test; source review proved that route inert, so the final620test selection includes it. No complete623test or real-service acceptance claim.

Audit probes copied into detached9e1a500 worktree are preserved as tracks/SafetyAuditRegressionTests.swift (7), tracks/PolicyAuditRegressionTests.swift (2), tracks/PolicyAuditPerformanceTests.swift (1 measurement test). Baseline source bytes match primary checkout; no implementation fix was made. Later only Tidy/TidyApp.swift was changed in the detached worktree for test-only storage injection, after baseline core/model/build runs; exact patch retained. Do not merge that injection. `fixture-worktree.json` records creation. Scripted tests allocate/remove only their own UUID scratch effect targets; compiler caches are ordinary tool side effects and not claimed fully isolated by HOME. Host process/disk/VM surveys are ambient read-only. No real simulator cleanup,cookie/Trash/cache cleanup,host resource exhaustion,signing change or remote write was run.

`/private/tmp/tidy-audit-9e1a500-app-model.xcresult` retains the119test result bundle externally. Debug/Release artifacts: `/private/tmp/tidy-audit-9e1a500-app/Build/Products/`; Intel cross-build under `/private/tmp/tidy-audit-9e1a500-intel/Build/Products/Release/`. No shipping ZIP/DMG was generated. `codesign -dvv` observes linker-ad-hoc arm64 binaries and an unsigned x86_64 binary; no resources sealed on these deliberately signing-disabled builds. This is expected test-build evidence, not chosen release hardened-runtime proof. Composite artifact-inspection command exits0 although the nested unsigned codesign display reports unsigned; interpret nested output directly.

`static-checks.log` prints `valid False` for empty entitlements because the helper used dictionary truthiness: parsing succeeded and the dictionary is empty. It is not a plist syntax failure. Personal-data rg exit1 means no matches. More exact final validation is recorded separately. First XcodeGen attempt failed because destination directory did not exist; after explicit mkdir, generation passed and target-by-target membership comparison confirmed drift. Primary project was never overwritten.

Timing records preserve toolUTC and monotonic durations separately; benchmarking uses measured monotonic intervals. Some platform scheduling/wall-clock differences are retained without rewriting evidence.

## Native and performance observations

[Native UI record](evidence/native-ui.md) gives safe fixture AX/screenshots and production menu-bar automation timeouts. Screenshots exist in tool conversation, not as exported PNGs here; no human VoiceOver session is claimed. [Performance record](evidence/performance.md) details fixture composition,sampling,limits and actual measurements. Test-driver process-tree RSS/footprint is not scan-only app memory. [Owned fixture cleanup](evidence/owned-fixture-cleanup.json) records termination of only our two explicitly launched scratch GUI executables. Audit worktree/builds are retained for reproduction.

## Current primary vendor references

|ID|Accessed|Source and use|
|---|---|---|
|V01|2026-09-17|[Apple:Safely open apps on your Mac](https://support.apple.com/en-us/102445), current Privacy & Security→Open Anyway instructions and trust/tampering meaning; DOC-02. No override was performed.|
|V02|2026-09-17|[Apple:Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc); file-metadata category/reason inventory remains GAP-03. Do not automatically impose App Store submission rules on GitHub distribution.|
|V03|2026-09-17|[Apple:Privacy manifest files](https://developer.apple.com/documentation/BundleResources/privacy-manifest-files) and [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest); resource presence differs from correct comprehensive reason mapping.|

## Provenance, redaction and preservation

Logs redact actual user home to `<HOME>` and per-user temporary-directory identifiers to `<USER_TMP>`. Synthetic fixture identities/names are not real users. Exact task-owned `/private/tmp/tidy-audit-*` paths remain for local reproducibility. Raw app-model xcresult/build artifacts can contain local source paths and are not approved for external sharing without redaction. No credentials/cookies/process argv dump was collected as audit evidence. Source manifests/hash listings cover baseline production and retained audit evidence separately; `sha256-manifest.json` is generated after final artifact validation (excluding itself).

One adversarial GPT-6 Astra Medium review produced plan-review.md; one consolidated revision addressed PR-01–05 in remediation-plan.md. Safety/policy source review used Astra High; bounded coverage used Terra Medium. No model substitution. No other adversarial plan-review loop was commissioned.

## Final inventory and validation

- `inventory-build`: exit0, 2026-09-17T15:49:20.021154+00:00 to 2026-09-17T15:49:21.781644+00:00; [command](evidence/inventory-build.json), [output](evidence/inventory-build.log).
- `runtime-inventory`: exit0, 2026-09-17T15:49:21.823901+00:00 to 2026-09-17T15:49:22.399659+00:00; [command](evidence/runtime-inventory.json), [output](evidence/runtime-inventory.log).
- `final-validation`: exit0, 2026-09-17T15:50:47.758958+00:00 to 2026-09-17T15:50:48.534055+00:00; [command](evidence/final-validation.json), [output](evidence/final-validation.log).

Compiled static inventory confirms97catalog items,96mutation-denied,128expanded registry definitions. Ledger covers all128concrete IDs as well as79contract family rows,165plan checkboxes and262named task-card subdivisions. Final verification confirms6deliverables,20dimensions,S01–S16,T01–T24,15combined scenarios,valid local links,no trailing whitespace,no source personal-pattern matches and empty primary tracked diff. [Baseline source hashes](evidence/baseline-source-sha256.json) cover236files.
