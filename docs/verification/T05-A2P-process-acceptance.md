# T05 A.2P process acceptance evidence

Scope: actual cross-process contention and abrupt settings-publication recovery only. This does not claim the A.3 app cutover, native UI acceptance, accepted cleanup effects, power-loss durability, Intel/macOS14 device coverage or full T05/product acceptance.

## Implementation and TDD

- Governing correction and implementation: `af739d4..d525f36`; production settings/process code is unchanged. The shipping package excludes only the two nonshipping fixture sources while preserving Config resources.
- Natural RED: with the driver absent, the source manifest failed `.missing` before compiler launch; the remaining cases failed the one-attempt guard. No child fixture ran.
- The real driver compiles the current explicit79-file TidyCore source set plus itself with `swiftc -j2`, records source hashes and compiler arguments before launch, and uses the accepted bounded `ProcessSession` with fail-closed identity, retained ownership, finite deadlines, one consuming reap and zero signal attempts.
- Initial runtime exposed a test-only preload race: simultaneous initialized-store reads legitimately contended on the nonblocking store lock. Two retained failures and diagnostic root `674F1F28-D337-4155-95FF-B96B61A1E1B7` proved the contender loaded `recoveryReadOnly`/`unavailable`. The corrected test completely preloads the winner, then the loser, retaining both live before either starts; actual publication contention is unchanged.

## Runtime results

- Focused final: `swift test --jobs 2 --filter SettingsProcessAcceptanceTests`, exit0;3 methods/1suite/eight executions passed in41.772s. Both writer-contention variants passed, bootstrap winner death exited80, and P1-P5 exited81-85. All printed observations recorded one consuming reap and zero signal attempts. Retained log: `.superpowers/sdd/T05.A2P-review-fix-green.log`.
- Exact assertions cover config/backup bytes, complete names, device/inode preservation, exact `0600` modes, stable metadata/store UUID, marker schema/stage/digest, distinct overlapping PIDs, stale retry rejection, fresh-child read-only recovery for P1-P4, and ordinary revision3 reopen for P5.
- Controller coverage partition at the same implementation, with only assertion/comment changes between runs: ordinary tests excluding both global process-owner suites passed323 tests/42 suites in33.597s; bounded-process suite passed21/1 in41.638s; final A2P passed3 methods/1suite. This is complete347-method/44-suite package coverage without overlapping global child-owner assertions.
- Unsigned arm64 production app build exited0 with no output after the final assertion fix.

## Reviews and limitations

- Independent source review initially found two Important oracle gaps: P1/P2 used an unvalidated backup baseline and contention results did not require exact modes. A fresh fixer added canonical revision1/day180 backup assertions and exact `0600` checks. Focused runtime passed again.
- Independent re-review: spec compliant and task quality Approved; no Critical, Important or Minor remains.
- The host is an8GiB arm64 Mac on macOS27 developer build. Intel, macOS14 oldest-supported and stable-OS native acceptance remain open and cannot be inferred from this evidence.

