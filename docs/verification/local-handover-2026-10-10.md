# Tidy reconciled local handover

Subsequent macOS work and fresh evidence are recorded in
[10 October local completion](completion-20261010.md). The Linux checkpoint below
remains historical; its unrun-test statement is not the latest verification state.

The audit checkpoint has been reconciled onto main for continuation on macOS.
Use `codex/audit-reconciled-20261010`. Its base is
`9da3196c8fc3b17791c15cacbf15f2b02aa7e3d4`, which already includes the 67 commits
missing from the original audit workspace. This patch has not been compiled or
tested. Production cleanup remains quarantined; no release acceptance is claimed.

## Branches and local checkout

Repository: <https://github.com/Ajraba04/tidy>.
The original `codex/audit-remediation-handover-20261010` branch at `418ec00` is
preserved as historical evidence. Its older implementation and unfinished-feature
list are superseded by this reconciliation. No blind merge or forced update of
that checkpoint was performed.

From an existing clone, obtain the reconciled source in a separate worktree:

```bash
git fetch origin
git worktree add -b local/audit-reconciled ../tidy-audit-reconciled origin/codex/audit-reconciled-20261010
cd ../tidy-audit-reconciled
```

Choose unused branch/directory names if these already exist. Inspect the new patch
with `git diff origin/main...HEAD`. Its base includes main's richer recovery,
project inventory, Build Prep, ecosystem adapters, assistance and verification
infrastructure. These were not replaced by the older checkpoint implementations.

## Reconciliation decisions

| Audit group | Decision and source evidence |
| --- | --- |
| F01 tool discovery and first scan | Retain main's scope-authorized discovery and store-bound fresh-default admission in `ScanScope`, `ExecutionPolicyBridge`, and `AppExecutionServices`. Do not add bootstrap tool discovery or save settings merely to enable the first scan. The older onboarding detector remains; detected tools do not grant adapter authority. |
| F02 reviewed resource binding | Retain main's `ResourcePreflight`, `ReviewedManifestStore`, original-resource dispatch and producer-proof checks. Do not replace them with in-memory recapture comparison. |
| F03 recovery | Retain `EffectLifecycle`, persisted terminal proof, artifact validation and main's recovery tests. Do not port the older lock-only synchronous-intent retirement, legacy-run abandonment, or reduced fixture suite. |
| F04 bounded capture | Keep main's existing total manifest/work/deadline bounds. Add the missing 64-component limit before `DirectoryAnchor` acquires ancestor descriptors. |
| F05 protected paths | Add mandatory cloud roots to explicitly supplied environment lists while preserving order; forward exclusions through older bounded build-output and stale dependency discovery and its legacy scan caller. Reject planning candidates that contain a protected descendant. Retain main's scoped production traversal and richer protected-resource checks. |
| F06 live scheduling | Keep main's monotonic, configured critical cooldown and scoped scan observation path. Carry independent power/thermal flags through the existing app-to-bridge-to-scheduler route so a thermal-only signal cannot apply a low-power-only pause rule, or vice versa. Warning pressure retains main's conservative constrained mapping. Do not port the five-second cooldown or alternate observation queue. |
| F07 scan lifecycle | Keep main's scope-bound startup, cancellation during startup/rescan, retained results, index checkpoint continuation and cleanup ownership. Its scoped scan path explicitly permits live observation changes; the older epoch-deduplication workaround is not substituted. |
| F08 monitor consumers | Keep main's generation-ordered scene leases, explicit-work leases and disposal. Do not replace them with raw visibility UUIDs. Preserve raw history across unchanged or cadence-only configuration updates, while still checking independently revoked local authority on every update. |
| F09 pressure recovery | Main already subscribes to normal/warning/critical and rejects obsolete callbacks. Clear pressure and page-out baselines when sampling stops, so a later measurement does not reuse the stopped subscription's signal. Retain main's immediate event publication without extra probes. |
| F10 settings imports | Carry nonblocking, no-follow descriptor open; regular-file/type/size checks; bounded reads and elapsed-time checks off the UI actor. Add visible progress/cancel and reject late results. Cancellation now also reaches the detached reader between syscalls. |
| F11 build and delivery | Keep main's pinned project tooling, stronger CI verifier, explicit test inventory, native UI/runtime isolation checks, universal Release build and packaging validation. Do not add the older weaker project checker or replace its release script. Require the new regression cases in the existing verifier. |
| F12 optional history | Keep `OptionalRunHistoryStore`, acknowledged revision ordering, bounded atomic storage and existing privacy/recovery witnesses. `RunLog` has no production caller; the older replacement of that legacy API is not imported. |
| F13 product claims | Keep main's capability/acceptance README and full Developer Workspace/Assistance UI. Correct remaining onboarding and menu cleanup claims, label removed allocation separately from physical reclamation, and expose effect statuses. Headroom already reads live card order from acknowledged policy. |
| Partial T11 inventory and policy projection | Keep main's `ProjectInventory`, `ActivityResolver`, `ResourceOwnership`, workspace protection controls, ranking and scoped ecosystem consumers. Do not add the older Scan marker section, alternate `ScanReport` fields, optional-policy environment plumbing or blanket claims that those newer features are absent. |

