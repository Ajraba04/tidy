# R13 resumed privacy API/source mapping

Date: 2026-09-19

Status: source inventory and current Apple reason mapping updated; production privacy acceptance remains open.

## Scope and result

This checkpoint owns the lexical inventory tool, its evidence record, and one privacy-manifest
comment correction. The manifest reason/category values are unchanged. It does not add a diagnostic
feature, change networking, exercise permissions, alter signing, or claim human/runtime acceptance.

Apple's current DocC API catalogue was supplied from the official `NSPrivacyAccessedAPIType` page.
Its SHA-256 is `19546c6db12067a6e6441140399e8323fd73d5e79d1c682e1d0b826b16da6cf5`.
The fetched official required-reason guidance SHA-256 is
`e5cc866c722a51e3e06f82edf65d8ef1bc96489dae5c75a88696af5261aafafb`.
The catalogue's `primaryContentSections`/`possibleValues` data, rather than an incomplete Markdown
rendering, supplied the five current categories, their API lists, and reason text.

The prior scanner conflated Swift `stat()` structure initialization with a syscall, omitted the
current Apple `getattrlistat` and `getattrlistbulk` entries, had no active-keyboards coverage, scanned
only Swift, and gave line numbers without matched API names. The revised tool:

- scans Swift, C, Objective-C, Objective-C++, and header files in the app and core source roots;
- reports exact matched tokens and lines for all five current Apple categories;
- keeps `kern.boottime` and `kern.bootsessionuuid` in a separate review category because Apple does
  not name them in the current required-reason API list;
- reports `fgetattrlist` in both categories where Apple lists it;
- distinguishes C function calls from imported `stat()`/`statfs()` structure initializers; and
- has a deterministic `--self-test` covering all 35 scanner patterns, including negative controls.

The refreshed source-to-field-to-purpose mapping is in
[`privacy-api-inventory.md`](privacy-api-inventory.md). The main disposition is intentionally
unresolved: current file metadata spans implicit home roots, ancestor identity checks, installed
executables, persisted project paths, and unsandboxed `~/Library/Application Support/Tidy` storage.
The checked-in empty entitlement file does not demonstrate Apple's `C617.1` container condition,
and Tidy has no document picker/security-scoped grant establishing `3B52.1`. In-app full-home consent
and persisted scan roots are product authorization, not automatically Apple's documented file-access
grant.

The existing manifest's `35F9.1` maps directly to the two `ProcessInfo.systemUptime` timer/elapsed
uses, so its old `kern.boottime` comment was corrected without changing manifest values. `85F4.1`
maps directly to displayed disk capacity, with derived policy use called out separately. Filesystem
locality, filesystem/volume identity, and mount-alias checks use APIs Apple lists under disk space,
but none of the current reason descriptions matches those purposes. No file-timestamp or additional
disk reason was added merely to make the manifest appear complete.

## Verification

Reproduce the scanner checks and inventory with:

```text
python3 scripts/verification/privacy-api-inventory.py --self-test
python3 -m py_compile scripts/verification/privacy-api-inventory.py
python3 scripts/verification/privacy-api-inventory.py
```

The inventory was refreshed after the R05 scan source froze at `dbf9c72`; its exact generated table
matches the committed evidence table. The runtime-verification source present at this checkpoint
contains no direct required-reason token; it composes production services against disposable `/tmp`
storage and remains test evidence only. The controller will rerun the inventory at final whole-branch
freeze in case the concurrently finishing runtime-host stream adds or moves a relevant token.

## Remaining R13/R14 gates

- Decide, with primary Apple support or a product/storage change, how unsandboxed application-support
  metadata qualifies; `C617.1` is a candidate rather than an accepted conclusion.
- Add a documented user-grant mechanism or otherwise resolve metadata use on quick, selected-project,
  full-home, ancestor, and executable paths; current in-app consent is insufficient evidence for
  `3B52.1`.
- Resolve `fstatfs`/`fgetattrlist` locality and volume-identity purposes against an approved reason or
  change the implementation/distribution contract.
- Inspect the frozen packaged executable, linked libraries, privacy resource, signature, entitlements,
  and hardened-runtime state. Source build settings and plist syntax are not packaged evidence.
- Instrument representative app and child traffic and permissions. Absence of `URLSession` in source
  and this required-reason inventory do not prove zero network activity.

These open rows keep full privacy and distribution acceptance incomplete. No external-distribution
exemption, App Store acceptance, runtime permission behavior, or human review is inferred here.
