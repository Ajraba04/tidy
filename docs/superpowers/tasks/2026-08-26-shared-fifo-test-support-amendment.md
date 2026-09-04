# Shared FIFO test support amendment

The user directly replied `resume` to the narrow shared-helper approval request on 2026-08-26. Proceed with the recommended correction. This supersedes only the earlier T04/T05 instructions to retain separate private watchdog copies and source-unchanged T02 helper ownership.

Own exactly these test sources: ConfirmedExecutionTests.swift, RunRecoveryTests.swift, SettingsMigrationTests.swift, and new FIFOReadWatchdog.swift under TidyCore/Tests/TidyCoreTests. Extract the existing T02 watchdog into the shared package-test-internal final class FIFOReadWatchdog. Retain its init(fifo:) and finishAndDrain() signatures, five-second rescue, FD ownership, synchronization and thread drainage. Neutralize only feature-specific diagnostic/comment text. Replace the three constructor names and remove their private class copies. Keep the settings async wrapper and every test assertion/catch/drain/cleanup order unchanged. No production/package/app behavior or test authority changes.

Future T05 A.2 initialized-FIFO fixtures use the same helper, not another copy. New test support is not public production API. Controller owns this amendment and corresponding task-card reconciliation; fresh fixer owns only the four test files and report append.

Verification is behavior-preserving refactor verification, not fabricated RED: baseline full suite; controller inspection of actual shared lifetime code before FIFO runs; focused ConfirmedExecutionTests, RunRecoveryTests and SettingsMigrationTests; controller full suite; independent T04.A source re-review including extraction. Keep prior production-build evidence scoped to unchanged production source. No publication until the full program is complete.
