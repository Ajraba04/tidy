# Cleanup completion contract — decision required

The current source can be built and locally validated, but the original full
cleanup promise cannot be accepted under its existing production dependency.
The owner explicitly approved **Choice 2** on 10 October 2026 in this chat:
“Authorize the manual per-adapter redesign.” This supersedes the prior pending
decision and the coordination message that supplied no owner approval.
The engineering scope and live-effect/release boundaries below still apply.

## Evidence

The current host still uses Xcode 27.0 (27A266a), the same relevant supported
tool surface investigated in
[the producer dependency record](remediation-producer-dependency-resume.md).
No supported interface has been established for complete shared DerivedData
producer ownership and an externally held exclusion lease. The binding
[remediation plan](../audits/2026-09-17-9e1a500/remediation-plan.md), R02,
requires that proof before R03/R04 positive-effect acceptance and cleanup
enablement. Process absence, a Tidy lock and synthetic fixtures do not satisfy it.

## Choice 1: preserve the existing strict contract

Keep shared DerivedData and every other unaccepted mutation unavailable.
Complete independent source, read-only, UI, fixture and packaging work, while
recording the full cleanup program as blocked until a supported producer
interface or another explicitly approved contract exists. This does not deliver
the original complete cleanup app or authorize a release.

## Choice 2: approve a manual per-adapter redesign

Replace the universal shared-DerivedData prerequisite with independent manual
adapter acceptance. The next implementation plan would:

- Prefer supported producer/service operations for an exact reviewed identity,
  rather than direct unlinking of shared producer data without exclusion.
- Require a reviewed contract for every operation: supported tool/version,
  complete effect scope, explicit per-run consequence confirmation, no remote
  endpoints or implicit downloads, cancellation semantics, durable intent,
  truthful partial/uncertain results, and adapter-specific terminal recovery.
- Keep generic direct shared-cache deletion unavailable whenever exact ownership
  and exclusion cannot be proved. An inactivity checkbox is not a substitute.
- Keep unattended cleanup off with an empty allowlist. Preserve all existing
  repository/database/model/Docker-volume/broad-prune prohibitions.
- Allow a producer-managed operation only after its own contract and disposable
  integration tests pass. A provider's supported API is not by itself proof that
  its effect scope satisfies Tidy's review.
- Update the capability manifest and dependency graph explicitly; do not mark
  the old R02 gate passed or imply that every currently advertised cleanup is
  restored. Retain inventory-only status for unsupported adapter versions.

This choice authorizes engineering the revised manual capability contracts and
their local fixtures. It does not authorize deletion of the user's data, live
tool/device effects, Git publication, signing changes or release. Final product
acceptance still requires the revised capability matrix and the remaining
native/accessibility/privacy/physical/distribution evidence.

The decision matters because implementation effort alone cannot manufacture the
missing supported interface. The original strict contract remains the execution gate until each replacement
adapter contract is implemented and accepted; redesign approval does not
immediately enable capabilities.
