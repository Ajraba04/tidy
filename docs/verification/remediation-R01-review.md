# R01 code/spec review — compiled mutation quarantine

Date: 2026-09-17

Reviewed commit: `651e70372daa12724bd605c0b2a064839648be20`

Baseline: `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`

## Verdict

Approved. No substantive standards or specification findings.

The commit closes the immediate R01 containment exit without claiming that any cleanup adapter is production-ready. Review was limited to the committed R01 patch and its recorded verification evidence; completed tests were not rerun, as requested.

## Standards review

No findings.

- The production change is confined to the compiled capability boundary. `CapabilityRegistry.denialReason` discards both inputs and unconditionally returns the fixed quarantine reason (`TidyCore/Sources/TidyCore/Execution/CapabilityRegistry.swift:3-13`). There is no runtime flag, caller exception, item exception, or environment escape hatch.
- Existing defense in depth remains intact: coordinator confirmation validates every selected row through the registry, execution repeats that validation under the policy barrier, and the private effect loop checks the registry again immediately before adapter dispatch (`TidyCore/Sources/TidyCore/Execution/ExecutionCoordinator.swift:139-198,248-257,320-327`).
- The added fixtures use owned UUID temporary roots, preserve byte witnesses, and clean up only those roots. The change adds no network behavior, personal paths, or deletion shortcut contrary to `CONTRIBUTING.md`.
- The test changes describe quarantine behavior directly and remove the former positive-delete expectations. I found no misleading test name, duplicated production policy, or abstraction added beyond the R01 scope.

## Specification review

No findings.

- **All compiled mutations denied:** the registry now denies every action/identifier combination, including the formerly accepted DerivedData pair. The all-catalog assertion also covers the retained DerivedData row (`TidyCore/Tests/TidyCoreTests/DerivedDataExecutionTests.swift:95-104`).
- **Inventory and explicit reasons preserved:** the DerivedData row remains in the Safe review, is non-selectable, and exposes the exact quarantine reason (`TidyCore/Tests/TidyCoreTests/DerivedDataExecutionTests.swift:56-74`). The deep coordinator regression requires the produced review to contain every catalog row and rejects each mutation row (`TidyCore/Tests/TidyCoreTests/QuarantineSafetyRegressionTests.swift:70-99`).
- **Raw and forged routes denied:** the retained raw-engine suite enumerates every catalog action plus forged delete, tool, and custom combinations, then proves zero command/custom-executor calls and unchanged fixture bytes (`TidyCore/Tests/TidyCoreTests/LegacyQuarantineTests.swift:50-90`). The coordinator regression rejects an unknown selected ID and a forged binding while leaving admission ready and its witness unchanged (`TidyCore/Tests/TidyCoreTests/QuarantineSafetyRegressionTests.swift:70-99`).
- **Old preset denied:** the app-model regression applies the former DerivedData preset to a real registered review, then proves zero selected rows, zero selection requests, no confirmable/frozen presentation, no confirmation token, and unchanged payload bytes (`TidyAppModelTests/ConfirmationLifecycleTests.swift:241-274`).
- **No effect or scratch changes:** the adapted audit regressions preserve late-created content, growth, replacement roots, protected descendants, ownership-unknown content, journal state, admission state, and outside witnesses (`TidyCore/Tests/TidyCoreTests/QuarantineSafetyRegressionTests.swift:101-193`).
- **Containment is distinguished from acceptance:** the verification record explicitly limits the result to immediate containment and leaves R02-R04, positive adapter acceptance, production quiescence, hardware, accessibility, privacy/network, and release evidence open (`docs/verification/remediation-R01.md:9-11,84-90`). The former positive DerivedData tests were rewritten as inventory/quarantine tests rather than retained as false production-success evidence.

## Evidence assessment

The recorded focused runs are proportionate to R01: 15 core tests cover catalog/forged/raw denial, zero executor calls, byte witnesses, journals, and repeated attempts; the focused app-model test covers the preset path (`docs/verification/remediation-R01.md:47-82`). The record also discloses that aggregate shared-branch verification remains pending after concurrent R06/R08/R12 work, so it does not overstate whole-branch status.
