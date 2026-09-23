# Bounded current-host observation — 2026-09-19

This is a diagnostic observation of the Debug production-scene fixture host on the current 32 GiB M1 Max. It does not close full-workflow traffic, hidden-idle/background, reference performance, or scan-peak acceptance.

The runtime owner launched the acknowledged-settings fixture without XCTest injection for this observation and reported its control window open. Root verified the exact executable path and stable process-start identity for PID 50870. No additional automated UI actions were taken: the manual CUA native pipe failed to start twice. The separate six production-scene XCTest journeys passed and retain their own evidence.

- 30 process samples over 30.442 seconds; RSS remained 89,552 KiB (87.453 MiB).
- At `ps`'s reported counter resolution, CPU counter delta 0.000 seconds across 29.416 seconds (0.0000% of one core). This is a short visible-window observation, not the ten-minute authorized-background gate.
- `footprint --pid 50870 --noCategories --format bytes --json ...` succeeded. Kernel physical footprint was 36,160,472 bytes; recorded process-lifetime peak was 36,275,160 bytes. No active scan was driven during capture, so these are not scan-peak measurements.
- `nettop -n -P -x -p 50870 -L 30 -s 1 -J bytes_in,bytes_out` produced headers and no TCP/UDP process rows. Name resolution and connection-detail output were disabled. No children were observed at the one-second process samples; this cannot exclude short-lived children between samples.
- Before this capture, a separate owned loopback-only positive control sent 1,572,864 bytes and `nettop` observed positive byte counters. This validates that the observer can report traffic, not that every workflow or IPC-mediated request is covered.

Raw observation evidence: `/private/tmp/tidy-r13-observation-tqsr4497/`. Positive-control evidence: `/private/tmp/tidy-r13-nettop-control-r66q6l93/`. Numeric summary: `remediation-R13-observation.json`.

After capture the runtime owner revalidated the executable/PID, terminated that host, validated the exact canonical temporary-root prefix, non-symlink directory, UID and 0700 mode, removed only its owned `tidy-production-runtime-ucIvb9` root, and confirmed zero matching roots remained. No normal Tidy launch, user-home traversal, global permission change, or release action was performed for this capture. The positive-control traffic was loopback-only; the absence of sampled process rows is not a universal no-network claim.
