# R02 verification — sealed reviewed resources and ownership foundation

Date: 2026-09-17

Baseline: `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`

Containment prerequisite: `651e703`
Status: **foundation implemented; production acceptance BLOCKED**

## Result

R02 now has a review-time filesystem authority contract for Xcode DerivedData. The coordinator captures the exact local volume, selected root, ancestor chain, descendant names and identities, bounded manifest batches, manifest digest, and canonical protection-scope digest during review. Archive restoration also derives the descendant exclusions from the canonical root and protected roots and requires exact equality with the manifest's exclusion list, so independently valid manifest and protection blocks cannot be spliced into authority. Execution cannot substitute a fresh tree: the retained legacy production entry now returns `productionProofUnavailable`, and the internal effect primitive consumes only a coordinator-retained review seal.

The ownership boundary is separate from filesystem identity. An effect-capable association must identify the adapter/version, exact sealed resource, recognized producers, complete owners, all shared owners, observation/expiry, and producer-manifest revalidation method. Immediately before the first effect, an internal lease provider must acquire a producer-owned exclusion primitive. The returned proof must match the same adapter/version/resource/producers/owners, be complete, use `producerExclusionLease`, and be no older than five seconds with a declared lifetime no longer than five seconds. The live lease also carries non-Codable `ContinuousClock.Instant` acquisition/deadline values; the effect checks monotonic age and a maximum five-second monotonic lifetime. Wall-clock rollback/future observations deny, and frozen wall time cannot extend the monotonic deadline. The lease is retained across every unlink. Process absence, a Tidy-owned advisory lock, and manual inactivity are represented as unsupported runtime methods and cannot satisfy validation.

The compiled `CapabilityRegistry` remains fixed-deny. `AppleDerivedDataInventory` reports the real root as `inventoryOnly`, `unknown`, with no owners and the explicit reason: `Inventory only: no supported Xcode producer exclusion or complete shared-owner proof is available.` Its production lease provider is explicitly absent. Public app/settings/import callers can read inventory but cannot construct association evidence, runtime proof, leases, or reviewed trees.

## Exact manifest and R03 interface

`ReviewedManifestArchive` schema 1 is the durable R03 handoff. It contains:

- the canonical root path, volume UUID, exact root metadata, and complete ancestor identity chain;
- each reviewed relative name, parent identity chain, leaf type/device/inode/generation/link count/size/allocation/mtime/ctime;
- the ordered batch UUIDs and encoded sizes;
- canonical excluded relative paths;
- the manifest SHA-256;
- canonical protected roots and their separate SHA-256.

The archive is `Codable`, but authority consumers use `encodedBounded()` and `decodeBounded(_:)`. Bounds are enforced during capture and again before restoration:

| Field | Limit |
|---|---:|
| Nodes per batch | 5,000 |
| Canonical bytes per batch | 8 MiB |
| Total batches | 20 |
| Total nodes | 100,000 |
| Total canonical manifest bytes | 64 MiB |
| Serialized archive input | 96 MiB |
| Protection roots / exclusions | 256 each |

R03 must bound its durable file read to 96 MiB before allocating the input `Data`, persist this archive together with operation identity and pending intent before effect, and call `restore()` after bounded decode. Restoration re-encodes every header/batch, verifies structure and aggregate limits, verifies both digests, derives the canonical descendant exclusions from the protected roots, requires exact equality with the archived exclusions, and only then recreates an internal `ReviewedFileResource`. A digest or open file descriptor by itself is not authority. R03 must retain exact manifest bytes for positive terminal reconciliation; it must not recapture a fresher tree after a crash. Runtime freshness is intentionally absent from the archive: every process launch must acquire a new producer lease and new monotonic epoch immediately before effect.

## Safe-withholding behavior

The effect primitive opens the reviewed root with no-follow descriptors and verifies the retained volume/root/ancestor identity. It never adds execution-time descendants. Each reviewed leaf is checked again immediately before `unlinkat`:

- a new descendant is not in the manifest and remains;
- a grown or metadata-changed regular file is skipped;
- a replaced root/directory/leaf is denied or skipped;
- protected descendants never enter the manifest, and changed protection scope invalidates the seal;
- symlinks and unsupported nodes do not gain authority;
- a new hard link changes reviewed metadata and cannot inherit stale authority;
- a reviewed directory is removed only when reviewed and empty.

