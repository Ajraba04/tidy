import Foundation

public enum EffectStatus: String, Codable, Sendable {
    case succeeded, partial, failed, skipped, cancelled, uncertain
}

public struct ByteObservation: Codable, Equatable, Sendable {
    public let bytes: Int64?
    public let explanation: String?
    public init(bytes: Int64?, explanation: String?) {
        self.bytes = bytes
        self.explanation = explanation
    }
}

public struct TargetEffectOutcome: Codable, Equatable, Sendable {
    public let relativePath: String
    public let status: EffectStatus
    public let reason: String?
    public let completedRemovals: Int
    public let removedApparentBytes: ByteObservation
    public let removedAllocatedBytes: ByteObservation
    public let provenReclaimedBytes: ByteObservation

    public init(relativePath: String, status: EffectStatus, reason: String?,
                completedRemovals: Int, removedApparentBytes: ByteObservation,
                removedAllocatedBytes: ByteObservation, provenReclaimedBytes: ByteObservation) {
        self.relativePath = relativePath
        self.status = status
        self.reason = reason
        self.completedRemovals = completedRemovals
        self.removedApparentBytes = removedApparentBytes
        self.removedAllocatedBytes = removedAllocatedBytes
        self.provenReclaimedBytes = provenReclaimedBytes
    }
}

public struct VolumeSpaceObservation: Codable, Equatable, Sendable {
    public let volumeID: UUID
    public let before: ByteObservation
    public let after: ByteObservation
    public init(volumeID: UUID, before: ByteObservation, after: ByteObservation) {
        self.volumeID = volumeID
        self.before = before
        self.after = after
    }
    public var signedDelta: ByteObservation {
        guard let before = before.bytes, let after = after.bytes, before >= 0, after >= 0 else {
            return ByteObservation(bytes: nil, explanation: "Before or after measurement unavailable or invalid")
        }
        let (delta, overflow) = after.subtractingReportingOverflow(before)
        return ByteObservation(bytes: overflow ? nil : delta,
                               explanation: overflow ? "Byte delta overflow" : nil)
    }
}

enum EffectAccounting {
    static func checkedSum(_ values: [ByteObservation]) -> ByteObservation {
        var total: Int64 = 0
        for value in values {
            guard let bytes = value.bytes, bytes >= 0 else {
                return ByteObservation(bytes: nil, explanation: "A required measurement is unavailable or invalid")
            }
            let (sum, overflow) = total.addingReportingOverflow(bytes)
            guard !overflow else { return ByteObservation(bytes: nil, explanation: "Byte sum overflow") }
            total = sum
        }
        return ByteObservation(bytes: total, explanation: nil)
    }
    static func aggregateStatus(_ values: [TargetEffectOutcome]) -> EffectStatus {
        if values.contains(where: { $0.status == .uncertain }) { return .uncertain }
        if values.contains(where: { $0.completedRemovals > 0 }) {
            return values.allSatisfy { $0.status == .succeeded && $0.completedRemovals > 0 }
                ? .succeeded : .partial
        }
        if values.contains(where: { $0.status == .failed }) { return .failed }
        if values.contains(where: { $0.status == .cancelled }) { return .cancelled }
        return .skipped
    }
    static func toolReclaimedBytes(exitCode: Int32, before: ByteObservation,
                                   after: ByteObservation) -> ByteObservation {
        ByteObservation(bytes: nil, explanation: exitCode == 0
            ? "Tool exit and volume delta do not prove attributable physical reclaim"
            : "Failed tool did not establish physical reclaim")
    }
}

/// The outcome of executing one `PlannedItem`.
public struct ItemResult: Identifiable, Sendable, Codable {
    /// Nil means the record did not observe memory reclaim; explicit zero is measured.
    public let measuredReclaimedMemoryBytes: Int64?
    public let id: String
    public let title: String
    public let freedBytes: Int64
    /// RAM returned by this item, if any. Separate from `freedBytes`
    /// because disk and memory are different resources: summing them would
    /// produce a headline number that is wrong about both.
    public let reclaimedMemoryBytes: Int64
    public let succeeded: Bool
    public let message: String?
    public let targetOutcomes: [TargetEffectOutcome]?
    public let effectStatus: EffectStatus?

    public init(
        id: String,
        title: String,
        freedBytes: Int64,
        reclaimedMemoryBytes: Int64? = nil,
        succeeded: Bool,
        message: String? = nil,
        targetOutcomes: [TargetEffectOutcome]? = nil,
        effectStatus: EffectStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.freedBytes = freedBytes
        self.reclaimedMemoryBytes = reclaimedMemoryBytes ?? 0
        self.measuredReclaimedMemoryBytes = reclaimedMemoryBytes
        self.succeeded = succeeded
        self.message = message
        self.targetOutcomes = targetOutcomes
        self.effectStatus = effectStatus
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, freedBytes, reclaimedMemoryBytes, succeeded, message, targetOutcomes, effectStatus
        case measuredReclaimedMemoryBytes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        freedBytes = try values.decode(Int64.self, forKey: .freedBytes)
        let legacyMemory = try values.decodeIfPresent(Int64.self, forKey: .reclaimedMemoryBytes)
        reclaimedMemoryBytes = legacyMemory ?? 0
        measuredReclaimedMemoryBytes = values.contains(.measuredReclaimedMemoryBytes)
            ? try values.decodeIfPresent(Int64.self, forKey: .measuredReclaimedMemoryBytes) : legacyMemory
        succeeded = try values.decode(Bool.self, forKey: .succeeded)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        targetOutcomes = try values.decodeIfPresent([TargetEffectOutcome].self, forKey: .targetOutcomes)
        effectStatus = try values.decodeIfPresent(EffectStatus.self, forKey: .effectStatus)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(freedBytes, forKey: .freedBytes)
        try values.encode(reclaimedMemoryBytes, forKey: .reclaimedMemoryBytes)
        // Encode explicit null so the compatibility zero cannot become a measurement on reopen.
        try values.encode(measuredReclaimedMemoryBytes, forKey: .measuredReclaimedMemoryBytes)
        try values.encode(succeeded, forKey: .succeeded)
        try values.encodeIfPresent(message, forKey: .message)
        try values.encodeIfPresent(targetOutcomes, forKey: .targetOutcomes)
        try values.encodeIfPresent(effectStatus, forKey: .effectStatus)
    }
}

