# T07.1b pure profile and restriction verification — 2026-08-28

Scope: pure named-profile transformations and the complete monotone restriction comparator. This checkpoint adds no persistence, active selection, import/export, authority, I/O, coordinator, app or UI behavior and is not full T07 acceptance.

## Accepted boundary

The source-entry contract was independently rejected twice before approval. Its final RED suite binds every current static and dynamic restriction definition, both comparison directions, invalid operands, error precedence, UTF-8 name bounds, array invariants, all factory profiles, CRUD validation, diff provenance and reset purity.

`PolicyRestrictionValidator` resolves the production registry and compares every current R family: ordinary enable/inventory/action/item/budget booleans, inverse hidden-sampling suppression, both power/thermal pause rows, exclusions/pins/domains as protection supersets, and both optional hard caps. Unknown, non-R, malformed or unsupported comparator shapes fail closed. Profile values must be structurally valid at the profile layer and cannot weaken inherited/default restrictions.

`SessionProfiles` is pure and caller-ID-driven. It validates the complete collection before each transformation, preserves array order, permits duplicate display names, limits profiles to 50, enforces trimmed nonempty names at 4,096 UTF-8 bytes, derives all six factories only from `PolicyDefaults.factory`, and never activates a profile. Diff metadata comes from the registry rather than invented copy. Reset returns only a preview candidate and requires explicit permission before removing an owned restriction.

Fresh code review found one Important boundary defect: structurally valid `scope.currentProject` and canonical `headroom.volumeOverrides.<UUID>` values could enter profiles. A new regression reproduced three acceptances (two distinct volume UUIDs and one project identity). The source now performs structural validation first—preserving A-row `authorityIsLocal` behavior—then rejects optional-project and volume-override kinds as `nonProfileField`. Re-review returned **Approved** with no remaining finding.

## Evidence

- Required RED: focused build failed because all prescribed T07.1b symbols were absent.
- Initial focused GREEN caught an incorrectly grouped registry filter; after correction, 19 tests passed.
- Review-fix RED: valid project and two canonical volume identities were accepted, recording three issues.
- Final focused: `swift test --jobs 2 --filter SessionProfileTests`; 20 tests / 1 suite passed in 4.749 seconds.
- Final ordinary package partition: `swift test --jobs 2 --skip BoundedProcessRunnerTests --skip SettingsProcessAcceptanceTests`; 382 tests / 47 suites passed in 11.287 seconds.
- Final isolated bounded-process partition: 21 tests / 1 suite passed in 29.857 seconds.
- Final isolated settings process acceptance: 3 tests / 1 suite passed in 14.513 seconds, including both contention modes, bootstrap exit 80 and publication-prefix exits 81–85.
- `git diff --check` clean; exact implementation allowlist was `Policy/SessionProfile.swift` plus `SessionProfileTests.swift`.
- No app files changed, so this pure checkpoint did not require an Xcode app build.

## Remaining gates

T07.1a strict transfer parsing/classification, T07.2 persistence/active-profile handoff, T07.3 UI/workflows, T07.4 hostile production regression, dependency-bound T07.3d/T22.3/T22.4, device evidence and release work remain open.
