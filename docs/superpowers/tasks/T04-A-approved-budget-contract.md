# T04.A — approved history interpretation and bounded recovery proposal

The user approved the controller recommendation on 2026-08-26: `history.maxMiB` caps **optional completed reports only**. Mandatory recovery storage has separate hard bounds and is never evicted to satisfy a history preference. The product interpretation is settled; the implementation constants, API refinement and proposed tests below still require controller/independent source-entry review. Nothing here implements recovery, enables a capability or proves completion.

This supplement supersedes the inclusive `R+A+H<=B` equation, residual allowance, over-budget rules and budget-dependent tests in `.superpowers/sdd/T04.A-entry-proposal.md`. Its independently accepted corrections 2–3 (scanner propagation, staging-slot checks, one-segment retention memory and fault/parser tests) remain binding without weakening. The original T04 card and proposal remain binding elsewhere.

## Exact classes and bounds

All sizes are actual encoded logical bytes, not allocated disk blocks; MiB = 1,048,576. Every addition/multiplication/subtraction is checked before allocation/publication. A logical allowance does not reserve disk space or guarantee fsync/ENOSPC success.

| Class | Accounting and hard bound | Removal |
|---|---|---|
| Optional completed history `H` | Sum of complete validated report/segment file lengths. `B = history.maxMiB * MiB`, 1…50 MiB, default 10 MiB; retention 1…90 days, default 30. Enabled: `H<=B` after successful retention/finalization; disabled: `H=0`. | Only fully validated, finished, unreferenced no-effect segments in A; future effect reports need C's genuine proof before this classification. |
| Mandatory admission `L` | One existing schema-1 envelope, actual encoded length `0<L<=1 MiB`. The 1 MiB allowance is separate from B, not added to L twice. | Never history-pruned. A cannot remove an operation. |
| Active/unresolved diagnostics `A` | Every non-finished segment (including planned/confirmed without intent), and every segment referenced by the ledger. Reserve one full 1 MiB segment slot for each distinct active run; at most **8 slots**, so `A<=8 MiB`. Count referenced run IDs even when its segment is missing; missing referenced data remains corruption, not free capacity. | Never history-pruned. In A only a confirmed no-effect run can finish and release its slot. |
| Installation metadata | Stable empty lock and schema-1 bootstrap are outside B. Publication/read retains the existing 1 MiB per-file envelope ceiling for bootstrap too. Bootstrap is not a history class. | Never history-pruned/reinitialized as recovery. |
| A-owned publication staging | At most one in-flight `.pending-*` publication per installation lock, at most 1 MiB encoded bytes; final prospective directory-slot check remains mandatory. The old destination and stage coexist. Any failed stage blocks later publication/acquire; no cleanup/retry that accumulates stages. | Never prune failed staging. Successful rename consumes its stage. |
| Manifest/terminal-proof batches | Separate from B, L and A; T03's existing per-batch 5,000-node/8 MiB bound is **not an aggregate bound**. A creates none. | Never history-pruned while unresolved. |

The 8-slot reservation deliberately charges the entire segment ceiling rather than only its current length: existing child/outcome bookkeeping can grow within a previously admitted slot, independent of optional retention. It is a defensive run-count bound, not eight permitted concurrent effects; T02's single mutation reservation/admission rules still apply. Finished no-effect segments do not consume active slots. All classification uses a complete bounded scan and one-segment-at-a-time validation, not an in-memory authoritative counter. Reopening cannot reset the limits. Observed excess/corruption preserves all bytes and blocks new work; never silently select eight runs or classify corrupt bytes as zero.

There is no whole-directory bound: unrelated owner-created files remain counted by the 16,384-entry scanner but are not opened, charged as history or deleted. At most 4,096 canonical diagnostic entries; original per-frame 64 KiB/per-segment 1 MiB limits apply to active **and** finished segments. A cannot create arbitrary unbounded staging payloads through the shared helper: enforce the 1 MiB payload ceiling before staging creation, including direct diagnostic replacement. Future 8 MiB manifest publication must not silently reuse this helper with a relaxed ceiling.

**T03.B/T04.C positive-effect gate:** before any production manifest persistence or positive effect, supply and independently review numeric aggregate manifest-plus-proof bytes, file/node counts, maximum staging bytes/count (including simultaneous old/new generations), and prospective admission accounting. Reserve those resources before intent/release; include worst-case terminal evidence and replacement growth. Reopening reconstructs occupancy from original bound evidence, and unresolved files/reservations cannot be evicted/refunded to enlarge scheduling. Add real boundary/overflow, first-stage failure, crash/reopen and no-release tests through the accepted adapter/coordinator. Until that contract exists, manifest/proof allocation and positive effects stay unavailable; A/B scratch foundation success cannot satisfy it. This gate avoids inventing a manifest format, proof or completion producer in A.