/// The record of one `CleanEngine.execute` run, matching what the shell
/// script appended to its log file, but structured and written to
/// `runs.jsonl` as one JSON object per line.
public struct RunReport: Sendable, Codable {
    public var measuredTotalReclaimedMemoryBytes: Int64? {
        guard !results.isEmpty else { return nil }
        return EffectAccounting.checkedSum(results.map {
            ByteObservation(bytes: $0.measuredReclaimedMemoryBytes, explanation: nil)
        }).bytes
    }
    public let tier: Tier
    public let results: [ItemResult]
    public let startedAt: Date
    public let finishedAt: Date
    public let freeSpaceBeforeBytes: Int64
    public let freeSpaceAfterBytes: Int64
    public let disposition: RunDisposition
    public let coordinatorMeasurementsAvailable: Bool?
    public let volumeObservations: [VolumeSpaceObservation]?
    public let provenReclaimedBytes: ByteObservation

    public init(
        tier: Tier,
        results: [ItemResult],
        startedAt: Date,
        finishedAt: Date,
        freeSpaceBeforeBytes: Int64,
        freeSpaceAfterBytes: Int64,
        disposition: RunDisposition = .completed,
        coordinatorMeasurementsAvailable: Bool? = nil,
        volumeObservations: [VolumeSpaceObservation]? = nil,
        provenReclaimedBytes: ByteObservation? = nil,
        toolExitCode: Int32? = nil
    ) {
        self.tier = tier
        self.results = results
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.freeSpaceBeforeBytes = freeSpaceBeforeBytes
        self.freeSpaceAfterBytes = freeSpaceAfterBytes
        self.disposition = disposition
        self.coordinatorMeasurementsAvailable = coordinatorMeasurementsAvailable
        self.volumeObservations = volumeObservations
        // A tool's actual exit code is optional report data, never inferred
        // from legacy success/estimates and never an execution capability.
        if let provenReclaimedBytes {
            self.provenReclaimedBytes = provenReclaimedBytes
        } else if let toolExitCode {
            self.provenReclaimedBytes = EffectAccounting.toolReclaimedBytes(exitCode: toolExitCode,
                before: ByteObservation(bytes: nil, explanation: "No accepted measurement"),
                after: ByteObservation(bytes: nil, explanation: "No accepted measurement"))
        } else {
            self.provenReclaimedBytes = ByteObservation(bytes: nil, explanation: "Physical reclaim was not measured")
        }
    }

    public var totalFreedBytes: Int64 {
        results.reduce(0) { $0 + $1.freedBytes }
    }

    private enum CodingKeys: String, CodingKey {
        case tier, results, startedAt, finishedAt, freeSpaceBeforeBytes, freeSpaceAfterBytes
        case disposition, coordinatorMeasurementsAvailable, volumeObservations, provenReclaimedBytes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tier = try values.decode(Tier.self, forKey: .tier)
        results = try values.decode([ItemResult].self, forKey: .results)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        finishedAt = try values.decode(Date.self, forKey: .finishedAt)
        freeSpaceBeforeBytes = try values.decode(Int64.self, forKey: .freeSpaceBeforeBytes)
        freeSpaceAfterBytes = try values.decode(Int64.self, forKey: .freeSpaceAfterBytes)
        disposition = try values.decodeIfPresent(RunDisposition.self, forKey: .disposition) ?? .completed
        coordinatorMeasurementsAvailable = try values.decodeIfPresent(Bool.self, forKey: .coordinatorMeasurementsAvailable)
        volumeObservations = try values.decodeIfPresent([VolumeSpaceObservation].self, forKey: .volumeObservations)
        provenReclaimedBytes = try values.decodeIfPresent(ByteObservation.self, forKey: .provenReclaimedBytes)
            ?? ByteObservation(bytes: nil, explanation: "Historical record did not measure this value")
    }

    public var measuredDeltaBytes: Int64 {
        max(0, freeSpaceAfterBytes - freeSpaceBeforeBytes)
    }

    public var totalReclaimedMemoryBytes: Int64 {
        results.reduce(0) { $0 + $1.reclaimedMemoryBytes }
    }

    /// True when the estimate and the observed free-space change disagree
    /// by more than a rounding-level margin, which is the moment the app
    /// owes the user an explanation rather than a number.
    public var freedFigureNeedsReconciling: Bool {
        guard totalFreedBytes > 0 else { return false }
        let difference = abs(totalFreedBytes - measuredDeltaBytes)
        return difference > max(64 * 1024 * 1024, totalFreedBytes / 10)
    }
}
