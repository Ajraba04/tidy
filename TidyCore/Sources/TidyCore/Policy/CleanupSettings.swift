import Foundation

public enum VolumeField: Equatable, Codable, Sendable {
    case inherit
    case automatic
    case fixedGiB(Int64)
}

public struct VolumeOverride: Equatable, Codable, Sendable {
    public var target: VolumeField
    public var warning: VolumeField
    public var clear: VolumeField

    public init(target: VolumeField, warning: VolumeField, clear: VolumeField) {
        self.target = target
        self.warning = warning
        self.clear = clear
    }
}

public struct PolicyInputs: Equatable, Sendable {
    public var layers: [PolicyLayer: PolicyValues]
    public var selectedVolumeID: UUID?
    public var approvedVolumeIDs: Set<UUID>
    public var capacityBytes: Int64?
    public var logicalCPUCount: Int
    public var lowPower: Bool
    public var seriousThermal: Bool
    public var critical: Bool
    public var mandatoryExclusions: Set<String>

    public init(layers: [PolicyLayer: PolicyValues], selectedVolumeID: UUID?,
                approvedVolumeIDs: Set<UUID>, capacityBytes: Int64?, logicalCPUCount: Int,
                lowPower: Bool, seriousThermal: Bool, critical: Bool,
                mandatoryExclusions: Set<String>) {
        self.layers = layers
        self.selectedVolumeID = selectedVolumeID
        self.approvedVolumeIDs = approvedVolumeIDs
        self.capacityBytes = capacityBytes
        self.logicalCPUCount = logicalCPUCount
        self.lowPower = lowPower
        self.seriousThermal = seriousThermal
        self.critical = critical
        self.mandatoryExclusions = mandatoryExclusions
    }
}

public enum FieldSource: Equatable, Sendable {
    case builtIn
    case layer(PolicyLayer)
    case volume(PolicyLayer, UUID)
    case immutable
    case localAuthority
}

public enum FieldReason: String, Sendable {
    case defaultValue, replaced, denied, union, strictestCap, automatic, inherited
    case preset, cpuCeiling, pressureCeiling, capacityUnavailable, invalidForVolume
    case unmatchedVolume, authorityUnavailable, protected, quarantine
    case notConfigured
}

public enum EffectiveValue: Equatable, Sendable {
    case stored(SettingValue)
    case bytes(Int64)
    case unavailable(FieldReason)
}

public struct EffectiveField: Equatable, Sendable {
    public let value: EffectiveValue
    public let sources: [FieldSource]
    public let reason: FieldReason

    public init(value: EffectiveValue, sources: [FieldSource], reason: FieldReason) {
        self.value = value
        self.sources = sources
        self.reason = reason
    }
}

public enum ScanAdmission: Equatable, Sendable {
    case paused, userRequestedOnly, discretionaryAllowed
}

public struct EffectivePolicy: Equatable, Sendable {
    public let fields: [SettingID: EffectiveField]
    public let allowedFeatures: Set<String>
    public let walkWorkers: Int
    public let readOnlyProcesses: Int
    public let scanAdmission: ScanAdmission
    public let manualBatchBytes: Int64
    public let manualBatchItems: Int
    public let exclusions: Set<String>

    public init(fields: [SettingID: EffectiveField], allowedFeatures: Set<String>,
                walkWorkers: Int, readOnlyProcesses: Int, scanAdmission: ScanAdmission,
                manualBatchBytes: Int64, manualBatchItems: Int, exclusions: Set<String>) {
        self.fields = fields
        self.allowedFeatures = allowedFeatures
        self.walkWorkers = walkWorkers
        self.readOnlyProcesses = readOnlyProcesses
        self.scanAdmission = scanAdmission
        self.manualBatchBytes = manualBatchBytes
        self.manualBatchItems = manualBatchItems
        self.exclusions = exclusions
    }
}

enum CleanupSettings {
    static var rows: [SettingDefinition] {
        let all = Set(PolicyLayer.allCases)
        return [
            row("scope.excludedRoots", .setIDs, .strings([]), .exclusions, .restriction, .invalidate, all, "scope"),
            row("scope.pinnedProjects", .setIDs, .strings([]), .pins, .restriction, .invalidate, all, "scope"),
            row("scope.currentProject", .optionalProjectID, .null, .projectID, .preference, .invalidate, all, "scope"),
            row("cleanup.inactiveDays", .integer, .integer(60), .integer(7, 365), .preference, .invalidate, all, "cleanup"),
            row("cleanup.transcriptDays", .integer, .integer(45), .integer(7, 365), .preference, .invalidate, all, "cleanup"),
            row("cleanup.recentProtectionDays", .integer, .integer(7), .integer(1, 90), .preference, .invalidate, all, "cleanup"),
            row("cleanup.warmProjectCount", .integer, .integer(5), .integer(0, 50), .preference, .invalidate, all, "cleanup"),
            row("cleanup.minimumCandidateMiB", .integer, .integer(100), .integer(1, 102_400), .preference, .invalidate, all, "cleanup"),
            row("cleanup.minimumItemMiB", .integer, .integer(1), .integer(0, 102_400), .preference, .invalidate, all, "cleanup"),
            row("cleanup.retainRecentArtifacts", .integer, .integer(2), .integer(0, 100), .preference, .invalidate, all, "cleanup"),
            row("cleanup.costCeiling", .choice, .choice("low"), .choices(["low", "medium", "high"]), .preference, .invalidate, all, "cleanup"),
            row("cleanup.requestedBatchGiB", .integer, .integer(10), .integer(1, 100), .preference, .invalidate, all, "cleanup"),
            row("cleanup.requestedBatchItems", .integer, .integer(20), .integer(1, 100), .preference, .invalidate, all, "cleanup"),
            row("cleanup.hardBatchGiB", .optionalInteger, .null, .optionalInteger(1, 100), .restriction, .invalidate, all, "cleanup"),
            row("cleanup.hardBatchItems", .optionalInteger, .null, .optionalInteger(1, 100), .restriction, .invalidate, all, "cleanup"),
            row("cleanup.manualInactiveAcknowledgementMinutes", .integer, .integer(10), .integer(1, 30), .preference, .invalidate, all, "cleanup"),
            row("headroom.targetGiB", .optionalInteger, .null, .headroomTarget, .preference, .invalidate, all, "headroom"),
            row("headroom.warningGiB", .optionalInteger, .null, .headroomWarning, .preference, .invalidate, all, "headroom"),
            row("headroom.clearGiB", .optionalInteger, .null, .headroomClear, .preference, .invalidate, all, "headroom")
        ]
    }

    static func volumeRow(id: UUID) -> SettingDefinition {
        row("headroom.volumeOverrides.\(id.uuidString)", .volumeOverride, .null, .volumeOverride,
            .preference, .invalidate, Set(PolicyLayer.allCases), "headroom")
    }
}
