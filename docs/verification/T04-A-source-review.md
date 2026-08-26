# T04.A independent source review

Range142f90a..b6c585d. Reviewer: independent `t04a_source_review`, 2026-08-26. Functional spec compliant; quality **Needs fixes**. No Critical or Minor findings and no production functional safety defect identified.

## Important — plan-mandated duplicated test watchdog

`RunRecoveryTests.swift:96` duplicates descriptor ownership, rescue-thread, semaphore and final-drainage logic from `ConfirmedExecutionTests.swift:71`. The card explicitly supplies a local duplicate while requiring existing tests source-unchanged. This conflicts with the review rubric's prohibition on duplicated safety-sensitive logic. A future lifetime correction could diverge between copies.

Recommended correction: one shared test-only watchdog, both suites retain all assertions and immediate-drain-before-cleanup ordering. This requires a narrow plan/ownership amendment. Controller requested the user's decision rather than silently overriding the reviewed plan. No source fix has been dispatched pending that decision.

## Reviewed strengths

Shared checked publisher bounds bytes and staging, retries EINTR, rejects invalid progress, checks synchronization and retains ambiguous staging. Both writers use it. Readers reject nonregular nodes before reads and validate anchored/named identities. Retention validates every segment before deletion, retains metadata only and rechecks candidate/references. Tests cover actual syscall faults, correctly framed malformed records, capacity-before-I/O, reopen, disabled history and finish/prune ambiguity.

Reviewer read the supplied complete diff, checked the named watchdog duplication against the unchanged T02 helper and narrowly searched the coordinator for direct intent-persistence calls. No test/build/source/git changes were made by review. Root's297/41 full suite and unsigned arm64 build remain passing onb6c585d.

Real process recovery, accepted effects/proofs, aggregate manifests, shared optional history, settings/app integration and physical supported-OS/hardware acceptance remain separate unfinished work. Functional A approval is not full T04 or release acceptance.
