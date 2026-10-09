# Required-reason API mapping — current source review

Checked 2026-09-19 against Apple's current [required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [accessed API type catalogue](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). The catalogue was read from Apple's DocC JSON because the rendered Markdown omitted the `possibleValues` API and reason lists. The fetched catalogue SHA-256 was `19546c6db12067a6e6441140399e8323fd73d5e79d1c682e1d0b826b16da6cf5`.

Apple's guidance says a bundle containing an executable or dynamic library that uses a required-reason API needs a privacy manifest for that executable, and every declared reason must accurately match the API use and derived data. It describes App Store Connect enforcement, but this review found no primary statement exempting externally distributed software. External ZIP/DMG classification therefore remains unresolved and is not treated as an exemption.

## Current Apple catalogue and manifest

Apple currently lists five categories: file timestamps, system boot time, disk space, active keyboards, and user defaults. Relevant reason boundaries are:

- File timestamps: `DDA9.1` is display-only; `C617.1` covers metadata inside an app, app-group, or CloudKit container; `3B52.1` covers files or directories the user specifically granted access to. `0A2A.1` is third-party-SDK-only.
- System boot time: `35F9.1` covers elapsed-time and timer calculations inside the app. `8FFB.1` covers absolute timestamps for in-app events; `3D61.1` covers a user-submitted optional bug report.
- Disk space: `85F4.1` covers display; `E174.1` covers an observable low-space or sufficient-write-space behavior. `7D9E.1` is optional bug reporting and `B728.1` is health-research-only.
- Active keyboards and user defaults have their own reasons; the current source inventory finds neither API category.

`Tidy/PrivacyInfo.xcprivacy` declares disk space `85F4.1` and system boot time `35F9.1`. It declares no file-timestamp reason. `Tidy/Tidy.entitlements` is empty. Although production resolves storage under `~/Library/Application Support/Tidy`, the checked-in configuration does not demonstrate that this unsandboxed directory is an Apple app, app-group, or CloudKit container for `C617.1`. The production build setting requests hardened runtime, while final signature and entitlement state remain artifact-inspection gates.

No privacy-manifest reason or category change is justified by this review. Its boot-time comment binds `35F9.1` to the `systemUptime` timer/elapsed uses and keeps the sysctl identity uses separate. The two existing reasons match some call sites, but the file-metadata and identity uses below still lack a demonstrated reason/mechanism. Adding `C617.1` or `3B52.1` globally would conceal that gap.

The 10 October 2026 reconciliation adds a bounded settings-import reader. Its metadata and deadline uses are mapped below; token locations were updated by source inspection. The Apple catalogue review above remains dated 19 September, and the native verification gates have not been rerun for this patch.

## Function, fields, purpose, and reason disposition

