# Required-reason API mapping — partial distribution evidence

Checked 2026-09-17 against Apple's [API categories and reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) and [required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api). The selected distribution remains external macOS ZIP/DMG, not an App Store submission. This document does not infer App Store eligibility or make a legal conclusion about the external path.

| Use | Mapping / remaining decision |
|---|---|
| Displaying capacity and available bytes in DiskStats/Headroom/Scan | `85F4.1`; corrected manifest from `E174.1`, which describes observable low-space/write-space decisions rather than display alone. |
| Monotonic elapsed-time and cooldown calculations | `35F9.1`; no raw boot/time data is exported. |
| Reboot identity from `kern.boottime` | Used to reject misleading counter deltas after reboot. Inventory separately from elapsed time; do not assume one reason proves every boot-identity use. |
| `fstatfs` for local-filesystem or volume-identity checks | Safety checks in settings and resource capture; `85F4.1` does not automatically cover this distinct use. Distribution mapping remains open. |
| `stat`/`fstat`/`fstatat`/`lstat` and timestamp resource keys | Identity, protection, size, age and freshness checks span app-owned storage and external roots. `C617.1` is container-limited; `3B52.1` depends on specific user-granted access. Neither is asserted to cover arbitrary home discovery. Per-root consent/distribution assessment remains open. |
| UserDefaults / app storage | No direct source occurrence currently found by the inventory script; this does not prove indirect framework use absent. |

No timestamp category was fabricated merely to make the plist look complete. Full R13 privacy acceptance remains open until each external-root/identity use and the chosen distribution are reconciled, packaged resources are inspected, and representative app/child traffic is instrumented. Source enumeration cannot prove zero network traffic.

Reproduce direct source occurrences with `python3 scripts/verification/privacy-api-inventory.py`. This conservative source inventory includes struct constructor calls and can require manual triage; it is not a runtime trace. Re-run after source changes before distribution review.

| Source | Direct API category | Lines |
|---|---|---|
| `Tidy/Execution/AppExecutionServices.swift` | Time/boot | 275 |
| `TidyCore/Sources/TidyCore/Detect/StaleNodeModulesScanner.swift` | File metadata | 25, 37 |
| `TidyCore/Sources/TidyCore/Detect/TranscriptPruneScanner.swift` | File metadata | 16, 24 |
| `TidyCore/Sources/TidyCore/Exec/ProcessIdentity.swift` | File metadata | 44, 45 |
| `TidyCore/Sources/TidyCore/Execution/DerivedDataEffectAdapter.swift` | Disk/volume | 113, 114 |
| `TidyCore/Sources/TidyCore/Execution/GuardedFileDeleter.swift` | File metadata | 174, 175, 199 |
| `TidyCore/Sources/TidyCore/Execution/GuardedFileDeleter.swift` | Disk/volume | 180, 181 |
| `TidyCore/Sources/TidyCore/Execution/JournalPOSIXIO.swift` | File metadata | 46, 47 |
| `TidyCore/Sources/TidyCore/Execution/JournalStorage.swift` | File metadata | 80, 81, 147, 148, 152, 153, 174, 175, 176, 191, 192 |
| `TidyCore/Sources/TidyCore/Execution/MutationAdmissionStore.swift` | File metadata | 155, 156, 160, 161, 162, 168, 169 |
| `TidyCore/Sources/TidyCore/Execution/ResourcePreflight.swift` | File metadata | 39, 40, 48, 49, 54, 55, 62, 64, 78, 85, 86 |
| `TidyCore/Sources/TidyCore/Execution/ResourcePreflight.swift` | Disk/volume | 63, 65 |
| `TidyCore/Sources/TidyCore/Measure/DiskStats.swift` | Disk/volume | 29, 30, 31, 44, 45, 47, 51, 53, 56 |
| `TidyCore/Sources/TidyCore/Monitoring/SystemMonitor.swift` | Time/boot | 32, 34 |
| `TidyCore/Sources/TidyCore/Policy/SettingsPublication.swift` | File metadata | 74, 75, 108, 109, 133, 134, 143, 144, 414, 415 |
| `TidyCore/Sources/TidyCore/Policy/SettingsPublication.swift` | Disk/volume | 68, 69 |
| `TidyCore/Sources/TidyCore/Scanning/BoundedTraversal.swift` | File metadata | 1162, 1163, 1181, 1182, 1189, 1190, 1221, 1222, 1278, 1279, 1288, 1289 |
| `TidyCore/Sources/TidyCore/Scanning/ScanInvalidation.swift` | File metadata | 252, 253 |
| `TidyCore/Sources/TidyCore/Scanning/ScanScope.swift` | Time/boot | 131 |
