# T03.A guarded filesystem foundation evidence

Scope: internal anchored filesystem mechanisms, in-memory manifest validation, scratch-only primitive effects and additive report compatibility. This is not accepted production cleanup, full T03 completion or low-spec performance acceptance.

Source base: `cefbbae`; implementation worktree `/private/tmp/tidy-headroom.wUbV9h`, branch `CAJ/developer-headroom`. The intervening `5f5722a` checkpoint contains unrelated reviewed settings documentation, not filesystem source.

## Implemented boundary

- Internal `DirectoryAnchor` retains root and ancestor descriptors; raw symlink components and unsafe relative components are refused. Volume UUID comes from the retained descriptor, with device/fsid/mount metadata comparisons. Metadata mount paths are never reopened as authority.
- Captured manifests retain original snapshots, exclusions and batches. Canonical binary SHA-256 validation re-encodes these values, checks actual batch sizes/counts and compares both stored and expected digest. Batch ceilings are 5,000 nodes and 8 MiB; callers can only lower them.
- The internal primitive performs one descriptor-relative unlink after checks. It is called only by its disposable-fixture tests. The production engine remains unconditional denial; no accepted adapter or coordinator filesystem facade was introduced.
- Typed outcomes distinguish partial, failed, skipped, cancelled and uncertain. Removed metadata is not proven physical reclaim. Unknown and overflow remain unavailable; signed volume observations are separate.
- New report fields decode old records as unavailable. Required legacy memory decoding remains unchanged until T05 adds explicit availability. Generic report construction has neutral unavailable wording; optional actual tool exit data is not inferred from a success flag and cannot prove reclaim.

The check/unlink interval is not an atomic inode-conditional operation. Production use still requires the accepted producer exclusion and coordinator/recovery boundaries in T03.B.

## Implementer evidence

All focused package commands used `--jobs 2`; initial sandbox/cache failure was followed by approved access and is not behavioral RED.

| Check | Evidence |
|---|---|
| Missing API | Expected compilation failures for the absent proposed interfaces; no behavior claim. |
| Initial behavioral RED | 18 tests / 26 issues with interface stubs, followed by 18 / 24 issues with actual anchors/manifests and not-yet-implemented primitive/scheduling behavior. |
| Initial supplied GREEN | 18/18 tests passed; real scratch removals, preserved exclusions/new children/hardlinks and sentinels. |
| Directory accounting regression | 22 tests / one issue: old directory size 96 was reported instead of the immediately-before-removal size 64. Outcomes now use the final checked snapshot. |
| Shared ancestor churn | Two intermittent fail-closed test failures were traced to unchanged ancestor identity with changing sibling-driven size/link/time metadata. Acquisition now compares ancestor identity while retaining full selected-root/leaf checks; diagnostics removed, parallel tests retained. |
| Historical memory/report regressions | Missing old memory unexpectedly decoded as zero; generic report text inferred tool exit from a legacy Boolean. Genuine focused failures preceded required decoding restoration and the explicit optional exit-data boundary. |
| Final focused GREEN | `swift test --jobs 2 --filter GuardedDeletionTests`: exit 0, 25 tests / one suite, 0.016 seconds. |
| History compatibility | `swift test --jobs 2 --filter RunLogTests`: exit 0, three tests / one suite, 0.003 seconds. |
| Public API visibility | Ordinary imported-module client cannot access the anchor/primitive. Public observation and matching `@testable` control clients typecheck, proving visibility rather than a missing module. |

Component-order prefix coverage (`a`, `a/leaf`, `a-`) passed the existing correct comparator on its first run; it is not claimed as reproduced RED. Constructed tool exit values and scheduling inputs are value-semantic tests, not actual tool or mutation integration evidence.

## Controller final verification

Source writes were paused before the following checks. No other package/build job ran concurrently.

- Host-effect audit: all new deletion tests operate only inside generated UUID temporary roots. Each fixture verifies an outside-of-selection sentinel before cleanup. No home cache, permissions, mounts, daemon, application quit or user workload fixture was added.
- Caller scan across `TidyCore/Sources` and `Tidy` found only the internal primitive declaration, no production caller of it, `DirectoryAnchor.open` or `ReviewedTree.capture`. The raw CleanEngine denial remains unchanged.
- Full package: from `TidyCore`, `swift test --jobs 2`; approved cache access, exit 0, **229 tests / 39 suites passed**, 17.572 seconds test duration. No observed compiler warnings. Duration is not a performance benchmark.
- Production app: `xcodebuild -quiet -project Tidy.xcodeproj -scheme Tidy -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/tidy-headroom-build -jobs 2 build CODE_SIGNING_ALLOWED=NO`; exit 0, no output. No launch or signing change.
- `git diff --check` passed. Core/app source contains no temporary diagnostic prints. App-model/manual-host tests were not rerun for this core mechanism/report change; prior evidence is not relabeled as current.

Independent source/spec review of `cefbbae..149c44e` found one Important structural-validation gap: a correctly hashed manifest could contain a malformed or inconsistent ancestor chain because canonical rehashing did not fully validate parent-directory types and relationships. This is an internal malformed-value acceptance defect, not a demonstrated production authority bypass. Independent re-review approved the correction through `ec9dbc5`: spec compliant and quality approved for T03.A only, with no remaining Critical, Important or Minor findings. Full T03 and production integration remain subject to the gates below.

### Correctly hashed malformed-structure follow-up

- Tests use the existing value serializer, now internal rather than private, to rebuild exact batch sizes and hashes. A valid captured-tree control proves the rebuilt digest equals the original. No malformed value is executed; the serializer adds no public API or authority.
- Genuine behavioral RED before the validator fix: `swift test --jobs 2 --filter GuardedDeletionTests`; exit 1, 29 tests / one suite, 18 issues. Eight header ancestor positions, eight nested type/device/inode/metadata cases and two missing-parent cases were incorrectly accepted with matching hashes. Initial runner sandbox failure was environmental, not RED.
- Header ancestors now must be directories. An O(depth) active directory-prefix stack spans batches and requires each nested parent to match the complete previously reviewed directory snapshot on the selected device. Legitimate header volume transitions remain permitted. The canonical format is unchanged.
- Covering GREEN: same focused command, exit 0, **29 tests / one suite**, 0.032 seconds. Failed assertions bind a Boolean locally to avoid dumping complete trees; the first RED's verbose diagnostics were not retained as application output.
- Controller post-fix full suite: `swift test --jobs 2`, exit 0, **233 tests / 39 suites**, 10.917 seconds. Controller post-fix unsigned arm64 production build: the exact command above, exit 0, no output. No launch or additional app-model/native tests.
- `git diff --check` passed. Added validation does not change the primitive, production caller boundary, total-capture limitations or physical acceptance gates.

## Remaining acceptance

- Before any production capture caller, bound total capture memory, recursion/depth, descriptors and cancellation. The current in-memory tree retains all batches and repeated ancestor arrays and sorts a directory's names; per-batch limits do not bound the whole capture. Persisted streaming and scheduler integration are required before production use.
- Accepted adapter ownership/exclusion, original manifest storage/binding, actual coordinator dispatch, per-leaf policy/cancellation/caps and durable outcomes/reconciliation.
- The card's mount/permission/clone/inode-reuse/fault/FD-leak cases, plus real tool result integration and full historical UI migration.
- Physical 8 GiB Intel/Apple Silicon, macOS 14 and supported stable-OS behavior/performance. Current host is a developer OS/toolchain, not the full acceptance matrix.

No capability registry entry, production mutation authority, remote state or user data was changed. Detailed chronological evidence is in `.superpowers/sdd/T03.A-report.md`.