| Source/function | Accessed fields or derived data | Actual purpose and scope | Manifest/reason disposition |
|---|---|---|---|
| `DiskStats.current`: capacity resource keys | total capacity, strict available capacity, important-usage capacity; separately, volume UUID | Display disk/headroom figures and feed selected-volume capacity into policy resolution | `85F4.1` directly fits displayed capacity. Whether the same display reason covers the derived policy calculation remains unresolved; `E174.1` is not claimed without a demonstrated observable low-space/write-space behavior. `volumeUUIDStringKey` is not in Apple's current required-reason list and remains separately mapped as local volume identity. |
| `DerivedDataEffectAdapter.fstatfs` | `f_bavail * f_bsize` before and after a reviewed effect | Report displayed free-space change for a currently quarantined adapter | `85F4.1` is a plausible display reason if this path becomes reachable. Current denial is reachability evidence, not a reason exemption. |
| `SettingsPublication.fstatfs` | `f_flags & MNT_LOCAL` only | Reject non-local settings storage | Apple lists `fstatfs` under disk space, but none of the current disk-space reasons describes filesystem-locality validation. Unresolved. |
| `GuardedFileDeleter.fstatfs/fgetattrlist` | local flag, filesystem ID, mount path, `ATTR_VOL_UUID` | Bind a reviewed filesystem target to one local volume and reject mounted aliases | `fgetattrlist` appears in both Apple's file-timestamp and disk-space API lists, although this call requests only volume UUID. No listed reason describes volume-identity safety. Unresolved. |
| `ResourcePreflight.fstatfs/fgetattrlist` | local flag and `ATTR_VOL_UUID` | Capture and recheck an exact local reviewed resource | Same unresolved volume-identity use. The target is not thereby an app container or user-granted document. |
| `SettingsPublication` `fstat/fstatat` | device, inode, mode, owner, link count, size | Protect settings publication and detect replacement in `~/Library/Application Support/Tidy` | `C617.1` is only a candidate. Empty entitlements and an unsandboxed support path do not demonstrate Apple's formal container condition. |
| `JournalStorage`, `JournalPOSIXIO`, `MutationAdmissionStore` `fstat/fstatat` | device, inode, mode, owner, link count, size, modification time | Protect mandatory recovery, staging, and admission records below the same support directory | Same `C617.1` candidate, not demonstrated eligibility. Mandatory persistence does not justify inventing a reason. |
| `OptionalRunHistory` `fstat/fstatat` | type, owner, link count, size, device, inode | Bound and safely replace/remove optional run history below the support directory | Same `C617.1` candidate, not demonstrated eligibility. |
| `ScanIndex` `lstat` | type, owner, mode, link count | Protect the app-owned SQLite index family below the support directory | Same `C617.1` candidate, not demonstrated eligibility. |
| `BoundedTraversal` `lstat/fstat/fstatat` | device, inode, generation, type/mode, link count, allocated blocks, size, modification and change timestamps | Bound read-only traversal, detect churn/cross-volume nodes, calculate allocated bytes, and apply age filters | Scope varies. Default quick roots are implicit home subpaths. Selected-project roots come from persisted `gitRoots`, without an OS document picker or security-scoped grant. Full-home uses an in-app one-run consent token. None currently demonstrates `C617.1` or Apple's `3B52.1` user-grant condition. |
| `StaleNodeModulesScanner` timestamp keys | directory flag and content modification date | Age-filter `node_modules` beneath configured project roots | No OS picker/security-scoped grant is wired. `3B52.1` remains unproven. The bounded production traversal above is the current scan path, but compiled source still requires inventory. |
| `TranscriptPruneScanner` timestamp keys | directory flag and content modification date | Age-filter transcript files beneath a supplied Claude projects directory | The catalog derives this from the home directory; there is no demonstrated specific user grant. No current reason is asserted. |
| `ProcessIdentity.fstat/lstat` | executable device, inode, and file type | Bind a process instance to the executable currently at its absolute path | Installed/user executable paths are neither the app container nor specifically granted through a documented picker. No current reason is asserted. |
| `GuardedFileDeleter` `fstat/fstatat` | device, inode, generation, type/mode, link count, apparent/allocated size, modification/change timestamps | Seal and recheck reviewed leaves and ancestors before any effect | Current registry denial keeps mutations unavailable. Implicit home roots and ancestor metadata still lack a demonstrated file-timestamp reason. |
| `ResourcePreflight` `fstat/fstatat` | ancestor and leaf device/inode/generation/mode; leaf size and modification time | Capture exact review-time identity and detect replacement | Same unresolved external-root/ancestor classification. |
| `ScanInvalidation.stat` | root device ID | Bind FSEvents state to a volume incarnation | Inherits the scan root's unresolved grant classification. |
| `AppExecutionServices`, `ScanScopeAuthority`, and `SettingsImportFileReader`: `ProcessInfo.systemUptime` | monotonic elapsed time | Epoch live scheduler observations, expire one-run scan consent, and bound import reads between syscalls | `35F9.1` covers elapsed-time/timer calculations and is declared. |
| `SettingsImportFileReader` `fstat` | file type and size only | Reject special files and oversized payloads selected through the settings file importer | `3B52.1` is a candidate for this specifically selected file; the manifest does not declare it. This row does not establish a reason for unrelated metadata accesses or change the existing unresolved category gate. |
| `SystemMonitor`: `kern.boottime` | boot timestamp identity | Reject page-out deltas that cross a reboot | The current Apple accessed-API catalogue does not name this sysctl string. It remains a separate privacy/platform review row; `35F9.1` is not stretched to claim this identity use. |
| `ProcessIdentity`: `kern.bootsessionuuid` | boot-session UUID | Prevent process-instance evidence from transferring across boots | Also not named in the current Apple accessed-API catalogue; retained as a separate sensitive identity review row. |
| Dedicated runtime-verification target: `RuntimeTestComposition.lstat` | fixture-root type, owner UID, and mode | Before test-only cleanup, require the exact owned mode-0700 disposable `/tmp` root; production services then use the same APIs against its synthetic home/state subtree | Apple lists `lstat` in file timestamps even though this call reads no timestamp. The guarded temporary root is neither a demonstrated Apple container nor a user-granted document, so no current reason is asserted. The target has no code-signing entitlements, skips installation, and must remain absent from distributed artifacts. |
| Dedicated runtime-verification target: `RuntimeObservationCoordinator.lstat/fstat` | Root/state/staging file type, owner, mode, link count and size | Validate owned synthetic observation storage and atomically publish fixed ready/final state records | Guarded test-only storage validation; no reason is asserted for temporary roots. This code and its measurement controls must remain absent from the normal distributed artifact. |

