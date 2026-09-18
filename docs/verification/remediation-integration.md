# Remediation integration record

The implementation branch started at `9e1a500`. It covers R01 containment, R02 reviewed-resource foundations, R06/R07 scan/index corrections, R08 live policy/measurement/history, R12 verification enforcement, and R13/R14 evidence/documentation/packaging preparation. It is not full-program or release acceptance. See [dependency closures](remediation-dependency-blocks.md) and [headroom acceptance](headroom-acceptance.md).

## Workspace continuity

During verification on 2026-09-18, the entire original Desktop/AJR directory moved into iCloud Desktop. The original Git history and uncommitted work survived. A new local isolated clone at `/Users/mac/Developer/tidy-remediation-20260918` was created from the moved repository, with exact index/worktree patches and untracked files preserved. All 389 source files matched SHA-256 against the moved worktree, and `git fsck --connectivity-only` passed. The iCloud copies were left unchanged. No remote push, tag or publication occurred.

The recovery preservation manifest and patches are `/private/tmp/tidy-workspace-move-preservation-20260918`. Historical commands in package reports retain their original paths; current verification uses the recovered local clone.

## Shared application integration

`AppExecutionServices.swift` integrates the independently owned R06/R08 work: one serialized scan transition, generation-owned observation/index resources, retained terminal results, acknowledged cache policy, expiring scoped grants, monitor scene/work leases, monotonic volume observations, and revision-bound confined optional history. Its ordinary deinitializer closes monitoring callbacks and cancels/removes only its own bindings; it does not require Swift 6.2 isolated-deinitializer syntax.

Fresh focused source evidence before the combined integration commit:

- Scan/index core foundation: 79 tests, followed by 39 invalidation/index tests after real FSEvents corrections.
- Scan app models: 14 passed, zero skipped, including simultaneous starts, replacement teardown, retained results, closed-window global cancellation and the real 100k index gate.
- R08 monitoring/history corrections: 40 tests passed (33 monitor + 7 history).
- Recovered-path monitoring lifetime compatibility: 2 model tests passed.
- Scope alias correction: 9 tests passed, including four hostile cache aliases and moved-ancestor denial.

Real app/FSEvents fixture: 500 directories, 100,000 files, 49,152 allocated bytes, fresh metadata visits 100,502, unchanged visits 0, complete content parity, zero catch-up retries. The 100% measured reduction exceeds the 80% correctness gate on this M1 Max fixture. This is not reference-hardware latency, physical footprint or whole-app idle performance evidence.

Final full core/model/architecture checks and whole-branch review are recorded below once complete. Earlier failures remain in the package reports and must not be erased by focused passes.
