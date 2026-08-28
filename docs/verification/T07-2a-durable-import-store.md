# T07.2a durable profile/import store verification — 2026-08-28

Scope: additive schema-2 active-profile/inert state, exact preferences-document deltas, store-issued import analysis/previews, and complete-state rollback in the single accepted `SettingsStore`. This checkpoint adds no bridge/app caller, selected-profile resolver handoff, synchronous coordinator invalidation, two-window behavior or SwiftUI and is not full T07.2 acceptance.

## Accepted boundary

Schema 2 now has a finite backward-compatible root grammar. Older bytes without active/inert fields decode as nil/empty without rewrite. New durable documents bind active selection to exactly one stored profile and preserve at most 1,000 closed-wire inert records; malformed keys, tags, digests, UUIDs, ownership, UTF-8/count/aggregate limits or orphans enter read-only recovery without truncation or repair.

`PreferencesDocumentDelta` carries exact touched bases for global fields, profile insert/update/delete, active selection and inert ownership. Older revisions may apply only while every touched base still matches. Structural invalidity and stale bases have distinct failures; unrelated globals/projects/config fields survive. Deleting the active profile requires the same atomic delta to select nil. Locally owned global eligibility opt-ins remain valid durable state, while saved profiles remain monotone against global policy and portable import remains stricter against defaults.

Only `SettingsStore` issues import identities. Analysis retains parsed values and source digest, not raw source bytes, and is bound to exact revision/disk image. Issuance consumes analysis even on invalid choices; preview binds copied choices, classifications, exact candidate, source digest and SHA-256 of the exact next encoded envelope including compatibility-projected config. Commit consumes the preview before one publication attempt, accepts no replacement candidate/bytes/choices, rechecks revision/disk/digest, preserves projects/active selection, and publishes once. Load, save, recovery, cancellation and newer tokens invalidate older bindings.

Hostile bytes covering maintenance/background/notification/login authority, roots/project identity, executable/endpoint/device/application IDs and volume overrides pass through the real store analysis/issue/commit path. They remain classification-only, never active or durable. A safe preference and a safe unknown inert scalar may commit. Portable compatibility globals reverse-project atomically into `TidyConfig`; nonportable cookie domains remain unchanged.

Adversarial source review found two Important defects after initial GREEN: durable global opt-ins incorrectly reused import-only monotonic validation, and a recognized inert safe tag could hide an additional unknown tag. New RED regressions reproduced both; durable/import validation was split and nested exact-key validation moved to `StrictJSON`. Re-review returned **Approved**. Integration then found that rollback restored backed-up profiles while retaining current active/inert state. The binding/preview now freezes and verifies the entire backed-up graph and restores it atomically; focused regression and adversarial re-review are **Approved**.

## Evidence

- Required RED: focused compilation failed on the missing approved envelope, delta and issued-import APIs before production edits.
- Final focused: `swift test --jobs 2 --filter SettingsProfilePersistenceTests`; 25 tests / 1 suite passed in 0.658 seconds.
- Existing policy persistence: 11/11 passed.
- Existing strict transfer: 28/28 passed.
- Settings migration/publication compatibility: 46/46 passed.
- Final ordinary partition: `swift test --jobs 2 --skip BoundedProcessRunnerTests --skip SettingsProcessAcceptanceTests`; 435 tests / 49 suites passed in 45.545 seconds.
- Isolated bounded-process partition: 21 tests / 1 suite passed in 29.833 seconds.
- Final isolated settings process acceptance: 3 tests / 1 suite passed in 14.078 seconds; abrupt-publication evidence retained under `/private/tmp/tidy-t05-a2p-*`.
- The standalone compiler manifest includes and hashes both `Policy/SessionProfile.swift` and `Policy/SettingsTransfer.swift`.
- `git diff --check` clean and exact implementation allowlist respected.
- No app files changed, so this store-only checkpoint did not require an Xcode app build.

## Test-card integrity amendment

The initial RED file was created verbatim. `StrictJSON.canonicalData` correctly refuses to manufacture values beyond its own bounds, so the deliberately malformed 1,001-inert and 4,097-byte persisted fixtures were changed to emit the same explicit closed Codable wire directly. Production parsing/encoding limits were not weakened. Three post-review regressions—durable global opt-ins, recognized-plus-unknown inert tags, and complete-state rollback—are binding and are recorded in the task card.

## Remaining gates

T07.2b must route this delta through the existing bounded bridge/app owner, synchronously invalidate policy when required, replay outcomes in order, restore selected profile to `PolicyResolver`, and prove relaunch/two-window behavior. T07.3 UI/workflows, T07.4 hostile coordinator regression and dependency-bound T07.3d/T22.3/T22.4 remain open. No full T07 or release acceptance is claimed.
