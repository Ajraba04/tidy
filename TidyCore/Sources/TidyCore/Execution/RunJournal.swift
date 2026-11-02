import Foundation
import CryptoKit

public enum RecoveryDecision: Equatable, Sendable {
    case blockMutations, requireFreshReview
    public static func forUnfinishedEffect(quiescenceProven: Bool) -> Self {
        quiescenceProven ? .requireFreshReview : .blockMutations
    }
}
enum JournalPhase: String, Codable, Sendable { case planned, confirmed, started, itemTerminal, finished }
struct JournalEvent: Codable, Equatable, Sendable {
    let runID: UUID
    let sequence: UInt64
    let phase: JournalPhase
    let operationID: UUID?
    let status: EffectStatus?
    let reason: String?
    let proof: EffectProofReference?

    init(runID: UUID, sequence: UInt64, phase: JournalPhase,
         operationID: UUID?, status: EffectStatus?, reason: String?,
         proof: EffectProofReference? = nil) {
        self.runID = runID
        self.sequence = sequence
        self.phase = phase
        self.operationID = operationID
        self.status = status
        self.reason = reason
        self.proof = proof
    }
}
enum JournalError: Error, Equatable {
    case invalidTransition, corrupt, unavailable, capacity, unsupportedSchema, notFound
}
enum JournalSequence {
    static func next(after value: UInt64) throws -> UInt64 {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { throw JournalError.capacity }
        return next
    }
}

/// Transient evidence of this journal completing every durable terminal phase.
/// Decoding an archive, publishing a proof alone, or reconciling after restart
/// cannot construct this capability. Its archive remains data, not a new proof.
struct DurablyRetiredManualServiceReceipt: Sendable {
    let archive: EffectTerminalProofArchive
    let proofReference: EffectProofReference

    fileprivate init(archive: EffectTerminalProofArchive, proofReference: EffectProofReference) {
        self.archive = archive; self.proofReference = proofReference
    }
}

final class RunJournal {
    private let store: MutationAdmissionStore
    private let storage: any JournalStorage
    private let artifacts: ReviewedManifestStore
    var serviceChildCaptureStoreIdentity: ObjectIdentifier { ObjectIdentifier(store) }
    private var historyEnabled = true
    private var historyDays = 30
    private var historyBytes = 10_485_760
    private static let header = Data([0x54, 0x44, 0x59, 0x4a, 0, 1, 0, 0])
    private struct Summary: Equatable {
        let entry: JournalStorageEntry
        let runID: UUID
        let finished: Bool
        let artifactBytes: Int
        let artifactCount: Int
    }

    init(store: MutationAdmissionStore, storage: any JournalStorage) throws {
        self.store = store
        self.storage = storage
        self.artifacts = ReviewedManifestStore(admission: store)
        try checkLock()
        try artifacts.resumeRetirements(storage: storage)
    }

    private func checkLock() throws {
        // An absent borrowed lock is a precondition, not a storage failure.
        try store.requireJournalLock()
        do {
            guard try store.journalDirectoryIdentityWhileLocked() == storage.directoryIdentity() else {
                throw JournalError.unavailable
            }
        } catch {
            store.latchJournalStorageFailure()
            throw JournalError.unavailable
        }
    }

