# R08 source/spec review — live policy, monitoring, and optional history

Date: 2026-09-18

Reviewed commits:

- `19fec518ac1b05b17f5ed96f7cf95c54c9e3d143` — live policy, monitor, measurement, settings-consumer, history, and privacy-renderer implementation
- `30c06c8a9160a3b2a9ae2be95c4febabe6aca563` — cleanup-consumer availability correction
- `79935f3c840ccd6fe1ecc61737448ab05774baf2` — revision-bound optional-history correction

Inputs: `.superpowers/sdd/r08-review.patch`, `.superpowers/sdd/r08-app-services-snapshot.swift`, `docs/verification/remediation-R08.md`, R08 in `docs/audits/2026-09-17-9e1a500/remediation-plan.md`, and the applicable settings contracts in `docs/superpowers/specs/2026-08-26-headroom-policy-and-adapter-contracts.md`.

## Verdict

**Corrective disposition: all three Important findings are resolved in the follow-up source and tests.** The production pressure mask includes nominal recovery, an acknowledged feature disable publishes an unavailable snapshot without probing or manual refresh, and optional history applies a newly smaller/off policy to files valid beneath the fixed 50 MiB storage ceiling. The R08 source checkpoint is approved within the evidence limits below.

This review is limited to the supplied R08 commits, the follow-up correction, and the R08-owned binder/history portions of the shared `AppExecutionServices` snapshot. The active R06 scan lifecycle and incremental-index sections were excluded. No app build or app-model suite was run because of the recorded low-disk constraint. The follow-up used the controller's existing scratch path with two jobs: 33 `HeadroomSignalsTests` and 7 `OptionalRunHistoryTests` passed, 40 total. The earlier 53-core, 30-monitor, 15-app-model, and 5-history results remain supplied prior evidence.

## Findings

### Resolved Important — the production pressure source did not subscribe to nominal recovery

`LiveMemoryPressureObserving` creates its dispatch source with only `.warning` and `.critical` in the event mask, while its event handler contains an `else` branch that maps an event to `.normal` (`TidyCore/Sources/TidyCore/Monitoring/SystemMonitor.swift:90-103`). Dispatch exposes `.normal` as a distinct event indicating that memory pressure returned to normal; an event excluded from the mask is not delivered. Once production publishes warning or critical pressure, `latestPressureLevel` can therefore remain elevated indefinitely, and each later scheduled measurement copies that stale level into the next snapshot (`SystemMonitor.swift:524-546,582-585`). The shared scheduler bridge consequently continues to derive `.critical` or `.constrained` from stale production state even after recovery (`.superpowers/sdd/r08-app-services-snapshot.swift:27-40`).

The focused tests do not exercise the production mask. Their controlled observer calls the callback directly; the only nominal-event regression sends `.normal` through an obsolete subscription and asserts that it is rejected (`TidyCore/Tests/TidyCoreTests/HeadroomSignalsTests.swift:385-428`). It therefore proves stale-subscription rejection, not current-subscription recovery.

Disposition: the production mask now explicitly contains normal, warning, and critical. One regression asserts that exact mask; another drives critical then nominal through the current subscription and proves immediate recovery without another probe. Production/platform delivery remains a separate runtime gate.

### Resolved Important — an acknowledged feature disable left visible consumers showing the prior successful measurement

Applying a disabled configuration clears only the monitor's internal `latestSnapshot` and pressure value, then cancels the timer/subscription; it does not publish an unavailable snapshot to existing subscribers (`TidyCore/Sources/TidyCore/Monitoring/SystemMonitor.swift:299-320,475-492`). A visible Headroom window or menu popover therefore retains its previous successful `snapshot` indefinitely after the acknowledged disable, because the canceled loop will not produce another value. The UI continues to display old disk/memory/swap figures without the `featureDisabledReason`, contrary to R08's immediate acknowledged-policy behavior and its prohibition on false success in denied/unavailable states.

The app-model test named `testVisibleHeadroomAppliesAcknowledgedFeatureDisableImmediately` verifies only that the timer stops. It then explicitly invokes `model.refreshNow()` before expecting the disabled snapshot (`TidyAppModelTests/SharedSettingsWiringTests.swift:2117-2149`). That manual action masks the stale visible-state behavior and does not establish immediate presentation revocation.

Disposition: accepting a disabled configuration now installs and broadcasts the same explicit unavailable snapshot used by manual disabled requests before canceling repeating work. The regression observes the publication directly and proves the probe count remains unchanged; no refresh is involved.

### Resolved Important — lowering or disabling history could reject a file valid under the previous policy

