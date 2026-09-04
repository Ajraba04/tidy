# T07 settings customization entry contract — 2026-08-28

Status: documentation-only source-entry contract. It narrows T07 from the execution plan into independently reviewable checkpoints. It claims no implementation, test, UI, accessibility, device or release result.

Binding inputs:

- `docs/superpowers/plans/2026-08-26-developer-headroom-execution-plan.md`, T07;
- the complete policy registry and factory profiles in `docs/superpowers/specs/2026-08-26-headroom-policy-and-adapter-contracts.md`;
- T06.1 pure registry/resolution, T06.2 atomic typed persistence and T06.3 base-bound revision handoff through `98cf0ba`;
- T01/T02/T04/T05 default-deny capability, coordinator, recovery and single-store boundaries.

## Global constraints

T07 adds customization and portable preference transfer. It grants no execution authority. It must not add a second store, bridge, coordinator, resolver or writer; start scans/processes; activate profiles automatically; repair/reset corrupt settings; clear the mandatory effect journal; implement maintenance, notifications, login items, adapters or local identity reassociation; or claim typed cleanup values are already consumed by execution.

All transfer and durable limits use UTF-8 bytes: at most 1 MiB encoded data, depth 16, 50 profiles, 1,000 members per array/object/list, 4,096 bytes per string and the existing aggregate typed-field cap. Duplicate JSON keys, invalid UTF-8, nonfinite/overflow numbers, invalid tagged values and noncanonical UUIDs reject.

## Shared portable/inert model

One production `PortableSettingPolicy.classify(id:value:layer:)` is used by import and export. P/R classification alone never implies portability.

Portable active values are limited to known global/profile fields that:

- are not authority/consent or hard constraints;
- contain no project, root, path, URL, domain, volume, device, executable, application, Docker endpoint or other machine identity;
- are valid at that exact layer;
- for restrictions, satisfy the monotone restriction contract below.

Transfer always excludes projects, active profile selection, `TidyConfig`, local diagnostics/history/journal bytes and any local authority state. Exact exclusions include all `scope.*`, `browsers.keepCookieDomains`, `headroom.volumeOverrides.*`, `rescue.approvedApplications`, simulator/device approvals, executable approvals, Docker endpoints and future identity-bearing rows.

Known authority/local-identity fields appear in preview as `requiresLocalReassociation` or `rejectedAuthority`; they are never durable through transfer and never exported.

Unknown IDs are retained durably only in a permanently inert quarantine structurally separate from active global/profile/project values. The resolver has no quarantine input and registry growth never promotes an inert record. Promotion requires a fresh explicit preview.

- The stable-key grammar is exactly `[a-z0-9][A-Za-z0-9._-]{0,255}` in ASCII.
- Unknown bool, integer and null values may be retained exactly.
- Unknown valid tagged choice, strings and volume values retain only their finite value kind, SHA-256 of canonical input and a redacted label; path/domain/identity-like content is a semantic reason for that redaction, never a separate wire kind. Unknown outer tags and arbitrary object/list shapes are malformed and reject atomically. Original sensitive strings/identities are neither durable nor exported.
- Invalid/unsafe IDs retain only a digest and redacted label in the current preview, not durable data.
- Quarantine entries count toward the same size/member/string budgets, survive relaunch and export safe scalar values or redacted markers only.

This is the binding interpretation of “unknown IDs retained disabled.” Safety and non-portability override exact value round-trip for identity/string-bearing unknowns.

## Monotone restriction contract

One `PolicyRestrictionValidator` covers every expanded registry row whose resolution is `.restriction`; a coverage test fails if any current/future R row has no comparator.

