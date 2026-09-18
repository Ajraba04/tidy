# R02 source/spec/security review — sealed resource authority foundation

Date: 2026-09-17

Reviewed foundation commit: `0ddd0f9d858783affdb87995622ec1b52277b1c4`

Inputs: `.superpowers/sdd/r02-review.patch`, `docs/verification/remediation-R02.md`, R02 in `docs/audits/2026-09-17-9e1a500/remediation-plan.md`, and the applicable T03 authority contract in `docs/superpowers/tasks/T03-guarded-filesystem-effects.md`.

## Verdict

**Corrective disposition: the Important archive-binding finding and Minor evidence overclaim are resolved.** `ReviewedManifestArchive.restore()` now derives canonical descendant exclusions from the archived root and protected roots and requires exact equality with the manifest exclusions before reconstructing authority. The verification note now limits the synthetic lease claim to proof matching, freshness checks, and lease-object lifetime. No current production mutation bypass was found: `CapabilityRegistry` remains fixed-deny, coordinator selection cannot admit the DerivedData row, the retained coordinator adapter entry always throws `productionProofUnavailable`, and the raw engine remains denial-only.

This verdict is for the R02 foundation checkpoint. It does not require unfinished R03 durability, R04 scheduling/cancellation, R08 second-window integration, R13 physical runtime evidence, or a supported Xcode producer lease to be implemented in this commit. Production R02 acceptance remains blocked exactly as the verification note states.

The correction was verified in a disposable `git archive` of `HEAD` plus only the two R02-owned code/test files, reusing `/tmp/tidy-r02-isolated-build` with `--jobs 2`: 8 `ResourceAuthorityTests` and 29 `GuardedDeletionTests` passed. The splice test also failed in the expected way when only the structural check was removed, then passed when restored. A current shared-tree attempt stopped before R02 execution on an unrelated in-flight `RunLogTests` API mismatch; no unrelated tests were changed.

## Findings

### Resolved Important — restored protection identity is bound to the restored exclusion set

Before correction, `ReviewedManifestArchive.restore()` validated the tree digest (which commits `excludedRelativePaths`) and independently recomputed the protection digest (which commits `canonicalProtectedRoots`), but it never proved that the exclusions were the canonical descendants derived from those protected roots. `makeReviewedResource` then created a new `ReviewedManifestIdentity` using the independently supplied tree and protection digests. Consequently, `openValidated`'s later equality checks were self-consistency checks on that reconstructed pair, not a cross-binding between protection policy and manifest scope.

A same-root archive could therefore combine a valid manifest captured with no protected descendant (and containing that descendant's leaves) with a separately valid protection block that named the descendant. Both digests still validated, `matchesProtectionScope` accepted the current protected-root list, and the internal effect primitive consumed the manifest's empty exclusion list. Current compiled denial prevented this from reaching a production effect, but the archive was not yet safe as the claimed R03 durable authority handoff.

Disposition: restoration now canonically derives descendant exclusions from `header.canonicalRootPath` and `protection.canonicalProtectedRoots` and requires exact equality with `excludedRelativePaths`. The regression combines a valid unprotected manifest with a valid protected scope for the same root and verifies that restoration throws `invalidManifest`; unchanged protected and unprotected witnesses confirm no effect occurred. Its red run accepted the splice and failed the expectation when the structural check was removed, proving that the regression exercises this relation.

### Resolved Minor — the fixture proves retention/validation plumbing, not producer exclusion or acquisition ordering

The private test lease increments an acquisition counter and records whether its object is released after a witness disappears. It does not hold a producer exclusion primitive, contend with a writer, or demonstrate that state is observed after exclusion is acquired; its wall-clock `observedAt` is prepared before `acquireLease` runs. This is appropriate for an internal primitive test, but the original statement that it “proves the contract” overstated the evidence. It does not satisfy R02's separate race-fixture requirement or the provider contract's acquire-then-observe ordering.

Disposition: the verification note now describes the fixture only as validation of proof matching, freshness checks, and lease-object lifetime across unlink operations. It explicitly leaves acquire-then-observe ordering, the mechanical exclusion race, and supported real producer proof open.

## Confirmed boundaries

- Review capture binds the local volume UUID, root metadata, exact ancestor chain, ordered descendant paths, parent/leaf identity, batch IDs and sizes, manifest digest, and protection digest. Execution does not enumerate a fresh tree, and each reviewed leaf is rechecked through no-follow descriptor-relative operations.
- Archive input, aggregate batches, nodes, canonical bytes, per-batch nodes/bytes, protection roots, and exclusions have explicit limits. Restoration re-encodes and validates header/batches and rejects malformed ordering, duplicate batch IDs, unsupported nodes, invalid ancestry, digest changes, and any mismatch between protected-root-derived exclusions and archived exclusions.
- Association validation requires the exact sealed resource, adapter/version, nonempty producers and owners, complete ownership, known shared owners, a producer-manifest method, and a bounded 24-hour validity window. Runtime validation requires exact producer/owner/shared-owner equality, a producer-exclusion method, wall-clock freshness, and a non-Codable monotonic interval no longer than five seconds.
- Synthetic association/proof/lease constructors exist only at internal module visibility and the positive provider is private to the test target. Module-wide searches found no production caller of `executeReviewed`; its only production-source unlink caller is the quarantined internal primitive itself.
- The real Apple inventory is `inventoryOnly`, unknown-activity, ownerless, and has no production lease provider. The old coordinator route calls only the explicit-denial adapter entry. Generic and forged public routes remain blocked by the fixed registry and denial-only raw engine.

## Remaining acceptance boundary

Even after the archive correction, this commit is not full R02 or T03.B acceptance. A future accepted effect still needs the private coordinator lookup facade, mandatory-protection union, supported complete Xcode owner mapping, a real producer-owned lease, durable intent and reconciliation, per-leaf policy/budget/cancellation scheduling, race and mounted-volume evidence, and R08's second-window invalidation coverage. Synthetic leases and green primitive tests cannot close those production gates.
