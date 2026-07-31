# Tidy

A native macOS menu bar app for reclaiming disk space and memory: regeneratable
developer tool caches, browser caches, Xcode and simulator data, git object
cleanup, and more — organized into Scan, Safe, Normal, Deep, and Custom
modes, with a plan you review before anything is deleted.

Requires macOS 14 (Sonoma) or later.

## Why

Developer machines fill up with caches, derived data, simulator artifacts,
and dependency downloads that are all individually safe to delete and
collectively enormous. Tidy finds them, shows you what it found and how
much space it would free, and only deletes after you say so.

## Modes

- **Scan** — read-only. Ranks the largest items in your home directory and
  `~/Library`, lists files over 1 GB, APFS local snapshots, idle simulator
  runtimes, stale `node_modules`, LaunchAgents, and top memory consumers.
  Nothing is deleted.
- **Safe** — regeneratable caches only: developer tool and package-manager
  caches, logs, Xcode DerivedData and simulator caches. Everything here
  rebuilds itself the next time you use the relevant tool.
- **Normal** — Safe, plus browser caches, Chrome cookies (keeping domains
  you choose), Trash, build output directories, stale `node_modules`, old
  Claude Code session transcripts (your `memory/` files are never touched),
  and conservative git housekeeping.
- **Deep** — Normal, plus everything that costs a real re-download or loses
  local history: full dependency caches, Android SDK components, Xcode
  Archives, APFS local snapshot deletion, aggressive git reflog expiry, and
  simulator deletion — opt-in, per device, nothing is ever deleted by
  default.
- **Custom** — every catalog item, individually checkable, with savable
  named presets.

Every mode works the same way: build a plan (locate + measure, zero
writes) → review it → confirm → execute. There's no code path from a plan
to a deletion that skips your confirmation.

## Privacy

**Zero network calls, ever.** No analytics, no crash reporting, no update
checker, no remote dependencies. This isn't a claim you have to take on
faith — `TidyCore` has no third-party dependencies (see
[`TidyCore/Package.swift`](TidyCore/Package.swift)) and you can watch its
network activity yourself in Activity Monitor or any traffic monitor while
using the app. Updates are manual, via GitHub Releases.

Specifically:

- Cookie keep-domains, project roots, and the simulator delete-approval
  list all ship **empty**. Nothing is assumed about your machine.
- Suggestions (cookie domains found in your own browser, project roots
  found on your own disk) are computed locally and only ever shown to you
  to confirm — never sent anywhere.
- iCloud-backed folders (`~/Library/CloudStorage`, `~/Library/Mobile
  Documents`) are never scanned or touched.
- Safari cookies are never touched — its `binarycookies` store has no safe
  per-domain delete. Chrome cookie deletion uses the SQLite3 C API directly
  against a local database, with a validated backup taken before any
  write and restored automatically if anything looks wrong afterward.

## Installing

Download the latest release from the
[Releases page](https://github.com/ajraba04/tidy/releases).

Whether a given release is code-signed and notarized depends on whether
this repository has signing secrets configured — see
[Privacy & signing](#privacy--signing) below. If you see a Gatekeeper
warning when opening it, see
[docs/UNSIGNED_INSTALL.md](docs/UNSIGNED_INSTALL.md) — the app works
identically either way.

## Building from source

Requires Xcode 15+.

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
signing stays opt-in rather than required — an unsigned release is fully
functional, just with an extra click to open the first time (see
[docs/UNSIGNED_INSTALL.md](docs/UNSIGNED_INSTALL.md)).

The app runs with Hardened Runtime enabled and App Sandbox disabled — it
needs to shell out to developer tools (`git`, `npm`, `xcrun`, ...) and read
across your home directory, which App Sandbox would block.

## How it's built

- **Native SwiftUI**, `MenuBarExtra`, macOS 14+.
- **`TidyCore`** is a local Swift package with zero third-party
  dependencies: all the logic (catalog, detection, size scanning, the
  clean engine, path safety, browser cookie handling) lives there, fully
  unit-tested, independent of the UI.
- **`PathGuard`** validates every deletion target twice — once when the
  plan is built, once again immediately before the delete happens — and
  refuses anything outside its declared root, inside a protected iCloud
  path, or equal to `/` or your home directory.
- Shelling out is deliberate and narrow: CLIs are used when a tool owns its
  own index or database (`npm cache clean`, `git gc`, `simctl`), plain
  `FileManager` otherwise. Tools are resolved via `xcrun --find` and a
  fixed list of install locations — never your inherited `PATH`, never a
  shell.

## License

MIT — see [LICENSE](LICENSE).