- enable/inventory/manual-action/item/budget flags: `false` is stricter than `true`;
- `monitor.suppressHiddenSampling`: `true` is stricter;
- exclusion/protection/pin sets: a superset is stricter;
- optional hard caps: smaller non-null is stricter; adding a cap to null is stricter; removing/raising a cap is weaker;
- `pauseAll` is stricter than `pauseDiscretionary`;
- identity-bearing restrictions remain nonportable even when monotone;
- profiles/imports cannot enable maintenance, rescue/manual effects, inventory/actions, budgets or items when inherited state disables them;
- imported global restrictions cannot replace a stricter local global value with a weaker value.

Removing a restriction owned by the same profile is allowed only through an explicit reset/edit preview; inherited/global protection stays effective. Ordinary selective reset never weakens global protections, pins, exclusions, authority or hard constraints.

## T07.1a — Shared strict JSON and pure transfer analysis

Create `Policy/StrictJSON.swift`, `Policy/SettingsTransfer.swift` and focused parser/transfer tests. Modify `SettingsEnvelope.swift` only to use the shared package-internal parser.

Deliver:

- one bounded AST/parser used by settings and transfer, with existing malformed settings tests unchanged;
- deterministic schema-1 portable JSON encoding with the closed grammar and canonical order below;
- the exact portable classifier and inert quarantine representation above;
- pure, base-aware `SettingsTransfer.analyze(bytes:current:)` returning an untrusted inert analysis, never a commit token;
- every semantically valid input row classified as `committable`, `inert`, `redacted`, `requiresLocalReassociation`, `rejectedAuthority`, `rejectedProtectionWeakening`, `rejectedInvalid`, `rejectedNonPortable`, `rejectedUnsupportedLayer` or `collision`;
- export of portable active values plus safe inert records only.

Schema 1 has this exact closed wire grammar; every listed object rejects extra keys:

```text
root = {
  "schemaVersion": 1,
  "global": {"fields": {settingID: taggedValue, ...}},
  "profiles": [
    {"id": canonical-lowercase-hyphenated-UUID,
     "name": string,
     "values": {"fields": {settingID: taggedValue, ...}}}, ...
  ],
  "inertImports": [
    {"scope": "global"|"profile", "profileID": UUID|null,
     "id": stableID, "value": taggedSafeScalar|null,
     "valueKind": kind|null, "valueDigest": lowercase-hex-SHA256|null,
     "label": "redacted"|null}, ...
  ]
}
taggedValue = exactly one of {"bool":bool}, {"integer":int64},
  {"choice":string}, {"strings":[string,...]}, {"null":true},
  {"volume":{"clear":volumeField,"target":volumeField,"warning":volumeField}}
volumeField = exactly one of {"inherit":true}, {"automatic":true},
  {"fixedGiB":int64}
taggedSafeScalar = {"bool":bool}|{"integer":int64}|{"null":true}
kind = "choice"|"strings"|"volume"
```

`profileID` is non-null exactly for profile scope. Safe scalar inert rows have non-null `value` and null `valueKind`, `valueDigest` and `label`. Redacted safe-ID rows have null `value`, a value kind, a digest and the literal label `redacted`. Unsafe-ID rows never enter `inertImports`. Import rejects duplicate profile UUIDs, invalid canonical UUID spelling, noncanonical lowercase 64-hex digests and any invariant-breaking inert shape.

A profile-scoped inert row must refer to exactly one imported profile in the same transfer document and, after collision resolution, exactly one profile in the final candidate. `replace` retains the imported UUID and its inert rows. `clone` remaps the imported profile and every associated inert row to the newly supplied UUID. `keep local` never attaches imported inert rows to the unrelated existing local profile: the rows must either be shown and explicitly discarded as noncommittable or retained only with an explicitly cloned imported profile. Orphaned or ambiguous references reject analysis/preview binding before commit. Canonical sorting occurs after clone remapping.

Canonical encoding is UTF-8 without whitespace: object keys sort lexically by their UTF-8 bytes; field keys use the same order; profiles sort by canonical UUID; inert rows sort by `(scope, profileID-or-empty, id, valueKind-or-empty, valueDigest-or-empty)` in UTF-8 byte order; string arrays preserve semantic order. SHA-256 for a redacted value covers the canonical JSON bytes of the original tagged value subtree before redaction. Encoder output must be byte-identical across dictionary, profile and inert insertion orders.

