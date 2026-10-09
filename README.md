# Tidy

Tidy is a native macOS menu bar developer headroom utility for inspecting disk and workload pressure and reviewing narrowly scoped cleanup actions. It targets macOS 14 or later, Apple Silicon and Intel, with English UI.

**Development status: remediation in progress; not release-ready.** All catalog mutations, including Xcode DerivedData, are currently quarantined in the compiled capability registry. Safe, Normal, Deep and Custom reviews show unavailable actions with reasons. Tool discovery, a saved preset, a settings import or a confirmation cannot enable them. The approved cleanup program remains incomplete; these restrictions do not replace its promised implementation or acceptance gates.

The [acceptance record](docs/verification/headroom-acceptance.md) separates implemented changes, test evidence, missing production contracts and runtime/hardware gates. There is no newly approved release from this remediation.

The [10 October local handover](docs/verification/local-handover-2026-10-10.md)
records the audit checkpoint reconciled onto current main and its pending native verification.

## Scope and modes

| Surface | Intended scope | Current boundary |
| --- | --- | --- |
| Scan | Explicit read-only catalog/project scans; full-home scans only with separate one-run consent | Fresh installs can run a Quick scan without first saving settings. Scope, pressure and cancellation stay enforced. Partial results remain labeled, and Continue requires a trustworthy event-history checkpoint. |
| Headroom | Disk availability, memory pressure, swap activity, thermal and power signals | Measurements can be unavailable; missing values must not be reported as zero. Target readiness requires measured selected-volume identity/capacity. |
| Safe | Regeneratable developer caches, logs, DerivedData and simulator caches | Inventory/review only; mutation unavailable pending each adapter's acceptance. |
| Normal | Additional browser/cache, Trash, project-output, dependency, transcript and Git workflows | Promised adapter work remains incomplete and mutations are denied. |
| Deep | Explicitly reviewed actions with redownload or local-history consequences | Mutations denied, including simulator deletion, snapshots and Git housekeeping. |
| Custom | Individual catalog selection and named presets | Presets preserve preferences; they never confer effect authority. |
| Build Prep / Pressure Rescue / optional assistance | Project-aware ranking, target-limited preparation, manual graceful relief and separately authorized assistance | Full production workflows remain incomplete. Initial unattended mutation allowlist is empty. |

Neither a cache label nor its age proves it safe to delete. Future accepted mutations must bind reviewed resource identities and descendants, protections, complete owner evidence, supported quiescence, fresh policy and durable recovery. Unknown or shared ownership withholds effects. Models, databases, Docker volumes, repository deletion and generic duplicate deletion remain outside permitted destructive scope.

A missing settings file supplies validated in-memory defaults for an explicit scan. Corrupt or unsupported settings keep scans unavailable. If stored files differ when first-launch admission revalidates them, the scan is blocked and the files are preserved. Opening Tidy does not start a scan, create a saved settings file or grant background-work consent. Cleanup actions remain quarantined independently of scan availability.

## Memory and swap

macOS manages swap and physical memory. Tidy does not manipulate swap files, tune the kernel or promise a fixed amount of reclaimed memory. A measured swap page-out rate indicates activity; it is not a promise of disk space returned by quitting or restarting. A restart changes system state but its savings cannot be guaranteed in advance.

Graceful application quit, purge and restart catalog entries are currently unavailable. A future supported graceful quit must identify the actual app instance and respect refusal or unsaved work; force-quit is forbidden. Disk bytes, RAM and swap activity are reported separately and must never be added into one savings total.

## Privacy and protections

The runtime design prohibits internet requests, telemetry, remote updates, tool-triggered downloads and remote service contexts. TidyCore has no third-party runtime packages. Controlled app-and-child traffic acceptance is still open; source inspection or one Activity Monitor snapshot does not establish a universal zero-network result.

Cookie keep-domains, project roots and device approval lists start empty. Settings and imported profiles do not grant cleanup authority. Protected cloud roots remain excluded. Safari cookie mutation is forbidden; Chrome cookie mutation is quarantined, and validated backup/WAL/restore acceptance remains unfinished. No cookie-write or automatic-restore functionality is claimed by this build.

Mandatory unresolved recovery records are independent of optional history. Never delete or reset journals to make cleanup admission succeed. Local diagnostic reports should contain capability/status information, not personal paths, environment values, command arguments, credentials or cookie contents.

## Building and verification

Open `Tidy.xcodeproj`, or build locally:

```bash
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug \
  -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO
```

The project targets macOS 14+, Swift 5 language mode, and a Swift package tools version of 5.10. Exact toolchain versions used for verification are recorded with each result; older toolchains are not presumed verified.

Run core tests with serialized process-global fixtures:

```bash
cd TidyCore
swift test --jobs 2 --no-parallel
```

The repository-wide verifier includes generated-project membership, all model tests, synthetic native UI tests, isolated production-scene journeys and both Release architectures:

```bash
bash scripts/verification/verify.sh
```

It requires Xcode and XcodeGen 2.46.0. See [CONTRIBUTING.md](CONTRIBUTING.md) for pinned tooling and the distinction between fixture tests and production acceptance.

## Distribution and signing

The intended distribution is a manually installed ZIP/DMG; signing and notarization are optional. Current package installation/upgrade/uninstall acceptance remains open. Existing [GitHub releases](https://github.com/ajraba04/tidy/releases) are separate artifacts and do not acquire this branch's changes until an explicitly authorized release.

For a verified, trusted unsigned artifact, use the documented per-app [Gatekeeper procedure](docs/UNSIGNED_INSTALL.md). Notarization is a malware check and developer-identity mechanism; it is not a proof that every app workflow is correct. Project settings request Hardened Runtime with App Sandbox disabled, but final packaged signatures and entitlements require separate inspection.

## License

MIT. See [LICENSE](LICENSE).
