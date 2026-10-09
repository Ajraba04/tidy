import Foundation
import CryptoKit

public enum RecoveryDecision: Equatable, Sendable {
    case blockMutations, requireFreshReview
    public static func forUnfinishedEffect(quiescenceProven: Bool) -> Self {
        quiescenceProven ? .requireFreshReview : .blockMutations
    }
}
enum JournalPhase: String, Codable, Sendable { case planned, confirmed, started, itemTerminal, finished, abandoned }
struct JournalEvent: Codable, Equatable, Sendable {
    let runID: UUID
    let sequence: UInt64
    let phase: JournalPhase
    let operationID: UUID?
    let status: EffectStatus?
    let reason: String?
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
final class RunJournal {
    private let store: MutationAdmissionStore
    private let storage: any JournalStorage
    private var historyEnabled = true
    private var historyDays = 30
    private var historyBytes = 10_485_760
    private static let header = Data([0x54, 0x44, 0x59, 0x4a, 0, 1, 0, 0])
    private struct Summary: Equatable {
        let entry: JournalStorageEntry
        let runID: UUID
        let finished: Bool
    }

    init(store: MutationAdmissionStore, storage: any JournalStorage) throws {
        self.store = store
        self.storage = storage
        try checkLock()
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
        return try observed { try Self.parse(bytes, runID: runID, intents: intents) }
    }

    func append(_ event: JournalEvent) throws {
        try checkLock()
        let previous = try load(runID: event.runID)
        let intents = try store.unfinishedIntentsWhileLocked()
        if event.phase == .started {
            guard intents.contains(where: { $0.runID == event.runID && $0.operationID == event.operationID }) else {
                throw JournalError.invalidTransition
            }
        }
        try Self.validate(event, previous: previous, intents: intents)
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
        if event.phase == .finished || event.phase == .abandoned { try retain(now: Date()) }
    }

    func persistIntent(_ intent: PendingEffectIntent) throws {
        try checkLock()
        let previous = try load(runID: intent.runID)
        guard previous.contains(where: { $0.phase == .confirmed }),
              previous.last?.phase != .finished, previous.last?.phase != .abandoned else { throw JournalError.invalidTransition }
        let summaries = try scan()
        guard summaries.filter({ !$0.finished }).count <= 8 else { throw JournalError.capacity }
        try requireOptionalCapacity(summaries)
        do { try store.persistIntentWhileLocked(intent) }
        catch let error as JournalError { throw error }
        catch { throw JournalError.unavailable }
    }
    func recordChild(_ intent: PendingEffectIntent) throws {
        try checkLock()
        _ = try load(runID: intent.runID)
        do { try store.persistIntentWhileLocked(intent, update: .capturedChild) }
        catch let error as JournalError { throw error }
        catch { throw JournalError.unavailable }
    }
    func finish(runID: UUID) throws {
        try checkLock()
        let previous = try load(runID: runID)
        try append(JournalEvent(runID: runID, sequence: JournalSequence.next(after: previous.last?.sequence ?? 0),
            phase: .finished, operationID: nil, status: nil, reason: nil))
    }
    func completeFilesystemEffect(_ effect: DerivedDataEffectAdapter.Effect,
                                  runID: UUID, sequence: UInt64) throws {
        try append(JournalEvent(runID: runID, sequence: sequence, phase: .itemTerminal,
            operationID: effect.operationID, status: EffectAccounting.aggregateStatus(effect.outcomes),
            reason: "Synchronous filesystem effect returned; no child process was submitted."))
        // Ordering matters: a crash between publication and release stays blocked.
        try store.completeFilesystemIntent(effect, runID: runID)
    }
    /// One bounded launch/retry pass. Never resumes effects or reconciles a child process.
    func reconcileSynchronousFilesystemEffects() throws {
        let summaries = try scan()
        let intents = try store.unfinishedIntentsWhileLocked()
        guard intents.count <= 8 else { throw JournalError.capacity }
        for intent in intents where intent.adapterID == DerivedDataEffectAdapter.acceptedItemID
            && intent.executablePath.isEmpty && intent.childPID == nil && intent.phase == .prepared {
            var events = try load(runID: intent.runID)
            if !events.contains(where: { $0.phase == .started && $0.operationID == intent.operationID }) {
                try append(JournalEvent(runID: intent.runID,
                    sequence: JournalSequence.next(after: events.last?.sequence ?? 0), phase: .started,
                    operationID: intent.operationID, status: nil, reason: "Interrupted filesystem submission."))
                events = try load(runID: intent.runID)
            }
            if !events.contains(where: { $0.phase == .itemTerminal && $0.operationID == intent.operationID }) {
                try append(JournalEvent(runID: intent.runID,
                    sequence: JournalSequence.next(after: events.last?.sequence ?? 0), phase: .itemTerminal,
                    operationID: intent.operationID, status: .uncertain,
                    reason: "Previous synchronous caller is quiescent. Removed leaves are unknown; fresh review required."))
            }
            try store.reconcileQuiescentFilesystemIntent(intent)
        }
        let remaining = try store.unfinishedIntentsWhileLocked()
        for summary in summaries where !summary.finished && !remaining.contains(where: { $0.runID == summary.runID }) {
            let events = try load(runID: summary.runID)
            if events.last?.phase == .planned {
                try append(JournalEvent(runID: summary.runID, sequence: 2, phase: .abandoned,
                    operationID: nil, status: nil, reason: "Plan was never confirmed."))
                continue
            }
            let started = Set(events.filter { $0.phase == .started }.compactMap(\.operationID))
            let terminal = Set(events.filter { $0.phase == .itemTerminal }.compactMap(\.operationID))
            guard started == terminal else { continue }
            try append(JournalEvent(runID: summary.runID,
                sequence: JournalSequence.next(after: events.last?.sequence ?? 0), phase: .finished,
                operationID: nil, status: nil, reason: "Closed interrupted record. Unrecorded legacy effects remain unknown."))
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
            let (sum, overflow) = $0.addingReportingOverflow($1.entry.byteCount)
            guard !overflow else { throw JournalError.capacity }
            return sum
        }
    }
    /// The segment and decoded events die with this call; only metadata escapes.
    private func summarize(_ entry: JournalStorageEntry, intents: [PendingEffectIntent]) throws -> Summary {
        guard let runID = try JournalFiles.runID(entry.name) else { throw JournalError.corrupt }
        let bytes = try storage.read(name: entry.name)
        guard bytes.count == entry.byteCount else { throw JournalError.unavailable }
        let events = try Self.parse(bytes, runID: runID, intents: intents)
        let finished = (events.last?.phase == .finished || events.last?.phase == .abandoned)
            && !intents.contains(where: { $0.runID == runID })
        return Summary(entry: entry, runID: runID, finished: finished)
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
        let summaries = try scan() // Validate ALL files before the first deletion.
        var optional = summaries.filter(\.finished).sorted {
            let a = $0.entry, b = $1.entry
            if a.modifiedSeconds != b.modifiedSeconds { return a.modifiedSeconds < b.modifiedSeconds }
            if a.modifiedNanoseconds != b.modifiedNanoseconds { return a.modifiedNanoseconds < b.modifiedNanoseconds }
            return a.name.utf8.lexicographicallyPrecedes(b.name.utf8)
        }
        var bytes = try Self.total(optional)
        let cutoff = now.addingTimeInterval(-Double(historyDays) * 86_400)
        while let candidate = optional.first {
            guard !historyEnabled || candidate.entry.modifiedAt < cutoff || bytes > historyBytes else { break }
            try checkLock()
            try observed {
                let intents = try store.unfinishedIntentsWhileLocked()
                guard !intents.contains(where: { $0.runID == candidate.runID }),
                      try summarize(candidate.entry, intents: intents) == candidate else { throw JournalError.unavailable }
                try storage.removeJournal(candidate.entry)
            }
            bytes -= candidate.entry.byteCount
            optional.removeFirst()
        }
        try requireOptionalCapacity(scan())
    }