## Admission, completion and history disabled

`RunJournal` defaults to enabled/30 days/10 MiB. Keep existing `applyHistoryLimits(days:bytes:now:)` as an enabled-history convenience and add exactly this internal overload to express the existing product preference:

```swift
func applyHistoryLimits(enabled: Bool, days: Int, bytes: Int, now: Date) throws
```

The old signature delegates with `enabled: true`. Both validate days/bytes even when disabled; disabling is not `bytes=0` and never widens supported settings. The object retains validated preferences for later finishes. A has no persistent settings authority: D/T05 must apply the current validated setting before new run work after each reopen; omission cannot disable mandatory safety. The overload changes retention only, never ledger admission. Callers that wish to remain disabled must not call the enabled convenience accidentally.

1. New planned run: require prospective distinct-active-count `<=8`, per-frame/segment and scanner/staging capacity before I/O. The valid 1 MiB history minimum permits planned→confirmed→intent on an empty installation. Optional history consumes no active or ledger allowance.
2. Confirmed/new intent: require valid existing association and transitions, active slot, prospective encoded envelope `<=1 MiB` and all mechanical capacities before I/O. No reservation or history policy creates dispatch authority. A does not reserve unknown future child/proof growth; C must preflight its bounded evidence before positive release under the gate above.
3. Existing child, started and outcome bookkeeping: may continue regardless of reduced B/history disabled, within the already reserved active slot and hard envelope/segment/staging/scanner bounds. Full segment/envelope rejection is pre-I/O capacity, retains uncertainty and cannot fabricate success. The accepted cumulative-cap test still requires a smaller legitimate outcome to work after an oversized caller append is rejected. No exception permits a ninth active run, oversized segment or another stage.
4. `finish` and `append(.finished)` share no-effect-only validation. Publish the finished frame durably first, then classify/release its active slot and apply current retention. No intent/started run can finish in A, even with diagnostic success or an externally absent ledger entry. Completion publication may transiently make `H<=B+1 MiB` (or `H<=1 MiB` when disabled), because exactly one newly finished segment moves from its active slot to H. This is a bounded finalization allowance, not a higher steady history setting. No next run/intent/finalization may grow an observed H overage until explicit retention succeeds; existing unresolved bookkeeping remains available if storage itself is healthy. Finishing cannot bypass scanner or hard segment limits.
5. Retention validates every candidate before the first unlink, then removes age-expired optional segments, then oldest optional segments until `H<=B`; disabled removes all eligible H. Age is validated final-publication mtime; ordering remains full mtime then UTF-8 name. Mandatory references and entry identity are rechecked before each unlink. Lowering B never rejects new work merely because `L+A>B`, and never removes L/A. Finish includes retention, so successful finish while disabled retains no optional report. A failure throws and latches on actual I/O/corruption per existing rules; it must not claim successful finalization/achieved retention. Crash between durable finish and pruning retains at most the single-segment allowance under the previously applied policy; a newly lowered preference can of course encounter prior H up to the previous 50 MiB limit. Reopen/explicit apply must prune before growing optional history further. No rollback of a published finish.

Future D optional RunLog/report files share this **one** H allowance; they do not each receive B. A accounts only its owned finished segments because no new D representation is implemented. D entry must specify joint enumeration/accounting and tests before enabling an additional optional writer. Clear history uses the disabled-retention classification, never recursive directory deletion. Failure to save an optional report cannot erase mandatory recovery.

## Exact replacement/additional proposed tests

These are documentation-only Swift tests to append to the existing proposed `RunRecoveryTests` file, reusing the original card/proposal helpers (`journalScratch`, `event`, `intent`, `envelope`, `completeNoEffect`, `ownedSafetyBytes`, `childRecord`, `journalName`, `FaultIO`). Replace, do not also compile, the two historical methods `minimumHistoryBudgetPreservesAndChargesActiveEvidence` and `bytePruningRemovesOnlyOldestFinishedHistory`. All other accepted tests remain. This is not executed RED/GREEN evidence. Fixtures contain untrusted records; no effect/process/proof producer is introduced.