Import transformation rules:

- explicit imported global keys merge; absent keys preserve current values;
- profiles merge by UUID; duplicate names are valid;
- UUID collisions require an explicit choice: keep local, replace or clone with a newly supplied UUID;
- replacing an active profile is never implicit;
- imported data never carries or changes active selection;
- projects, local identities, legacy config and local authority state are preserved;
- the complete post-merge candidate validates and contains at most 50 profiles;
- analysis/cancel performs no I/O.

Duplicate JSON keys, invalid UTF-8, invalid schema/tag/object shape, integer overflow, duplicate profile UUIDs and invalid inert invariants reject the whole document atomically and produce no preview. Known fields with invalid value/range/relation, unsupported layer, protection weakening or nonportable semantics remain visible noncommittable preview rows and are removed before candidate validation. Collision choices are resolved before the complete post-merge candidate is validated.

T07.1a contains no actor, coordinator, bridge, app or UI code.

## T07.1b — Pure profiles and restrictions

Create `Policy/SessionProfile.swift` and focused profile/restriction tests.

Deliver:

- pure create/clone/rename/delete/diff/reset transformations over `SavedProfile` values;
- unique UUIDs, duplicate names permitted, at most 50 profiles;
- trimmed nonempty names of at most 4,096 UTF-8 bytes;
- caller-supplied UUIDs for deterministic core tests; UI may generate one;
- factory template keys `xcode`, `android`, `flutter`, `web`, `localAI`, `battery` backed exactly by `PolicyDefaults.factory`; template keys never become stored UUIDs;
- cloning never activates;
- all profile values validate at `.profile`, contain no authority/hard/local-identity/volume-identity fields and pass the complete monotone restriction validator;
- diffs contain stable ID, old/new/default, effect, range/rule and provenance metadata, but no invented human copy;
- selective reset removes chosen explicit P fields and, only after explicit preview, restrictions owned by that profile. It never changes inherited/global protection, projects, quarantine or authority.

T07.1b adds no active selection or persistence.

## T07.2 — Durable profile state, issued previews and shared app handoff

### Controlled T07.2 checkpoint split — 2026-08-28

T07.2 is executed as two bounded checkpoints, each requiring its own approved preimplementation card, observed RED, full relevant verification and fresh adversarial source review:

- **T07.2a — durable profile state and issued import store:** the additive schema-2 wire, exact base-bound preferences-document delta, active/inert validation, and `SettingsStore`-issued analysis/preview/one-attempt commit lifecycle. It has no app caller and cannot complete T07.2.
- **T07.2b — shared bridge and app handoff:** bounded queue retention/accounting, effect aggregation, synchronous invalidation, ordered acknowledgement/replay/failure reconciliation, selected-profile input to `PolicyResolver`, relaunch restoration, and two-window app-visible synchronization.

T07.2 remains incomplete until both checkpoints are independently accepted. T07.2a must not claim bridge replay, invalidation, selected-profile resolution, relaunch UI behavior or two-window behavior; T07.2b may not weaken or replace the accepted store token/delta contract.

Extend the existing typed settings document compatibly:

- `activeProfileID: UUID?`, missing on older schema-2 data means nil;
- `inertImports: [InertPortableSetting]`, missing means empty;
- non-nil active ID must name exactly one stored profile; invalid persisted selection enters read-only recovery;
- profile UUIDs stay unique and all existing size/validation limits apply.

Add one base-bound preferences-document delta through the existing `SettingsStore`, `ExecutionPolicyBridge` and `AppConfigStore`. It explicitly carries touched global fields, profile UUID bases/edits/deletes, active-profile base/edit and inert additions/removals. Every touched base is compared exactly; unrelated durable edits survive. Queue retention, checked accounting, synchronous invalidation, exact outcomes, ordered acknowledgement/replay and recovery behavior remain those accepted in T06.3.

