# T01.B verification checkpoint

Date: 2026-08-26. Source base: `f3d4e47`. Implementation is confined to the `CAJ/developer-headroom` worktree. This is a foundation checkpoint, not complete T01/T05 or release acceptance.

## Automated and build evidence

- Core compile RED: missing review/selection types. The old-filter behavioral failure was subsequently reproduced after initial implementation, then restored GREEN; it is postimplementation regression evidence, not claimed preimplementation TDD.
- Additional tombstone regression captured RED with the retained Xcode requirement and GREEN after removing it. The permanent erase-all explanation now does not depend on Xcode being installed.
- Controller final `swift test --jobs 2`: exit 0, **175 tests / 37 suites passed**, 43.358 seconds, arm64e-apple-macos14.0 target. Build took 11.60 seconds. The zero-test XCTest preamble is separate from the successful Swift Testing run.
- Implementer final unsigned Debug builds of `TidyUITestHost` and `Tidy`: both exit 0, arm64, jobs2, `/private/tmp/tidy-headroom-build`, no warning output on these final incremental builds. The earlier baseline Xcode scheme warning remains recorded in the program ledger; these runs do not erase that history.
- Controller `git diff --check`: exit 0.

## Fixture isolation

The controller inspected all catalog metadata factories, model/selection constructors and the shared views before launch. They only construct data/closures on this host path; no locate/discover/declaredRoot callback, environment initialization, settings access, engine, process runner or IPC is invoked. All fixture rows are unavailable/no-work/blocked, targets are empty, and presentation callbacks are explicit no-ops. CapabilityRegistry is unchanged.

The generated host target `18AA2F4D435F7DEE91E3E1E8`, Sources phase `CA847ACE26E62B9FBB1CC0BF`, has exactly these app sources: TestHostApp, CleanPlanView, PlanReviewRow, PlanSelectionModel and CustomPlanView. It has no resource phase or target dependency and only the local TidyCore package dependency. The production Sources phase `97738F4C6C5F983A079A2BEE` excludes TestHostApp; production resources contain only its asset catalog. Production source and bundle scans, including Tidy.debug.dylib, found no fixture marker/type or dispatch flag.

Only `/private/tmp/tidy-headroom-build/Build/Products/Debug/TidyUITestHost.app` was launched, using the Computer Use skill. Normal Tidy was not launched. No real cleanup, settings change, restart, app quitting request or home scan was performed by this fixture. Normal OS/framework window machinery is not a claim of zero OS I/O.

## Native observations

Host: 8 GiB arm64 Mac, macOS 27 developer build 26A5406e. Inspection used the actual shared SwiftUI components at the observed 680×760 window size.

| Surface | Observed result |
|---|---|
| Safe | 58 distinct catalog row titles observed in accumulated AX snapshots, matching its 58-row header. Scrolled to the final Flutter row. Missing path, protected path, missing tool and targetless npm action all remain visible with exact reasons. |
| Normal | 72 distinct catalog titles observed across snapshots, matching its header. Browser, Xcode, Git and project sections reached. Warning/cost text remained readable. |
| Deep | 97 distinct catalog titles observed across the scroll sequence, matching its header and reviewed catalog families. Permanent erase-all reason retained; zero-byte memory actions show danger and cost notes; restart copy makes no guaranteed reclaim claim. |
| Custom | 98-row header (97 catalog rows plus Other fixture). Real category headings and Other row rendered. Other's danger and cost notes both visible. |
| Presets | Expanded immutable input disclosure shows `deep.memory.purge-inactive`, `deep.simulator.erase-all`, `safe.tool.npm-cache-clean`, `unknown.preset.id`. Three clicks on the preset leave zero selected/zero bytes and preserve all four input IDs. |
| Disabled controls | Representative checkbox clicks and Return on standard surfaces do not select rows or open confirmation. Custom save/clean mouse attempts, Tab and Return leave zero selected and no sheet/dialog. AX snapshots after focus expose disabled checkbox titles/reason hints and disabled footer buttons. This is a limited native check, not a full accessibility audit. |

The first screenshots exposed excessively faded row titles: disabling the whole Toggle also styled its label subtree. The shared row now keeps its explanatory content outside the disabled checkbox. Postbuild screenshots verified normal native text contrast while controls remain disabled. Final PlanReviewRow SHA-256: `0deed5794094e498e9f22bd58395fef050fb9e3db033e09fa493c1f1636f8a0f`.

Key local screenshots (CUA temporary artifacts; may expire):

- [Corrected Safe titles](</private/var/folders/jj/_xfw89rd22xdj75hnf0hhd900000gp/T/com.openai.sky.CUAService/TidyUITestHost Screenshot 2026-08-26 at 1.43.43 PM.jpeg>)
- [Permanent simulator restriction](</private/var/folders/jj/_xfw89rd22xdj75hnf0hhd900000gp/T/com.openai.sky.CUAService/TidyUITestHost Screenshot 2026-08-26 at 1.49.10 PM.jpeg>)
- [Deep memory warnings](</private/var/folders/jj/_xfw89rd22xdj75hnf0hhd900000gp/T/com.openai.sky.CUAService/TidyUITestHost Screenshot 2026-08-26 at 1.49.28 PM.jpeg>)
- [Preset input after repeated clicks](</private/var/folders/jj/_xfw89rd22xdj75hnf0hhd900000gp/T/com.openai.sky.CUAService/TidyUITestHost Screenshot 2026-08-26 at 1.50.29 PM.jpeg>)
- [Custom Other and memory](</private/var/folders/jj/_xfw89rd22xdj75hnf0hhd900000gp/T/com.openai.sky.CUAService/TidyUITestHost Screenshot 2026-08-26 at 1.51.59 PM.jpeg>)
- [Safe final rows](</private/var/folders/jj/_xfw89rd22xdj75hnf0hhd900000gp/T/com.openai.sky.CUAService/TidyUITestHost Screenshot 2026-08-26 at 1.53.01 PM.jpeg>)

## Remaining gates and tool limitations

- **Minimum-window-size verification remains open.** Corner and edge resize gestures did not change the observed window dimensions. No claim is made about 620-point/minimum layout. This outstanding manual requirement needs a working native resize path or a separately reviewed size fixture; it is not silently replaced by a build/source check.
- One native scroll call returned `noWindowsAvailable`; reinspection found the same window, and coordinate focus plus native scroll actions restored inspection. AX snapshots sometimes omitted labels until focus settled; labeled controls were subsequently observed. These transient tool observations are not asserted to be app defects or a pristine automated UI run.
- Quit was sent only to the fixture host after inspection. Positive selection/execution, real settings persistence/migration, outer production container lifetime, sealed coordinator/recovery, full T05 automation and physical Intel/macOS14/stable-OS acceptance remain open.
- Independent task-scoped spec/code-quality review is required before accepting this source checkpoint. Passing default-denied tests is not proof of useful cleanup.
