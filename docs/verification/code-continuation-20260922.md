# Code continuation — 22 September 2026

Resumed from `35095b3` in the existing remediation worktree. The user's constraints remain: continue the code, avoid cosmetic work and repetitive checks, and defer GUI/real-system tests.

## Remaining consumers addressed

- Developer Workspace now writes global project pins/current selection through the shared settings store. Profile protection remains distinct and cannot be removed by clearing a global pin. Saved protections remain manageable after inventory invalidation.
- Filesystem/project reports expose allocation uncertainty, identity and policy details. Explicit Reveal actions consume a fresh one-use scope and revalidate exact no-follow identity before handing a URL to Finder. No Finder action is run during this continuation.
- Build Prep preserves the measured target/status when there are no candidates. Ranking consumes warm-project and recent-artifact retention, respects a zero retention count, deduplicates retained resource identities and protects covering actions/aliases. Missing artifact dates remain protected when retention is requested.
- Notify-only maintenance consumes explicit inventory and existing permitted signal events. It starts no discovery or repeating timer. Exact rule/root/policy/authority checks and private per-rule frequency state remain separate from cleanup authority. Missing age/owner/activity evidence yields a visible denial; scan time is never used as inactivity evidence.

The source inspection suggestion that ecosystem disable controls were missing was rejected: the existing Core service already gates each adapter/probe before reads. No duplicate policy layer was added.

## Evidence

A single continuation code review found retention alias/covering-action gaps, incorrect overlapping profile-pin attribution, hidden reveal error feedback, and a missing final live-root check. All were corrected before the source freeze; the reviewer reported no unresolved correctness findings.

Fresh evidence in `dist/verification/code-continuation-20260922/`:

- `app-build.log`: normal Debug application build passed; no app launch.
- `core.log`: 28 focused tests in six suites passed in 0.793 seconds (ranking/Build Prep, maintenance, notification policy, presentation grant consumption and generated settings reference).
- `models.xcresult` / `models.log`: one headless Settings routing/authority test passed in 5.664 seconds.
- Generated project membership, personal-data source scan, exact privacy API source table and diff whitespace checks passed.

The Settings reference was regenerated from the compiled registry. Prior passing checks were retained; no full Core/model aggregate or GUI suite was rerun.

All catalog mutations remain compiled denied pending the existing supported producer/service proof requirements. The unattended allowlist remains empty. No GUI test, real cleanup, live notification delivery, real application termination, login registration, release or remote Git operation is authorized by this checkpoint.
