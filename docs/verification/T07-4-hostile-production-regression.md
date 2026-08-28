# T07.4 hostile production regression verification

Date: 2026-08-28

## RED

`swift test --jobs 2 --filter HostileProductionRegressionTests` was first blocked before compilation by the host SwiftPM sandbox/cache (`sandbox_apply: Operation not permitted`, then shared-cache `databaseFull` / linker `errno=28`). Re-running the same command with worktree-local temp, module, cache, and scratch paths reached compilation and failed exactly as required:

```text
HostileProductionRegressionTests.swift:8:19: error: cannot find 'T074HostileHarness' in scope
HostileProductionRegressionTests.swift:11:19: error: cannot find 'T074HostileHarness' in scope
```

## Test-only fixture corrections

The complete embedded harness exposed two genuine compilation/fixture defects without changing acceptance coverage:

1. Swift rejects `try` on the right of `&&` inside `#expect`; each compound assertion was split into the same two assertions.
2. `JSONEncoder.sortedKeys` does not sort the elements of `Set<String>` inside presets. The deterministic full-config snapshot now normalizes every preset `itemIDs` array before sorted-key JSON encoding. Exact `TidyConfig` equality remains separately asserted.

No production source was edited and no assertion was removed or weakened.

## GREEN evidence

Working directory for every Swift command was `/private/tmp/tidy-headroom.r1yE0o/TidyCore`. Because the shared SwiftPM cache was full/corrupt, every successful compile/test invocation used this exact command prefix:

```bash
TMPDIR="$PWD/.build-local/tmp" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build-local/module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build-local/module-cache" \
swift test --cache-path "$PWD/.build-local/cache" \
  --scratch-path "$PWD/.build-local/scratch" --jobs 2
```

Exact suffixes and exit statuses:

- `--filter HostileProductionRegressionTests`: exit 0, PASS, 2 tests.
- `--filter SettingsProfilePersistenceTests`: exit 0, PASS, 25 tests.
- `--filter ConfirmedExecutionTests`: exit 0, PASS, 28 tests.
- `--filter LegacyQuarantineTests`: exit 0, PASS, 4 tests.
- `--filter existingPublicRunnerUsesAggregateReplacementGate`: exit 0, PASS, 1 test in isolation.

## Full-suite result

The exact prefix above with no filter was run twice. Each invocation exited 1 after executing 471 tests in 54 suites. T07.4 and every relevant compatibility suite passed, but both full runs ended with the same one unrelated existing process-runner concurrency issue:

```text
BoundedProcessRunnerTests.existingPublicRunnerUsesAggregateReplacementGate
Expectation failed: await ProcessRunner.jobSnapshot().active == 0
Test run with 471 tests in 54 suites failed with 1 issue.
```

That exact test passed when immediately rerun alone (1/1). This is recorded as a pre-existing full-suite interference blocker, not represented as full GREEN and not changed under the T07.4 allowlist.

## Final hygiene

- Only `TidyCore/Tests/TidyCoreTests/HostileProductionRegressionTests.swift` and this verification note are T07.4 implementation changes.
- Worktree-local `.build-local` caches were removed after verification.
- From `/private/tmp/tidy-headroom.r1yE0o`, `git diff --check` exited 0.
- Because both allowlisted files are untracked, `git diff --no-index --check /dev/null TidyCore/Tests/TidyCoreTests/HostileProductionRegressionTests.swift` and the equivalent command for this verification note each produced no whitespace-error output. Their expected exit status was 1 solely because no-index reports file differences.
- No production edits, commit, push, tag, DMG, or release were performed.
