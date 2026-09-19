# R13 Current-Host Observation Harness Design

## Purpose

Build an external, test-only observer for the compile-scoped
`TidyProductionRuntimeHost`. It records current-host diagnostics that remain
independently feasible after the source remediation: hidden-off work, hidden work
with Headroom enabled but background authority unavailable, internal monitor/scan
state, file descriptors, children, process traffic, repeated scan/cancel settling,
and a bounded 50k whole-app scan. None of these observations may be relabeled as 8 GiB, Intel,
macOS 14, human VoiceOver, privacy-reason, package-install, or release acceptance.

## Architecture

Use a Python orchestrator at `scripts/verification/run-r13-observation.py` and a
small fixed-scenario contract in the runtime-only Swift source. The Python process
launches the already verified runtime bundle directly, retains exact child
ownership, samples it with installed read-only tools, and writes raw JSON/logs
under a UUID-owned `/private/tmp/tidy-r13-observation-*` directory. It never
launches normal `Tidy.app`.

The runtime host accepts only enumerated scenario flags. It accepts no home,
settings path, journal path, settings bytes, duration, worker count, capability,
or authority input. It prints its generated canonical root once and atomically
writes `state/runtime-ready.json` once after services and fixed policy settle.
The ready file is event-driven; the app does not run a repeating diagnostic poll.

The external script may accept the runtime `.app` path because that path selects
the binary to inspect, not storage or product authority. Before launch it requires
the exact runtime bundle identifier, executable location inside the bundle, and
the existing fixture markers. Durations and scenario settings are compiled into
the script and runtime host.

## Fixed runtime scenarios

### Hidden off

- Fixed launch flag: `--tidy-runtime-hidden-off`.
- Validated revision-one settings keep background monitoring disabled.
- Ready attestation requires `timerRunning=false`, zero scene leases, zero
  explicit-work leases, zero scan sessions, zero scan work, and all mutations
  denied.
- The observer records two minutes of CPU, RSS, footprint, FD, child, and network
  diagnostics. This is a current-host zero-work diagnostic, not universal proof
  that frameworks perform no I/O.

### Hidden with no background authority

- Fixed launch flag: `--tidy-runtime-hidden-no-authority`.
- Fixed valid revision-one settings enable Headroom, keep hidden suppression off,
  and use a 60-second hidden interval. The production resolver must report
  `monitor.backgroundEnabled` unavailable from local authority; it is never persisted.
- Ready attestation requires `backgroundAuthority="unavailable"` and
  `timerRunning=false` with zero scene leases, explicit-work leases, scan sessions,
  and scan work.
- The observer records exactly ten minutes and requires zero timer schedule/cancel
  instrumentation. It calculates CPU as a delta of the
  process CPU counter, records RSS samples and physical footprint separately,
  samples children and FDs, and runs `nettop` with name resolution disabled.

### Queued cancellation

- Fixed launch flag: `--tidy-runtime-cancel-queued`.
- Runtime-only code occupies the resolved read-only scheduler permits through
  real explicit sessions, without supplied caps.
- A production Full Home scan registers and waits behind those permits. The
  production Cancel control must produce one retained registry `.cancelled`
  terminal. The helper then releases its permits and attests no scan-owned
  session, lease, index watch, observation, or transition remains.
- Close/reopen must show the retained cancelled state and preserve the witness.

### Performance 50k

- Fixed launch flag: `--tidy-runtime-performance-50k`.
- The host creates one bounded 50,000-entry zero-byte fixture only after a free
  space/headroom check and records exact logical/allocated counts.
- Internal monotonic timestamps identify request, first useful result, terminal,
  and worker-settled boundaries. External sampling records peak physical
  footprint and RSS. Incomplete/partial traversal cannot satisfy timing gates.

## External observation

The script launches only binaries it validates as the runtime fixture. It records:

- PID, process start identity, executable and bundle identity;
- one-second RSS and process CPU counter samples for long windows;
- bounded higher-frequency child and FD samples for cycle windows;
- `footprint` bytes and lifetime peak where the installed tool supplies them;
- `nettop -n -P -x` rows with a separate loopback positive control;
- exact runtime ready attestation and final fixed-scenario attestation;
- tool versions, commands, exit statuses, timestamps, and raw logs.

The script refuses root, rejects noncanonical/symlinked fixture roots, never sends
signals to an unverified PID, and removes only a root created by its exact child
after termination and owner/mode/prefix validation. On uncertain process identity
or cleanup, it retains evidence and fails.

## Remaining diagnostics

The production-native XCTest target owns UI actions for twenty scan/cancel cycles
and appearance/contrast/Reduce Motion. The external observer wraps the cycle run
to record PID-aware FD/RSS/child samples. Representative traffic uses the native
workflow suite while the observer follows each exact runtime-host PID. Paired
authorized-background builds remain blocked because the production machine-local
background-monitor authority workflow is not implemented. The harness fails that
mode before launching an app or build rather than substituting an off/off or
synthetic-authority comparison.

## Evidence and verdicts

The harness writes raw evidence outside the repository and commits only a compact
redacted JSON summary plus Markdown interpretation. Absolute personal paths,
environment values, command arguments unrelated to the fixed harness, and raw
traffic payloads are excluded. Every report labels results as current-host
diagnostics. A passing current-host number cannot close reference-hardware,
supported-OS, human, privacy-purpose, installation, signing, or release gates.
