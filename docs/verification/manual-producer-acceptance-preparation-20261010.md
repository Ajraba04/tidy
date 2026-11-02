# Manual producer acceptance preparation — 10 October 2026

Status: preparation only. No live simulator or Docker effects are authorized by
this record. The owner approved engineering and local synthetic fixtures; the
[decision](cleanup-contract-decision-20261010.md) explicitly reserves live
service/device effects. The app's compiled provider acceptance remains denied.
The coordinator must finish the fixed clients and acceptance driver, inspect the
exact procedure, and obtain the remaining authority before executing it.

## Earlier read-only host inventory

The current isolated source worktree is
`/Users/mac/.codex/worktrees/tidy-completion/tidy`, branch
`CAJ/tidy-completion-20261010`, based on checkpoint `a09bc5d` plus the recorded WIP.
Xcode is **27.0 / 27A266a**. The resolver is `/usr/bin/xcrun`; the selected actual
simctl is `/Applications/Xcode.app/Contents/Developer/usr/bin/simctl`, reporting
**CoreSimulator1171.7**. `Contents/version.plist` agrees with Xcode's version/build.
The available iOS runtime is `com.apple.CoreSimulator.SimRuntime.iOS-27-0`, build
24A434, arm64. No runtime installation or download is needed for the simulator
fixture described below.

At the earlier inspection, the shared default set contained four Shutdown devices, with one phone/watch
pair belonging to the independent BADAN task. The earlier retained inventory of
two devices and no pairs is stale. The independent resource queue has since run other device tests, so this is a
historical snapshot, not the current set inventory. Refresh the outside witness
immediately before any authorized acceptance run. Inventory establishes no
authority to alter these resources; they are outside this procedure.

Installed command-line tooling reports Docker29.8.2, Colima0.10.3 and Lima2.2.1.
These are CLI versions; no actual Docker daemon's API/version, identity or local
backend arrangement has been accepted. CoTeam's existing Lima/QEMU VM is reserved
by that independent task and is excluded. No Docker daemon was contacted during
this preparation.

## Simulator procedure to finalize before requesting authority

Create a new private temporary parent and explicit device set, retaining its
canonical path and filesystem identity. Every simctl invocation uses the pinned
actual executable, `--set <that exact path>` and explicit DEVELOPER_DIR/HOME/PATH.
No default-set command, ambient `booted` selector, `all` selector, erase, runtime
download, project script or user device is included.

1. Capture complete default devices/runtimes/pairs data as an outside state
   witness, plus an independently retained private-file witness.
2. Create two named disposable devices in the new explicit set using the
   installed iOS27 runtime and a supported exact device-type identifier. Record
   each returned full UDID once; a missing/duplicate/malformed identity aborts.
3. Keep one fixture Shutdown as the outside target witness. Boot only the other
   exact fixture UDID. Capture complete devices/runtimes/pairs in that set and
   verify the target is available, Booted and unpaired.
4. Run one fixed typed shutdown of the reviewed UDID through the owned process
   launcher and real isolated journal. This step must persist submission before
   spawn, persist the captured child identity, consume its own normal exit and
   obtain complete fresh same-set inventory before publishing a terminal proof.
5. Verify the target is Shutdown, the second fixture is unchanged, the default
   devices/pairs witness is unchanged, and recovery after proof publication
   reconciles without replay. Retain source/tool/host/command/object/proof hashes.
6. Delete only the two recorded disposable UDIDs from that same set after their
   state and ownership are revalidated. Remove only this procedure's private
   temporary files after evidence export. Retain the outside witness.

The approved engineering scope does not yet authorize these creation, boot,
shutdown or fixture-deletion effects. The exact finalized driver, identifiers
allocated at setup, resource limits and cleanup commands belong in the eventual
owner request. A failed postcondition remains uncertainty, never permission to
retry or mutate another device.

## Docker procedure remains a separate preparation gate

Do not reuse the default Docker context, a user daemon, CoTeam's VM or any
container found by inventory. A qualifying fixture needs a new dedicated local
backend, no home/project mounts, no Kubernetes, no context activation, fixed
resource limits and an explicitly reviewed image source or local image input.
Creating/downloading/starting that backend is a separate live authority action.
Its macOS Unix peer and local backend arrangement require a named versioned
provider contract; self-reported Engine JSON is insufficient.

After that provider is established, create an owned exited unmounted unmanaged
container and a separate outside witness container. Record the full64hex target
ID, labels, configuration and complete version/info/inspect data. The fixed
operation uses one retained peer connection and
`DELETE /v<bound-api>/containers/<full-id>?force=false&v=false&link=false`, then an
exact-ID same-connection absent postcondition. Do not prune, force-stop, remove
volumes, remove images or resend a lost request. A documented409 is refusal;
strict exact-ID404 is no work; unknown/lost/malformed replies remain uncertain.
The full-container writable/log/configuration consequence is mandatory even
when reported SizeRw is zero or absent.

