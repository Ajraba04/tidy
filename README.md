# Tidy

A native macOS menu bar app for local disk inventory and timestamped disk,
memory, swap, thermal, and power observations. Requires macOS 14 (Sonoma)
or later.

## Current capabilities

- **Scan** performs bounded, read-only discovery with partial-result reporting
  and global cancellation. Concurrent scan requests share one active session.
- **Projects in Scan** lists bounded marker evidence under approved project roots,
  including nested projects and unresolved Git indirections. Unknown ownership and
  activity remain protected; marker discovery never authorizes cleanup.
- **Headroom** shows independent observations and a per-volume target when
  capacity and volume identity are available. A target is not a buildability guarantee.
- **Safe, Normal, Deep, and Custom** organize catalog inventory and saved
  selections. These names describe catalog groupings, not proof that a resource
  is safe to delete.
- **Cleanup is currently unavailable.** Every production mutator is quarantined.
  In particular, detecting Xcode does not establish exclusive ownership of its
  DerivedData. Re-enabling any adapter requires an accepted scope, producer,
  interruption, and recovery contract with native verification.
- Complete project ownership workflows, Build Prep, Pressure Rescue, additional ecosystem adapters,
  budgets/notifications, and unattended maintenance remain roadmap work. Settings
  for an unfinished consumer do not establish that the feature is operational.

## Memory and swap

Tidy observes these signals; it currently does not purge memory, quit apps,
restart the Mac, or delete swap files. Observed system changes cannot establish
how much memory or physical disk space a particular operation reclaimed.

## Privacy and local data

The inspected application source has no HTTP client, telemetry service, or
third-party Swift package dependency. Runtime network verification remains a
release acceptance check. Tool discovery and inventory must not execute project
scripts or trigger downloads.

Mandatory cloud exclusions include `~/Library/CloudStorage` and
`~/Library/Mobile Documents`. Project traversals receive the same exclusions.
Browser cookie deletion, Git mutation, simulator deletion, snapshots, and memory
actions remain unavailable.

Settings, settings backups, optional history, aggregate scan cache, and mandatory
execution records live under the app's Application Support directory. Run history
honors the acknowledged enable/retention/size preferences and omits per-leaf paths
and diagnostic messages. Disabling optional history does not clear recovery records.
Raw monitoring history is bounded and held in memory. Aggregate cache watchers run
only during an explicit scan.

These support files may be included in operating-system backups: Tidy does not
promise that clearing a local file removes external backup copies. Required-reason
privacy declarations, data-clearing UX, and physical-device behavior still need the
checks recorded in [the acceptance ledger](docs/verification/headroom-progress.md).

## Installing

Download the latest release from the
[Releases page](https://github.com/ajraba04/tidy/releases).

Whether a given release is code-signed and notarized depends on whether
this repository has signing secrets configured. See
[Privacy & signing](#privacy--signing) below. If you see a Gatekeeper
warning when opening it, see
[docs/UNSIGNED_INSTALL.md](docs/UNSIGNED_INSTALL.md). The app works
identically either way.

## Building from source

Use Xcode 16 or newer for Swift Testing. The minimum toolchain and both supported
architectures must be confirmed by the macOS acceptance matrix.

```bash
git clone https://github.com/ajraba04/tidy.git
cd tidy
open Tidy.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug \
  -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO
open DerivedData/Build/Products/Debug/Tidy.app
```

`TidyCore` (all the logic, zero UI) is a standalone Swift package you can
build and test on its own:

```bash
cd TidyCore
swift test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and how to
add a catalog item.

## Privacy & signing

Signing and notarizing this app is optional and gated on repository
secrets. Notarizing a legitimate utility doesn't endanger a Developer
account, but the signature embeds the registered developer's name, so
signing stays opt-in rather than required. An unsigned release is fully
functional, just with an extra click to open the first time (see
[docs/UNSIGNED_INSTALL.md](docs/UNSIGNED_INSTALL.md)).

The app runs with Hardened Runtime enabled and App Sandbox disabled, since
it needs to shell out to developer tools (`git`, `npm`, `xcrun`, ...) and
read across your home directory, which App Sandbox would block.

## How it's built

- **Native SwiftUI**, `MenuBarExtra`, macOS 14+.
- **`TidyCore`** is a local Swift package with zero third-party
  dependencies: all the logic (catalog, detection, size scanning, the
  clean engine, path safety, browser cookie handling) lives there, fully
  unit-tested, independent of the UI.
- **`PathGuard`** validates every deletion target twice (once when the
  plan is built, once again immediately before the delete happens) and
  refuses anything outside its declared root, inside a protected iCloud
  path, or equal to `/` or your home directory.
- Shelling out is deliberate and narrow: CLIs are used when a tool owns its
  own index or database (`npm cache clean`, `git gc`, `simctl`), plain
  `FileManager` otherwise. Tools are resolved via `xcrun --find` and a
  fixed list of install locations, never your inherited `PATH`, never a
  shell.

## License

MIT. See [LICENSE](LICENSE).
