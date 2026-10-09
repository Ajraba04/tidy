# Tidy local continuation handover

Prepared 10 October 2026 for continuation on macOS. This branch preserves the
Linux audit remediation and partial project inventory work. It is unverified:
no Swift compilation, app launch, tests, project generation, packaging, or release
was performed. Production cleanup remains denied, including DerivedData.

## Start with the newer main branch

Repository: <https://github.com/Ajraba04/tidy>.
Checkpoint branch: `codex/audit-remediation-handover-20261010`.
Original base: `9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a`.
Remote main observed at handover: `9da3196c8fc3b17791c15cacbf15f2b02aa7e3d4`.

Remote main is 67 commits ahead of the original base. It includes a separate audit
remediation, richer project/ownership inventory, Build Prep, ecosystem inventory,
assistance, and native verification tooling. Its checkpoint reports still defer
full acceptance. Those changes were discovered during publication and have not
been merged into this checkpoint. Both histories modify many of the same files,
including files with identical names under `TidyCore/Sources/TidyCore/Projects`.

Use current main as the integration baseline. Compare this branch for fixes or
regression cases that main still needs; do not replace its newer implementations
or copy this branch's incomplete-feature claims into current documentation.
The October date of this handover does not make its source baseline newer.

From an existing local clone, fetch and create a separate worktree to inspect the
exact checkpoint without disturbing local changes:

```bash
git fetch origin
git worktree add -b local/audit-handover ../tidy-audit-handover origin/codex/audit-remediation-handover-20261010
```

For integration on the latest main in another worktree:

```bash
git worktree add -b local/audit-integration ../tidy-audit-integration origin/main
```

Choose unused local branch and directory names if these already exist. Inspect
the checkpoint's own patch against its base, then compare relevant paths with main:

```bash
git diff 9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a..origin/codex/audit-remediation-handover-20261010 --stat
git log --oneline 9e1a50094b73e3c2a9bf136d9ed7e58ea8dc9c4a..origin/main
git diff origin/main origin/codex/audit-remediation-handover-20261010 -- TidyCore/Sources/TidyCore/Execution
```

Read main's `docs/verification/code-completion-20260920.md`,
`docs/verification/code-continuation-20260922.md`, and current acceptance/recovery
records before selecting changes. Their reported passing checks apply to their
recorded revisions, not to this branch or a future integration.

## What this checkpoint contains

The [implementation ledger](headroom-progress.md#implemented-source-changes-awaiting-native-verification)
maps findings F01–F13 to source changes and unresolved validation. Main areas are:

- Retained reviewed manifests and identities, bounded capture/effects, explicit
  intent/start/terminal/finish journaling, and conservative synchronous recovery.
- Shared tool discovery and acknowledged policy, cloud protections, scan session
  lifetime and cancellation, explicit-scan indexing, and per-session results.
- Shared monitor visibility, normal-pressure recovery, scheduler signal wiring,
  and deduplication so unchanged observations do not invalidate active scans.
- Bounded regular-file imports off the UI actor and serialized optional history
  retention, redaction, and opt-out handling.
- Read-only project marker inventory under approved roots, bounded traversal,
  unresolved Git indirection presentation, and conservative activity evidence.
- App-model/CI source membership changes, regression fixtures, and truthful
  inventory-only UI and documentation.

Project inventory is partial T11 only: marker evidence does not establish
ownership, quiescence, or permission to delete. No producer lease exists in this
branch. All production mutation stays quarantined; the unattended allowlist stays
empty. Fixture access to an internal adapter is not production authorization.

## Local verification order

First reconcile source against main, preserving its stronger contracts and test
coverage. Then inspect the chosen revision's verification scripts and run its
native gates. This branch's `.github/workflows/ci.yml` contains the following
baseline commands; these are instructions for macOS, not commands run here:

```bash
python3 scripts/check-project-sources.py
swift test --package-path TidyCore
TIDY_ISOLATED_GATE_TESTS=1 swift test --package-path TidyCore --filter CoreOrchestrationTests
xcodebuild -project Tidy.xcodeproj -scheme TidyAppModelTests -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath ./DerivedData test CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug \
  -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64"
```

Use main's newer verification entrypoints when validating an integrated revision.
Do not overwrite its committed Xcode project by blindly regenerating this older
branch's `project.yml`. Check source/resource membership and inspect any generated
diff deliberately. Run the process admission gate separately from other tests.

Prioritize scan startup/cancel/reopen, policy changes during work, scheduler epoch
stability, concurrent monitor consumers, import FIFO/symlink handling, history
retention/opt-out, and journal interruption/relaunch cases. Effects belong only in
disposable fixtures. Record the exact revision, toolchain, commands, failures and
passing results in the ledger. The Linux checks were limited to source inspection,
diff whitespace, configured path existence, and Python syntax parsing.

## Remaining work and known limits

Reassess the [remaining program gates](headroom-progress.md#remaining-program-gates--do-not-mark-complete)
against main before implementing more features. This branch leaves privacy data
clearing/reassociation, full project ownership, ranking/Build Prep, Pressure Rescue,
ecosystem acceptance, budgets/notifications, maintenance authority, and complete
native/device/release acceptance unfinished. Several already have newer source
implementations on main; their acceptance must be assessed there.

Branch-specific limitations include uncertain per-leaf outcomes after a crash,
non-atomic optional-history rewrites, and inability to interrupt an already blocked
kernel read. Git indirections remain unresolved. UI, accessibility, minimum OS,
both architectures, physical performance, privacy declarations, signing and
notarization remain acceptance work. Neither this handover nor the push grants
production mutation acceptance or constitutes a release.

## Suggested continuation prompt

Continue Tidy locally on macOS. Read this handover and the latest main verification
records first. Compare the audit checkpoint branch against current main, retain
only missing improvements, and preserve current main's stronger implementation
and tests. Run appropriate native gates for the resulting revision, fix failures,
and update evidence before proceeding through the remaining program. Keep all
unsupported production mutations denied and distinguish source completion from
runtime and device acceptance.
