# R08/R12 resumed settings migration and diagnostic privacy verification

Date: 2026-09-19

Status: the independent settings-fixture and diagnostic-candidate test rows are implemented and
focused verification is green. Production diagnostic export remains unavailable and is not claimed
by this checkpoint.

## Persisted settings shapes and provenance

The repository has two release tags. `v0.1.0` (`6301304`) used schema 1 without the later
application/restart compatibility fields; `v1.5.0` (`224461c`) used schema 1 with
`appsApprovedForQuit` and `allowRestartToReclaimSwap`. The existing `v1-original.json` and
`v1-memory.json` fixtures exercise those two released schema-1 grammars with deterministic
non-personal values.

Schema 2 was introduced after those tags. No repository tag contains its persistence commits, so
the new v2 files are labeled supported historical shapes rather than released builds:

- `v2-base.json` covers the config-only envelope introduced by the T05 migration/publication work
  (`aa956b0`, `ab991f7`).
- `v2-preferences.json` covers the typed-preferences envelope introduced by `853127b`.
- `v2-inert.json` covers the preferences plus inert-import grammar.
- `v2-active.json` covers the complete active-profile plus inert-import grammar introduced by
  `1d772e8`.

Each v2 fixture loads at revision 7 without rewriting its bytes or creating a backup. The test also
retains an independent authority witness and a real mandatory mutation-admission ledger containing
an unresolved `PendingEffectIntent`. The ledger bytes remain identical and admission remains
`uncertainAndPossiblyRunning`.

`v3-future-envelope.json` is a constructed downgrade fixture, not a released shape. Together with
the existing corrupt and schema-999 fixtures, it proves unsupported/corrupt data enters read-only
recovery, rejects edits and rollback, preserves exact settings bytes, creates no backup, leaves the
authority witness unchanged, and leaves the real unresolved mandatory ledger unchanged and
blocking.

The import/reset fixture begins from the complete v2 shape. A hostile authority row remains
rejected, one portable preference commits, selective reset removes only that preference, active
profile and inert state remain intact, and the independent authority plus real mandatory-recovery
witnesses remain byte-identical. This establishes SettingsStore noninterference; it does not invent
or validate the deferred T22 local-authority ledger.

## Diagnostic artifact scope

`DiagnosticExportRenderer` still has no app caller. `export.redactDiagnostics` remains visibly
unavailable, and the Settings `FileDocument` portal exports portable settings rather than
diagnostics. No production writer, save-panel flow, temporary-file recovery, symlink boundary, or
backup lifecycle was added here.

The privacy regression now materializes the renderer's exact primary, temporary, and backup
candidate bytes as three regular files inside a disposable mode-0700 directory, changes each file to
mode 0600, reads the disk bytes back, and checks exact candidate equality. With cosmetic redaction
disabled, every disk file excludes seeded credentials, cookies, environment values, argv, remotes,
personal path identity, a settings value, and a profile name. This closes the R08/R12 forbidden
sentinel test requirement for the current pure renderer. It is source/test evidence only and does
not close production diagnostic export or R13/R14 privacy and distribution acceptance.

## TDD and focused evidence

The RED run used:

```text
swift test --package-path TidyCore --scratch-path /tmp/tidy-r08-resume-build \
  --jobs 2 --no-parallel --filter 'SettingsMigrationTests|DiagnosticPrivacyTests'
```

It failed with six expected issues because the four supported v2 resources and the v3 future
resource did not exist. Existing diagnostic tests and unrelated migration/publication cases stayed
green.

After adding the fixture resources, the same command passed 52 tests across three suites in 5.016
seconds. The recovery witness was then strengthened to use the real mandatory admission store. The
fresh broader command was:

```text
swift test --package-path TidyCore --scratch-path /tmp/tidy-r08-resume-build \
  --jobs 2 --no-parallel \
  --filter 'SettingsMigrationTests|DiagnosticPrivacyTests|SettingsProfilePersistenceTests|SettingsTransferTests|SettingsWorkflowTests'
```

Result: 111 tests across six suites passed in 54.479 seconds. The build emitted only pre-existing
warnings in unrelated test files. `jq empty` accepted all five new JSON resources, and
`git diff --check` passed for the working tree at review time.

The previously recorded complete branch baseline remains Core690 plus isolated1, model137,
native2, and universal Release. This focused pass does not replace that aggregate and no full
aggregate was run in this independent stream. Registry mutations remain denied; no monitor, scan,
engine, authority, app-service, app UI, project, CI, packaging, acceptance, or shared progress file
was changed by this work.