    private static func validate(_ event: JournalEvent, previous: [JournalEvent],
                                 intents: [PendingEffectIntent]) throws {
        guard event.sequence == (try JournalSequence.next(after: previous.last?.sequence ?? 0)),
              previous.last?.phase != .finished, previous.last?.phase != .abandoned else { throw JournalError.invalidTransition }
        switch event.phase {
        case .planned:
            guard previous.isEmpty, event.operationID == nil, event.status == nil else { throw JournalError.invalidTransition }
        case .abandoned:
            guard previous.count == 1, previous.first?.phase == .planned,
                  event.operationID == nil, event.status == nil,
                  !intents.contains(where: { $0.runID == event.runID }) else { throw JournalError.invalidTransition }
        case .confirmed:
            guard previous.count == 1, previous.first?.phase == .planned,
                  event.operationID == nil, event.status == nil else { throw JournalError.invalidTransition }
        case .started:
            guard previous.contains(where: { $0.phase == .confirmed }), let operation = event.operationID,
                  event.status == nil,
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
            guard previous.contains(where: { $0.phase == .confirmed }), event.operationID == nil, event.status == nil,
                  started == terminal,
                  !intents.contains(where: { $0.runID == event.runID }) else { throw JournalError.invalidTransition }
        }
    }
    private static func integer(_ value: UInt64, count: Int) -> Data {
        Data((0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private static func frame(_ payload: Data, sequence: UInt64) -> Data {
        let body = integer(UInt64(payload.count), count: 4) + integer(sequence, count: 8) + payload
        return body + Data(SHA256.hash(data: header + body))
    }
    private static func parse(_ bytes: Data, runID: UUID, intents: [PendingEffectIntent]) throws -> [JournalEvent] {
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
            do { try validate(event, previous: result, intents: intents) }
            catch { throw JournalError.corrupt }
            result.append(event)
            offset = end + 32
        }
        for event in result where event.phase == .started {
            guard result.contains(where: { $0.phase == .itemTerminal && $0.operationID == event.operationID })
                || intents.contains(where: { $0.runID == runID && $0.operationID == event.operationID }) else {
                throw JournalError.corrupt
            }
        }
        return result
    }
}
