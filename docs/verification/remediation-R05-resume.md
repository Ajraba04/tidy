# R05 resume verification — fresh-install explicit scan

Date: 2026-09-19

Baseline: `b4acfff2a78343884457b14ee5d9efba3df91e12`

Status: **revision-zero explicit scope-only scan implemented and focused verification passed;
mutation/tool handoff remains blocked**

## Result

A pristine installation can now run the existing bounded explicit Scan without first making an
unrelated settings edit. The absence of a settings file produces the existing canonical schema-2,
revision-zero defaults in memory. App bootstrap obtains a store-bound, single-use bootstrap result
from the real `SettingsStore` actor and passes it to `ExecutionPolicyBridge`. Only that exact
provenance may install revision-zero scheduler policy.

The ordinary bridge initializer still rejects every revision-zero document, including a caller-
constructed byte-for-byte copy of the defaults. A `.loaded` revision-zero file, corrupt or future
settings, a modified `.newDefaults` value, a token from a different settings actor, and replay of an
already consumed token all remain unavailable. The scheduler independently requires the
`.freshDefaults` origin and exact canonical bytes, and carries the accepted origin in its prepared
token and acknowledged state so live observation can safely re-resolve the same policy.

The token also captures the exact `SettingsDiskImage` observed by the issuing load. Immediately
before scheduler preparation, the settings actor reopens the bounded path and requires the same
directory/config/backup/lock/metadata identities and bytes. The sole exception is the existing
absent-parent to empty-settings-parent refresh caused by execution-journal bootstrap. Any external
settings creation, replacement, corrupt/future document, staging remnant, or directory replacement
denies without modifying the observed bytes.

`ScanScopeAuthority` now consumes the exact envelope actually accepted by the read-only scheduler,
rather than treating every positive revision as sufficient or globally allowing revision zero.
The first real settings save still crosses the existing synchronous admission barrier; after durable
publication, revision one replaces the in-memory default policy. Sessions cannot cross the barrier.

## Preserved boundaries

- App bootstrap, scan view construction, and opening Settings start no scan session, traversal,
  explicit monitor lease, timer, index watch, or command.
- `ScanViewModel`, app bootstrap, and `ScanScopeAuthority` continue to construct environments with
  `detectedTools: []`.
- `CapabilityRegistry` remains fixed-deny. The R01 quarantine regression still proves every catalog
  mutation and forged identifier is denied.
- The new bootstrap evidence grants scheduler/scope authority only. It is not coordinator cleanup
  authority, a tool-presence bit, owner/quiescence proof, or a DerivedData producer lease.
- Explicit Quick scan still resolves only existing same-volume catalog roots. Selected-project
  scope with no roots performs no unrelated traversal. Full-home still requires its existing
  owner-bound, expiring, single-use consent.
- The read-only scan does not persist the default settings document as a side effect.

R01 therefore continues to prohibit tool-detection handoff. R02–R04 remain blocked on the supported
real producer/exclusion and durable positive-effect contracts recorded in
`remediation-producer-dependency-resume.md`. This change restores only the R05 read-only first-launch
path allowed after the implemented R06/R08 source gates.

## Implementation

### Store-bound bootstrap provenance

`SettingsStore.loadForSchedulerBootstrap()` returns an opaque `SettingsSchedulerBootstrap` holding
the exact `SettingsLoadResult`, a strong reference to the originating actor, its checked monotonic
generation, and shared single-use state. Retaining the actor rules out address reuse. Every later
load or state-changing request advances the store-owned generation; overflow permanently denies
bootstrap provenance. Its initializer and matching logic are file-private.

`AppExecutionServices.bootstrap` obtains this value inside its existing detached settings load and
passes it to the bridge that owns the shared scheduler. The bridge atomically acquires a short
reservation from the same settings actor before scheduler preparation and releases it after commit.
Competing settings load and persisted update/rollback/import-commit work is denied during that
bounded installation window. This establishes serialization without adding a global watcher or changing external-file
conflict semantics.

Acquisition also reopens `SettingsFiles` and compares the current disk image with the captured image.
When the settings directory did not exist at issuance, only the already accepted parent-creation
case is allowed, and only while config, backup, lock, and metadata all remain absent. The refreshed
directory identity becomes the store's current image; every other difference denies.

