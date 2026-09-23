# Performance evidence and limits

2026-09-17, Apple M1 Max32GiB, macOS27.0(26A428), Swift6.4. These measurements exercise production TidyCore components with explicit audit drivers. They are not the complete SwiftUI app or required8GiB reference machines. Other host workloads were preserved; compiler/audit activity overlapped portions of monitoring. No physical stress was induced.

## Live monitor component

Driver: `../tracks/MonitorAudit.swift`, linked against the baseline Debug package `libTidyCore.a` (not an optimized full-app release measurement). Real SystemMonitor/LiveSystemProbe, local `/private/tmp` volume; no history. Cold process first remains hidden with background off, then configuration explicitly enables background sampling at60s. One5s warm-up precedes the monitoring interval. getrusage process user+system CPU and mach_task_basic_info RSS are sampled by the driver; sampling adds minor driver overhead. RSS is not physical footprint.

- Off interval:31.05598s;0.001255 CPU seconds;8,060,928B RSS; instrumentation scheduled/cancelled `[0,0]`; timerRunning=false.
- Authorized monitoring interval:626.81579s (nominal120×5s waits stretched by scheduling);0.052836 CPU seconds, approximately **0.00843% of one core**. Ten minute checkpoints ranged11,583,488–12,877,824B RSS; final11,698,176B ≈11.16MiB; process maximum RSS12,959,744B ≈12.36MiB. Instrumentation `[1,0]` before explicit stop.
- Component-only diagnostic meets CPU/RSS thresholds on this host. **Whole-app/reference gate remains Partial/Blocked.** Off-mode driver does not itself instrument all app filesystem I/O or commands. No full-app interactive, background-build-overhead or scan footprint proof follows from these numbers. One run: variance across independent runs not measured.

Logs/command/timestamps: monitor-build.*, monitor-measurement.*. Nominal versus measured interval is retained; CPU denominator is actual626.81579s.

## Large scratch trees and immediate cancellation

Driver: `../tracks/PolicyAuditPerformanceTests.swift`, real SettingsStore/bridge/scheduler/ScanEngine without an index, matching app wiring. Subprocess stage replaced with availableEmpty to avoid ambient service effects; ambient read-only VM/kernel/disk probes remain. Zero-length files,200 per bucket:50k in250 buckets and100k in500 buckets under owned scratch home/Documents. One non-home protected witness. Two unchanged passes each, no OS cache flush; fixture creation naturally warms metadata. Single execution, no representative-file-size or independent variance claim.

|Files|Pass|Seconds|First item-bearing update s|Processed entries|Coverage|
|---|---|---|---|---|---|
|50,000|1|0.103097|0.067130|7|Partial queueOverflow|
|50,000|2|0.077953|0.062334|7|Partial queueOverflow|
|100,000|1|0.016394|0.003528|6|Partial queueOverflow|
|100,000|2|0.015263|0.002972|6|Partial queueOverflow|

**These are failed completeness/usefulness gates, not fast successful scans.** First item-bearing update is an event proxy, not proof of a useful complete UI result. `processedEntries` is not metadata visits. No index is wired, so neither80% reduction nor content parity was demonstrated.

Each fixture then ran20 immediate scan/cancel cycles. Max core acknowledgement0.000279s (50k) and0.000205s (100k); registry active0, scheduler active0/queued0, file descriptors14→14; witness bytes remained intact. Cancellation happened immediately after start, so this does not prove cancelling active loaded workers or UI≤100ms. No settled-memory growth measurement was collected.

`/usr/bin/time -l swift test` reports436,633,600B maximum RSS and253,133,976B peak memory footprint for the build/test process tree. **Do not attribute these to scan-only Tidy app memory or score150MiB app gate from them.** The measurement test passes only its witness/worker assertions and deliberately prints partial coverage. A preceding zero-selected-test invocation is retained as scan-measurement-no-tests.* and supplies no evidence.

## Remaining physical/whole-app protocol

R13 and acceptance-gates.md retain actual app interactive RSS, scan-only physical footprint, active cancellation,20-cycle settled growth,100k real metadata visits/full parity,5paired build overhead and both8GiB hosts. Pressure/thermal/LPM/sleep/near-full tests first need production observation wiring (PS02), then controlled injections; physical stress uses disposable/isolated setup. No hidden stress or workstation memory exhaustion is authorized.
