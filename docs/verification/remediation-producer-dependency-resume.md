# Producer dependency resume: R02 and revision-zero scan

Date: 2026-09-19

Revision inspected: `b4acfff2a78343884457b14ee5d9efba3df91e12`

Scope: read-only dependency investigation plus this report. No build, test, Xcode
project action, process termination, permission change, security change, or
production/test/source edit was performed.

Implementation follow-up: the bounded R05 revision-zero explicit scan unit identified below was
subsequently implemented and focused-verified in the same resume; see
`remediation-R05-resume.md`. The R02 producer verdict and blocked mutation dependencies are
unchanged.

## Decision

**R02 production acceptance remains unavailable on the installed supported Xcode
surface.** The current tools establish a supported way to choose a DerivedData
output path, but do not establish either of the two positive authorities required
by the approved contract:

1. a complete current mapping of every producer and shared owner that may write
   the reviewed shared DerivedData resource; and
2. a producer-owned exclusion/quiescence lease that Tidy can acquire immediately
   before mutation and hold across every unlink.

This is a finding that no qualifying supported interface was established after
checking the installed interfaces and Apple's primary documentation. It is not a
proof that no undocumented Xcode-internal lock exists. Undocumented locks, private
frameworks, process absence, Tidy's own advisory lock, and manual inactivity do not
satisfy the approved contract.

No alternate adapter in the approved appendix can be substituted to call R02
complete. The appendix permits independent per-adapter `.I` and `.M` units, but the
binding remediation plan assigns R02 the minimum **DerivedData** ownership subset
and separately makes supported real Xcode producer proof mandatory. Simulator,
Node output, Docker, Git, or app-owned-cache work belongs to later adapter units;
it neither proves ownership of the shared DerivedData root nor removes R02 from the
required order.

The independently implementable product unit now available is R05's **read-only,
explicit revision-zero scan admission**, because R06/R08 have supplied the source
gates on which that part of R05 depends. That change can and should retain
`detectedTools: []` and all fixed-deny mutation behavior. It does not depend on R02,
R03, or R04 because it grants traversal only, never effect authority.

## Installed supported interface evidence

The current host reports:

```text
$ xcodebuild -version
Xcode 27.0
Build version 27A266a

$ xcrun xcresulttool --version
xcresulttool version 25115, schema version: 0.4.0

$ sw_vers
ProductName: macOS
ProductVersion: 27.0
BuildVersion: 26A428

$ uname -m
arm64
```

The installed `xcodebuild -help` surface contains:

```text
-derivedDataPath PATH
    specifies the directory where build products and other derived data will go
-resultBundlePath PATH
-resultStreamPath PATH
```

The installed `xcodebuild(1)` manual describes `-derivedDataPath` as overriding the
folder used for derived data for an action on a scheme. Its `clean` action removes
build products and intermediate files from the build root. Neither the help nor
the manual documents owner enumeration, an externally acquirable exclusion lease,
or a quiescence token for the shared root. Searches of those installed primary
interfaces for `exclusive`, `quiescence`, `owner`, `producer`, and `lock` yielded no
such interface. `xcresulttool help` exposes read/export/metadata/merge/compare of
result bundles; it does not mediate live DerivedData producers.

Apple's current primary documentation is consistent with the installed tools:

