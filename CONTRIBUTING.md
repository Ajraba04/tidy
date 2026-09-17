# Contributing to Tidy

## Project layout

```
Tidy.xcodeproj      thin app target; references TidyCore as a local package
Tidy/               SwiftUI layer only: views and view models
TidyCore/           all logic, zero UI, zero third-party dependencies
project.yml         xcodegen source of truth for Tidy.xcodeproj
```

`project.yml` is the source of truth. Regenerate after changing source membership and commit the project with it. The verifier generates a second disposable project and compares every source/resource build phase.

Use the pinned XcodeGen release without changing system tooling:

```bash
bash scripts/verification/install-xcodegen.sh /tmp/tidy-tools
export PATH="/tmp/tidy-tools/xcodegen/bin:$PATH"
xcodegen generate
python3 scripts/verification/check-project.py
```

## Building and testing

Run `bash scripts/verification/verify.sh` for source/privacy checks, serialized core tests, all model tests, synthetic native UI tests and an arm64/x86_64 Release build. Results and exact tool versions go to `dist/verification`; set `TIDY_VERIFICATION_OUTPUT` to a new empty directory for another run. Native UI testing needs a working logged-in macOS test session. A startup failure or zero selected tests is a failure, not acceptance.

The three simulator response tests use synthetic JSON rather than starting the host CoreSimulator service. They prove parser behavior only; real service/adapter acceptance requires a provisioned disposable setup. Filesystem/effect tests use owned scratch witnesses. Compiler/SDK cache writes are reported separately from user-data effect isolation. Never exhaust the user's real disk or memory for a test.

Fixture/model/build results do not establish physical performance, supported OS runtime, production app accessibility, human VoiceOver, controlled network traffic or installation acceptance. Keep those evidence gates explicit.

## Adding an adapter

1. Read the approved design and settings/adapter appendix under `docs/superpowers/specs`.
2. Add bounded read-only inventory with exact identity, supported version, complete ownership and explicit unknown/unavailable states. Do not evaluate repository code, hooks or tool wrappers during discovery.
3. Keep mutations denied in `CapabilityRegistry` until that individual adapter has accepted exact scope, reviewed descendants, producer exclusion, preflight, cancellation, durable lifecycle and positive recovery proofs. A `CustomActionExecutor`, tool-presence bit or generic path helper cannot create authority.
4. Test both the positive accepted contract and hostile/changed/unknown cases on disposable fixtures. Preserve protections and outside witnesses. Raw `CleanEngine.execute` remains a denied legacy route; accepted effects must use the coordinator's sealed authority.
5. Update tested registry/consumer documentation and the capability acceptance record. Do not count an unavailable promised workflow as complete.

No hardcoded personal paths, credentials, domains or device approvals belong in source. The personal-data gate tests seeded forbidden patterns and withholds matching values from CI logs. Runtime network access, telemetry, remote contexts and hidden cleanup remain forbidden. Changes to CI/action/tool pins require upstream review, updated exact version/digest, generated-project comparison and fresh full verification. Remote publication and signing changes require separate authority.

## Reporting issues

Open a GitHub issue. Include your macOS version and, if a specific catalog
item misbehaved, the item's title as shown in the plan screen.
