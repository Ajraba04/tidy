# Developer Headroom: Adversarial Review

Date: 2026-08-26.
Scope: independent, read-only review of the proposed product contract and execution plan against the current repository. No implementation or release approval.

Reviewed artifacts:

- [Execution plan](2026-08-26-developer-headroom-execution-plan.md)
- [Product contract](../specs/2026-08-26-developer-headroom-design.md)
- [Settings and adapter contracts](../specs/2026-08-26-headroom-policy-and-adapter-contracts.md) (added in response to review)

## Initial verdict

The independent reviewer, `adversarial_plan_review`, returned **not ready to execute as written**. It considered the product boundaries strong but found safety/policy decisions left implicit and several tests too weak. The initial draft is not approved.

## Findings and revisions

| # | Severity | Finding | Revision made |
|---|---|---|---|
| 1 | P1 | Stage A could retain unsafe legacy effects while their audit waited until later stages. | T01 now requires default-deny capability enforcement for every unaccepted legacy action, including broad package tools, Git remote/immediate/worktree pruning and lock removal. Raw/custom/preset entry points must all be tested. Stage A can ship fewer mutations than v1.5.0. |
| 2 | P1 | A child or daemon operation could survive Tidy's crash, allowing a second mutator after relaunch. | S16/T02/T04 require durable uncertainAndPossiblyRunning state, process/operation identity, a submission handshake and positive adapter-specific quiescence before any new mutation. A free lock or fresh review is insufficient. |
| 3 | P1 | Default cap versus explicit restriction precedence was ambiguous; customization defaults were incomplete. | Added the stable settings registry and exact factory profiles. P/R/A/H distinguish preferences, explicit restrictions, local authority and immutable limits. Tests must allow a 40 GiB request over the 10 GiB default while honoring an explicit 8 GiB cap. |
| 4 | P1 | Directory identity did not authorize new descendants or enforce byte/time limits under churn. | S03/T03 bind bounded reviewed descendant manifests, skip new/changed/grown entries, distinguish estimated manual caps from strict unattended effect bounds and use monotonic scheduling deadlines with safe boundaries. |
| 5 | P1 | Confirmed inactivity had no operational proof or usable transition. | Added ownership/activity evidence matrix, freshness, shared-owner denial and separate expiring manual acknowledgement. Positive producer lease and unknown-shared-owner fixtures are mandatory. Unsupported proof remains manual-with-warning or read-only. |
| 6 | P2 | Invalidations during baseline scans could be overwritten by a stale fresh publication. | T09 requires root generations, event-delivery/publication barrier and atomic aggregate/coverage/cursor publication. Epoch changes force dirty state/rescan; event-loss/crash race tests are required. |
| 7 | P2 | Constant/enum/local-boolean test seeds could pass while production safety failed; integration packages were too broad. | Removed the import/dependency/environment/model tautologies and specified production-bound effect/ledger tests. Added concrete per-adapter fixtures and .I inventory/.M mutation-or-denial units. Each work unit needs a separately reviewed task card with exact signatures and complete failing tests before code. Remaining snippets illustrate contracts only. |

The revisions preserve the review's strengths: read-only models/data/VMs, no authority transfer through imports, unknown-state protection and physical low-spec Mac acceptance.

## Follow-up review

The second independent pass found original findings 1, 2, 4, 5, 6 and 7 resolved at the program-plan level. Finding 3 remained partially open, so the reviewer withheld program adoption pending these corrections:

| Follow-up blocker | Revision made |
|---|---|
| Hidden-idle zero-work guarantee contradicted explicit scans, safe draining and separately authorized maintenance. | Added an operating-mode matrix. Zero-work applies to hidden idle with monitoring/maintenance off. Explicit work, draining and bounded reconciliation are distinct; monitoring grants no cleanup/scan authority. |
| Per-volume headroom had no persistable registry representation. | Added volume-identity override records with inherit/automatic/fixed values, explicit precedence, inert unresolved imports and a two-volume relaunch test in T06. |
| Battery profile restrictions contradicted “preferences only”; subprocess cap could be read as additive. | Profiles may set P and stricter R only, never A/H. Defined a total two-command-job permit ceiling including the mutator, with T08 contention tests and separate bounded descendant contracts. |

## Final independent verdict

The third pass returned **ready to adopt as a PROGRAM execution plan**. The reviewer confirmed all seven original findings and all three follow-up blockers resolved at the planning-contract level, with no remaining blocking contradictions in its bounded consistency check.

This is not approval to directly implement every package without the task-card gate. Unsupported mutations remain unavailable; illustrative snippets do not satisfy acceptance. Feasibility, safety, performance and physical-device evidence remain implementation-stage obligations.

## Document verification

- All four planning documents have valid local Markdown links, balanced code fences and no trailing whitespace.
- The execution plan contains exactly T01–T24 in order.
- The 22 remaining illustrative Swift blocks pass syntax parsing. This is not a production test/build or behavioral verification claim.
- Only planning documents were added. No tracked application source was changed; no commit, push or release was performed.

## What this document can establish

This is a comprehensive program execution plan with stage gates. It is not a claim that all 24 packages are small commits or that every future adapter's production interface is already implemented or proven feasible. Unsupported mutation contracts remain unavailable.

Before implementation, each narrow work unit must receive concrete production signatures, complete failing tests and its own reviewed task card. Implementation still requires user authorization. No app tests, performance gates, signing or release status are claimed by this planning review.
