# Adversarial remediation-plan review

Date: 2026-09-17. Reviewer: GPT-6 Astra, Medium. Reviewed draft: `remediation-plan.md`, 97 lines, baseline `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`.

**Verdict: revise once before treating this as an executable dependency plan.** The immediate containment step is correct, and the draft generally preserves the distinction between safe denial, useful functionality, and acceptance evidence. Two ordering defects and three closure ambiguities need the consolidated revision below. This review does not authorize remediation or release.

This is the single requested adversarial plan review. It used the audit prompt, safety/policy/coverage tracks, approved execution plan and ownership/adapter appendix, and the production capability registry/app bootstrap. No tests, implementation, delegation, release actions, or second review were performed. Only this review file was written. Pending UI/performance/coverage evidence is not presumed to pass. The coordinator-reported green core/app-model/build results do not resolve the expected-red safety/policy regressions or hardware/human gates.

## Findings and consolidated corrections

### PR-01 — High: ownership prerequisites form a dependency cycle

**Location:** draft lines 7, 17, 59 and 65.

R02 requires completed T11/T15.I ownership requirements before accepted mutation, but R09 owns T11 and consumes R02–R08; R10 owns T15 and follows ownership/ranking. Therefore R02 cannot reach its positive acceptance fixture without work nominally deferred until after R02. The opening graph also suggests R02/R03/R04 can proceed together, although R03 depends on R02's manifest and R04 depends on both. A worker could either stall indefinitely or substitute fixture-only owner evidence for the missing production mapping and prematurely enable DerivedData.

**Revision:** extract an early ownership/inventory prerequisite from R09/R10, or explicitly assign the minimum production T11/T15.I subset to R02 and list the remaining later work without duplication. Publish one acyclic graph that agrees with each package's local dependencies: quarantine first; bounded reviewed-manifest/ownership design and implementation; durable lifecycle; effect scheduling; capability-specific acceptance; only then production enablement. Inventory-only and shared infrastructure work may proceed while mutation remains denied. Keep the actual supported producer-exclusion proof as an external capability gate where no supported protocol is available; a synthetic positive fixture proves the primitive, not Xcode's production proof.

**Closure:** every prerequisite has one owning package; every enablement has a completed production ownership contract and adapter acceptance record; there is no path from R02 through R09/R10 back to R02. Absence of a real supported producer proof leaves that adapter denied and its promised mutation incomplete.

### PR-02 — High: first-launch scan restoration can precede scope and pressure corrections

**Location:** draft lines 7 and 35–43; policy track PS01–PS04.

R05 admits revision-zero defaults and makes explicit scanning available, but R06 independently fixes the currently ignored scope, missing live critical-pressure input, and lost global cancellation ownership. The draft permits landing the fresh-install usability fix before those High findings close. This expands access to the defective scan route. An explicit Run Scan is not full-home consent; the policy track shows current orchestration starts at home regardless of selected scope.

**Revision:** make production scan restoration in R05 depend on R06's scope/live-observation/session gates, or split out a quarantined R05 integration stage that cannot ship/enable scanning until those gates pass. Add explicit one-run full-home consent and expiry, acknowledged-policy/root binding, and a second-window policy-change case. Prove lack of unrelated metadata visits, not merely omission of unrelated rows in the result. Preserve the existing stronger rule that detectedTools handoff cannot precede re-quarantine and the stated foundational gates.

**Closure:** a pristine install can scan only its authorized roots under live constraints, with global cancellation retained; Quick and empty selected-project scope visit no unrelated scratch witnesses; a full-home request expires and cannot leak into a later run or another window.

### PR-03 — Medium: current-product correction and full-program completion need separate package exit states

**Location:** draft lines 3, 37, 53 and 91–93; audit prompt section 7.

The draft correctly declares NO-GO/INCOMPLETE, but R05/R08 allow explaining unavailable behavior as package acceptance and R14 depends on “applicable” gates without defining the release capability set. Explanation is a valid current scope-integrity correction, while missing promised consumers/adapters remain full-program work. A future executor could mark R08 complete after disabling all unwired controls, then infer that every R package has closed. Conversely, interpreting R14 as requiring every future capability could unnecessarily couple all packaging work to completion of the entire program.

