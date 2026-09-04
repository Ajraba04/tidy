# T04.A entry review — approved implementation contract

## Final independent entry verdict — 2026-08-26

Independent reviewer `t04a_entry_review` approved the final 362-line approved-budget supplement for T04.A source entry: spec compliant and entry quality Approved, with no remaining Critical, Important or Minor findings. Controller read the complete contract, replacement/additional test code and report. Separate 1 MiB ledger, eight reserved 1 MiB active slots, optional-only history, bounded durable-finish/retention ordering and disabled-history behavior are accepted. Prior corrections 2–3 remain binding. The original budget finding is closed.

Nine proposed test methods (twelve executions with parameters) cover the new minimum/disabled/capacity/retention/overage boundaries. They have not yet executed. This is implementation-contract approval, not source approval, completed recovery or a release. The controller assigns the source BASE after this documentation checkpoint; T03.B/C manifest/proof aggregate admission, real effects, B process recovery, D joint report accounting/settings binding and hardware acceptance remain open.

## User decision — 2026-08-26

The user approved the recommended interpretation: `history.maxMiB` caps optional completed reports only. Mandatory recovery storage has separate explicit hard bounds; unfinished evidence is never evicted to satisfy a history preference, and history off never disables safety persistence. The prior inclusive equation is superseded, not an implementation requirement. Exact accounting, hard bounds and replacement acceptance tests are being reconciled in `../superpowers/tasks/T04-A-approved-budget-contract.md` before independent source-entry review.

The user also clarified that GitHub push, README update and DMG release are to happen **after the full implementation and release checks**, not as an intermediate preview release. No remote Git or release changes were made during the read-only release inspection.

The review below records the original finding and subsequent independent corrections. Its request for a product choice is historical and no longer blocks execution. T04.A source still requires approval of the reconciled implementation contract.

Reviewed proposal: `.superpowers/sdd/T04.A-entry-proposal.md`, 645 lines, against approved T02/T03.A foundations and the T04 task card. No T04 source or test implementation is authorized yet.

Independent reviewer `t04a_entry_review` returned **Needs fixes** for spec and entry quality. No Critical finding and no confirmed contradiction with explicit binding wording.

## Product interpretation requiring confirmation

The settings registry specifies a history limit of 1–50 MiB (default 10 MiB) and a 1 MiB unfinished-ledger reserve, but does not state whether that reserve is inside the history limit. The proposal counts the reserve plus active and completed diagnostic bytes inside it. At the valid 1 MiB minimum, this would prevent even an empty installation from recording its first planned run.

Controller recommendation for user confirmation: the configurable limit caps optional completed reports; mandatory recovery storage receives a separate, explicitly bounded allowance. Unfinished evidence is never evicted to meet a history preference, and disabling history never disables safety persistence. Active-diagnostic aggregate limits and separate manifest admission accounting must be specified and independently reviewed before source entry. No whole-directory cap or physical disk reservation is claimed.

The alternative inclusive interpretation would need explicit acceptance that the minimum setting prevents new work. No interpretation has been silently implemented.

## Required entry corrections after the decision

1. Specify the selected accounting equation and exact empty-installation/minimum-limit test, including manifest classification and bounded bookkeeping exceptions.
2. Bound every mandatory-store directory scan (initialization, acquire and staging checks), not only diagnostic enumeration. Retention parses one bounded segment at a time and retains only bounded metadata/summaries. Add exact-limit and limit-plus-one tests, including unrelated entries and byte preservation on overflow.
3. Complete first-intent and diagnostic-publication fault cases; zero/over-remaining write progress and EINTR; checksum corruption and correctly checksummed sequence-gap/prefix-payload/foreign-run frames; header-only and invalid-length cases; cumulative segment caps. Assert actual preservation/latching and continued valid bookkeeping after deterministic pre-I/O rejection.

Review was read-only: no tests, builds, source edits or commits. Implementer remains paused pending the accounting decision and corrected entry review. T04 process/reconciliation integration and physical acceptance remain open.

## Independent corrections reviewed while the budget decision remains open

The expanded proposal now specifies one bounded scanner for every mandatory-store and diagnostic scan, including initialization, acquire and publication. Production limits are 16,384 total directory entries and 4,096 diagnostic entries; internal overrides can only lower them. The shared publication helper requires the owning instance's limits and performs the final prospective staging-slot check itself. Retention parses one segment at a time and retains only bounded summaries.

Ten additional proposed test methods cover thirty executions: first-intent/diagnostic publication faults, zero/over-remaining writes and EINTR, checksum and correctly checksummed structural corruption, cumulative segment limits, exact/overflow enumeration and preservation. These tests have not run.

Independent re-review closed findings 2 and 3 at proposal level after correcting propagation of scan limits into the shared helper. Finding 1—the history-budget interpretation—remains open. This is not full source-entry approval. Work on the separately approved T05.A1 read-only settings migration proceeds without selecting the history policy.