    /// Only observed read/parse/publication faults enter this boundary.
    private func observed<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch {
            store.latchJournalStorageFailure()
            throw (error as? JournalError) ?? .unavailable
        }
    }
    private func publish(_ bytes: Data, runID: UUID) throws {
        do { try storage.replace(name: Self.name(runID), bytes: bytes) }
        catch JournalError.capacity { throw JournalError.capacity }
        catch { store.latchJournalStorageFailure(); throw JournalError.unavailable }
    }
    private static func name(_ runID: UUID) -> String { "run-" + runID.uuidString + ".journal" }

    func events(runID: UUID) throws -> [JournalEvent] {
        try checkLock()
        return try load(runID: runID)
    }

    private func load(runID: UUID) throws -> [JournalEvent] {
        let intents = try store.unfinishedIntentsWhileLocked()
        let bytes: Data
        do { bytes = try storage.read(name: Self.name(runID)) }
        catch JournalError.notFound {
            if intents.contains(where: { $0.runID == runID }) {
                store.latchJournalStorageFailure()
                throw JournalError.corrupt
            }
            return []
        } catch {
            store.latchJournalStorageFailure()
            throw (error as? JournalError) ?? .unavailable
        }
        return try observed { try Self.parse(bytes, runID: runID) }
    }

    func append(_ event: JournalEvent) throws {
        try checkLock()
        let previous = try load(runID: event.runID)
        let intents = try store.unfinishedIntentsWhileLocked()
        try Self.validateHistorical(event, previous: previous)
        try validateAdmission(event, previous: previous, intents: intents)
        let payload = try JSONEncoder().encode(event)
        guard payload.count <= 65_536 else { throw JournalError.capacity }
        let record = Self.frame(payload, sequence: event.sequence)
        let original = previous.isEmpty ? Self.header : try observed { try storage.read(name: Self.name(event.runID)) }
        guard record.count <= JournalFiles.maximumBytes - original.count else { throw JournalError.capacity }
        let summaries = try scan()
        let active = Set(summaries.filter { !$0.finished }.map(\.runID)).union(intents.map(\.runID))
        guard active.count <= 8 else { throw JournalError.capacity }
        if previous.isEmpty {
            guard active.count < 8 else { throw JournalError.capacity }
        }
        if event.phase == .planned || event.phase == .confirmed || event.phase == .finished {
            try requireOptionalCapacity(summaries)
        }
        try publish(original + record, runID: event.runID)
        if event.phase == .finished { try retain(now: Date()) }
    }

    func persistIntent(_ intent: PendingEffectIntent) throws {
        try checkLock()
        let previous = try load(runID: intent.runID)
        guard previous.contains(where: { $0.phase == .confirmed }),
              previous.last?.phase != .finished else { throw JournalError.invalidTransition }
        let summaries = try scan()
        guard summaries.filter({ !$0.finished }).count <= 8 else { throw JournalError.capacity }
        try requireOptionalCapacity(summaries)
        do { try store.persistIntentWhileLocked(intent) }
        catch let error as JournalError { throw error }
        catch { throw JournalError.unavailable }
    }
    func prepareReviewedManifest(_ reviewed: ReviewedFileResource) throws
        -> ReviewedManifestStore.PreparedManifestPublication {
        try checkLock()
        return try artifacts.prepare(reviewed)
    }
    func publishReviewedManifest(
        _ prepared: ReviewedManifestStore.PreparedManifestPublication
    ) throws {
        try checkLock()
        try artifacts.publish(prepared)
    }
    func persistTerminalProof(_ proof: VerifiedEffectTerminalProof) throws
        -> EffectProofReference {
        try checkLock()
        return try artifacts.persist(proof)
    }
    func forEachReviewedBatch(_ reference: ReviewedManifestReference,
                              reversed: Bool,
                              _ body: (ReviewedBatch) throws -> Void) throws {
        try checkLock()
        try artifacts.forEachBatch(reference, reversed: reversed, body)
    }
    func recordChild(_ intent: PendingEffectIntent) throws {
        try checkLock()
        guard intent.schemaVersion == 1 else { throw JournalError.invalidTransition }
        _ = try load(runID: intent.runID)
        do { try store.persistIntentWhileLocked(intent, update: .capturedChild) }
        catch let error as JournalError { throw error }
        catch { throw JournalError.unavailable }
    }

    /// The retired raw-data route is explicitly inert, including for well-formed
    /// tuples. It is retained only to make rejection fixtures exercise the boundary.
    func recordManualServiceChild(_: PendingEffectIntent) throws {
        throw JournalError.invalidTransition
    }

    /// Capture authority must come from this exact journal's submission owner;
    /// this receipt is forensic evidence, never a compiled terminal proof.
    func recordOwnedServiceChild(_ receipt: OwnedServiceChildCaptureReceipt) throws {
        try checkLock()
        try receipt.requireJournal(self)
        let intent = receipt.intent(phase: .submitted)
        let previous = try load(runID: intent.runID)
        guard intent.schemaVersion == 3,
              [.submitted, .uncertainAndPossiblyRunning].contains(intent.phase),
              previous.filter({ $0.phase == .started && $0.operationID == intent.operationID }).count == 1,
              !previous.contains(where: { $0.phase == .finished
                  || ($0.phase == .itemTerminal && $0.operationID == intent.operationID) }) else {
            throw JournalError.invalidTransition
        }
        let matches = try store.unfinishedIntentsWhileLocked().filter {
            $0.runID == intent.runID && $0.operationID == intent.operationID
        }
        guard matches.count == 1, let prior = matches.first, prior.schemaVersion == 3,
              prior.binding == intent.binding, prior.adapterID == intent.adapterID,
              [.submitted, .uncertainAndPossiblyRunning].contains(prior.phase),
              prior.binding == .service(receipt.binding) else { throw JournalError.invalidTransition }
        // Late forensic capture must preserve an already-uncertain submission;
        // writing identity never moves its durable disposition backwards.
        let preservingPhase = receipt.intent(phase: prior.phase)
        do { try store.persistIntentWhileLocked(preservingPhase, update: .ownedServiceChildCapture(receipt)) }
        catch let error as JournalError { throw error }
        catch { throw JournalError.unavailable }
    }

    func requireExactManualServiceIntent(_ intent: PendingEffectIntent) throws {
        try checkLock()
        guard intent.schemaVersion == 3, intent.phase == .prepared,
              try store.unfinishedIntentsWhileLocked().filter({ $0 == intent }).count == 1 else {
            throw JournalError.invalidTransition
        }
    }

    func markManualServiceSubmission(_ intent: PendingEffectIntent) throws {
        try requireExactManualServiceIntent(intent)
        guard case .service(let binding)? = intent.binding else { throw JournalError.invalidTransition }
        let submitted = PendingEffectIntent(runID: intent.runID, operationID: intent.operationID,
            service: binding, phase: .submitted)
        try store.persistIntentWhileLocked(submitted, update: .serviceSubmission)
    }
    func finish(runID: UUID) throws {
        try checkLock()
        let previous = try load(runID: runID)
        try append(JournalEvent(runID: runID, sequence: JournalSequence.next(after: previous.last?.sequence ?? 0),
            phase: .finished, operationID: nil, status: nil, reason: nil))
        try retireTerminalIntents(previous)
        try retain(now: Date())
    }

    /// The process gate may consume only the receipt returned after this entire
    /// transaction succeeds. Each publication retains the existing crash-safe
    /// recovery behavior; a failure at any phase returns no close capability.
    func finishManualService(proof: VerifiedEffectTerminalProof) throws -> DurablyRetiredManualServiceReceipt {
        try checkLock()
        let archive = proof.archive
        let matching = try store.unfinishedIntentsWhileLocked().filter {
            $0.operationID == archive.operationID
        }
        guard matching.count == 1, let intent = matching.first,
              intent.schemaVersion == 3, case .service? = intent.binding,
              CompiledEffectTerminalVerifier.validate(archive, intent: intent) else {
            throw JournalError.invalidTransition
        }
        let events = try load(runID: archive.runID)
        guard events.filter({ $0.phase == .started && $0.operationID == archive.operationID }).count == 1,
              !events.contains(where: { $0.phase == .finished
                  || ($0.phase == .itemTerminal && $0.operationID == archive.operationID) }) else {
            throw JournalError.invalidTransition
        }
        let reference: EffectProofReference
        if let existing = try artifacts.findServiceProof(for: intent) {
            reference = existing
        } else {
            reference = try persistTerminalProof(proof)
        }
        guard try artifacts.proof(reference, for: intent) == archive else { throw JournalError.invalidTransition }
        let terminal = JournalEvent(runID: archive.runID,
            sequence: try JournalSequence.next(after: events.last?.sequence ?? 0),
            phase: .itemTerminal, operationID: archive.operationID,
            status: archive.terminalStatus, reason: nil, proof: reference)
        try append(terminal)
        let published = try load(runID: archive.runID)
        guard published.last == terminal else { throw JournalError.invalidTransition }
        try finish(runID: archive.runID)
        try checkLock()
        guard try !store.unfinishedIntentsWhileLocked().contains(where: {
            $0.operationID == archive.operationID
        }) else { throw JournalError.invalidTransition }
        // Optional history retention may already have removed the finished
        // archive. All mandatory publication/retirement calls above succeeded;
        // there is no reconstruction from optional historical data here.
        return DurablyRetiredManualServiceReceipt(archive: archive, proofReference: reference)
    }

    func reconcileTerminalRun(runID: UUID) throws -> Bool {
        try checkLock()
        var events = try load(runID: runID)
        guard events.contains(where: { $0.phase == .started }) else { return false }
        for intent in try store.unfinishedIntentsWhileLocked() where intent.runID == runID && intent.schemaVersion == 3 {
            guard !events.contains(where: { $0.phase == .itemTerminal && $0.operationID == intent.operationID }) else { continue }
            guard let reference = try artifacts.findServiceProof(for: intent) else { return false }
            let archive = try artifacts.proof(reference, for: intent)
            let event = JournalEvent(runID: runID, sequence: try JournalSequence.next(after: events.last?.sequence ?? 0),
                phase: .itemTerminal, operationID: intent.operationID, status: archive.terminalStatus,
                reason: nil, proof: reference)
            try append(event)
            events.append(event)
        }
        try validateHistoricalProofs(events)
        if events.last?.phase != .finished {
            try finish(runID: runID)
            return true
        }
        try retireTerminalIntents(events)
        return true
    }

    private func retireTerminalIntents(_ events: [JournalEvent]) throws {
        try validateHistoricalProofs(events)
        let liveIDs = Set(try store.unfinishedIntentsWhileLocked().map(\.operationID))
        for terminal in events where terminal.phase == .itemTerminal {
            guard let operationID = terminal.operationID, let proof = terminal.proof else {
                throw JournalError.invalidTransition
            }
            // Finished publication precedes retirement. A crash may have
            // retired some/all intents already; validated history is replayed
            // idempotently without removing any other outstanding operation.
            guard liveIDs.contains(operationID) else { continue }
            _ = try store.retireIntentWhileLocked(operationID: operationID,
                proof: proof, artifacts: artifacts)
        }
    }
    func applyHistoryLimits(days: Int, bytes: Int, now: Date) throws {
        try applyHistoryLimits(enabled: true, days: days, bytes: bytes, now: now)
    }
    func applyHistoryLimits(enabled: Bool, days: Int, bytes: Int, now: Date) throws {
        try checkLock()
        guard (1...90).contains(days), (1_048_576...52_428_800).contains(bytes) else { throw JournalError.capacity }
        historyEnabled = enabled
        historyDays = days
        historyBytes = bytes
        try retain(now: now)
    }

    private func requireOptionalCapacity(_ summaries: [Summary]) throws {
        let total = try Self.total(summaries.filter(\.finished))
        guard total <= (historyEnabled ? historyBytes : 0) else { throw JournalError.capacity }
    }
    private static func total(_ summaries: [Summary]) throws -> Int {
        try summaries.reduce(0) {
            let (withJournal, journalOverflow) = $0.addingReportingOverflow($1.entry.byteCount)
            let (sum, artifactOverflow) = withJournal.addingReportingOverflow($1.artifactBytes)
            guard !journalOverflow, !artifactOverflow else { throw JournalError.capacity }
            return sum
        }
    }
    /// The segment and decoded events die with this call; only metadata escapes.
    private func summarize(_ entry: JournalStorageEntry, intents: [PendingEffectIntent]) throws -> Summary {
        guard let runID = try JournalFiles.runID(entry.name) else { throw JournalError.corrupt }
        let bytes = try storage.read(name: entry.name)
        guard bytes.count == entry.byteCount else { throw JournalError.unavailable }
        let events = try Self.parse(bytes, runID: runID)
        try validateHistoricalProofs(events)
        let finished = events.last?.phase == .finished && !intents.contains(where: { $0.runID == runID })
        let artifacts = finished ? try terminalArtifacts(events) : (bytes: 0, count: 0)
        return Summary(entry: entry, runID: runID, finished: finished,
            artifactBytes: artifacts.bytes, artifactCount: artifacts.count)
    }
    private func scan() throws -> [Summary] {
        try observed {
            let entries = try storage.journalEntries()
            let intents = try store.unfinishedIntentsWhileLocked()
            var result: [Summary] = []
            for entry in entries { result.append(try summarize(entry, intents: intents)) }
            let present = Set(result.map(\.runID))
            guard intents.allSatisfy({ present.contains($0.runID) }) else { throw JournalError.corrupt }
            return result
        }
    }
    private func retain(now: Date) throws {
        try artifacts.resumeRetirements(storage: storage)
        let summaries = try scan() // Validate ALL files before the first deletion.
        var optional = summaries.filter(\.finished).sorted {
            let a = $0.entry, b = $1.entry
            if a.modifiedSeconds != b.modifiedSeconds { return a.modifiedSeconds < b.modifiedSeconds }
            if a.modifiedNanoseconds != b.modifiedNanoseconds { return a.modifiedNanoseconds < b.modifiedNanoseconds }
            return a.name.utf8.lexicographicallyPrecedes(b.name.utf8)
        }
        var bytes = try Self.total(optional)
        var occupancy = try artifacts.retentionOccupancy()
        let cutoff = now.addingTimeInterval(-Double(historyDays) * 86_400)
        while let candidate = optional.first {
            guard !historyEnabled || candidate.entry.modifiedAt < cutoff
                    || bytes > historyBytes
                    || occupancy.artifacts > ReviewedManifestStore.retainedArtifactCeiling else {
                break
            }
            try checkLock()
            try observed {
                let intents = try store.unfinishedIntentsWhileLocked()
                guard !intents.contains(where: { $0.runID == candidate.runID }),
                      try summarize(candidate.entry, intents: intents) == candidate else { throw JournalError.unavailable }
                let events = try Self.parse(storage.read(name: candidate.entry.name),
                                            runID: candidate.runID)
                try validateHistoricalProofs(events)
                try artifacts.retireFinishedRun(runID: candidate.runID,
                    journalEntry: candidate.entry, events: events, storage: storage)
            }
            let (candidateBytes, candidateOverflow) = candidate.entry.byteCount
                .addingReportingOverflow(candidate.artifactBytes)
            guard !candidateOverflow, candidateBytes <= bytes else {
                throw JournalError.capacity
            }
            bytes -= candidateBytes
            occupancy = try artifacts.retentionOccupancy()
            optional.removeFirst()
        }
        try requireOptionalCapacity(scan())
    }

    private func validateHistoricalProofs(_ events: [JournalEvent]) throws {
        let finished = events.last?.phase == .finished
        for terminal in events where terminal.phase == .itemTerminal {
            guard let operation = terminal.operationID else { throw JournalError.corrupt }
            guard let proof = terminal.proof else {
                if finished { throw JournalError.corrupt }
                continue
            }
            let archive = try artifacts.historicalProof(proof)
            guard archive.runID == terminal.runID,
                  archive.operationID == operation,
                  archive.terminalStatus == terminal.status else {
                throw JournalError.corrupt
            }
            if let manifest = archive.manifest { _ = try artifacts.load(manifest) }
        }
    }

    private func terminalArtifacts(_ events: [JournalEvent]) throws
        -> (bytes: Int, count: Int) {
        var proofIDs = Set<UUID>()
        var manifestIDs = Set<UUID>()
        var total = 0
        var count = 0
        for terminal in events where terminal.phase == .itemTerminal {
            guard let proof = terminal.proof, proofIDs.insert(proof.id).inserted else {
                throw JournalError.corrupt
            }
            let archive = try artifacts.historicalProof(proof)
            let (withProof, proofOverflow) = total.addingReportingOverflow(proof.encodedBytes)
            guard !proofOverflow else { throw JournalError.capacity }
            total = withProof
            let (withProofCount, proofCountOverflow) = count.addingReportingOverflow(1)
            guard !proofCountOverflow else { throw JournalError.capacity }
            count = withProofCount
            if let manifest = archive.manifest, manifestIDs.insert(manifest.id).inserted {
                _ = try artifacts.load(manifest)
                let (withManifest, manifestOverflow) = total.addingReportingOverflow(
                    manifest.encodedBytes)
                guard !manifestOverflow else { throw JournalError.capacity }
                total = withManifest
                let (nextCount, countOverflow) = count.addingReportingOverflow(
                    manifest.artifactCount)
                guard !countOverflow else { throw JournalError.capacity }
                count = nextCount
            }
        }
        return (total, count)
    }

    private static func validateHistorical(_ event: JournalEvent,
                                           previous: [JournalEvent]) throws {
        guard event.sequence == (try JournalSequence.next(after: previous.last?.sequence ?? 0)),
              previous.last?.phase != .finished else { throw JournalError.invalidTransition }
        switch event.phase {
        case .planned:
            guard previous.isEmpty, event.operationID == nil,
                  event.status == nil, event.proof == nil else {
                throw JournalError.invalidTransition
            }
        case .confirmed:
            guard previous.count == 1, previous.first?.phase == .planned,
                  event.operationID == nil, event.status == nil,
                  event.proof == nil else { throw JournalError.invalidTransition }
        case .started:
            guard previous.contains(where: { $0.phase == .confirmed }), let operation = event.operationID,
                  event.status == nil, event.proof == nil,
                  !previous.contains(where: { $0.operationID == operation }) else { throw JournalError.invalidTransition }
        case .itemTerminal:
            guard let operation = event.operationID, event.status != nil,
                  previous.contains(where: { $0.phase == .started && $0.operationID == operation }),
                  !previous.contains(where: { $0.phase == .itemTerminal && $0.operationID == operation }) else {
                throw JournalError.invalidTransition
            }
        case .finished:
            let started = Set(previous.filter { $0.phase == .started }.compactMap(\.operationID))
            let terminal = Set(previous.filter { $0.phase == .itemTerminal }.compactMap(\.operationID))
            guard previous.contains(where: { $0.phase == .confirmed }),
                  event.operationID == nil, event.status == nil, event.proof == nil,
                  started == terminal else { throw JournalError.invalidTransition }
        }
    }

    private func validateAdmission(_ event: JournalEvent, previous: [JournalEvent],
                                   intents: [PendingEffectIntent]) throws {
        switch event.phase {
        case .planned, .confirmed:
            return
        case .started:
            guard let operation = event.operationID,
                  intents.contains(where: {
                      $0.runID == event.runID && $0.operationID == operation
                  }) else { throw JournalError.invalidTransition }
        case .itemTerminal:
            guard let operation = event.operationID else { throw JournalError.invalidTransition }
            if let proof = event.proof {
                guard let intent = intents.first(where: {
                    $0.runID == event.runID && $0.operationID == operation
                }) else { throw JournalError.invalidTransition }
                _ = try artifacts.proof(proof, for: intent)
            }
        case .finished:
            let runIntents = intents.filter { $0.runID == event.runID }
            let terminals = previous.filter { $0.phase == .itemTerminal }
            guard runIntents.count == terminals.count else {
                throw JournalError.invalidTransition
            }
            for intent in runIntents {
                guard let terminal = terminals.first(where: {
                    $0.operationID == intent.operationID
                }), let proof = terminal.proof else {
                    throw JournalError.invalidTransition
                }
                _ = try artifacts.proof(proof, for: intent)
            }
        }
    }
    private static func integer(_ value: UInt64, count: Int) -> Data {
        Data((0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private static func frame(_ payload: Data, sequence: UInt64) -> Data {
        let body = integer(UInt64(payload.count), count: 4) + integer(sequence, count: 8) + payload
        return body + Data(SHA256.hash(data: header + body))
    }
    private static func parse(_ bytes: Data, runID: UUID) throws -> [JournalEvent] {
        guard bytes.count <= JournalFiles.maximumBytes else { throw JournalError.capacity }
        guard bytes.count >= 8, bytes.prefix(4) == header.prefix(4) else { throw JournalError.corrupt }
        guard bytes[4] == 0, bytes[5] == 1 else { throw JournalError.unsupportedSchema }
        guard bytes[6] == 0, bytes[7] == 0, bytes.count > 8 else { throw JournalError.corrupt }
        var offset = 8, result: [JournalEvent] = []
        while offset < bytes.count {
            guard bytes.count - offset >= 12 else { throw JournalError.corrupt }
            let length = bytes[offset..<(offset + 4)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard length <= 65_536 else { throw JournalError.capacity }
            guard length > 0, bytes.count - offset >= 44 + Int(length) else { throw JournalError.corrupt }
            let sequence = bytes[(offset + 4)..<(offset + 12)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let end = offset + 12 + Int(length)
            let body = bytes[offset..<end]
            guard Data(SHA256.hash(data: header + body)) == bytes[end..<(end + 32)] else { throw JournalError.corrupt }
            let event: JournalEvent
            do { event = try JSONDecoder().decode(JournalEvent.self, from: bytes[(offset + 12)..<end]) }
            catch { throw JournalError.corrupt }
            guard event.runID == runID, event.sequence == sequence else { throw JournalError.corrupt }
            do { try validateHistorical(event, previous: result) }
            catch { throw JournalError.corrupt }
            result.append(event)
            offset = end + 32
        }
        return result
    }
}
