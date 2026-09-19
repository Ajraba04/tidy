# R12 continued verification enforcement — 2026-09-19

The shared verifier now includes the six isolated production-scene native journeys alongside the two presentation-only native tests. It builds the dedicated host for testing, inspects its compiled fixture composition and bundle identity, and only then runs XCTest without rebuilding. The normal universal Release is checked for absence of those fixture markers. No test path supplies a runtime home or authority override to the distributed target.

`check-project.py` compares all 10 generated source/resource phases and requires every model/native test file. It checks exact compilation-condition tokens in every target/project build configuration: the runtime flag belongs only to the dedicated host, that host has its distinct bundle identifier, and the production-scene UI test target must select that host. Live generation passes. Seeded production-flag, missing host flag, near-name flag, and production-identity collisions reject.

`check-runtime-binary.py` scans built code in bounded chunks, checks the expected bundle identity, rejects escaping Info/code paths, requires fixture markers in the test host and forbids them in production. Existing real normal and runtime binaries pass their respective checks. Seeded content controls verify clean production, leaked fixture markers, missing fixture markers, wrong identity, markers spanning a read-chunk boundary, and escaping code-directory rejection. These controls test the content gate; native binary validity/signature and architectures have separate build/package checks.

Privacy inventory enforcement now includes the 35-pattern self-test and exact identity between the live generated source table and the committed document. Modified line data and duplicated generated tables both fail. This detects inventory drift; it does not grant an approved privacy reason or replace runtime traffic evidence.

New required-case gates cover fresh-default provenance and external file replacement, supported/future/corrupt settings shapes with real unresolved-recovery witnesses, private materialized diagnostic candidates, and scan-grant/consent lifetime. The current aggregate floors are 701 Core, 144 model, 2 presentation native and 11 ordinary production-native cases (six scene journeys plus five appearance/accessibility cases). The first integrated continuation run confirmed Core 700 plus isolated 1 and model 142, with all required cases present. A prediction of 143 incorrectly counted a moved existing model case as new; the gate rejected the run after all 142 models passed. The corrected full verifier must complete its remaining native/build gates before final acceptance is recorded. Skipped/zero/failing results remain failures except the explicitly isolated process-cap case, which must pass in its own process.

Historical shell, project, source and privacy checks passed at their recorded checkpoints. At the `ca24965` resume, project generation and seeded source-data controls pass again; the privacy table is stale and must be refreshed after final source edits. The continuation final review owns the source/specification disposition; fresh aggregate/build evidence is recorded separately after the final run. Reference hardware, human accessibility, producer/effect/recovery proof, full privacy/network and distribution acceptance remain independent.

## Retained aggregate failures

- The first continuation run passed Core700, isolated1 and model142, then rejected an incorrect expected model floor of143. All required model cases were present; 3f576d9 corrected the inventory count.
- The next run passed Core700 and isolated1, then recorded141 passing/1 failing model with zero skips. The lifecycle test could accept transient zero before scheduled appearances; fe90172 added an exact200-active entry barrier, preserving real deinit and the5-second cleanup bound. Ten fresh-process repetitions and the full11-case Headroom suite passed.
- The subsequent700-test Core run recorded two issues in the bootstrap-hold variant of SettingsProcessAcceptanceTests: the winner exited126 after seeing an invalid release signal, then the loser timed out because the parent aborted. The retained signal later had the correct one-byte/0600 contents. The parent had exposed its final filename before writing its payload; 17ce90d corrected publication with a validated same-directory stage and atomic no-overwrite rename, without relaxing child validation or timeouts. The new regression raises the Core gate to701.

- The next run on5bfd8ea passed Core701, isolated1, models142 and presentation native2; the production native suite recorded5 passing/1 failing case. The scan completed before the Cancel button could be observed by XCTest. The early-Cancel race was subsequently corrected in `530f665` and its focused native suite passed; completed scanning is not accepted as cancellation evidence. Release was not reached in that invocation.

Raw overall logs remain `/tmp/tidy-final-20260919-{72c699b,3f576d9,fe90172,5bfd8ea}.log`. Failed model bundles are preserved in the corresponding `-before-floor-fix` and `-before-teardown-oracle` output directories. These failed runs are not passing aggregate evidence.


## External observer test boundary

The production native target also contains fixed-duration hidden-monitor and externally observed performance cases. They deliberately require the observer to publish exact owned proceed/completion tokens. The ordinary verification invocation excludes only `ProductionObservationRuntimeUITests` and `ProductionPerformanceRuntimeUITests`; every ordinary production-scene/appearance case still runs, and no reported skip or zero-test success is accepted. `run-r13-observation.py` drives those external cases separately and retains their native result bundles plus process measurements. Their execution status belongs to the R13 reports; compiling them or excluding them from the short aggregate is not a passing measurement.

The observer's pure validation self-tests are part of the ordinary verifier. The app-model floor now includes the two real early-Cancel/Rescan regressions (144), each also required by exact method name.


## Resumed final pass

The single resumed verifier exited65: Core701, isolated1, models144 and presentation2 passed; production native10/11 passed. The required compact audit timed out inside XCTest (code -56), so normal Release was not reached in this script. No retry or skip was introduced. See [resumed verification](remediation-resume-verification.md) for exact evidence and the separately built package.