The complete checkpoint file set can be recovered with:

```bash
git diff --name-status 9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a 418ec0065022e01563f914efdd1b518abb94fd60
```

All other changes to app bootstrap, Settings projection, scan presentation,
coordinator, journals, project configuration and older roadmap documentation were
superseded by the newer implementations above. Original tests were retained; only
targeted regression cases were added or their existing fixture extended.

## Verification to run on macOS

No Swift compilation, tests, app launch, dependency installation, generators,
platform tools or packaging ran in Linux. Local evidence consists of
`git diff --check`, source/call-site inspection, shell syntax parsing without
execution, privacy-manifest XML parsing, and read-only handover link/API-location
checks. New cases cover protected catalog roots and
custom exclusions, protected ancestors, anchor descriptor limits, history
preservation/opt-out, stopped pressure, independent scheduling restrictions, and
FIFO/symlink imports. The verifier requires these cases so missing discovery
cannot silently pass. They are written but unrun.

Use Xcode and the repository's pinned XcodeGen tooling as described in
[CONTRIBUTING](../../CONTRIBUTING.md). First review and run the current source and
privacy inventory checks on macOS. Then run focused Core regressions, the app-model
target, and the full verifier when ready for its synthetic UI and Release gates:

```bash
swift test --package-path TidyCore --jobs 2 --no-parallel \
  --filter 'CoreOrchestrationTests|StaleNodeModulesScannerTests|PathGuardTests|HeadroomSignalsTests|ScanObservationTests|anchorDescriptorLimitPrecedesFilesystemAccess'
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath ./DerivedData test CODE_SIGNING_ALLOWED=NO
bash scripts/verification/verify.sh
```

The full verifier runs isolated process admission separately; retain that separation.
Resolve failures before accepting the integration. Check import cancellation and
close/reopen, monitor opt-out and local-consent revocation, cloud exclusions, and
the power-only/thermal-only pause rules. Existing production quarantines must stay
closed during validation. Use disposable fixtures for effects.

The required-reason API inventory was updated manually for changed source token
locations and the new import metadata/deadline uses. Its native checker remains
unrun, and no new manifest category or reason was asserted. A read deadline cannot
interrupt an already blocked kernel syscall; cancellation prevents applying a late
result and stops subsequent reads.

## Remaining acceptance and continuation

Start with main's [September 20 source checkpoint](code-completion-20260920.md),
[September 22 continuation](code-continuation-20260922.md),
[acceptance record](headroom-acceptance.md), and
[producer dependency record](remediation-producer-dependency-resume.md).
Read their dates and exact tested revisions; historical passing checks do not
validate this integration. Later source implementation supersedes earlier pending
feature lists, while unclosed production, device and release gates still apply.

Local next step: validate this reconciled branch, fix integration failures, then
continue the remaining accepted program from its newer main implementation.
Keep source completion separate from ownership/exclusion proof, native and
physical acceptance, privacy-purpose approval, signing and release acceptance.
The unattended mutation allowlist remains empty. This handover and branch push do
not authorize a release or turn fixture evidence into production effect authority.