The request and response contract is sourced from the
[Docker Engine API reference](https://docs.docker.com/reference/api/engine/version/v1.47/).
The negotiated live API and Engine version must be captured rather than inferred
from the installed CLI. The current fake peer tests establish transport and
journal behavior only. No production activation is justified by this document.


### Dedicated Docker backend preparation, resumed checkpoint

Read-only installed CLI help was refreshed: Colima0.10.3 commit
`00f6c297e92a82c04a4ab507db0a61435650d7e8`, Lima2.2.1.
`dist/verification/completion-20261010/colima-start-help.txt` confirms explicit
`--mount=none`, `--activate=false`, `--ssh-config=false`, `--ssh-agent=false`,
`--kubernetes=false`, `--template=false`, resource bounds and a profile name.
The official [Colima defaults](https://github.com/abiosoft/colima/blob/main/embedded/defaults/colima.yaml)
explain why defaults must not be assumed: home mounts and an automatic VM-image
download are possible. The [official FAQ](https://github.com/abiosoft/colima/blob/main/docs/FAQ.md)
describes separate configuration/cache/client directories and profile socket
paths. These are preparation facts, not installed-backend acceptance.

A future owner request must name a new fixture-only profile, independent
COLIMA_HOME/COLIMA_CACHE_HOME/LIMA_HOME/DOCKER_CONFIG directories, bounded CPU/RAM
and virtual disks, no home/project mounts, no Kubernetes or host context
activation, no agent forwarding or modification of host SSH configuration, and
an exact reviewed VM image/container image source. Do not reuse a template,
context, keys, socket or backend from another project. The retained Unix peer
must then be bound to that named versioned backend arrangement; the installed
CLI versions and self-reported daemon JSON cannot establish that binding.
No VM creation, download, socket connection or Docker effect ran here.

## Prepared SDK command-semantics driver

`scripts/verification/manual-simulator-acceptance.py` is preparation for a
separate owner-authorized SDK experiment. It does **not** exercise Tidy's native
owned launcher, policy bridge, journal, proof verifier or durable process-gate
retirement. Its successful result cannot qualify a producer or activate the
compiled registry. The production providers remain **DENIED**. A later Tidy
app-owned positive acceptance procedure remains a separate gate.

The default invocation prints a plan without invoking simctl or codesign. It
reads bounded filesystem witnesses only and creates no resource unless `--plan`
explicitly requests one new mode0600 JSON file directly inside the existing,
caller-owned mode0700 `--output-root`. It neither creates the output root nor
creates devices in planning mode. The coordinator must inspect the script and
plan and obtain the owner's remaining authority before using `--execute`.

```sh
python3 scripts/verification/manual-simulator-acceptance.py \
  --output-root /absolute/caller-owned/evidence \
  --plan /absolute/caller-owned/evidence/reviewed.json
```

The printed review includes the exact pinned executable/environment, supported
version tuple, installed-runtime requirement, command templates, fresh UUID
private parent/set, names, output-root identity, default-set filesystem witness,
limits and cleanup scope. Execution additionally requires that existing plan's
exact canonical path, reviewed SHA256 and exact output root. These arguments
bind the reviewed procedure; they are not a substitute for owner approval.
Changed commands/types/limits, replaced roots, existing fixture paths or a
changed host filesystem witness are refused before resource creation.

Execution validates Xcode27.0/27A266a metadata, Apple signature and pinned actual
simctl CoreSimulator1171.7. Complete bounded runtime JSON must establish that
the exact iOS27 runtime is available and supports the exact iPhone17 type before
the driver creates either device. There is no download/install command. Default
device/runtimes/pairs JSON is retained as an outside witness; device_set.plist,
device.plist configuration hashes and filesystem inventory are bound separately.
All simctl calls use an explicit set path and fixed PATH/HOME/DEVELOPER_DIR.

The driver creates two disposable devices in the fresh private set, records each
full UUID once, keeps the witness Shutdown, boots only the target, and submits
one exact shutdown of that recorded target. It retains its own observed Popen
wait result (success additionally requires exit code0) and complete same-set
postcondition. Exact target/runtime/type/name,
availability, witness state, unpaired set, outside default-set hash and an
independent private-file witness are required. All evidence is semantics data,
never a Tidy native receipt or terminal proof.

Resource bounds are 180 seconds total, 15 seconds per child, at most80 commands,
eight finite Booted observations, 1MiB per captured stdout/stderr stream and a
192MiB maximum evidence envelope derived from command/capture/report bounds.
No mutation is force-killed or retried. Timeout, nonzero/abnormal wait, malformed
or missing IDs, unknown state, output overflow, changed witnesses or identity
substitution stops the procedure, preserves fixtures and reports uncertainty.
An incomplete child wait does not establish quiescence or permission to retry.

Deletion occurs only after verified shutdown/postconditions and original
witness checks. Before each deletion, the complete private set must contain
exactly the remaining recorded devices, all available and Shutdown, with no
pairs; private set/parent identity and outside witnesses are rechecked. Only
those two individually recorded full UUIDs are deletion arguments. No all,
booted, unavailable, erase, default-set mutation or recursive filesystem cleanup
exists. Evidence and the private set/parent remain for inspection after success
as well as failure. There is no automatic uncertain-fixture cleanup.

Focused Python tests live in
`scripts/verification/tests/test_manual_simulator_acceptance.py`; they use pure
data and caller-owned temporary files, replace Popen with a mock, and cover the
no-SDK planning boundary, plan/host tampering, runtime availability/type checks,
exact target/witness postconditions, selector rejection and symbolic-file
refusal. No script execution, tests, SDK probe or live effects were performed by
the implementation helper. The coordinator owns inspection and verification.

### Dataless and retained-directory boundaries

The driver refuses SF_DATALESS0x40000000 on files and directories using metadata
before any corresponding file open/content read or directory enumeration.
Ancestors are checked without following aliases. Opened file and directory
descriptors are rechecked for this flag; no content read may hydrate a dataless
resource. Complete device-set filesystem enumeration uses a retained directory
descriptor, and device configuration reads are relative to that same chain.

The existing output root, evidence directory, /private/tmp, fresh private parent
and explicit device set use retained O_DIRECTORY|O_NOFOLLOW descriptor chains.
Owned children are created with mkdir(dir_fd=...), then captured and verified.
Every evidence file is written to a new private temporary leaf relative to the
held evidence descriptor, fsynced and published as a complete new hard link
without overwriting an existing leaf. The held and named identities of every
ancestor are checked before publication and before each SDK command. A renamed,
replaced or symbolic root/evidence/ancestor therefore refuses publication and
cannot redirect writes. Descriptors remain open for the whole execution and
close from child to parent afterward. Directory depth is capped at32; the
procedure's concurrent descriptor chains fit within128 owned directory FDs.
The bounded executable/source hash reads are also included in the reviewed
resource limits. A refused evidence namespace still preserves owned fixtures
and reports uncertainty on stdout; it does not retry publication elsewhere.

The coordinator's initial five pure Python tests passed. The four added P2
regressions then produced the expected RED (two failures and two missing-API
errors) before implementation. Implementation of the boundaries above is now
source-only, pending the coordinator's new verification; no SDK command or live
effect was executed by the helper.

After hard-link publication, the no-follow final leaf and staging name are
checked against the still-held staging descriptor: regular type, current owner,
mode0600, exact device/inode and exact written size must match; dataless flags
are checked again. A mismatched final leaf is refused and never blindly
unlinked. Staging cleanup likewise removes only a leaf still matching that held
owned inode and metadata. The coordinator observed the added publication-race
test fail for both a symlink substitution and a same-size foreign regular inode
before this fix. Its post-fix verification remains coordinator-owned. This
publication evidence still establishes SDK experiment data only and grants no
Tidy native proof or production acceptance.


### Coordinator verification and remaining execution boundary

The coordinator observed the dataless/parent-substitution RED (9 tests,
2 failures and2 missing-API errors), then9-test GREEN. A final publication
race review exposed staging-name substitution immediately before linking;
both symlink/foreign-regular regressions failed before the fix. The final
10-test suite passed in0.024s after held-descriptor/final-leaf validation and
preservation of unexpected leaves. Independent source review found those
P2 findings resolved and no new actionable P0/P1/P2 findings in that correction.
No SDK command or device effect occurred in these checks.

The reviewed plan is
`/private/tmp/Tidy-SDK-Review-C305ECA5-93BC-4852-B706-4F31E69F1D7A/reviewed.json`,
SHA256 `9fd07f3086605c1320659a249536b13ee8a10073294ec6a010e379ef8059e00e`.
Its private set parent is
`/private/tmp/Tidy-SDK-Semantics-8A9B5C5F-DC20-410B-93C3-15AA2A878AD8`.
Planning read bounded metadata only: zero SDK commands/device effects.
The owner explicitly approved this disposable SDK experiment in the current
chat. Do not ask that permission again for the same operation/resource scope.
The shared native/device slot remains held by Ghawazi; this authorization does
not override its lease. Revalidate the default-set witness after that lease is
released, refresh the review baseline if it changed without broadening any
approved effects, and wait for the coordinated exclusive SDK slot. Production
adapters remain denied and this experiment cannot qualify Tidy's bridge/journal.
