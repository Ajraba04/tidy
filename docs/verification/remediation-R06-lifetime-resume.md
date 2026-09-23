# R06 scope-ledger lifetime resume

Date: 2026-09-19

Parent implementation: `dbf9c72` / `4fe419e`

Status: **bounded source lifetime correction implemented; focused scope suite passed**

## Result

`ScanScopeGrantLedger` no longer retains successfully consumed grants or their captured root and
ancestor identities for the lifetime of the application. Successful consumption validates owner,
home, policy revision, expiry, and every root identity, then removes the entry while holding the
ledger lock. A replay still finds no entry and throws `consumedConsent`, preserving the existing
one-use behavior.

Registration now reaps expired abandoned grants under the same lock before inserting the new grant.
This is lifecycle cleanup, not a global hard cap. No pending-grant capacity or eviction policy was
invented, and no public testing API was added.

The adjacent full-home consent ledger now follows the same successful lifecycle. After owner,
home, expiry, and policy-revision validation, the consent is removed before root authorization.
Therefore a successful authorization retains no consumed consent, and a root-capture failure still
consumes the consent before returning `invalidRoot`. Missing and previously consumed consent both
continue to throw `consumedConsent`; a foreign owner does not consume the valid owner's token, and
direct expiry still removes the token and throws `expiredConsent`.

## TDD evidence

The four focused tests were added after only an internal retained-count observation seam. The red run
showed:

- 32 successful default-scope grants accumulated 32 retained entries;
- two abandoned expired grants remained after the next registration;
- 32 successful full-home starts accumulated both consumed consent and grant entries; and
- a failed full-home root capture retained its consumed consent.

After the source correction, the same four tests passed. They verify zero retained grant metadata
after repeated success, expiry reaping, zero retained consent/grant metadata after repeated full-home
authorization and start, denial on both replay paths, and fail-consumed root-capture behavior.

## Verification

Focused RED/GREEN command, using the existing two-job external scratch path:

```text
cd TidyCore
swift test --scratch-path /tmp/tidy-r05-resume-build --jobs 2 \
  --filter 'repeatedGrantConsumptionRetainsNoLedgerState|abandonedExpiredGrantsAreReapedOnNextRegistration|repeatedFullHomeStartRetainsNeitherLedger|fullHomeRootCaptureFailureStillConsumesConsent'
```

Green result: **4 tests passed, 0 failures**.

Complete affected suite:

```text
cd TidyCore
swift test --scratch-path /tmp/tidy-r05-resume-build --jobs 2 --filter ScanScopeTests
```

Result: **15 tests passed, 0 failures**. This includes all prior scope, alias, expiry, full-home,
root-replacement, protection, and continuation cases plus the four lifetime regressions.

The independent final reviewer inspected the shared `ScanScope.swift` diff and found no residual
substantive issue. A new full Core aggregate is still required after this commit; the controller's
earlier 696-test checkpoint predates this correction and is not claimed as evidence for it.
