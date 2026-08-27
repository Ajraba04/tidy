# T06.2 typed policy persistence verification — 2026-08-28

Scope: the T06.2 extension of the accepted atomic `SettingsStore` envelope, revisions and rollback path to persist `PolicyPreferences`. This does not accept T06.3 app revision handoff, settings UI, scheduler or adapter consumption, authority, device performance or release readiness.

## Implementation boundary

Checkpoint `40118ce` extends the schema-2 envelope with an optional typed preference document while retaining legacy schema-2 byte compatibility. `SettingsChange` remains limited to transcript age, whole legacy preferences and whole typed preferences. One actor and one atomic publication path own config and preferences; no second store, resolver, coordinator or authorization surface was introduced.

The decoder rejects duplicate members, unknown typed preference members, malformed tagged values, excessive depth, excessive fields, invalid UTF-8 and oversized documents. Encode and load share validation. Successful typed edits increment the storage revision once, legacy edits preserve unrelated typed fields, reverse projection keeps the four compatibility mirrors coherent, and rollback restores config plus preferences together at a new revision.

Removing a previously explicit typed compatibility value resets its legacy mirror to the canonical fallback (`45`, `60`, `[]` or `false`) so relaunch cannot resurrect the removed value. If neither the prior nor replacement typed document owns a compatibility field, a legacy-only nondefault remains unchanged.

## Test and build evidence

- Focused persistence and malformed-input coverage after the review fix: 9 policy persistence tests / 1 suite plus 10 malformed preference fixtures passed, zero failures.
- Ordinary package partition excluding the two global child-owner suites: 360 tests / 46 suites passed in 11.028 seconds, exit 0.
- Isolated bounded-process partition: 21 tests / 1 suite passed in 30.575 seconds, exit 0.
- Isolated settings process acceptance: 3 tests / 1 suite passed in 12.672 seconds, including all five abrupt-publication prefixes and the exact retained-artifact reopen checks.
- Unsigned Debug arm64 production app build, two jobs: exit 0 and `** BUILD SUCCEEDED **`.
- `git diff --check`: clean.

The first cross-process attempt exposed two fixture-only integration gaps: the explicit helper compilation closure lacked the new policy model sources, then the literal schema-2 byte oracle still expected an envelope without the optional member. The corrected mechanical fixture names the exact additional sources and distinguishes a new envelope (`preferences` absent on disk and decoded as `nil`) from a persisted typed envelope. Subsequent runs used `set -o pipefail`, so test failures could not be masked by `tee`.

## Adversarial review

The first independent review returned Needs fixes with one Important finding: removing explicit typed compatibility keys left their legacy mirrors intact, allowing projection on relaunch to recreate deleted typed values. It also reported one Minor documentation-scope error in the ignored implementation report.

A fresh fixer reproduced the defect with real scratch-store tests, implemented prior-versus-replacement reverse projection for all four compatibility keys, and added independent legacy-only preservation coverage. The same reviewer inspected the fix-only range `853127b..40118ce` and the full range `30258fe..40118ce`, confirmed both findings resolved, found no new Critical, Important or Minor issue, and returned **Approved**.

## Remaining gates

T06.2 accepts typed persistence only. T06.3 must separately review and implement the base-bound app delta handoff, distinguish presentation-only from policy-invalidating edits, preserve unrelated intervening edits, reject conflicts, and ensure failure never reopens admission. Settings reachability, profiles/import/reset UI, scheduler and adapter consumption, Intel/macOS 14, physical 8 GiB performance, full product acceptance, README publication, GitHub push and DMG release remain open.
