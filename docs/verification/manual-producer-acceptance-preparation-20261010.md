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