Both `record` and enabled `reconcile` call `load(maxBytes:)` with the **new** history cap, and disabled `reconcile` calls `removeValidatedIfPresent(maxBytes:)` with that same new cap (`TidyCore/Sources/TidyCore/Policy/OptionalRunHistory.swift:50-92`). `validatedFile` rejects any existing file larger than the passed cap before it can be decoded, pruned, or removed (`OptionalRunHistory.swift:129-143`). Thus a history file valid under a 10 MiB policy can make a subsequent 1 MiB policy throw `.oversized` rather than retain the newest records within 1 MiB. A single acknowledged change that sets `history.enabled=false` and lowers `history.maxMiB` can likewise fail to remove the optional file.

This breaks the R08 requirement that off/age/byte controls apply independently of mandatory recovery. It also leaves `historyPersistenceError` set in the shared binder instead of completing the newly acknowledged retention decision (`.superpowers/sdd/r08-app-services-snapshot.swift:113-135`). Existing tests create and reconcile data under one unchanged 1 MiB cap; they do not cover a downward cap transition or disable combined with a lower cap (`TidyCore/Tests/TidyCoreTests/RunLogTests.swift:109-177`).

Disposition: pre-existing history is now validated/read or removed against one named 50 MiB safety ceiling, after which enabled reconciliation applies the acknowledged age/byte policy to the decoded records. New transition fixtures prove a 2 MiB-valid file is trimmed to the newest record under 1 MiB, and that disable plus a lower cap removes only optional history while preserving the mandatory-recovery witness. The unsafe oversized fixture now uses a sparse 50 MiB + 1 byte file and remains rejected.

## Confirmed boundaries

- Scene visibility uses independent leases plus monotonically checked generations; a late appear cannot resurrect a lease after a newer disappear or teardown.
- Configuration delivery from the shared app binder is revision-bound, and the history actor now rejects older revisions plus conflicting policy at an equal revision. The shared error-state update also checks that the app still acknowledges the originating revision.
- `feature.headroom=false` prevents explicit and repeating OS probes. Pressure callbacks from canceled/replaced subscriptions are generation-rejected.
- Disk measurement rejects missing or invalid total, strict-available, and important-usage values. Only a measured UUID string and positive capacity are used to resolve the selected-volume policy; a display path is not admitted through that seam.
- Headroom rendering reads acknowledged `ui.cards` and `ui.units`, preserves an explicitly empty card subset, and labels binary and decimal values distinctly. Native two-window/card-order/accessibility behavior remains a runtime gate.
- Consumer metadata keeps unsupported R09-R11, index, authority, presentation, and diagnostic-export rows unavailable. The committed settings reference is renderer-derived, but its green equality test is source evidence rather than runtime acceptance.
- Optional completed-run history is a separate file/actor from mandatory recovery and uses descriptor-relative validation, owner checks, no-follow opens, regular-file/link-count checks, bounded reads, atomic replacement, and directory synchronization. The cap-transition finding above must be corrected without weakening those storage checks.
- The diagnostic renderer structurally omits the supplied sensitive classes, settings values, and profile names. It is only a pure metadata renderer: actual primary/temporary/backup export-file lifecycle, supported-host privacy declarations, and forbidden-sentinel inspection of real exported artifacts remain open.

## Remaining evidence boundary

Even after these source corrections, R08 does not close full hardware, native UI, accessibility/VoiceOver, actual export-file, released-shape migration/import/reset, real missing-resource-key, two-volume/remount, hidden-idle physical observation, constrained-host, Intel, package, or release gates. Final integrated Debug/Release and aggregate suites are still required after the shared R06/R08 file is settled; the existing focused results cannot substitute for those gates.

## Additional integration-review disposition

Two later integration findings are resolved in the shared app binder:

- Measured-volume delivery now uses a strictly increasing app-owned epoch rather than wall-clock `Date`. Newer missing and remounted observations replace stale UUID/capacity state despite clock rollback, while equal/older epochs are rejected.
- Service teardown now cancels the volume-observation stream and removes only its own acknowledged-policy observer token. The regression retains an unrelated observer and proves it remains registered after the service and monitor subscription are released.

The focused app-model red run reproduced stale volume state and leaked registrations with five assertion failures. The green run passed both targeted tests. The shared `AppExecutionServices` file remains a joint R06/R08 integration artifact for the controller's commit and aggregate verification; this follow-up does not review or alter its scan/index/history mutation sections. Real remount delivery and clock-change behavior remain platform/runtime gates.

### Toolchain-compatibility correction

The first automatic-teardown correction used Swift 6.2's `isolated deinit`, but the supported macOS 14 CI toolchain is Swift 6.0. It was replaced with an ordinary deinitializer that synchronously closes a lock-protected Sendable callback lifetime and cancels the Sendable task, then schedules main-actor observer removal from captured token/store values without an escaping `self`. The explicit disposal method remains idempotent. Two focused model tests pass: automatic deinitialization releases the stream and only the owned observer, and repeated explicit disposal prevents a later acknowledged callback from changing the monitor while an unrelated observer still receives it. This remains model/source evidence rather than runtime lifecycle acceptance.
