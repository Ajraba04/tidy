# R14 local package preparation — 2026-09-19

## Current resumed checkpoint — source `1782b4d`

The final-source package build and bounded inspector both exited 0. The normal app was
not launched. Source was an isolated detached local clone of
`1782b4df58f2993da397e7811414e2f89f7c6f9f`, with clean relevant source inputs.
Command: `bash scripts/make-release.sh dev`, using the existing ad-hoc signing policy.
Build/source root: `/private/tmp/tidy-resume-package-ZInt1V/`.
Inspection: `/private/tmp/tidy-resume-inspection-25a43567/result.json`.
Inspector SHA-256: `2406206d7eec8584675e60460da93ac7982212344d14f8191864263f708568aa`.
Package script SHA-256: `5539ec11bae918ce2796e86ed524e2328fc83e0e7e4e28888ac776cb9ab77e7b`.

Stable local copies are under `dist/remediation-1782b4d/` in the active worktree, with
`Tidy-dev.sha256` and `inspection-result.json`. Copied bytes were hash-verified.

| Artifact | SHA-256 |
| --- | --- |
| Tidy-dev.zip | `3ec416c326fdc2e680b7b9796ca08765edf2a300819ae567c17c2f601f3dfa8d` |
| Tidy-dev.dmg | `2ea0e19e10a6379c6d0002ad5cb505a87b59820e47c4949cc60ee9be4976c484` |

Version1.5.0/build1, arm64 and x86_64, English and privacy resources, strict ad-hoc
signature, empty entitlements, and ZIP/DMG bundle parity passed. The actual signature
has no hardened-runtime flag; policy was not changed. The normal binary contains no
fixture markers. The DMG was inspected read-only and detached; its Applications link
is correct. The disposable filesystem copy/replace/remove rehearsal preserved its
independent recovery witness.

This packaging success is separate from the final verifier's native-audit timeout.
It is not Gatekeeper, install/upgrade/uninstall, supported-OS, notarization, privacy-purpose
or release acceptance. No normal-app launch, installation, security change, or publication
occurred. Current application NO-GO and full-program INCOMPLETE are unchanged.

## Historical checkpoint (before this resume)


Status: package-byte inspection passed for the recorded checkpoint; full distribution and supported-host installation acceptance remain open.

Built an isolated `git archive` of source `b4acfff2a78343884457b14ee5d9efba3df91e12` using the existing local ad-hoc signing path. The only packaging-script change is a two-job Xcode build limit, matching the verification workflow. Command: `bash scripts/make-release.sh dev`. It completed successfully and produced both ZIP and DMG. The normal production app was not launched, no existing installation was modified, and no security/permission/notarization/publication step was performed.

## Recorded artifacts

| Artifact | SHA-256 |
| --- | --- |
| Tidy-dev.zip | `087f65ca9330cf2428259bbcdf968e2860ec313cdc599bff74ef3689a40f1149` |
| Tidy-dev.dmg | `1582fdc4b93262e783878b98714e1c3d799385ec1736342c4be185b69a17182e` |

Local artifact directory: `/private/tmp/tidy-r14-package-20260919-9j2l7n3z/source/dist/`. Source snapshot, build log `/tmp/tidy-r14-package-20260919.log`, signature output, resource hashes and `inspection/result.json` are retained. These immutable checkpoint bytes predate the new R05/R08/R13 continuation work and must be rebuilt/inspected again for the final source.

## Checks performed

- Verified both expected SHA-256 values before extraction and confirmed a substituted byte sequence does not match the expected ZIP checksum.
- Checked all 23 ZIP members for absolute/traversal paths and bounded their total uncompressed size before extraction.
- Extracted the ZIP with `ditto`; checked version 1.5.0/build 1, both arm64 and x86_64 slices, privacy plist syntax, and compiled English localization resource presence.
- Verified the ad-hoc signature with `codesign --verify --deep --strict`. Actual entitlements are empty. The ad-hoc artifact has **no hardened-runtime flag**; this is the existing unsigned signing policy, not a claim of hardened/notarized distribution. No signing policy was changed.
- Mounted the DMG read-only without browsing; verified its Applications link, strict app signature, and exact file-content/mode parity with the ZIP app. Detached the owned mount afterward.
- Rehearsed copy, replacement and removal of the app bundle in a disposable directory. A separate synthetic mandatory-recovery witness remained byte-identical across those filesystem operations.

The copy rehearsal is not an application upgrade/recovery run, a disposable-account Gatekeeper installation, or oldest-supported/current-stable OS acceptance. No real recovery database was fabricated or cleared. Human security-dialog behavior, optional signed/notarized artifacts, launch/upgrade/uninstall behavior on supported hosts, complete privacy/network evidence and the approved release manifest remain separate gates.

The installed macOS 27 `hdiutil` warned that its create/attach commands are deprecated; both succeeded. The helper retains those existing commands; execution on macOS 14 remains unverified. This record makes no bit-for-bit rebuild reproducibility claim: it records exact source, commands, inspected bytes and checksums.
