# T04.A entry review — decision pending

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
