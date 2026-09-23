# R13 hidden observation resume

Status: the controller's single 120-second hidden-off capture PASSED on this host.
This closes the bounded negative hidden-off fixture, not reference or release acceptance.

## Failure and diagnosis

The retained hidden-off run at
`/private/tmp/tidy-r13-observation-u9jrbl5w/xcodebuild.stdout` failed before its
ready document. `RuntimeObservationControl.task` called `NSApp.hide(nil)` from the initial SwiftUI
view lifecycle, before the test controlled the launch-complete boundary, then
treated one `Task.yield()` as proof that the application had become hidden. At 4.24 seconds the test observed `application did not become
hidden`.

An identical-source focused rerun later published a valid ready document after
10.985708 milliseconds with PID 2251, `applicationHidden: true`, unavailable
background authority, and zero timers, timer transitions, scene leases,
explicit-work leases, scan sessions, and scan work. The ready document and its
interrupted-run log are preserved under
`/private/tmp/tidy-r13-hidden-lifecycle-success-20260919/`; the ready SHA-256 is
`264ed71a36e2fd6ff7701590b16e4c27584eed26c37d1b713d9fa6a8d1a28f7c`.
That rerun was stopped rather than allowed to become an uncoordinated 120-second
capture, so it supplies a valid ready-state counterexample only. Its incomplete
result bundle is not test evidence.

The failure and valid counterexample are consistent with a launch-time hidden
transition race. No notification trace proved the exact AppKit event ordering.
They do not show a settings, authority, timer, lease, scan-work or publication failure.

## Source correction

The runtime-only observation control no longer starts from a SwiftUI `.task`.
It exposes one start button that the UI test clicks only after launch completes
and the disposable settings path and diagnostic controls are reachable. The
coordinator then requests `NSApp.hide(nil)` and waits for the actual
`NSApp.isHidden` condition, checking cancellation every 25 milliseconds and
failing after a fixed five-second deadline.

The scenario settings, unavailable-authority requirement, ready/final document
shape, 120-second duration, zero timer counters, zero leases, zero scan work,
mutation denial, external observer token, and cleanup contract are unchanged.
The UI test also reports an early coordinator diagnostic instead of masking it
as a missing-ready-file timeout.

## Final focused evidence

Controller build-for-testing completed successfully in Release and the compiled fixture
isolation check passed. Build log: `/private/tmp/tidy-resume-runtime-build.log`.
The external observer then exited 0 with a complete native bundle, 1 test passed,
0 failures/skips, 154.013 seconds including setup/observer/cleanup.
Evidence directory: `/private/tmp/tidy-r13-observation-81azbpn5/`.

Ready and final attestations both require actual hidden state, unavailable background
authority, all mutations denied, and zero timer transitions, active timers, leases,
scan sessions and scan work. The source WIP and artifact hashes were unchanged across
the observation; baseline HEAD is `ca24965` plus the recorded working-tree diff.
The guarded fixture was removed by XCTest and the observer verified its disappearance.

121 external samples covered 120.003 seconds. RSS ranged 117,936–126,032 KiB;
CPU delta was 0.160 seconds (0.1333% of one core); sampled file descriptors stayed
at 8. No child PIDs or nettop process rows were sampled; nettop and footprint exited 0.
These are sampled current-host measurements, not exhaustive zero-network/child proof
or scan-peak/reference performance. This negative feature-off run does not establish
the separate authorized-background RSS/CPU gate.

Following the user's “don't overtest” instruction, no 600-second negative capture,
50k/20-cycle measurement or workflow-traffic run followed. They remain unverified.
