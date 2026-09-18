# R08 source/spec review — live policy, monitoring, and optional history

Date: 2026-09-18

Reviewed commits:

- `19fec518ac1b05b17f5ed96f7cf95c54c9e3d143` — live policy, monitor, measurement, settings-consumer, history, and privacy-renderer implementation
- `30c06c8a9160a3b2a9ae2be95c4febabe6aca563` — cleanup-consumer availability correction
- `79935f3c840ccd6fe1ecc61737448ab05774baf2` — revision-bound optional-history correction

Inputs: `.superpowers/sdd/r08-review.patch`, `.superpowers/sdd/r08-app-services-snapshot.swift`, `docs/verification/remediation-R08.md`, R08 in `docs/audits/2026-09-17-9e1a500/remediation-plan.md`, and the applicable settings contracts in `docs/superpowers/specs/2026-08-26-headroom-policy-and-adapter-contracts.md`.

## Verdict

Corrective changes are required before the R08 checkpoint is approved. The review found three Important specification findings. The acknowledged-policy binder, scene-generation ordering, disabled-probe boundary, missing disk-value validation, unit labels, measured UUID/capacity binding, registry consumer metadata, generated settings reference, and structural privacy-renderer boundary otherwise match the reviewed R08 scope.

This review is limited to the supplied R08 commits and the R08-owned binder/history portions of the shared `AppExecutionServices` snapshot. The active R06 scan lifecycle and incremental-index sections were excluded. No tests or builds were run because of the recorded low-disk constraint; the existing 53-core, 30-monitor, 15-app-model, and 5-history results were assessed as supplied evidence only.

## Findings

### Important — the production pressure source never subscribes to nominal recovery

`LiveMemoryPressureObserving` creates its dispatch source with only `.warning` and `.critical` in the event mask, while its event handler contains an `else` branch that maps an event to `.normal` (`TidyCore/Sources/TidyCore/Monitoring/SystemMonitor.swift:90-103`). Dispatch exposes `.normal` as a distinct event indicating that memory pressure returned to normal; an event excluded from the mask is not delivered. Once production publishes warning or critical pressure, `latestPressureLevel` can therefore remain elevated indefinitely, and each later scheduled measurement copies that stale level into the next snapshot (`SystemMonitor.swift:524-546,582-585`). The shared scheduler bridge consequently continues to derive `.critical` or `.constrained` from stale production state even after recovery (`.superpowers/sdd/r08-app-services-snapshot.swift:27-40`).

The focused tests do not exercise the production mask. Their controlled observer calls the callback directly; the only nominal-event regression sends `.normal` through an obsolete subscription and asserts that it is rejected (`TidyCore/Tests/TidyCoreTests/HeadroomSignalsTests.swift:385-428`). It therefore proves stale-subscription rejection, not current-subscription recovery.

Correction: subscribe to `.normal` as well as warning and critical (or use the complete pressure mask), and add a regression that drives critical then nominal through the current subscription and proves immediate recovery publication without another probe. Production/platform delivery remains a separate runtime gate.

### Important — an acknowledged feature disable leaves visible consumers showing the prior successful measurement

Applying a disabled configuration clears only the monitor's internal `latestSnapshot` and pressure value, then cancels the timer/subscription; it does not publish an unavailable snapshot to existing subscribers (`TidyCore/Sources/TidyCore/Monitoring/SystemMonitor.swift:299-320,475-492`). A visible Headroom window or menu popover therefore retains its previous successful `snapshot` indefinitely after the acknowledged disable, because the canceled loop will not produce another value. The UI continues to display old disk/memory/swap figures without the `featureDisabledReason`, contrary to R08's immediate acknowledged-policy behavior and its prohibition on false success in denied/unavailable states.

The app-model test named `testVisibleHeadroomAppliesAcknowledgedFeatureDisableImmediately` verifies only that the timer stops. It then explicitly invokes `model.refreshNow()` before expecting the disabled snapshot (`TidyAppModelTests/SharedSettingsWiringTests.swift:2117-2149`). That manual action masks the stale visible-state behavior and does not establish immediate presentation revocation.

Correction: as part of accepting the newer disabled revision, publish one policy-disabled snapshot without invoking any OS probe, or make every subscribed presentation clear/replace its snapshot directly from the same acknowledged policy event. Add a visible-consumer test that performs no manual refresh, observes the disabled state, and proves the probe count remains unchanged.

### Important — lowering or disabling history can reject a file valid under the previous policy instead of applying the new policy

Both `record` and enabled `reconcile` call `load(maxBytes:)` with the **new** history cap, and disabled `reconcile` calls `removeValidatedIfPresent(maxBytes:)` with that same new cap (`TidyCore/Sources/TidyCore/Policy/OptionalRunHistory.swift:50-92`). `validatedFile` rejects any existing file larger than the passed cap before it can be decoded, pruned, or removed (`OptionalRunHistory.swift:129-143`). Thus a history file valid under a 10 MiB policy can make a subsequent 1 MiB policy throw `.oversized` rather than retain the newest records within 1 MiB. A single acknowledged change that sets `history.enabled=false` and lowers `history.maxMiB` can likewise fail to remove the optional file.

This breaks the R08 requirement that off/age/byte controls apply independently of mandatory recovery. It also leaves `historyPersistenceError` set in the shared binder instead of completing the newly acknowledged retention decision (`.superpowers/sdd/r08-app-services-snapshot.swift:113-135`). Existing tests create and reconcile data under one unchanged 1 MiB cap; they do not cover a downward cap transition or disable combined with a lower cap (`TidyCore/Tests/TidyCoreTests/RunLogTests.swift:109-177`).

Correction: validate/read a pre-existing file against the fixed storage safety ceiling (currently 50 MiB), then apply the new age/byte cap to the decoded records before publishing. The disabled path should safely remove a validated optional-history file that was legal under the preceding acknowledged cap. Add transitions from a larger valid cap to a smaller cap and to disabled, while retaining the existing mandatory-recovery witness assertion.

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