| Dedicated runtime-verification target: `RuntimePerformanceComposition.lstat/fstat` | Root/state/proceed-token type, owner, mode and size; fixture entry type, owner, link count, logical size and allocated blocks | Validate the owned observer handshake and fixed 50k synthetic fixture, measure its composition, and publish bounded result documents | Test-only storage and fixture measurements; no new reason is asserted. This code must remain absent from the distributed artifact. |
| Dedicated runtime-verification target: `RuntimeTestComposition.statfs` | Available blocks and block size | Refuse performance fixture setup unless at least 2 GiB is available on its temporary volume | Test-only sufficient-write-space guard; no new manifest reason is asserted by this source refresh. The test target remains excluded from distribution. |

| `DiagnosticExportWriter` `fstat/fstatat` and extended-ACL inspection | Device/inode, owner, mode, link count, size, and ACL grant/deny tags; no timestamp fields are consumed | Validate the selected output parent, private staging inode and atomic create-only publication; parent ACL grants are rejected and staging ACLs are cleared before payload writes | The source uses an explicit save-panel destination and exports only metadata. No new manifest reason is asserted for parent/staging safety checks; privacy-purpose classification and GUI delivery remain separate gates. ACL entries are never serialized. |

## Direct source inventory

The scanner reports direct tokens from Swift, C, Objective-C, and Objective-C++ files in the app and core source roots, including conditionally compiled runtime-host source. It intentionally does not infer private framework implementation from ordinary `FileManager` methods. Generic `fgetattrlist` is reported in both categories because Apple lists it in both. `kern.boottime` and `kern.bootsessionuuid` are separate review rows because Apple's current required-reason list names neither.