The existing public `ExecutionPolicyBridge(... loaded:)` initializer supplies no bootstrap evidence;
it cannot enable revision zero. The bootstrap initializer binds the result to the same settings actor.
Only `.newDefaults` with the exact canonical envelope can select `.freshDefaults` origin.

### Scheduler and scope

`PreparedSchedulerPolicy` now binds `SchedulerPolicyOrigin`. Ordinary prepares default to `.durable`,
which retains the positive-revision rule. `.freshDefaults` admits revision zero only when every
canonical default field, optional block, and inert collection matches. Commit retains the origin for
live observations; the first persisted revision replaces it with `.durable`.

The bridge records `acknowledgedScanEnvelope` only after scheduler commit. It clears this projection
while applying a durable save and republishes the exact saved envelope only after scheduler commit.
`ScanScopeAuthority` derives scope from that projection. Raw loaded settings no longer imply scope
authority by themselves.

## TDD evidence

The first app-model regression was added before production changes and failed with the original
user-facing condition:

```text
Fresh defaults did not admit the explicit scan:
failed("Tidy needs settings saved once before it can scan. Open Settings, save, then try again.")
```

After the first implementation, the exact-default caller-spoof regression was strengthened to use
byte-for-byte canonical defaults without store provenance. It failed because the forged value still
installed scheduler policy. The store-bound bootstrap change made that regression pass.

The valid bootstrap replay regression was then added and failed because a copied token could install
a second scheduler. Shared single-use state closed that replay path; the same token and a token from
another `SettingsStore` now deny.

The stale-state regression then showed that an unconsumed token still survived a later same-store
load or update. The store-owned generation and reserved installation window closed both cases.
Tests also cover strong issuing-actor retention and forced generation exhaustion.
The reservation regression pauses scheduler preparation after the lease is acquired and verifies
that competing load and update requests fail until installation releases it.

Final review then identified a cross-store/filesystem race outside the actor generation: another
store or process could create settings after issuance but before acquire. The added regression was
red for a second-store valid nondefault publication, raw corrupt creation, and atomic future-schema
replacement. Exact disk-image revalidation made all three green and preserved every resulting byte.

## Focused verification

Core command, using the requested two-job external scratch path:

```text
cd TidyCore
swift test --scratch-path /tmp/tidy-r05-resume-build --jobs 2 \
  --filter 'WorkSchedulerTests|ScanScopeTests|QuarantineSafetyRegressionTests|missingOnlyCreatesInMemoryDefaults|explicitFirstSaveCreatesOwnerOnlyDirectoryAndNoFakeBackup|firstSaveFailureNeverBecomesDefaultsOnRelaunch'
```

Result: **58 tests in 5 suites passed**. This includes scheduler origin/exact-default checks, live
observation at revision zero, the fresh-default Quick scope, the complete existing scope suite, the
fixed-deny mutation matrix, and the missing-settings/first-save publication boundaries.

App-model commands used `/tmp/tidy-r05-resume-xcode`, `-jobs 2`, the macOS arm64 destination,
signing disabled, and 17 selected tests:

- all fourteen `testT081b...` scheduler/settings handoff, provenance, disk-race, and reservation tests;
- pristine explicit scan without a settings write;
- bootstrap/Settings opening with no scan or process work;
- selected-project scope with no roots.

Result: **17 tests passed, 0 failures**. The pristine test also observed zero pre-request sessions,
zero active work, zero explicit monitor leases, no monitor timer, no index watch, unchanged absence of
`config.json`, a nonempty Quick result from the owned cache fixture, and released scan resources.

`git diff --check` passed for the R05-owned files. Existing compiler warnings in unrelated tests were
unchanged by this unit.

## Remaining acceptance

This source/model evidence does not establish the R13 human VoiceOver journey, supported physical
host/runtime matrix, 8 GiB reference performance, packaged install, distribution, or release
acceptance. Those remain separately recorded gates. They do not invalidate or block this bounded
source implementation, and none is claimed here.

Tool discovery, Clean mutation reachability, DerivedData ownership/quiescence, T04.C recovery, and
positive mutator contention remain unavailable until their approved dependencies close.
