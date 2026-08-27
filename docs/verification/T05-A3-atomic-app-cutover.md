# T05 A.3 atomic app settings cutover

Implementation checkpoint: `d82ba82`, reviewed from base `b235fc8`.

## Accepted scope

- The legacy fallback/raw `ConfigStore` is deleted with every caller; schema2 becomes the default in the same atomic checkpoint. The A2P fixture loses only that deleted source entry.
- One actual SettingsStore and one actual coordinator are constructed off MainActor and shared by all scenes. Recovery and unavailable states expose no settings, review or confirmation action.
- Each edit invalidates policy synchronously before validation or work scheduling. The bridge retains at most32 active/queued snapshots,1MiB per snapshot and32MiB total; writes remain ordered, policy is committed only from the actual saved config, and durable storage revision stays distinct from policy revision. Validation, overflow and durability failures remain disabled until an explicit valid resave.
- Automatic onboarding discovery and automatic scan startup are removed. Discovery remains reachable only through the explicit setup button; scans require explicit user action and use the shared config with unknown tools.
- CleanResultsView consumes the tested pure availability projection: missing/mixed memory is not measured, explicit zero is measured, and all T02 denial/no-op messages remain distinct.

## Verification

- Natural scaffold RED: fresh build-for-testing reached missing `AppStoragePaths`; no test executable ran.
- Fresh unhosted bundle: exact nine sources, local TidyCore only, empty TEST_HOST/BUNDLE_LOADER, Debug testability only.
- App models:29/29 pass (15 preserved confirmation,3 report presentation,11 shared settings wiring), exit0.
- Focused core cutover/settings/confirmation:80 tests/5 suites pass, exit0.
- Complete package partition: ordinary323/42, A2P3 methods/eight executions, bounded process21/1 all pass; no test omitted. A2P retained expected exits and zero signal attempts.
- Unsigned arm64 production app build exits0 with no output.
- Independent source review read the complete120,362-byte package: spec compliant and Approved, no Critical or Important. Its sole Minor was append-only report chronology; the implementation report now explicitly labels worker versus later controller evidence.

## Remaining gates

This accepts A.3 source/model integration only. No normal app/manual-host launch, live settings migration, native B.1/B.2 dialog/effect run, accepted cleanup, Intel, macOS14, stable-OS device, full T05 or full-product acceptance is claimed.