| Source | Direct API category | Matched tokens and lines |
|---|---|---|
| `Tidy/Assistance/AssistanceModel.swift` | File timestamp | `fstat`@574,585,608 |
| `Tidy/Assistance/AssistanceModel.swift` | Disk space | `fstatfs`@574,585 |
| `Tidy/Budgets/NotificationBroker.swift` | File timestamp | `fstat`@231,300,313,338; `fstatat`@317 |
| `Tidy/Budgets/NotificationBroker.swift` | Disk space | `fstatfs`@300,313 |
| `Tidy/Developer/DeveloperWorkspaceModel.swift` | File timestamp | `fgetattrlist`@495; `fstat`@431,442,458; `fstatat`@450,465 |
| `Tidy/Developer/DeveloperWorkspaceModel.swift` | Disk space | `fgetattrlist`@495; `fstatfs`@461 |
| `Tidy/Execution/AppExecutionServices.swift` | System boot time | `ProcessInfo.systemUptime`@715 |
| `Tidy/RuntimeVerification/RuntimeObservationCoordinator.swift` | File timestamp | `fstat`@410,437; `lstat`@388 |
| `Tidy/RuntimeVerification/RuntimePerformanceComposition.swift` | File timestamp | `fstat`@655; `lstat`@279,546,630 |
| `Tidy/RuntimeVerification/RuntimeTestComposition.swift` | File timestamp | `lstat`@155 |
| `Tidy/RuntimeVerification/RuntimeTestComposition.swift` | Disk space | `statfs`@272 |
| `Tidy/Settings/SettingsView.swift` | File timestamp | `fstat`@465 |
| `Tidy/Settings/SettingsView.swift` | System boot time | `ProcessInfo.systemUptime`@469,474 |
| `TidyCore/Sources/TidyCore/Assistance/LocalAuthorityStore.swift` | File timestamp | `fstat`@57,98,668; `fstatat`@138,768,782 |
| `TidyCore/Sources/TidyCore/Assistance/LocalAuthorityStore.swift` | Disk space | `fstatfs`@57,98,141,657,780 |
| `TidyCore/Sources/TidyCore/Detect/StaleNodeModulesScanner.swift` | File timestamp | `URLResourceKey.contentModificationDateKey`@25,37; `URLResourceValues.contentModificationDate`@46 |
| `TidyCore/Sources/TidyCore/Detect/TranscriptPruneScanner.swift` | File timestamp | `URLResourceKey.contentModificationDateKey`@16,24; `URLResourceValues.contentModificationDate`@35 |
| `TidyCore/Sources/TidyCore/Exec/ProcessIdentity.swift` | File timestamp | `fstat`@45; `lstat`@45 |
| `TidyCore/Sources/TidyCore/Exec/ProcessIdentity.swift` | Boot identity (not in current Apple required-reason list) | `kern.bootsessionuuid`@31 |
| `TidyCore/Sources/TidyCore/Execution/DerivedDataEffectAdapter.swift` | Disk space | `fstatfs`@228 |
| `TidyCore/Sources/TidyCore/Execution/GuardedFileDeleter.swift` | File timestamp | `fgetattrlist`@200; `fstat`@176; `fstatat`@176 |
| `TidyCore/Sources/TidyCore/Execution/GuardedFileDeleter.swift` | Disk space | `fgetattrlist`@200; `fstatfs`@182 |
| `TidyCore/Sources/TidyCore/Execution/JournalPOSIXIO.swift` | File timestamp | `fstatat`@47 |
| `TidyCore/Sources/TidyCore/Execution/JournalStorage.swift` | File timestamp | `fstat`@81,153,158,181,197; `fstatat`@180 |
| `TidyCore/Sources/TidyCore/Execution/MutationAdmissionStore.swift` | File timestamp | `fstat`@206,212,219; `fstatat`@211 |
| `TidyCore/Sources/TidyCore/Execution/ResourcePreflight.swift` | File timestamp | `fgetattrlist`@180; `fstat`@142,151,166; `fstatat`@157,188 |
| `TidyCore/Sources/TidyCore/Execution/ResourcePreflight.swift` | Disk space | `fgetattrlist`@180; `fstatfs`@167 |
| `TidyCore/Sources/TidyCore/Execution/ReviewedManifestStore.swift` | File timestamp | `fstat`@335,403,536,590,624; `fstatat`@371,628 |
| `TidyCore/Sources/TidyCore/Integrations/GitStorageAdapter.swift` | File timestamp | `lstat`@22 |
| `TidyCore/Sources/TidyCore/Integrations/LocalEndpointGuard.swift` | File timestamp | `lstat`@30 |
| `TidyCore/Sources/TidyCore/Integrations/ToolAdapter.swift` | File timestamp | `fstat`@511; `fstatat`@557 |
| `TidyCore/Sources/TidyCore/Measure/DiskStats.swift` | Disk space | `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`@31,47,56; `URLResourceKey.volumeAvailableCapacityKey`@30,45,53; `URLResourceKey.volumeTotalCapacityKey`@29,44,51 |
| `TidyCore/Sources/TidyCore/Monitoring/SystemMonitor.swift` | Boot identity (not in current Apple required-reason list) | `kern.boottime`@32,34 |
| `TidyCore/Sources/TidyCore/Policy/DiagnosticExport.swift` | File timestamp | `fstat`@141,203,223,312; `fstatat`@233,266,342 |
| `TidyCore/Sources/TidyCore/Policy/OptionalRunHistory.swift` | File timestamp | `fstat`@124,138; `fstatat`@175 |
| `TidyCore/Sources/TidyCore/Policy/SettingsPublication.swift` | File timestamp | `fstat`@75,109,144; `fstatat`@134,415 |
| `TidyCore/Sources/TidyCore/Policy/SettingsPublication.swift` | Disk space | `fstatfs`@69 |
| `TidyCore/Sources/TidyCore/Projects/ProjectInventory.swift` | File timestamp | `fstat`@374,428,597,619,693; `fstatat`@411,561 |
| `TidyCore/Sources/TidyCore/Rescue/WorkloadIdentity.swift` | File timestamp | `fstat`@106 |
| `TidyCore/Sources/TidyCore/Rescue/WorkloadIdentity.swift` | Disk space | `fstatfs`@106 |
| `TidyCore/Sources/TidyCore/Scanning/BoundedTraversal.swift` | File timestamp | `fstat`@1251,1291,1362; `fstatat`@1348; `lstat`@1232,1259 |
| `TidyCore/Sources/TidyCore/Scanning/ScanIndex.swift` | File timestamp | `lstat`@213,228 |
| `TidyCore/Sources/TidyCore/Scanning/ScanInvalidation.swift` | File timestamp | `stat`@335 |
| `TidyCore/Sources/TidyCore/Scanning/ScanScope.swift` | System boot time | `ProcessInfo.systemUptime`@201 |

## Reproduction and limits

```bash
python3 scripts/verification/privacy-api-inventory.py --self-test
python3 scripts/verification/privacy-api-inventory.py --check-document docs/verification/privacy-api-inventory.md
python3 scripts/verification/privacy-api-inventory.py
```

The self-test covers all 35 scanner patterns, including Apple-listed `getattrlistat` and `getattrlistbulk` plus the two separate sysctl identity rows, and rejects false matches from Swift `stat()`/`statfs()` struct initialization. The inventory is lexical source evidence. It does not prove reachability, runtime calls, permissions, traffic, packaged resource inclusion, signature state, App Store or external-distribution acceptance, or that a reason applies. Re-run after source freeze and compare the generated table before packaging.