**Revision:** record two exits for each relevant package: containment/current-product correction and full-program closure. Give every promised consumer/inventory/mutation a remaining implementation owner and testable acceptance even if its current UI is honestly unavailable. Define a proposed capability/distribution manifest for each release assessment, retain the audited current advertised scope for the baseline verdict, and require explicit authority for a changed advertised scope. Map each final coverage-ledger row to its package and exit, rather than relying on the blanket inheritance sentence.

**Closure:** no “unavailable” promised workflow is counted as full-program COMPLETE; contractual inventory-only rows remain eligible for their own acceptance; current-product GO is based on a stated approved scope with all applicable gates passed and no unresolved Critical/High findings. Neither documentation edits nor this plan change the baseline verdict.

### PR-04 — Medium: mandatory combined authority and process-contention scenarios lack explicit acceptance ownership

**Location:** draft R03/R04/R12/R13; audit prompt section 5, S02/S04/S05/S13.

The plan covers policy rechecks, crashes and two-window scans, but does not explicitly assign the combined scenario in which two read-only commands hold both permits when a mutator requests entry. Nor does it explicitly close the accepted-effect scenario where a second window edits/resets/imports after confirmation, preserving presentation-only edits separately. Broad “full checklist” inheritance does not define which package must prove these cross-component properties. Unit gate counters and model-only confirmation tests cannot establish real dispatch behavior.

**Revision:** assign production-bound contention/deadlock/child-reaping tests to R04 with the adapter work, and accepted-effect stale-seal/presentation-only tests to R02/R08 integration. Assign close-all-windows/reopen/app-quit during an accepted effect to R03/R13, including drain versus durable uncertainty. These can remain capability gates while no mutating command adapter is accepted; denial is a current boundary result, not positive future contention proof.

**Closure:** the global command ceiling stays at two including the mutator, no nested permit deadlock or bypass occurs, stale effect authorization invokes zero effects, presentation-only edits obey the documented invalidation contract, and accepted explicit effects retain one app-owned lifecycle across scenes and quit.

### PR-05 — Medium: final hardening omits explicit T24 migration, generated-reference and redaction closure

**Location:** draft R12–R14; approved execution plan T24 lines 783–795; audit prompt D14/D20.

R14 mentions a capability matrix and redacted support procedure, but does not explicitly assign the required generated settings reference, all-released-shape migrations, downgrade/future-schema recovery, or adversarial diagnostic redaction output tests. Current corrupt/future settings denial and preserving unresolved records across upgrade are narrower. The draft also lacks explicit personal-data CI and dependency/action provenance checks. These are approved acceptance requirements, not optional documentation polish.

**Revision:** add named T24 outputs (`docs/settings-reference.md`, `docs/verification/headroom-acceptance.md`), tested registry/default/range/source comparison, the released-schema/downgrade/recovery fixture matrix, and diagnostic/temporary/backup privacy checks to R08/R12–R14. Assert that credentials, cookies, environment, argv, remotes and personal path identities remain excluded even when configurable diagnostic redaction is disabled. Assign personal-data CI and dependency/action provenance verification to R12/R14. State the supported locale scope without inventing an additional-language requirement.

**Closure:** each fixture has a preserved authority/recovery witness and an exact expected result; generated documentation agrees with tested registry behavior; exported artifacts contain no forbidden sentinel values; package/release provenance and locale scope are recorded in the final acceptance evidence.

## Boundaries to retain in the revision

- Re-quarantine DerivedData in the compiled registry before any detectedTools reachability change. Source inspection confirms this is the sole currently accepted pair, while app bootstrap supplies empty detectedTools. Public API exposure is real; shipped-UI destructive reachability has not been demonstrated.
- Keep raw-engine/forged-route denial and old-preset regressions. Changing a positive-delete test to quarantine denial closes immediate containment only; retain separate positive adapter acceptance requirements.
- Keep recovery records intact. Never clear journals or invent terminal states to pass admission or the ninth-run test.
- Keep safe, isolated verification progressing while hardware, human VoiceOver, platform permissions or supported producer proof is unavailable. Record blocked setup and closure; do not lower thresholds or reinterpret source/model/build results as physical evidence.
- Preserve numeric gates and distinguish RSS, physical footprint, processed entries and metadata visits. A partial scan's successful process exit cannot satisfy complete-scope timing.
- Keep signing/notarization optional and remote publication/permissions outside this audit's authority. Do not treat assembling an audit report as an implemented correction or release.

The coordinator should record one consolidated disposition and revision against PR-01–PR-05. No further adversarial plan-review cycle is requested by this review.