```swift
private final class CompletionPruneIO: JournalPOSIXIO, @unchecked Sendable {
    private let base = DarwinJournalIO()
    private let lock = NSLock()
    private var remaining: Int?
    func failSecondDirectorySync() { lock.lock(); remaining = 2; lock.unlock() }
    func write(fd: Int32, bytes: Data, offset: Int) throws -> Int {
        try base.write(fd: fd, bytes: bytes, offset: offset)
    }
    func syncFile(fd: Int32) throws { try base.syncFile(fd: fd) }
    func replace(directoryFD: Int32, temporary: String, destination: String) throws {
        try base.replace(directoryFD: directoryFD, temporary: temporary, destination: destination)
    }
    func syncDirectory(fd: Int32) throws {
        lock.lock()
        let fail: Bool
        if let value = remaining {
            remaining = value > 1 ? value - 1 : nil
            fail = value == 1
        } else { fail = false }
        lock.unlock()
        if fail { throw POSIXError(.EIO) }
        try base.syncDirectory(fd: fd)
    }
}

extension RunRecoveryTests {
    @Test func minimumOptionalBudgetPermitsFirstRunAndIntent() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            try journal.applyHistoryLimits(days: 30, bytes: 1_048_576, now: .distantPast)
            let run = UUID(), pending = intent(run)
            try journal.append(event(run, 1, .planned))
            try journal.append(event(run, 2, .confirmed))
            try journal.persistIntent(pending)
            #expect(try journal.events(runID: run).map(\.phase) == [.planned, .confirmed])
            #expect(try envelope(root).unfinished == [pending])
            #expect(try storage.read(name: journalName(run)).count > 0)
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }

    @Test func minimumHistoryPreservesActiveBytesAndAllowsBookkeeping() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID(), finished = UUID()
            try journal.append(event(active, 1, .planned))
            try journal.append(event(active, 2, .confirmed))
            let pending = intent(active)
            try journal.persistIntent(pending)
            try completeNoEffect(journal, run: finished)
            let safety = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(active))
            try journal.applyHistoryLimits(days: 1, bytes: 1_048_576, now: .distantFuture)
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(finished)) }
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == diagnostic)
            // An unfinished intent still blocks execution, not scratch diagnostic preparation.
            try journal.append(event(UUID(), 1, .planned))
            let captured = childRecord(pending, pid: 123, seconds: 100, micros: 1)
            try journal.recordChild(captured)
            try journal.append(event(active, 3, .started, operation: pending.operationID))
            try journal.append(JournalEvent(runID: active, sequence: 4, phase: .itemTerminal,
                operationID: pending.operationID, status: .uncertain, reason: "No proof"))
            #expect(throws: JournalError.invalidTransition) { try journal.finish(runID: active) }
            #expect(try envelope(root).unfinished == [captured])
            #expect(store.readAdmissionWhileLocked() == .uncertainAndPossiblyRunning)
        }
    }

    @Test func eightActiveReservationsRejectNinthBeforeIOAndSurviveReopen() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            try journal.applyHistoryLimits(days: 30, bytes: 1_048_576, now: .distantPast)
            let runs = (0..<8).map { _ in UUID() }
            for run in runs {
                try journal.append(event(run, 1, .planned))
                try journal.append(event(run, 2, .confirmed))
            }
            let safety = try ownedSafetyBytes(root)
            let entries = try storage.journalEntries()
            #expect(entries.count == 8)
            #expect(entries.reduce(0) { $0 + $1.byteCount } <= 8 * 1_048_576)
            let trace = io.calls()
            #expect(throws: JournalError.capacity) { try journal.append(event(UUID(), 1, .planned)) }
            #expect(io.calls() == trace)
            #expect(try storage.journalEntries().sorted { $0.name < $1.name }
                == entries.sorted { $0.name < $1.name })
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(store.readAdmissionWhileLocked() == .ready)
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .ready)
            defer { reopened.release() }
            let recovered = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: root))
            #expect(throws: JournalError.capacity) { try recovered.append(event(UUID(), 1, .planned)) }
            // Finish is legal at the active bound and releases exactly one slot.
            try recovered.finish(runID: runs[0])
            try recovered.append(event(UUID(), 1, .planned))
            #expect(throws: JournalError.capacity) { try recovered.append(event(UUID(), 1, .planned)) }
            #expect(try ownedSafetyBytes(root) == safety)
        }
    }

    @Test func optionalBytePruningDoesNotChargeLedgerOrActiveReservation() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID()
            try journal.append(event(active, 1, .planned))
            let activeBytes = try storage.read(name: journalName(active))
            for _ in 0..<20 {
                try completeNoEffect(journal, run: UUID(), reason: String(repeating: "x", count: 60_000))
            }
            let before = try storage.journalEntries().filter { $0.name != journalName(active) }.sorted {
                if $0.modifiedSeconds != $1.modifiedSeconds { return $0.modifiedSeconds < $1.modifiedSeconds }
                if $0.modifiedNanoseconds != $1.modifiedNanoseconds { return $0.modifiedNanoseconds < $1.modifiedNanoseconds }
                return $0.name.utf8.lexicographicallyPrecedes($1.name.utf8)
            }
            #expect(before.reduce(0) { $0 + $1.byteCount } > 1_048_576)
            let safety = try ownedSafetyBytes(root)
            try journal.applyHistoryLimits(days: 90, bytes: 1_048_576, now: .distantPast)
            let after = try storage.journalEntries().filter { $0.name != journalName(active) }
            try #require(!after.isEmpty && after.count < before.count)
            let remaining = after.reduce(0) { $0 + $1.byteCount }
            #expect(remaining <= 1_048_576)
            let lastRemoved = before[before.count - after.count - 1]
            #expect(remaining + lastRemoved.byteCount > 1_048_576)
            #expect(Set(after.map(\.name)) == Set(before.suffix(after.count).map(\.name)))
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == activeBytes)
        }
    }

    @Test func disabledHistoryPrunesOnlyCompletedAndStillPersistsSafety() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            let old = UUID(), active = UUID()
            try completeNoEffect(journal, run: old)
            try journal.append(event(active, 1, .planned))
            try journal.append(event(active, 2, .confirmed))
            let pending = intent(active)
            try journal.persistIntent(pending)
            let safety = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(active))
            try journal.applyHistoryLimits(enabled: false, days: 30, bytes: 1_048_576, now: .distantPast)
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(old)) }
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == diagnostic)
            let noEffect = UUID()
            try completeNoEffect(journal, run: noEffect)
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(noEffect)) }
            let captured = childRecord(pending, pid: 123, seconds: 100, micros: 1)
            try journal.recordChild(captured)
            #expect(try envelope(root).unfinished == [captured])
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            defer { reopened.release() }
            let recovered = try RunJournal(store: reopened, storage: DurableJournalStorage(directory: root))
            try recovered.applyHistoryLimits(enabled: false, days: 30, bytes: 1_048_576, now: .distantFuture)
            #expect(try envelope(root).unfinished == [captured])
            #expect(try recovered.events(runID: active).map(\.phase) == [.planned, .confirmed])
        }
    }

    @Test(arguments: [0, 1_048_575, 52_428_801, Int.max])
    func disabledHistoryStillRejectsInvalidByteLimits(_ bytes: Int) throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let run = UUID()
            try completeNoEffect(journal, run: run)
            let safety = try ownedSafetyBytes(root)
            let original = try storage.read(name: journalName(run))
            let trace = io.calls()
            #expect(throws: JournalError.capacity) {
                try journal.applyHistoryLimits(enabled: false, days: 30, bytes: bytes, now: .distantFuture)
            }
            #expect(io.calls() == trace)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(run)) == original)
        }
    }

    @Test func finishAtOptionalCapAutomaticallyPrunesWithoutGrowingHistory() throws {
        try journalScratch { root in
            let store = try MutationAdmissionStore(directory: root)
            #expect(store.acquire() == .ready)
            defer { store.release() }
            let storage = try DurableJournalStorage(directory: root)
            let journal = try RunJournal(store: store, storage: storage)
            try journal.applyHistoryLimits(days: 90, bytes: 1_048_576, now: .distantPast)
            for _ in 0..<20 {
                try completeNoEffect(journal, run: UUID(), reason: String(repeating: "x", count: 60_000))
                #expect(try storage.journalEntries().reduce(0) { $0 + $1.byteCount } <= 1_048_576)
            }
            #expect(try storage.journalEntries().count < 20)
            #expect(store.readAdmissionWhileLocked() == .ready)
        }
    }

    @Test func finishedPublicationThenPruneSyncFailurePreservesSafetyAndLatches() throws {
        try journalScratch { root in
            let io = CompletionPruneIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID(), finished = UUID()
            for run in [active, finished] {
                try journal.append(event(run, 1, .planned))
                try journal.append(event(run, 2, .confirmed))
            }
            let pending = intent(active)
            try journal.persistIntent(pending)
            try journal.applyHistoryLimits(enabled: false, days: 30, bytes: 1_048_576, now: .distantPast)
            let safety = try ownedSafetyBytes(root)
            let diagnostic = try storage.read(name: journalName(active))
            io.failSecondDirectorySync() // First: durable finished rename; second: actual prune unlink.
            #expect(throws: JournalError.unavailable) { try journal.finish(runID: finished) }
            #expect(store.readAdmissionWhileLocked() == .storageUnavailable)
            #expect(try ownedSafetyBytes(root) == safety)
            #expect(try storage.read(name: journalName(active)) == diagnostic)
            // The real unlink already happened; no rollback/recreated report after sync ambiguity.
            #expect(throws: JournalError.notFound) { _ = try storage.read(name: journalName(finished)) }
            #expect(throws: JournalError.unavailable) { try journal.append(event(UUID(), 1, .planned)) }
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            defer { reopened.release() }
            #expect(try ownedSafetyBytes(root) == safety)
            // Injected sync failure is not physical crash/durability proof.
        }
    }

    @Test func observedOptionalOverageBlocksGrowthButNotExistingBookkeeping() throws {
        try journalScratch { root in
            let io = FaultIO()
            let store = try MutationAdmissionStore(directory: root, io: io)
            #expect(store.acquire() == .ready)
            let storage = try DurableJournalStorage(directory: root, io: io)
            let journal = try RunJournal(store: store, storage: storage)
            let active = UUID(), waiting = UUID()
            for run in [active, waiting] {
                try journal.append(event(run, 1, .planned))
                try journal.append(event(run, 2, .confirmed))
            }
            let pending = intent(active)
            try journal.persistIntent(pending)
            try journal.applyHistoryLimits(days: 90, bytes: 10_485_760, now: .distantPast)
            // Correctly framed owned fixtures model a recovered optional overage, not terminal proof.
            // 180 small segments exceed the default 10 MiB; one payload is retained at a time.
            for _ in 0..<180 {
                let run = UUID()
                let planned = JournalEvent(runID: run, sequence: 1, phase: .planned,
                    operationID: nil, status: nil, reason: String(repeating: "x", count: 60_000))
                let bytes = try fixtureJournalHeader + fixtureRecord(planned)
                    + fixtureRecord(event(run, 2, .confirmed)) + fixtureRecord(event(run, 3, .finished))
                try storage.replace(name: journalName(run), bytes: bytes)
            }
            let safety = try ownedSafetyBytes(root)
            let trace = io.calls()
            #expect(throws: JournalError.capacity) { try journal.append(event(UUID(), 1, .planned)) }
            #expect(throws: JournalError.capacity) { try journal.persistIntent(intent(waiting)) }
            #expect(throws: JournalError.capacity) { try journal.finish(runID: waiting) }
            #expect(io.calls() == trace)
            #expect(try ownedSafetyBytes(root) == safety)
            let captured = childRecord(pending, pid: 123, seconds: 100, micros: 1)
            try journal.recordChild(captured)
            try journal.append(event(active, 3, .started, operation: pending.operationID))
            store.release()
            let reopened = try MutationAdmissionStore(directory: root)
            #expect(reopened.acquire() == .uncertainAndPossiblyRunning)
            defer { reopened.release() }
            let recoveredStorage = try DurableJournalStorage(directory: root)
            let recovered = try RunJournal(store: reopened, storage: recoveredStorage)
            #expect(throws: JournalError.capacity) { try recovered.append(event(UUID(), 1, .planned)) }
            #expect(throws: JournalError.capacity) { try recovered.persistIntent(intent(waiting)) }
            #expect(throws: JournalError.capacity) { try recovered.finish(runID: waiting) }
            // Reapply current setting on reopen; this explicitly reconciles optional overage.
            try recovered.applyHistoryLimits(days: 90, bytes: 10_485_760, now: .distantPast)
            try recovered.finish(runID: waiting)
            #expect(try envelope(root).unfinished == [captured])
            #expect(try recovered.events(runID: active).last?.phase == .started)
            let optional = try recoveredStorage.journalEntries().filter { $0.name != journalName(active) }
            #expect(optional.reduce(0) { $0 + $1.byteCount } <= 10_485_760)
        }
    }
}
```

Retain all original invalid 1…50 MiB range tests, ledger/segment capacity tests, no-effect/false-success tests, unsafe/nonhistory preservation, oldest/age ordering, and accepted publication/scan fault tests. Before A entry, independent review must assess finalization's bounded H transfer and auto-retention fault ordering. Before D entry, supply complete additional production-settings/combined-report tests; before T03.B/C entry, supply the full manifest/proof aggregate and terminal-growth tests above. No test here substitutes for those future integration gates.
