# R01 verification — compiled mutation quarantine

Date: 2026-09-17
Baseline: `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`
Worktree: `codex/remediation-20260917`

## Result

R01 containment is implemented. `CapabilityRegistry.denialReason` now returns the fixed explicit quarantine reason for every item/action combination, including `safe.xcode.derived-data` with `.deleteContents`. Catalog inventory remains visible. Coordinator selection, old preset projection, forged identifiers/bindings, raw-engine compatibility execution and direct legacy helpers do not gain mutation authority.

This is the immediate containment exit only. It does not complete R02–R04, accept any production adapter, or deliver the promised cleanup workflows.

## Changed behavior

- Removed the compiled DerivedData exception from `CapabilityRegistry`.
- Replaced the former positive DerivedData effect tests with inventory/quarantine assertions. They verify the row remains present with the exact reason, cannot be selected, writes no run journal, leaves admission ready and preserves fixture bytes.
- Added `QuarantineSafetyRegressionTests.swift` separately from the historical audit artifact. The seven original safety scenarios now assert safe withholding while quarantine is active; an additional coordinator inventory/forgery test covers every catalog row and forged selections.
- Added an app-model expectation proving the DerivedData preset cannot select the quarantined row or open confirmation, even when an `.xcode` tool bit is supplied to the coordinator.
- Left app bootstrap/detected-tools handoff, journals, adapter implementation and audit artifacts unchanged.

## Test-first evidence

Focused baseline, before the registry change:

```text
swift test --scratch-path /tmp/tidy-r01-build --filter LegacyQuarantineTests
```

Result: exit 0; 4 tests in 1 suite passed.

RED proof after changing the all-catalog expectation but before changing production code:

```text
swift test --scratch-path /tmp/tidy-r01-build --filter DerivedDataExecutionTests.denialRemainsMandatoryForEveryCatalogItem
```

Result: exit 1; 1 expected issue. The sole failure was `safe.xcode.derived-data`, whose registry result was `nil` instead of the quarantine reason.

Immediate GREEN proof after removing the exception:

```text
swift test --scratch-path /tmp/tidy-r01-build --filter DerivedDataExecutionTests.denialRemainsMandatoryForEveryCatalogItem
```

Result: exit 0; 1 test passed.

## Final focused verification

Concurrent R06/R08/R12 work temporarily introduced incomplete test sources in the shared worktree. To avoid stashing, moving or changing those files, final R01 verification used a disposable `git archive` snapshot of baseline plus only the four R01-owned source/test files. Swift products still used the required `/tmp/tidy-r01-build` scratch path; all test fixtures created canonical UUID roots under temporary storage and removed only those owned roots.

```text
swift test --scratch-path /tmp/tidy-r01-build \
  --filter 'LegacyQuarantineTests|DerivedDataExecutionTests|QuarantineSafetyRegressionTests'
```

Result: exit 0; 15 tests in 3 suites passed. This includes:

- all catalog and forged raw-engine actions denied;
- all catalog coordinator rows non-selectable, with forged ID/binding rejection;
- zero recording-command or registered-custom-executor calls;
- DerivedData inventory retained with the exact quarantine reason;
- payload, protected descendant, replacement root and outside witnesses byte-identical;
- no effect run journal and no unfinished intent from denied selection;
- nine sequential denied attempts leave mutation admission ready.

```text
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests \
  -destination 'platform=macOS' -derivedDataPath /tmp/tidy-r01-xcode.K1CIRF \
  test \
  -only-testing:TidyAppModelTests/ConfirmationLifecycleTests/testDerivedDataQuarantineStaysVisibleAndPresetCannotOpenConfirmation
```

Result: `** TEST SUCCEEDED **`; 1 test executed, 0 failures.

```text
git diff --check -- <R01-owned tracked files>
git diff --no-index --check /dev/null TidyCore/Tests/TidyCoreTests/QuarantineSafetyRegressionTests.swift
```

Result: no whitespace errors.

The builds emitted existing warnings in unrelated monitoring, scanning and older test files. No R01-owned file emitted a diagnostic.

## Residual gates

- Every mutation remains deliberately unavailable. R02 must provide the production ownership/review manifest contract; R03 must provide durable effect lifecycle/reconciliation; R04 must provide bounded effect scheduling/cancellation. Denial is not evidence that those packages are complete.
- The dormant DerivedData effect adapter has not been accepted or enabled. Its future positive fixture remains a separate adapter acceptance gate after R02–R04 and supported Xcode producer/quiescence evidence.
- The empty app `detectedTools` handoff is unchanged, as required. R05 may address reachability only after its dependencies close.
- No real user home, CoreSimulator service, browser database, Git repository, snapshot service or other host mutation was used. Reference-hardware, native UI, human accessibility, privacy/network and release gates remain with R13/R14.
- Aggregate shared-branch verification must be rerun by the coordinator after the concurrent R06/R08/R12 sources reach a compile-ready checkpoint. The isolated focused results above prove R01 against the audited baseline plus only R01 changes.
