# A2P release-signal publication validation

Date: 2026-09-19

## Finding and correction

The retained failed Core run at
`/private/tmp/tidy-t05-a2p-A285256F-94E3-4980-AE85-CB5A7C043415` showed the
strict driver exit `126` while waiting for `resume`; the same final pathname was
later a valid one-byte mode-0600 file. `A2PRun.release` had created the final name
with `O_CREAT | O_EXCL` before writing byte `82`, so the driver could correctly
reject the transient zero-byte file. This was a test-harness publication race; no
production defect was found.

The harness now opens and validates the owned mode-0700 control directory, writes
the complete byte into a UUID-named sibling staging file, forces and validates
mode `0600`, validates owner/type/size, and closes the descriptor before publishing
with `renameatx_np(..., RENAME_EXCL)`. Publication cannot replace an existing
signal. Failure cleanup targets only the helper's UUID-named staging file. The
driver's strict size, mode, byte, deadline, exit, and zero-signal checks are
unchanged.

## Verification

- Focused no-replace case: **1 test passed**. It verifies the complete byte and
  mode, rejects a second publication, preserves the original inode and bytes, and
  leaves no staging name.
- Previously failing writer-contention method: passed in **5 separate test
  processes**, with both `bootstrap-hold` and `stable-hold` passing in every run
  (**10 argument executions**). Logs:
  `/tmp/tidy-a2p-release-contention-01.log` through
  `/tmp/tidy-a2p-release-contention-05.log`.
- Complete `SettingsProcessAcceptanceTests`: **4 tests, 9 argument executions,
  0 failures** in 25.045 seconds. Every recorded child reap retained zero signal
  attempts; the accepted abrupt exits remained 80 through 85.
- Independent final diff review found the anchored staging and exclusive rename
  correction clean and found no weakened reader or production behavior.

The new focused case raises the complete Core test floor from 700 to **701** and
must be required by the final verifier under the name
`releaseSignalPublicationIsAtomicAndNoReplace`. No production source changed;
the final aggregate rerun remains a separate controller gate.