- Any authority/consent/local row rejects before retention.
- A mixed change invalidates if any touched field is `.invalidate`; active selection always invalidates.
- Pure names, quarantine and presentation-only values use storage revision only.
- Activation/deactivation accepts only an existing profile and invalidates synchronously.
- Deleting the active profile atomically deletes it and sets active nil, visibly falling back to global and invalidating plans.
- Relaunch restores active selection; imported profiles never activate.
- The selected profile is actually supplied to `PolicyResolver` for app-visible effective policy. Storage revision, effective policy and profile identity never become execution authority.

Only `SettingsStore` may issue a commit-capable import preview. Analysis is not commit-capable; collision choices are bound while issuing the final preview:

```swift
analyzeImport(bytes:) -> SettingsImportAnalysis
issueImportPreview(analysisID:choices:) -> SettingsImportPreview
commitImport(expectedRevision:previewID:) -> SettingsEnvelope
cancelImport(analysisID:)
cancelImport(previewID:)
```

The store retains separate unguessable analysis and preview tokens. Preview issuance resolves all collision choices, validates the exact complete candidate and binds the displayed classifications, resolved choices, exact base revision/disk-image identity, SHA-256 of source bytes and canonical candidate digest. Commit accepts no choices or candidate bytes; it consumes the actor-issued preview token, rechecks revision/disk identity and bound candidate, and publishes exactly once. A load/external change/new analysis/new preview/cancel invalidates prior tokens. Stale preview conflicts; cancel writes nothing. Callers never supply a replacement candidate behind a reviewed token. Tests mutate choices after issuance and prove commit still writes only the reviewed candidate or rejects.

Required tests cover relaunch, two-window state, profile CRUD/activation/deletion, unrelated-versus-conflicting deltas, ordered failure replay, import collision choices, one-write commit, stale/cancelled/single-use preview, authority exclusion and quarantine durability.

## T07.3a — Registry-driven Settings UI foundation

Add a pure presentation registry keyed by exact setting ID/pattern with one-to-one coverage over every static `PolicyDefaults.rows` entry, every `PolicyDefaults.itemRows(catalogID:)` expansion for every current `CleanCatalog` ID, `headroom.volumeOverrides.<UUID>`, and every other finite or dynamic registry family. It supplies deterministic order, Basic/Advanced tier, localization keys, help/consequence keys and applicability/availability explanation without duplicating default, rule/range, resolution or effect. Coverage tests fail when a registry definition has no presentation match or a presentation pattern matches no registry definition.

Build searchable feature/scan/cleanup/experience settings surfaces. Every row shows default, effective value, source, rule/range, consequence and not-applicable/unavailable state. P/R controls route only through shared `AppConfigStore`; A rows remain visible but unavailable/deferred, with no invented consent flow. Search reaches Advanced rows even when the Advanced filter is off. Opening settings starts no scan/process/timer.

Tests cover complete row reachability, stable accessibility identifiers/labels, keyboard/focus order, text-size layout and contrast. Physical VoiceOver/device evidence remains a separate acceptance gate.

## T07.3b — Profile, transfer and reset workflows

Build profile clone/create/rename/delete/activate/diff preview; import/export; and selective reset preview.

- Import preview lists every outcome in the T07.1a classification taxonomy, including invalid, protection-weakening, nonportable and unsupported-layer rejections.
- Collision resolution and commit require explicit confirmation; cancel writes nothing.
- Local reassociation stays unavailable until a separate OS-picker task.
- Export contains portable preferences and safe inert records only.
- Reset has a scoped diff and confirmation; it cannot touch the mandatory journal, App Support root, projects, global protections, local identities or authority.
- History/index clearing stays visibly unavailable until those bounded stores exist.
- Two windows observe one owner and exact durable revisions.

## Controlled amendments to the parent T07 plan

