# R12/R14 code/spec review — reproducible enforcement and distribution preparation

Date: 2026-09-18

Reviewed commits:

- `981052b4590e4182941151c9d410baa776eb92cb` — R12 project, test and CI enforcement
- `e8ba1f53e4ce021019589ed2e758b8bdefd31f37` — R14 documentation, privacy and packaging preparation
- `914bac997ba53c41045e31858806cbf98523e8e7` — R14 version/architecture validation follow-up

Inputs: `.superpowers/sdd/r12-r14-review.patch`, `docs/verification/remediation-R12.md`, `docs/verification/remediation-R14.md`, R12/R14 in `docs/audits/2026-09-17-9e1a500/remediation-plan.md`, and the associated TEST-01/TEST-02/DOC-01/DOC-02/DIST-01 findings and acceptance gates.

## Verdict

Approved as a partial implementation/preparation checkpoint. No substantive standards or specification findings.

This is not full R12 or R14 acceptance. In particular, the native UI result is an XCTest bootstrap failure: both recorded attempts ended before runner connection/assertions with signal kill, **0 passing tests and 1 runner failure**. The target's successful build and CI wiring do not convert that failure into runtime, accessibility or production UI acceptance.

No tests or builds were run for this review because the host is under the recorded low-disk constraint. Review was limited to the committed blobs and supplied patch; unrelated uncommitted R02/R06 integration work was excluded. Static review re-parsed both workflow YAML files, all changed Python verifiers and all changed shell scripts. The two action tag refs and the XcodeGen 2.46.0 archive digest were independently checked read-only.

## Standards review

No findings.

- `project.yml` remains the source of truth and the regenerated `Tidy.xcodeproj` is committed with it. The disposable comparison resolves and compares every native target source/resource phase, and separately requires every Swift file under `TidyAppModelTests` to belong to its source phase (`scripts/verification/check-project.py:8-51`). All five model test files, their support sources, localization resources, and the native UI test source are present in the committed project.
- The native target is narrowly scoped to `TidyUITestHost` and its presentation sources. The fixture constructs descriptive `CleanPlan` values with no binding or execution authority; the production selection model therefore keeps confirmation disabled. The UI assertion checks all three tier surfaces and requires `Clean Now` to remain disabled (`project.yml:36-57,86-109`; `TidyNativeUITests/SyntheticReviewUITests.swift:3-20`).
- PR and release workflows call one verifier, use least-privilege read permissions on PR CI, and retain logs/result bundles/toolchain evidence even on failure. Checkout and upload-artifact are exact commit pins whose upstream tag refs resolve to the committed SHAs; XcodeGen is versioned and SHA-256 checked before extraction (`.github/workflows/ci.yml:8-33`; `.github/workflows/release.yml:17-48`; `scripts/verification/install-xcodegen.sh:1-17`). TidyCore continues to have no third-party runtime package dependency.
- Compiler and SDK caches are separated from user-data effect isolation. The settings process helper enumerates every current TidyCore Swift source, hashes every source plus the driver into retained evidence, compiles that exact list, and uses an explicit disposable module cache (`TidyCore/Tests/TidyCoreTests/SettingsProcessAcceptanceTests.swift:96-164`).
- The Simctl change separates bounded JSON decoding from service invocation. The three former ambient listing tests use controlled JSON, including malformed and oversized input, and no longer contact CoreSimulator. The remaining real service/mutation test and adapter acceptance are not misrepresented as isolated parser proof (`TidyCore/Sources/TidyCore/Detect/SimctlClient.swift:33-90`; `TidyCore/Tests/TidyCoreTests/SystemToolSurveyTests.swift:53-80`; `docs/verification/remediation-R12.md:9`).
- I found no newly introduced personal paths, credentials, unpinned third-party actions, hidden release claim, destructive install workaround, duplicated policy implementation or scope expansion in the reviewed patch.

## Specification review

No findings.

