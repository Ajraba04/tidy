# Native UI observation

Date2026-09-17, audit observation window approximately15:29–15:44UTC. Platform/tools same as baseline; CUA native AX/screenshot tooling, no new permission grants. Tool-call screenshots remain in the conversation; this directory contains the written observation record, not exported screenshot files. Human VoiceOver/screen-reader evidence was not collected.

## Safe fixture host

Built exact-baseline TidyUITestHost using external DerivedData, signing disabled; `fixture-host-build.*` records exit0. Inspected source `TidyUITestHost/TestHostApp.swift` before launch: synthetic review data, no discovery/settings persistence/cleanup, nil/no-op callbacks. This is an existing separate app fixture; all actions intentionally unavailable regardless of real core allowlist.

CUA `getApp` path `/private/tmp/tidy-audit-9e1a500-fixture-ui/Build/Products/Debug/TidyUITestHost.app` launched successfully and supplied AX state:

- Window620×620, Safe58rows,0selected,0bytes; Clean Now disabled; disabled checkboxes include explicit unavailable/blocked/no-work reasons and DerivedData rebuild consequence.
- Cmd-End moved the list; screenshot showed populated content and a disabled Clean Now. Setting AX scrollbar value1 also retained populated content. The historical blank-list issue was **not reproduced conclusively** in this limited sequence. Endpoint AX values differed from value-indicator values; no root-cause claim.
- Settings click reported a CUA timeout, but a subsequent screenshot confirmed Settings had opened with profilesEmpty,0submissions, light presentation,620width/default text size. Effective/default/source descriptions visible. Long settings content extends beyond compact viewport. No native compact-width/text-scaling/two-window/focus/VoiceOver acceptance claimed.
- AX calls intermittently took16–34s and one click timed out. This is an automation observation; it does not prove app-main-thread blocking or a product hang.

## Production app with storage injection

To make production UI checks safe, detached worktree changes only `resolveProductionPaths()` to exclusively created `/private/tmp/tidy-audit-9e1a500-ui-home/{home,support}`; build overrides bundleID to `io.github.ajraba04.Tidy.AuditFixture`. Patch saved as `production-ui-injection.patch`. Primary production source is unchanged. Scratch Documents has a witness; no destructive UI action was requested.

Build passed (`production-fixture-build.*`). CUA opening by exact path timed out; one discriminating retry by unique bundleID also timed out. Process launch was observed, but usable AX/menu state was not obtained, so **production UI journeys are Blocked by this automation failure**, not passed or inferred from model tests. No repeated speculative retry or permission/signing changes. The fixture witness remained exact expected bytes, SHA256 `5b6a5be308513a69188dc9dd4c3e2f10e35b201851cc549cb680d25e49086e8d`.

Closure: use an accessible synthetic production UI host preserving authorization logic, capture all first-launch/scan/Headroom/settings/review/error/two-window states; diagnose menu-bar-only CUA access separately. Run native keyboard and human VoiceOver on supported stable OS, including historical endpoint navigation, long paths, mixed/disabled selections and loss of focus. Model119green and safe-denied fixture screenshots cannot close this gate.
