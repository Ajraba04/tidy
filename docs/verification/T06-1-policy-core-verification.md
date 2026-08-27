# T06.1 pure policy core verification — 2026-08-28

Scope: the T06.1 registry, defaults, validation, effective-policy resolution, provenance, strict preference wire values and pure legacy projection. This does not accept T06.2 persistence, T06.3 app integration, settings UI, scheduling, execution authority, adapters, device performance or release readiness.

## Implementation boundary

Checkpoint `83087b4` contains exactly the seven approved policy sources and three approved pure test files. The finite registry has 91 literal fixture rows expanding to 133 unique entries for the accepted catalog item and selected-volume pattern. No store, filesystem/network/process I/O, app/UI, scheduler, coordinator, capability, authority writer, generated-project or dependency surface was added.

The resolver provides conservative defaults, global/profile/project/run ordering, false-dominant restrictions, mandatory exclusion union, strict batch caps, selected-volume headroom, capacity-bounded budgets, scan CPU/pressure ceilings, unavailable states and stable provenance. Authority-class fields remain unavailable with local-authority provenance and cannot be written through portable preferences.

## Test and build evidence

- Focused policy tests: `swift test --jobs 2 --filter 'PolicyResolutionTests|PolicyDefaultsTests|PolicyValidationTests'`; 28 tests / 3 suites passed, zero failures. The review-fix test-first run previously produced 17 expected issues across the newly asserted gaps; a separate malformed-UUID RED observed `unknownKey` before the field-specific correction.
- Ordinary package partition excluding both global child-owner suites: 351 tests / 45 suites passed in 11.822 seconds, exit 0.
- Isolated bounded-process partition: 21 tests / 1 suite passed in 29.948 seconds, exit 0.
- Isolated settings process acceptance: 3 test methods / 1 suite and eight prescribed executions passed in 14.519 seconds, exit 0. Bootstrap death retained exit 80; publication prefixes retained exits 81–85; observations reported one consuming reap and zero signal attempts.
- Unsigned Debug arm64 production app build, two jobs: exit 0.
- `git diff --check`: clean.

The initial focused restricted attempt failed before compilation because SwiftPM manifest sandbox application was unavailable. The identical approved retry supplied the runtime evidence; that environmental failure is not a source RED.

## Adversarial review

The first independent review of `f271752..ca59f70` returned Needs fixes with six Important findings and one Minor: synthesized JSON wire form, UUID aliases, noncanonical exclusions, missing maintenance eligibility, capacity-blocked budget disable, lost unavailable-headroom provenance and inaccurate inherited-item provenance.

A fresh fixer added regression tests first and corrected only five approved policy sources and two approved tests. The same reviewer inspected both the 33,591-byte correction package and complete 132,823-byte T06.1 package at `83087b4`, confirmed every finding resolved, found no new Critical, Important or Minor issue, and returned **Approved**.

## Remaining gates

T06.1 is accepted only as a pure policy boundary. T06.2 must persist the exact tagged preference wire form through the accepted atomic settings store, preserve revisions/rollback/recovery and avoid a dual writer. T06.3 must connect base-bound deltas to the existing synchronous invalidation bridge. Settings reachability, scheduler consumption, adapter authority, Intel/macOS 14, physical 8 GiB performance, full product acceptance, README publication, GitHub push and DMG release remain open.