- **Generated membership and model coverage:** the baseline omissions are repaired in both YAML and the committed project. The gate compares resolved source/resource membership rather than pretending that nondeterministic project object IDs must match byte-for-byte (`project.yml:36-84`; `scripts/verification/check-project.py:10-50`).
- **Safe synthetic native UI gate:** the UI target depends on the fixture host rather than the production app, compiles no discovery/execution service wiring, and is invoked by both PR and release verification. `check-test-results.py` rejects its recorded bootstrap failure and rejects zero passing tests (`project.yml:86-109`; `scripts/verification/verify.sh:24-33`; `scripts/verification/check-test-results.py:20-29`).
- **Aggregate integrity:** shell `pipefail` preserves a failed test command, Swift log inspection rejects any failed aggregate before summing passing counts, and Xcode result inspection rejects failed tests, runner-result failure and counts below the required floor. The recorded synthetic controls include zero tests, an aggregate failure, a failed aggregate followed by a smaller focused pass, and positive-count controls (`scripts/verification/check-test-results.py:9-30`; `docs/verification/remediation-R12.md:13,21`).
- **Actual module resolution:** the compiler probe searches from the loaded class bundle, main bundle, executable and SwiftPM's actual `--test-bundle-path`, then requires a successful public import of the located module before the negative access test. The negative control still requires diagnostics for all protected types and `fileprivate`, preventing a missing/unimportable module from becoming a false denial pass (`TidyCore/Tests/TidyCoreTests/ProcessBudgetIntegrationTests.swift:32-75,245-272`).
- **Personal-data and provenance gates:** seeded forbidden source values each fail in a subprocess without being echoed; the clean control passes. The verifier records the commit and exact host tool versions. Checkout `v4.2.2` resolves to `11bd71901bbe5b1630ceea73d27597364c9af683`, upload-artifact `v4.6.2` resolves to `ea165f8d65b6e75b540449e92b4886f43607fa02`, and the downloaded XcodeGen 2.46.0 archive hashes to the committed `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806` (`scripts/verification/check-personal-data.py:10-45`; `scripts/verification/verify.sh:8-18`).
- **Artifact identity and checksums:** local and release packaging reject unsafe version path components, require tag/version agreement with `CFBundleShortVersionString`, require a positive build number, and verify both executable slices before signing/packaging. ZIP and DMG hashes use portable relative filenames; release provenance records commit, Xcode, Swift and packaged executable architectures (`scripts/make-release.sh:13-64`; `.github/workflows/release.yml:20-64,128-154`).
- **Truthful scope and privacy:** README and acceptance records distinguish containment from implemented usefulness, source intent from controlled traffic evidence, requested hardened-runtime settings from inspected final signatures, and packaging preparation from release acceptance. The API inventory explicitly remains partial and does not invent reasons for unresolved external-root metadata/volume uses. English-only scope matches the source catalog. Unsigned-install guidance requires trusted provenance and pre-install checksum verification, uses the per-app Privacy & Security path, and rejects global Gatekeeper weakening and recursive quarantine removal (`README.md:3-35,63-67`; `docs/UNSIGNED_INSTALL.md:1-12`; `docs/verification/privacy-api-inventory.md:1-16`; `docs/verification/headroom-acceptance.md:3-19,36-50`).

## Evidence and remaining gates

The recorded focused R12 snapshot is credible for the owned changes: 19 tests across `ProcessBudgetIntegrationTests`, isolated `SimctlClientTests` and `SimulatorPrunerTests` passed, including the corrected positive import and negative compiler diagnostics. Static membership, personal-data and result-checker controls also passed. These results do not erase the earlier 637-test aggregate's module-location failure or the concurrent universal Release failure; the evidence record preserves both and requires fresh integrated results.

R12 therefore still requires a passing final core/model/Release aggregate, a genuinely running native UI test result, provisioned real-service isolation, generated settings-reference comparison, and the released-shape migration/privacy fixture matrix. R14 remains preparation only until immutable final ZIP/DMG bytes and provenance are inspected, final signature/entitlements/hardened-runtime and resources are verified, supported-OS install/upgrade/uninstall is demonstrated with recovery witnesses, and the remaining privacy/runtime gates close. No tag, push, upload, publication or signing-policy change was reviewed or performed here.