The existing guarded-deletion suite also retains Unicode path ordering, hard-link accounting, symlink-swap, protected descendant, cross-device metadata, changed/new child, replacement, malformed manifest, batch-cap, and moved-root coverage. Its cross-device case is a metadata control, not a real mounted-volume integration test; no host mount or service was created for R02.

## Supported Xcode producer-proof investigation

The installed primary command documentation was checked on:

- Xcode 27.0, build `27A266a`;
- `xcresulttool` 25115, schema 0.4.0;
- macOS 27.0, build `26A428`.

`xcodebuild -help` and `man xcodebuild` document `-derivedDataPath` as selection of the output directory, `-resultBundlePath`/`-resultStreamPath` as result outputs, and ordinary build/clean actions. They do not document an API to enumerate every producer of the shared DerivedData root, acquire an exclusion lease for that root, or positively prove that Xcode IDE, `xcodebuild`, indexing, previews, tests, documentation builds, package resolution, or helpers cannot write it. `xcresulttool help` reads completed result bundles; it does not own or exclude current DerivedData producers.

The current Apple primary documentation reaches the same supported surface:

- [Build system](https://developer.apple.com/documentation/xcode/build-system) describes Xcode's task-producing build system but exposes no external exclusion/lease interface.
- [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference) documents build-output settings, not a shared-root ownership or quiescence token.
- [Distributing documentation to other developers](https://developer.apple.com/documentation/xcode/distributing-documentation-to-other-developers) shows `xcodebuild docbuild -derivedDataPath ...`; the option selects where a producer writes and is not a lease.
- [Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference) exposes Xcode Cloud paths and post-action exit data, not a local shared-root exclusion primitive.

This is an evidence-bounded conclusion about documented supported interfaces, not a claim that undocumented Xcode internals have no locks. Undocumented lock files, absence of observed processes, a Tidy-only lock, and manual “not active” acknowledgement do not meet the approved producer-proof contract. Therefore the real DerivedData adapter remains inventory-only and R02 production closure is blocked.

## Red/green and verification evidence

The first focused test build failed because the new lease, association, inventory, and review-seal types did not exist. After implementation, verification used a disposable `git archive` of `HEAD` plus only R02-owned files because the current shared worktree had an unrelated in-flight `RunLogTests`/`OptionalRunHistoryStore` API mismatch. The current-tree attempt stopped at compilation before running R02 tests; no unrelated source or test file was edited. Existing logs were preserved and the corrective run reused `/tmp/tidy-r02-isolated-build` with two jobs.

Commands:

```text
cd /tmp/tidy-r02-correction-src.XHQj4E/TidyCore
swift test --scratch-path /tmp/tidy-r02-isolated-build --jobs 2 --filter ResourceAuthorityTests
swift test --scratch-path /tmp/tidy-r02-isolated-build --jobs 2 --filter GuardedDeletionTests
```

Results:

- `ResourceAuthorityTests`: 8 tests passed, including the archive-splice regression, an eight-case denial matrix (incomplete, unknown, unknown shared owner, stale association, changed owner, unsupported version, expired runtime proof, wall-clock rollback), and a frozen-wall/expired-monotonic-deadline case.
- `GuardedDeletionTests`: 29 tests passed.
- Regression red/green: with only the new exclusion/protection structural check removed, `mixedManifestAndProtectionAreRejected` failed because restoration threw no error; after restoring the check, the same test passed.
- Original foundation shared production package build: `swift build --scratch-path /tmp/tidy-r02-build --jobs 2` passed.

The fixture-only positive lease validates exact proof matching, wall-clock and monotonic freshness checks, and retention of the lease object across unlink operations on disposable files. It does not hold or prove a producer exclusion primitive, does not demonstrate acquire-then-observe ordering, and is not registered or installed as production Xcode authority. The exclusion race fixture and supported producer proof remain open acceptance gates.

## Remaining production acceptance gates

R02 is not complete as a production adapter package. Closure still requires a supported real Xcode producer exclusion/quiescence primitive and complete current owner mapping, followed by real positive/negative producer tests. R03 must durably persist and reconcile the exact archive and pending effect lifecycle. R04 must stream the bounded archive, apply selected-run limits/deadlines/cancellation/policy checks, and complete the real contention/resource measurements. R08 still co-owns accepted-effect second-window policy/reset/import behavior. R13 still owns mounted-volume/race/runtime acceptance. Until those gates pass, DerivedData selection and every compiled mutation remain quarantined.
