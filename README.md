# Tidy

A native macOS menu bar app for reclaiming disk space: regeneratable
developer tool caches, browser caches, Xcode and simulator data, git object
cleanup, and more. It's organized into Scan, Safe, Normal, Deep, and Custom
modes, with a plan you review before anything is deleted.

It also has a small, deliberately conservative set of memory and swap
actions. See [Memory and swap](#memory-and-swap) for what they can and
cannot do, which is mostly a story about what macOS does not allow.

Requires macOS 14 (Sonoma) or later.

## Why

Developer machines fill up with caches, derived data, simulator artifacts,
and dependency downloads that are all individually safe to delete and
collectively enormous. Tidy finds them, shows you what it found and how
much space it would free, and only deletes after you say so.

## Modes

- **Scan** is read-only. It ranks the largest items in your home directory
  and `~/Library`, lists files over 1 GB, APFS local snapshots, idle
  simulator runtimes, stale `node_modules`, LaunchAgents, and top memory
  consumers. Nothing is deleted.
- **Safe** covers regeneratable caches only: developer tool and
  package-manager caches, logs, Xcode DerivedData and simulator caches.
  Everything here rebuilds itself the next time you use the relevant tool.
- **Normal** builds on Safe, adding browser caches, Chrome cookies (keeping
  domains you choose), Trash, build output directories, stale
  `node_modules`, old Claude Code session transcripts (your `memory/`
  files are never touched), and conservative git housekeeping.
- **Deep** builds on Normal, adding everything that costs a real
  re-download or loses local history: full dependency caches, Android SDK
  components, Xcode Archives, APFS local snapshot deletion, aggressive git
  reflog expiry, and simulator deletion. Simulator deletion is opt-in and
  per device: nothing is ever deleted by default.
- **Custom** exposes every catalog item, individually checkable, with
  savable named presets.

Scan also reports two things it will never act on: space only a restart
can return, and large directories no catalog item covers.

Every mode works the same way: build a plan (locate + measure, zero
writes) → review it → confirm → execute. There's no code path from a plan
to a deletion that skips your confirmation.

## Memory and swap

Most "memory cleaners" on macOS are selling something that isn't real. Here
is exactly what Tidy can do, and what it can't:

- **Swap cannot be reclaimed while the Mac is booted.** macOS grows
  swapfiles on demand and does not return them until boot. There is no API,
  no supported command, and no privilege level that changes this. So the
  only honest "free swap" action is a restart, and that is literally what
  the restart item does. It ships disabled and has to be enabled in
  Settings before it will even appear.
- **Purging inactive memory is real, and usually not a win.** `purge(8)`
  evicts the file-backed page cache, moving pages from inactive to free.
  Those pages were caching data the machine was about to want again, so the
  number in Activity Monitor improves while real performance briefly gets
  worse. Offered, never on by default, and labelled with that trade-off.
- **Quitting an application is the one unambiguous win.** Its resident
  memory returns the moment it exits. Tidy asks apps to quit the way the
  Quit menu item does; an app with unsaved work can prompt or refuse, and
  nothing is ever force-killed. Only applications you name in Settings are
  eligible.

Memory figures are measured before and after, and are reported separately
from disk. They are never added into the "freed" total, because disk space
and RAM are different resources and one combined number would be wrong
about both.

Scan's **"Only a restart can reclaim this"** panel reports what macOS is
holding in swap and VM files, broken out per component. It has no button:
those bytes belong to the kernel, and Tidy will not pretend otherwise.

## Coverage gaps

Scan reports **"Big, and not covered by Tidy"**: directories over 500 MB
that no catalog item touches. Cleanup catalogs drift out of date as the
tools around them grow new directories, and this makes that drift visible
instead of silent. It reports only; nothing there can be deleted until
somebody writes a real catalog item for it.

## Privacy

**Zero network calls, ever.** No analytics, no crash reporting, no update
checker, no remote dependencies. This isn't a claim you have to take on
faith: `TidyCore` has no third-party dependencies (see
[`TidyCore/Package.swift`](TidyCore/Package.swift)) and you can watch its
network activity yourself in Activity Monitor or any traffic monitor while
using the app. Updates are manual, via GitHub Releases.

Specifically:

- Cookie keep-domains, project roots, and the simulator delete-approval
  list all ship **empty**. Nothing is assumed about your machine.
- Suggestions (cookie domains found in your own browser, project roots
  found on your own disk) are computed locally and only ever shown to you
  to confirm. They're never sent anywhere.
- iCloud-backed folders (`~/Library/CloudStorage`, `~/Library/Mobile
  Documents`) are never scanned or touched.
- Safari cookies are never touched, since its `binarycookies` store has no
  safe per-domain delete. Chrome cookie deletion uses the SQLite3 C API
  directly against a local database, with a validated backup taken before
  any write and restored automatically if anything looks wrong afterward.

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
