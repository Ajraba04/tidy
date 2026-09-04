# T07.1a strict settings transfer verification — 2026-08-28

Scope: deterministic, context-free settings import analysis, collision resolution and canonical portable export. This checkpoint adds no file picker, durable import transaction, active-profile selection, coordinator handoff, app UI or ambient I/O and is not full T07 acceptance.

## Accepted boundary

`StrictJSON` is the shared bounded parser and canonical encoder for settings envelopes and transfer documents. It rejects invalid UTF-8, duplicate keys, malformed escapes and surrogates, trailing bytes, excessive nesting or members, noncanonical constructed integers and input above 1 MiB. Canonical output sorts keys, normalizes integer spelling and enforces the same depth boundary.

`SettingsTransfer` classifies every registry row through an explicit immutable partition. Portable global/profile values are structurally validated; authority, local identity, project/volume association and nonportable domains remain preview-only and cannot enter the candidate. Unknown safe scalars remain inert, sensitive shapes are redacted by SHA-256 metadata, and unsafe identifiers never bypass validation through malformed tags.

Analysis is pure and issued only by `analyze`. Resolve requires an exact choice for every profile collision, owns keep/replace/clone inert behavior, preserves projects without exporting them, rejects invalid or over-limit preserved state without truncation, and checks post-merge restriction monotonicity plus cross-layer quiet-hours, warning/clear and budget relations. Export sanitizes hostile known fields, omits profile restrictions weaker than defaults or the merged global policy, and rejects canonical output above 1 MiB. Neither resolve nor export performs I/O.

Fresh adversarial review found nine production issues: weaker restriction escape, unsafe-ID tag bypass, stale inert retention during replace, incomplete project validation, missing cross-layer/UTF-8/output bounds, under-validated authority rows, encoder depth/noncanonical-integer gaps, repeated registry rebuilding, and an incorrect public-initializer promise. Nineteen RED observations reproduced them. All were corrected. The final integrity review additionally required structural wire assertion for weak-field omission and a binding record of the post-review regressions; re-review returned **Approved** with no remaining finding.

## Evidence

- Required RED: the focused transfer suite failed to compile on the prescribed absent transfer symbols before production edits.
- Review-fix RED: 19 observations reproduced the nine production findings before correction.
- Final focused: `swift test --jobs 2 --filter SettingsTransferTests`; 28 tests / 1 suite passed in 37.045 seconds.
- Final ordinary package partition: `swift test --jobs 2 --skip BoundedProcessRunnerTests --skip SettingsProcessAcceptanceTests`; 410 tests / 48 suites passed in 43.722 seconds.
- Final isolated bounded-process partition: 21 tests / 1 suite passed in 29.856 seconds.
- Final isolated settings process acceptance: 3 tests / 1 suite passed in 13.906 seconds, retaining abrupt-publication evidence under `/private/tmp/tidy-t05-a2p-*`.
- Existing malformed settings fixtures: 10 cases passed with the legacy public failure mapping preserved.
- Existing settings migration/publication coverage: 46 tests across 2 suites passed during focused compatibility verification.
- `git diff --check` clean.
- Source purity audit over `SettingsTransfer.swift` and `StrictJSON.swift` found no `FileManager`, file-read/write API, `Process`, network API, singleton or mutable global persistence use.
- Exact source/test allowlist: `Policy/SettingsEnvelope.swift`, `Policy/SettingsTransfer.swift`, `Policy/StrictJSON.swift`, `SettingsTransferTests.swift`, and the one-line standalone compiler manifest addition in `SettingsProcessAcceptanceTests.swift`.
- No app files changed, so this pure checkpoint did not require an Xcode app build.

## Remaining gates

T07.2 persistence and active-profile handoff, T07.3 UI/workflows, T07.4 hostile production regression, dependency-bound T07.3d/T22.3/T22.4, device evidence and release work remain open.