The following table supersedes only the cited T07 plan clauses. These corrections remove no safety gate; they separate currently executable proof from dependency-bound product acceptance.

| Older requirement | Why it cannot be accepted at the earlier checkpoint | Executable substitute and exact later owner | Completion effect |
|---|---|---|---|
| Plan line 345: confirm imported local roots during ordinary import | A portable document cannot safely assert a local path identity, and T07 has no accepted local authority owner | T07.3b records `requiresLocalReassociation` without storing the identity. New **T22.3 — local scope reassociation**, dependency-blocked on the separately accepted T22 local authority ledger, must use an OS picker, derive local canonical resource identity, show a separate diff/consent and persist only through that authority owner—not `SettingsStore`, `PolicyPreferences`, `TidyConfig` or transfer quarantine | T07.3b may pass; full T07 product acceptance remains open through T22.3 |
| Plan line 347: clear history/index | The bounded optional completed-report store and SQLite index do not both exist at T07 entry; the mandatory journal must never be cleared | New **T07.3d — bounded data clearing**, dependency-blocked on the optional T04 completed-report boundary and accepted T09 index, must preview exact stores/byte counts and clear only eligible optional reports/index transactions | T07.3b may show unavailable; full T07 product acceptance remains open through T07.3d |
| Plan line 350: literal authorization-ledger identity and recording effect client | Current production coordinator has neither the later local authorization ledger nor an injected adapter effect boundary; inventing test-only authority would be false proof | T07.4 proves all existing production boundaries below. New **T22.4 — accepted-adapter hostile import regression**, after T22 ledger plus at least one accepted T15–T20 adapter, must assert literal ledger bytes and zero injected effect calls | T07.4 may pass; full T07 product acceptance remains open through T22.4 |

T22.3, T07.3d and T22.4 each require their own independently approved preimplementation card and verification. They are explicit acceptance gates, not unspecified future work. T22.3 tests prove picker results never enter settings/export, `SettingsStore` cannot commit reassociation, cancellation writes neither settings nor authority, only the authority ledger owns canonical identity/consent, and transfer-preview text cannot authorize a root.

## T07.4 — Hostile production-bound regression

Send hostile bytes through the real `SettingsStore.analyzeImport`, `issueImportPreview` and `commitImport`. Include `maintenance.mode=authorizedCaches`, roots, executable/volume/device/app identity values, notification/login/background consent and unknown model-deletion IDs.

Assert:

- the complete existing `TidyConfig` remains identical, including roots, simulator approvals, approved apps and legacy authority-like fields;
- no A/local field enters active preferences;
- safe unknowns enter only inert quarantine and sensitive unknown values become redacted markers;
- imported profiles do not activate;
- the real coordinator rejects a forged/unavailable selection;
- the real `CleanEngine`/`CapabilityRegistry` boundary invokes zero recording command/custom effects.

This repository currently has no standalone local authorization ledger and the coordinator does not own an injected effect client. T07 must not invent either for a test. Literal authorization-ledger byte identity and injected-effect proof remain open until T22.4. T07.4 may not claim them.

## Checkpoint gates

Before any production edit, T07.1a, T07.1b, T07.2, T07.3a, T07.3b, T07.3d, T07.4, T22.3 and T22.4 each require a narrow independently approved preimplementation card. Every card contains the exact source allowlist, public/internal signatures, complete failing test code, concrete fixture bytes/inputs and expected bytes/outcomes, plus negative tests. Approval of this entry contract is not approval to skip those cards.

Each subtask then requires observed RED, focused GREEN, ordinary package coverage, relevant isolated process partitions, unsigned arm64 app build when app sources change, and fresh adversarial review before acceptance documentation. Full T07 product acceptance requires T07.1a–T07.4 plus dependency-bound T07.3d, T22.3 and T22.4; it cannot be marked complete earlier. Intel, macOS 14, physical 8 GiB performance/accessibility, README, GitHub push and DMG release remain open.
