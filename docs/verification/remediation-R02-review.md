# R02 source/spec/security review — sealed resource authority foundation

Date: 2026-09-17

Reviewed commit: `0ddd0f9d858783affdb87995622ec1b52277b1c4`

Inputs: `.superpowers/sdd/r02-review.patch`, `docs/verification/remediation-R02.md`, R02 in `docs/audits/2026-09-17-9e1a500/remediation-plan.md`, and the applicable T03 authority contract in `docs/superpowers/tasks/T03-guarded-filesystem-effects.md`.

## Verdict

**Needs one Important correction before `ReviewedManifestArchive` is accepted as the durable R03 handoff.** One Minor evidence correction is also required. No current production mutation bypass was found: `CapabilityRegistry` remains fixed-deny, coordinator selection cannot admit the DerivedData row, the retained coordinator adapter entry always throws `productionProofUnavailable`, and the raw engine remains denial-only.

This verdict is for the R02 foundation checkpoint. It does not require unfinished R03 durability, R04 scheduling/cancellation, R08 second-window integration, R13 physical runtime evidence, or a supported Xcode producer lease to be implemented in this commit. Production R02 acceptance remains blocked exactly as the verification note states.

No tests or builds were rerun because the review request records the focused 7 `ResourceAuthorityTests` and 29 `GuardedDeletionTests` passes and notes low host disk. Unrelated uncommitted R06/R08 work was excluded by reading the committed R02 blobs and supplied patch.

## Findings

### Important — restored protection identity is not bound to the restored exclusion set

`ReviewedManifestArchive.restore()` validates the tree digest (which commits `excludedRelativePaths`) and independently recomputes the protection digest (which commits `canonicalProtectedRoots`), but it never proves that the exclusions are the canonical descendants derived from those protected roots (`ResourcePreflight.swift:79-90`). `makeReviewedResource` then creates a new `ReviewedManifestIdentity` using the independently supplied tree and protection digests (`ResourcePreflight.swift:241-265`). Consequently, `openValidated`'s later equality checks are self-consistency checks on that reconstructed pair, not a cross-binding between protection policy and manifest scope (`ResourcePreflight.swift:268-288`).

A same-root archive can therefore combine a valid manifest captured with no protected descendant (and containing that descendant's leaves) with a separately valid protection block that names the descendant. Both digests still validate, `matchesProtectionScope` accepts the current protected-root list, and the internal effect primitive consumes the manifest's empty exclusion list (`DerivedDataEffectAdapter.swift:92-95`). Current compiled denial prevents this from reaching a production effect, but the archive is not yet safe as the claimed R03 durable authority handoff.

Required correction: during restoration, canonically derive the descendant exclusions from `header.canonicalRootPath` and `protection.canonicalProtectedRoots` and require exact equality with `excludedRelativePaths`. Binding the protection digest into the canonical manifest digest, or comparing both digests against a separately retained expected review identity, should remain defense in depth rather than replace that structural relation. Add a regression that splices a valid unprotected manifest with a valid protected scope for the same root and requires restoration to fail before any lease acquisition or syscall.

### Minor — the fixture proves retention/validation plumbing, not producer exclusion or acquisition ordering

The private test lease increments an acquisition counter and records whether its object is released after a witness disappears (`ResourceAuthorityTests.swift:6-57`). It does not hold a producer exclusion primitive, contend with a writer, or demonstrate that state is observed after exclusion is acquired; its wall-clock `observedAt` is prepared before `acquireLease` runs (`ResourceAuthorityTests.swift:195-204`). This is appropriate for an internal primitive test, but the statement that it “proves the contract” overstates the evidence (`docs/verification/remediation-R02.md:94`). It does not satisfy R02's separate race-fixture requirement or the provider contract's acquire-then-observe ordering.

Required correction: describe this fixture as validation of proof matching, freshness checks, and lease-object lifetime across unlink operations. Keep the exclusion race and supported producer proof explicitly open. If the synthetic mechanical race gate is included in this checkpoint, use a lock-backed fixture whose producer write is demonstrably blocked or denied while the effect holds the lease, and generate the runtime observation after acquisition.

## Confirmed boundaries

- Review capture binds the local volume UUID, root metadata, exact ancestor chain, ordered descendant paths, parent/leaf identity, batch IDs and sizes, manifest digest, and protection digest. Execution does not enumerate a fresh tree, and each reviewed leaf is rechecked through no-follow descriptor-relative operations.
- Archive input, aggregate batches, nodes, canonical bytes, per-batch nodes/bytes, protection roots, and exclusions have explicit limits. Restoration re-encodes and validates header/batches and rejects malformed ordering, duplicate batch IDs, unsupported nodes, invalid ancestry, and digest changes. The finding above is the missing relation between two otherwise validated domains.
- Association validation requires the exact sealed resource, adapter/version, nonempty producers and owners, complete ownership, known shared owners, a producer-manifest method, and a bounded 24-hour validity window. Runtime validation requires exact producer/owner/shared-owner equality, a producer-exclusion method, wall-clock freshness, and a non-Codable monotonic interval no longer than five seconds.
- Synthetic association/proof/lease constructors exist only at internal module visibility and the positive provider is private to the test target. Module-wide searches found no production caller of `executeReviewed`; its only production-source unlink caller is the quarantined internal primitive itself.
- The real Apple inventory is `inventoryOnly`, unknown-activity, ownerless, and has no production lease provider. The old coordinator route calls only the explicit-denial adapter entry. Generic and forged public routes remain blocked by the fixed registry and denial-only raw engine.

## Remaining acceptance boundary

Even after the archive correction, this commit is not full R02 or T03.B acceptance. A future accepted effect still needs the private coordinator lookup facade, mandatory-protection union, supported complete Xcode owner mapping, a real producer-owned lease, durable intent and reconciliation, per-leaf policy/budget/cancellation scheduling, race and mounted-volume evidence, and R08's second-window invalidation coverage. Synthetic leases and green primitive tests cannot close those production gates.
