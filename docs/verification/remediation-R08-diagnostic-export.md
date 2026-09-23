# R08 diagnostic export — code-side implementation, 2026-09-20

Status: **implemented, source-reviewed, focused headless checks passed**. Native save-dialog
interaction is deferred at the user's request while they use the laptop. No GUI check
ran after that instruction. This is not full-program or release acceptance.

## Behavior

Settings → Experience now offers Export Diagnostics. It captures the acknowledged
saved settings, presents a save panel, and writes only after explicit confirmation.
Cancel performs no write. The export contains schema/revision/count metadata and the
existing immutable exclusion declaration, not logs, credentials, cookies, environment,
arguments, remotes, paths, setting values or profile names. Pending optimistic settings
edits are excluded. An unavailable redaction policy defaults to true.

The public Core writer accepts DiagnosticExportInput and invokes the renderer itself;
callers cannot pass arbitrary file bytes. The payload is bounded at 64 KiB. A selected
parent must be an owned directory opened without following its final symlink, with no
group/other write bits and no extended ACL grants. Deny-only ACLs are supported.
A unique staging file is created with mode0600, its inherited ACL is cleared before
payload writes, and file identity, link count, size and empty ACL are verified.

Publication uses atomic RENAME_EXCL: **existing destination nodes are never opened,
replaced, backed up or deleted**. Failure before publication cleans only the exact
owned staging inode when its identity can be established. A post-publication validation
or directory-sync failure reports uncertainty and leaves the output in place. A crash
may leave a private staging artifact; the writer never adopts or repairs unknown files.
Create-only output avoids introducing replacement, backup restoration or recovery-reset
authority. It does not change mandatory journals, cleanup admission or local consent.

The normal app performs the small writer operation off the main actor. User-facing
errors contain no selected path or payload. The cosmetic-redaction preference remains
unavailable: metadata-only export is implemented, but optional cosmetic fields are not.
The generated settings reference now says so explicitly rather than claiming all
diagnostic export is unavailable.

## Review and platform corrections

Astra High source review found an extended-ACL gap in the initial POSIX-mode-only design.
The final code rejects parent grants, clears new-file ACL inheritance and verifies
publication. The review accepted that correction and the final absence handling.

A live, disposable FD probe showed that macOS reports no extended ACL as NULL/ENOENT.
Apple's [acl_get_fd_np implementation](https://github.com/apple-oss-distributions/Libc/blob/main/posix1e/acl_file.c)
reads FILESEC_ACL; [filesec_get_property](https://github.com/apple-oss-distributions/Libc/blob/main/gen/filesec.c)
uses ENOENT when that property is absent. Only this result is accepted as empty, after
fstat confirms a linked object; all other retrieval errors remain failures.

Retained initial failures: the symlink-parent regression expected ELOOP while this
Darwin returned ENOTDIR; both valid rejection codes are now accepted with unchanged
witness assertions. Swift's C bridge required raw pointer/enum conversions. The first
ACL run rejected valid no-ACL files; the exact absence semantics above corrected it.
These failed logs remain alongside the final passing evidence.

## Headless verification

Evidence root: `dist/verification/diagnostic-export-20260920/` in this worktree.

- `core-verified.log`: **15 tests passed**, covering DiagnosticPrivacyTests and
  SettingsPresentationTests. This includes private bytes/mode for both flag states,
  preservation of regular/symlink/FIFO/directory/hard-linked destinations, symlink-parent
  rejection, pre-publication cleanup, post-publication uncertainty, actual ACL grant
  rejection, inherited-deny clearing and parent ACL preservation, plus generated
  settings-reference equality.
- `models-final.xcresult`: **2 passed**, no failures/skips. A deliberately stalled
  settings write changes displayed profile/redaction state; diagnostic output still
  uses the acknowledged revision/profile count/redaction. The other case verifies the
  safe fallback when acknowledged policy cannot resolve.
- `app-build.log`: normal Debug app **BUILD SUCCEEDED**. This compiles the save-panel
  integration without opening it. A final copy-only clarification of the uncertain-save
  message was syntax-parsed afterward; no behavior changed or extra UI run followed.
- Normal app compiled-fixture-marker exclusion, built privacy plist syntax, generated
  project membership, current-source privacy inventory, source-data gate and diff
  whitespace checks passed.

The two app-model checks passed before the final isolated ACL-absence correction; they
exercise the unchanged snapshot/renderer path. The final Core run and normal app build
include that correction. No fresh whole-suite pass is claimed. CI now requires the six
new writer cases and two model cases; floors are707 Core and146 models, derived from
unchanged baseline701/144 plus those additions, not a newly executed aggregate count.

## Deferred GUI work and remaining scope

When the laptop is available, use the compiled synthetic runtime host to check the
Experience export action, dialog cancellation, successful export to its owned fixture
root, and existing-file rejection with preserved settings/recovery witnesses. Rebuild
the fixture before launch; its last binary predates this new export integration.

The existing compact audit is also queued. Its latest run, which finished before the
user's deferral, confirmed auxiliary-window hiding, native-menu restoration and cleanup,
but failed on an unnamed Touch Bar element. No exclusion was added for that issue.

Actual save-panel behavior, supported-OS distribution, privacy-purpose classification,
full GUI/assistive-technology acceptance and release gates remain unverified. The older
inspected1782b4d packages predate this exporter and are historical, not current packages.
