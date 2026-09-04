# T07.2b shared profile handoff verification — 2026-08-28

Scope: route T07.2a's exact preferences-document delta and store-issued import preview through the existing bounded `ExecutionPolicyBridge` and shared `AppConfigStore`. This checkpoint completes the durable/shared T07.2 handoff only. It adds no settings UI, file picker/exporter, local reassociation, optional-data clearing, adapter authority or cleanup effect.

## Accepted boundary

`PreferencesDocumentProjection` is now the single pure document application path used by storage, bridge prediction and app replay. It validates exact touched bases, duplicate profile/inert ownership, active-selection integrity and all touched registry rows before calculating effect. Unknown fields are invalid; authority, consent, local identity and nonportable fields reject as unsupported authority even for no-op edits. Active selection invalidates only after the complete candidate passes those checks. Only actually changed allowed fields contribute registry effects; names and inert records are storage-only.

The existing bridge queue now retains document deltas and issued import previews alongside legacy/global payloads under the same 32-snapshot and fixed 32 MiB ceilings. A separate internal test initializer is clamped to that production ceiling. Documents receive aggregate bounded-envelope preflight before retained encoding. Imports use deterministic sorted-key accounting bytes covering intent/revision, IDs, rows, collisions, choices, complete candidate preferences/inert state and digests, with checked addition before retention.

Import admission has a bridge-side fail-fast issuance binding in addition to the authoritative `SettingsStore` token. It binds the exact preview and acknowledged revision, requires an empty queue, consumes once on acceptance, and invalidates on analysis, issuance, cancellation and every saved outcome. A monotone lifecycle generation prevents an older async issuance from reinstalling a binding after another window supersedes it. Stale, cancelled, reused, mutated, foreign and queued previews reject before optimistic display, retention or coordinator invalidation.

`AppConfigStore` now submits exact documents/imports, forwards analysis/cancellation, resolves the selected profile over global policy for app-visible effective settings, and replays its own pending transformations over every ordered saved acknowledgement. Foreign failures/conflicts never occupy another window's local outcome buffer. Relaunch restores active selection, and two stores sharing the one bridge converge while one still owns an optimistic tail.

## Adversarial review

The preimplementation card required four hostile review passes before approval. Source review then found a public byte-limit bypass, duplicate-key traps, no-op forbidden-field bypass, async preview reordering and missing aggregate preflight. Test-led fixes closed each. Re-review found active-selection short-circuiting validation and a false-green aggregate fixture; the classifier was reordered and the fixture now seeds a valid near-1 MiB canonical excluded-root document before portable profile additions cross the bound. Final adversarial review returned **Approved**.

## Evidence

- Required RED: the focused app-model build failed on the missing `AppConfigStore` document/import APIs and bridge accounting entry point before production edits.
- Final focused app-model: `SharedSettingsWiringTests`, 39 tests, 0 failures, `TEST SUCCEEDED`.
- Durable profile/import compatibility: `SettingsProfilePersistenceTests`, 25/25 passed.
- Strict transfer compatibility: `SettingsTransferTests`, 28/28 passed.
- Controller full core: `swift test --jobs 2`, exit 0; all suites, including bounded-process and settings-process acceptance, passed. The subsequent standalone bounded filter selected no additional cases and is not claimed as separate evidence.
- Controller complete app-model bundle: 57 tests passed, 0 failed/skipped/expected failures; Xcode result `Passed`.
- Unsigned production arm64 app: `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO`, exit 0 with no output.
- `git diff --check` clean and the exact five-file implementation allowlist was respected.

## Test-card integrity corrections

Three reviewed fixtures required corrections without weakening production behavior: nested helpers received explicit `@MainActor` isolation; a durability-uncertain rename failure that cannot legitimately permit later persistence became a recoverable external-identity conflict; and the aggregate-bound test became valid near-limit durable state plus portable structural additions, ensuring it reaches the bounded pre-encoding path.

## Remaining gates

T07.3a registry UI, T07.3b profile/import/export workflows, T07.3d bounded optional-data clearing, T07.4 hostile coordinator regression, T22.3 local reassociation and T22.4 accepted-adapter authority/effect regression remain open. Physical 8 GiB/macOS 14 performance, accessibility, Intel compatibility, README, GitHub publication and DMG release remain program-level gates. No full T07 or customer release acceptance is claimed here.
