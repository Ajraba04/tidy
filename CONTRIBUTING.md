# Contributing to Tidy

## Project layout

```
Tidy.xcodeproj      thin app target; references TidyCore as a local package
Tidy/               SwiftUI layer only: views and view models
TidyCore/           all logic, zero UI, zero third-party dependencies
project.yml         xcodegen source of truth for Tidy.xcodeproj
```

`Tidy.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen). If you edit
`project.yml` (new source files usually don't require this: Xcode picks
up new files under existing groups automatically when the project already
references the containing folder), regenerate the project:

```bash
brew install xcodegen   # once
xcodegen generate
```

Commit the regenerated `Tidy.xcodeproj` alongside your `project.yml`
change.

## Building and testing

`TidyCore` is a plain Swift package. Iterate on it without opening Xcode:

```bash
cd TidyCore
swift test
```

Open `Tidy.xcodeproj` in Xcode to work on the SwiftUI layer, or build from
the command line:

```bash
xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Debug \
  -derivedDataPath ./DerivedData build CODE_SIGNING_ALLOWED=NO
```

Requires macOS 14+ and Xcode 15+.

## Ground rules

- **Zero network calls.** No analytics, no update checker, no remote Swift
  packages. This is a stated privacy feature: if your change needs the
  network, it probably belongs in a different project.
- **No delete path skips the plan screen.** `TidyCore`'s `CleanEngine`
  exposes `makePlan` (read-only) and `execute` (acts on exactly the plan
  handed to it). Every new catalog item goes through both. There is no
  shortcut for a "quick delete."
- **`PathGuard` gates every deletion**, twice: once when the plan is built,
  once again immediately before the delete happens. Don't add a code path
  that touches disk without going through it.
- **Nothing personal.** No hardcoded usernames, machine-specific paths, or
  personal domain/device lists. Catalog defaults ship empty; CI fails the
  build if `binjamshid`, `albayyan`, `claude.ai`, or a hardcoded
  `/Users/<name>` path shows up in `TidyCore/Sources` or `Tidy/`.
- **New catalog items need tests.** At minimum: `locate` resolves the
  expected targets on a scratch home directory, and the target falls under
  the item's declared root (see the existing `CleanCatalogTests` for the
  pattern already run against every item).

## Adding a catalog item

1. Pick a tier (`.safe`, `.normal`, `.deep`) and an existing category in
   `TidyCore/Sources/TidyCore/Catalog/`, or add a new one.
2. For a plain path deletion, use the `fixedPathItem`/`globPrefixItem`/
   `toolRunItem` helpers in `CleanCatalog+Helpers.swift`.
3. For anything needing real logic (parsing a tool's output, multi-step
   operations), implement it under `Engine/` or `Browsers/` and register it
   as a `CustomActionExecutor` in `DefaultCustomActionExecutors.swift`.
4. Add tests. If the item can delete something, add a test that proves it
   only deletes what it's supposed to.

## Reporting issues

Open a GitHub issue. Include your macOS version and, if a specific catalog
item misbehaved, the item's title as shown in the plan screen.
