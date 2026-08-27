# T06.3 typed policy revision handoff verification — 2026-08-28

Scope: the T06.3 handoff from the shared app settings owner through the existing bounded `ExecutionPolicyBridge` to the accepted atomic `SettingsStore` and coordinator policy barrier. This accepts storage-only presentation edits and policy-invalidating typed edits as revision handoff. It does not claim that typed cleanup limits are consumed by execution, nor accept settings UI, profiles/import/reset, scheduling, adapters, device performance or release readiness.

## Implementation boundary

The accepted range `4be267e..98cf0ba` modifies the existing settings envelope/store, existing bridge, shared app owner/bootstrap and their existing core/app-model tests. No second store, coordinator, resolver, authority writer or bridge was added.

The app owner separates exact durable acknowledgement from optimistic displayed state. Accepted intents have immutable IDs, remain bounded in one serialized queue, and reconcile in accepted order from exact saved envelopes. Rejected intents never enter displayed or pending state. Failed heads are removed and remaining transforms replay from the last durable acknowledgement; dependent stale transforms conflict rather than being silently rebased or partially applied.

Legacy and typed global deltas bind their exact raw bases, including absent versus explicitly stored defaults. Global admission validates the unique finite registry definition, layer, non-authority effect, base value and complete predicted global document before retention or coordinator invalidation. Count, byte and sequence overflow reject before changing queue state, policy generation, admission or confirmations.

`LegacyCompatibilityProjection` is the single pure compatibility implementation used by durable storage, bridge prediction and app replay. Legacy edits first project all existing nondefault compatibility fields, then apply their changes. Typed replacement projects explicit values into legacy config, resets removed explicit values to `45`, `60`, `[]` or `false`, and preserves a legacy-only nondefault when the typed value is absent before and after.

Presentation-only `.none` edits share durable ordering/accounting but never change the coordinator policy generation, execution-enabled state or confirmations. Invalidating edits acquire their opaque coordinator ticket synchronously after bounded admission and before asynchronous work. A successful exact saved envelope commits the legacy `CleanEnvironment` under that ticket. A conflict, invalid edit or publication failure cannot be healed by later presentation work. Recovery-required publication state obtains and retains an uncommitted coordinator ticket before failure publication.

`cleanup.requestedBatchGiB` therefore invalidates frozen confirmations and advances storage plus policy revisions, but the typed value is not yet an operative cleanup limit. Later scheduler/execution snapshot work must consume the typed effective policy before making that claim.

## Test and build evidence

- Focused core: `PolicyPersistenceTests` plus `ConfirmedExecutionTests`; 39 tests / 2 suites passed, including the ten malformed preference fixture cases.
- Unhosted app-model: `SharedSettingsWiringTests` 22 and `ConfirmationLifecycleTests` 15; 37/37 passed. The real shared-services tests cover blocked publication, presentation-only confirmation preservation, synchronous invalidation, valid-base and relation rejection, external durable conflicts, failed-head/dependent-tail reconciliation, successful-head/failed-tail reconciliation, whole-value explicit resubmit, two shared windows, both mixed compatibility orderings, exact durable/displayed revisions and zero drained accounting.
- Ordinary package partition excluding the two global child-owner suites: 362 tests / 46 suites passed in 9.500 seconds, exit 0.
- Isolated bounded-process partition: 21 tests / 1 suite passed in 29.665 seconds, exit 0.
- Isolated settings process acceptance: 3 tests / 1 suite passed in 14.932 seconds, including all five abrupt-publication prefixes and exact retained-artifact reopen checks.
- Unsigned Debug arm64 production app build, two jobs: exit 0 and `** BUILD SUCCEEDED **`.
- `git diff --check`: clean; worktree clean at the accepted source checkpoint.

## Adversarial review

Before source entry, a fresh adversarial interface reviewer rejected three drafts. The accepted contract added distinct acknowledged/displayed state, separate storage/policy pending state, authoritative recovery classification, exact typed outcomes, field-bound deltas, checked pre-ticket accounting, strict registry classification, revision-only snapshot truth and an ordered acknowledgement drain.

The fresh code review of `4be267e..11c888b` returned Needs fixes with three Important findings: incomplete pre-retention global validation, an unreconciled whole-config optimistic base, and missing accepted-order failure tests. A fresh fixer replaced the tracker with one ordered retained-payload prediction and added genuine durable-conflict and blocked-I/O reconciliation coverage.

Re-review found one remaining Important divergence between durable compatibility projection and bridge/app replay. A single pure projection helper replaced all three variants and two mixed-order blocked-I/O tests reproduced nine pre-fix failures before passing. The same reviewer inspected the latest fix, cumulative fixes and full range through `98cf0ba`, found no Critical, Important or Minor issue, and returned **Approved**.

## Remaining gates

T06.1 pure policy, T06.2 typed persistence and T06.3 app revision handoff are accepted as bounded foundations. Full T06 product acceptance remains open because no comprehensive customization UI, default/effective/source presentation, profile preview, import/reset flow, scheduler consumption, adapter consumption or physical-device performance evidence exists yet. Those product surfaces begin with T07 and later packages. Intel/macOS 14, physical 8 GiB performance, README publication, GitHub push and DMG release also remain open.
