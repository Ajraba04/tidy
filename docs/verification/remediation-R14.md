# R14 — documentation and packaging preparation

Status: preparation only; no release acceptance, signing-policy change, tag, push, upload or publication.

README now distinguishes the intended program from current quarantined mutations and unfinished workflows. It removes categorical swap/restart savings and implemented-cookie-write claims. Contributor instructions describe coordinator authority, pinned generation, all model/native test gates, and separate fixture versus production acceptance.

Unsigned-install instructions follow Apple's current [per-app Privacy & Security procedure](https://support.apple.com/en-us/102445), checked 2026-09-17. They require trusted provenance and checksum verification and no longer instruct recursive quarantine removal. Signing/notarization remains optional.

The existing package helper now rejects unsafe version path components before building, requests both arm64/x86_64, checks artifact version against the built bundle and requires a positive build number, emits portable ZIP/DMG SHA-256 entries, and explains that packaging is not release approval. The release workflow prepares matching artifact checksums and toolchain/commit/architecture provenance; tag text passes through a validated environment value rather than direct shell interpolation. Existing signing settings/credentials are unchanged. No workflow was dispatched.

Validation: README locale matches source string catalog (`en` only); plist syntax passed after correcting the display disk-space privacy reason; both workflow YAML files parsed and every shell block passed Bash syntax validation; package helper `bash -n` passed; `../invalid-version` failed before build with exit 1. Full package generation/install/upgrade/uninstall was not run because source integration and required acceptance remain unfinished. The [acceptance record](headroom-acceptance.md) and [partial API inventory](privacy-api-inventory.md) retain those exact gaps.

Open: final immutable ZIP/DMG contents/checksums/provenance inspection, actual signatures/entitlements/hardened-runtime behavior, preservation of unresolved recovery during upgrades, supported-OS installation path and uninstall witnesses. Cask remains a future template. External publication, signing-policy changes and new permissions require separate user authority after the concrete artifacts are prepared.