- [Xcode command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
  identifies `xcodebuild` as the project/workspace build tool and directs callers
  to its manual; it does not describe an external DerivedData exclusion service.
- [Distributing documentation to other developers](https://developer.apple.com/documentation/xcode/distributing-documentation-to-other-developers)
  demonstrates `xcodebuild docbuild -derivedDataPath ...` and states that
  `xcodebuild` produces many files there. This proves that the option selects a
  producer output location; it does not make the caller the exclusive owner of a
  pre-existing shared root.
- [Build system](https://developer.apple.com/documentation/xcode/build-system) and
  [Running custom scripts during a build](https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build)
  describe Xcode's internal task/dependency scheduling. Declared script inputs and
  outputs let Xcode order tasks within its build graph; they do not expose a lease
  to an unrelated cleanup application.
- [Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)
  exposes Xcode Cloud build paths, actions, and exit data, including
  `CI_DERIVED_DATA_PATH`; it does not enumerate or exclude local Xcode IDE,
  indexing, preview, test, documentation, package-resolution, or helper writers.

Consequently, these otherwise plausible approaches are not qualifying proof:

| Approach | Why it does not meet the approved contract |
|---|---|
| Invoke `xcodebuild` with `-derivedDataPath` and wait for it to exit | Selects one invocation's output path; does not exclude the IDE or other invocations/helpers from the same shared resource. |
| Invoke `xcodebuild clean` | Performs another effect and still does not establish complete shared owners or a lease for Tidy's reviewed manifest. |
| Read Xcode preference paths or DerivedData directory names | Associates paths heuristically; does not prove all current owners/producers or quiescence. |
| Observe no Xcode/build process | The contract explicitly rejects process absence as positive evidence; helpers and future writers remain unexcluded. |
| Acquire `flock`, `fcntl`, or a sentinel lock created by Tidy | A Tidy-owned advisory lock is not a primitive every Xcode producer is required to honor. |
| Ask the user to acknowledge inactivity | The appendix allows manual acknowledgement only under a separately approved adapter contract, while R02 additionally requires supported real Xcode producer proof. The current production validator accepts only producer-manifest association and producer-exclusion-lease runtime proof. |
| Use private Xcode frameworks, daemon protocols, or observed internal lock files | They are not a supported versioned interface and cannot provide the required portable contract or safe unsupported-version denial. |
| Have Tidy create and exclusively manage a new build root | This could define a different app-owned producer model, but Tidy does not currently own Xcode builds. Adding such a managed-build workflow is a feature and scope change, not R02 remediation. |

## Contract trace and alternate-adapter result

The binding contracts line up without an ambiguity that code alone can resolve:

- `docs/superpowers/specs/2026-08-26-headroom-policy-and-adapter-contracts.md`
  section 4 requires complete producer mapping and positive quiescence for every
  owner; a generic process scan is insufficient. It allows manual acknowledgement
  only for separately warned manual actions and says unsupported proof remains
  manual-with-acknowledgement or inventory-only.
- The same appendix section 5 makes `.I` and `.M` independent **per adapter**.
  Inventory may ship alone. Every `.M` must state its supported version, ownership
  proof, denial conditions, effect scope, and completion/recovery probe.
- `docs/audits/2026-09-17-9e1a500/remediation-plan.md` R02 narrows the first
  production prerequisite to shared Xcode DerivedData and says that supported real
  Xcode producer proof is additionally mandatory. A synthetic lease alone is
  insufficient; unsupported proof leaves the adapter denied and the promised
  mutation incomplete.
- The plan's required order is R01 -> R02 -> R03 -> R04. R09 follows R02-R08;
  R10 follows the relevant R09 contracts; R11 follows supported adapters and the
  authority foundation. Moving one of their adapters ahead as a replacement for
  DerivedData would change that approved order and would still leave R02 open.
- `docs/superpowers/tasks/T04-journal-and-recovery.md` section C requires an
  accepted adapter-specific positive terminal protocol and explicitly forbids a
  generic clear operation, caller-provided terminal Boolean, or PID-disappearance
  reset. Its entry remains stopped until the complete adapter-bound C matrix and
  controlled crash driver exist.

The approved appendix therefore supplies future adapter contracts, not an alternate
R02 exit. In particular:

- `Apple.M` for an exact simulator UDID has supported `simctl` identity/state
  semantics, but it is a different resource/effect and belongs to R10.
- `Node.M` describes removing unchanged leaves from a reviewed output manifest,
  but still requires its own complete ownership/activity contract and does not
  confer authority over shared Xcode DerivedData.
- The appendix's positive immutable-cache fixture proves the generic authority
  shape only. A fixture lease cannot be installed as production Xcode authority.

## Exact R02 dependency exit

R02 can exit only after one supported Xcode-versioned production contract supplies
all of the following and survives independent review:

1. **Exact resource identity:** the same sealed volume/root/ancestor/leaf manifest
   and protection scope already implemented.
2. **Complete association:** a supported producer-owned manifest/API identifies
   all recognized producer IDs, all current owner IDs, and every shared owner for
   that exact resource. Unsupported versions and incomplete/denied enumeration
   remain inventory-only.
3. **Positive exclusion:** immediately before the first effect, Tidy acquires a
   producer-owned lease that every producer for the resource must honor. Acquisition
   precedes the fresh observation; the live lease is held across every unlink and
   has the existing five-second wall/monotonic bound.
4. **Real race evidence:** positive unchanged-leaf removal and negative
   writer-start/shared-owner/version/expiry/replacement cases exercise the actual
   supported primitive, not the fixture provider.
5. **Adapter-specific terminal semantics:** the accepted `.M` contract defines how
   R03 proves the original operation terminal after crash without replay, a generic
   success flag, or PID absence.

The first two missing inputs are not implementable from the currently documented
Xcode surface. The existing source correctly expresses that state:

- `AppleDerivedDataInventory` returns `inventoryOnly`, no owner IDs, partial
  confidence, unknown activity, and a nil production lease provider.
- `DerivedDataEffectAdapter.execute` returns `productionProofUnavailable`.
- `ResourceAuthorityValidator` accepts only `.producerManifest` association and
  `.producerExclusionLease` runtime proof, with exact adapter/resource/producer/
  owner/shared-owner matching and five-second monotonic and wall-clock bounds.

If Apple later publishes a qualifying interface, the concrete engineering unit is
to implement those two producer-backed providers plus the real matrix above. Until
then, adding more process heuristics or another Tidy lock would add code without
advancing acceptance.

## Dependency consequences and work that remains independently implementable

| Unit | Current dependency result | Work permitted without weakening the plan |
|---|---|---|
| R02 DerivedData mutation | **Unavailable** | Preserve inventory and quarantine. No additional production-effect implementation has a supported authority input today. |
| R03 durable positive-effect lifecycle | **Blocked for production closure** | The bounded archive format exists, but T04.C cannot enter or close without an accepted real `.M` terminal protocol and its complete crash matrix. Existing no-effect admission/journal A/B foundations may remain verified; they cannot be presented as R03 closure. |
| R04 effect scheduling/contention | **Blocked for positive mutator acceptance** | Read-only scheduler and denial behavior can remain tested. Positive mutator contention, cancellation, resource measurement, and effect-boundary acceptance wait for R02/R03. |
| R05 tool handoff and mutation usefulness | **Blocked** | R01's explicit prohibition remains: do not hand detected tools into the cleanup environment before R02-R04. A tool-presence bit must not make any catalog mutation reachable. |
| R05 revision-zero explicit scan | **Implementable now** | Install validated in-memory new-default scan policy, keep `detectedTools: []`, and admit only user-requested authorized traversal. Details below. |
| R09 projects/ranking/Build Prep | **Not an R02 substitute; ordered later** | Task cards or read-only research can be prepared, but production completion remains after R02-R08 under the binding order. Its inventory cannot retroactively close DerivedData ownership. |
| R10 ecosystem `.I`/`.M` units | **Not an R02 substitute; ordered after R09** | Per-adapter inventory is separable in the appendix, but executing it ahead as the first accepted mutation would require a plan/order revision. Denial-only behavior remains valid. |
| R11 rescue/assistance | **Effect portions dependency-blocked** | Consent, notification, or presentation work does not grant mutation. Exact supported actions still follow their accepted adapters and authority foundation. |
| R12/R14 preparation and R13 harnesses | **Independent preparation remains valid** | Reproducible builds, packaging/docs preparation, safe fixture harnesses, and source/model verification can proceed. Missing human VoiceOver, physical host, distribution, and reference-performance evidence remains explicitly incomplete; it is not a source-implementation blocker. |

## R05 recommendation: revision-zero scope-only scan

### Why the approved plan permits it

R05 says R02-R04 are prerequisites **for mutation enablement** and R06/R08 are the
prerequisites **for scan/monitor enablement**. It separately requires validated
revision-zero defaults for explicit scan without background work. The plan review
required R06's scope, live-observation, session, cancellation, and continuation
gates before shipping that restoration. Those source gates are now present:

- `AppExecutionServices.beginReservedScan` authorizes policy-default or one-run
  full-home scope, creates one explicit `.headroom` scheduler session, starts the
  app-owned observation lease, and passes the opaque scope into `ScanEngine`.
- `ScanScopeAuthority` binds roots, exclusions, policy revision, owner, volume/root
  identities, expiry, and a private grant ledger. The default policy cannot silently
  select full-home; full-home requires a separate expiring single-use consent.
- The service retains global session/cancel ownership, prevents duplicate active
  starts, preserves generation-bound continuation, and closes observation/index
  resources at the session boundary.
- `ScanViewModel` and `ScanScopeAuthority` both deliberately create environments
  with `detectedTools: []`.

The remaining fresh-install failure is now a narrow bootstrap rule rather than a
missing scan safety layer:

- `SettingsStore` returns `.newDefaults` with a validated in-memory schema-2,
  revision-zero envelope when no settings bytes exist.
- `ExecutionPolicyBridge` only calls `installInitialScheduler` when
  `envelope.revision > 0`.
- `ScanScopeAuthority.policySnapshot` independently rejects every envelope whose
  revision is not positive.
- `AppExecutionServices.beginReservedScan` therefore sees scheduler availability
  `.unavailable` and reports `policyNotInstalled`.

### Bounded implementation shape

Implement this as scan-policy provenance, not as execution-policy or tool authority:

1. In `ExecutionPolicyBridge`, recognize only a successfully loaded
   `.newDefaults` envelope with schema 2 and revision 0 as an in-memory default scan
   policy. Run it through the same scheduler resolution/first-install invalidating
   path used by durable positive revisions. Keep `.recoveryReadOnly` unavailable.
   Do not infer this provenance from `revision == 0` alone: a migrated, forged test,
   or arbitrary stored revision-zero document is a separate case and should remain
   fail-closed unless explicitly specified and tested.
2. Expose an internal read-only snapshot/provenance check for
   `ScanScopeAuthority` so it can accept either a durable acknowledged policy or
   that exact validated `.newDefaults` scan policy. Do not merely delete the
   `revision > 0` guard.
3. Keep the coordinator environment and every scan environment at
   `detectedTools: []`. Do not call `ToolchainDetector`, alter
   `CapabilityRegistry`, populate `productionLeaseProvider`, or make Clean review
   execution-ready.
4. Installing scheduler policy at bootstrap must launch no traversal, command,
   index watcher, or hidden monitor lease. Existing `beginScan` remains the sole
   trigger for explicit work and obtains the scope grant and live observation.
5. Retain the admission transition around the first concurrent settings save.
   Once revision 0 is operative, a successfully persisted revision 1 must replace
   it through the existing invalidation barrier; save failure or recovery must fail
   closed without leaving the scan scheduler on unacknowledged edited values.
6. Replace the fresh-install “save settings once” error path with the normal scan
   result. Preserve actionable unavailable states for corrupt, future-schema,
   unsafe-location, oversized, and recovery-read-only settings.

### Minimum focused acceptance

The implementation should add source/model tests proving:

1. a pristine `.newDefaults` bootstrap performs no traversal until `runScan`, then
   scans only authorized Quick roots with `detectedTools: []`;
2. an empty selected-project scope visits no unrelated witness and finishes
   truthfully with no scope expansion;
3. corrupt and future-schema settings keep the scheduler and scan scope unavailable;
4. a concurrent first save closes admission, then revision 1 replaces revision 0;
   failed/cancelled/conflicting save never applies edited policy;
5. `CapabilityRegistry` remains fixed-deny, `AppleDerivedDataInventory` remains
   inventory-only, and a tool-presence bit is never introduced by the scan change;
6. merely bootstrapping/opening the Scan UI starts no traversal, command, or index
   watch; explicit work acquires and later releases the monitor lease;
7. global cancellation, duplicate-start convergence, policy invalidation, and
   continuation behavior remain unchanged at revision zero.

These tests establish the implementation boundary. R13 human accessibility,
physical macOS/hardware, reference-memory/performance, and production-journey
evidence still has to be recorded separately and must not be claimed from the
source/model pass, but those later acceptance gates do not block implementing this
approved read-only path.

## Recommended next dependency actions

1. Implement the bounded R05 revision-zero scan unit above without any tool
   discovery or mutation handoff.
2. Keep R02 marked `production acceptance BLOCKED` and retain DerivedData
   inventory/quarantine.
3. Do not enter T04.C/R03 positive-effect work until a real supported `.M` terminal
   protocol and the complete driver/matrix exist.
4. Continue independent packaging, safe native-harness, source/model, and truthful
   unavailable-state work, while recording R13 and distribution evidence as
   separate incomplete gates.
5. Revisit R02 only on a concrete supported producer interface or an explicitly
   approved plan revision. Neither process heuristics nor manual acknowledgement is
   a dependency exit.
