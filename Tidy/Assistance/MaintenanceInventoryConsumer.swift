import Dispatch
import Foundation
import TidyCore

struct MaintenanceRuleStatus: Equatable, Identifiable {
    enum State: Equatable {
        case denied
        case eligible
        case delivered
    }

    let id: UUID
    let state: State
    let detail: String
}

struct InstalledMaintenanceInventory {
    let snapshot: DeveloperInventorySnapshot
    let sourcePolicyRevision: UInt64
    let receivedAtMonotonicNanoseconds: UInt64
}

struct MaintenanceInventoryProjection {
    let candidate: MaintenanceCandidate?
    let denialReasons: [String]
}

enum MaintenanceInventoryProjector {
    private static let evidenceLifetimeNanoseconds: UInt64 = 300_000_000_000

    /// Converts only a caller-supplied inventory snapshot. This function does
    /// no filesystem access, tool launch, process inspection, or age inference.
    static func project(grant: MaintenanceGrant,
                        installation: InstalledMaintenanceInventory)
        -> MaintenanceInventoryProjection {
        guard installation.sourcePolicyRevision == grant.policyRevision else {
            return denied("The inventory was captured under a different policy revision.")
        }
        let matches = installation.snapshot.entries.filter { entry in
            guard entry.record.adapterID == AppleDeveloperAdapter.adapterID,
                  entry.record.adapterVersion == AppleDeveloperAdapter.contractVersion,
                  entry.record.kind == "apple:Library/Developer/Xcode/DerivedData",
                  case .filesystem(let identity) = entry.record.resource else { return false }
            return identity.canonicalPath == grant.root.canonicalPath
                && identity.volumeID == grant.root.volumeID
                && identity.device == grant.root.device
                && identity.inode == grant.root.inode
        }
        guard matches.count == 1, let entry = matches.first else {
            return denied(matches.isEmpty
                ? "No exact DerivedData inventory record matches the saved root identity."
                : "More than one inventory record matches the saved root identity.")
        }

        let (validUntil, overflow) = installation.receivedAtMonotonicNanoseconds
            .addingReportingOverflow(evidenceLifetimeNanoseconds)
        guard !overflow else { return denied("The monotonic evidence window is invalid.") }

        var reasons: [String] = []
        let record = entry.record
        if record.allocatedBytes == nil || record.allocatedBytes.map({ $0 < 0 }) == true {
            reasons.append("Allocated size is unknown.")
        }
        let exactConfidence: Bool
        switch record.confidence {
        case .exact: exactConfidence = true
        case .partial, .unknown: exactConfidence = false
        }
        if record.ownerIDs.isEmpty || !exactConfidence {
            reasons.append("Complete owner evidence is unknown.")
        }
        let activity: MaintenanceActivity
        switch record.activity {
        case .inactiveConfirmed: activity = .knownIdle
        case .unknown:
            activity = .unknown
            reasons.append("Producer activity is unknown.")
        case .running, .pinned, .recent:
            activity = .active
            reasons.append("The cache is active or recently active.")
        }
        // DeveloperInventorySnapshot has no producer-backed cache-age field.
        // observedAt is scan time and must never be reinterpreted as cache age.
        reasons.append("Cache age evidence is unavailable.")
        let candidate = MaintenanceCandidate(
            capabilityID: grant.capabilityID, root: grant.root,
            allocatedBytes: record.allocatedBytes, itemCount: 1, ageDays: nil,
            activity: activity, evidenceOrigin: .supportedAdapter,
            ownerEvidenceKnown: !record.ownerIDs.isEmpty && exactConfidence,
            evidenceValidUntilMonotonicNanoseconds: validUntil,
            immutableOrQuiescentScopeHeld: false, ruleVersion: grant.ruleVersion,
            policyRevision: installation.sourcePolicyRevision)
        return MaintenanceInventoryProjection(candidate: candidate, denialReasons: reasons)
    }

    private static func denied(_ reason: String) -> MaintenanceInventoryProjection {
        MaintenanceInventoryProjection(candidate: nil, denialReasons: [reason])
    }
}

extension MaintenanceDenial {
    var maintenanceStatusText: String {
        switch self {
        case .featureDisabled: return "Maintenance is disabled by the acknowledged policy."
        case .authorityMissing: return "The notify-only rule has no current local authority."
        case .ruleRevoked: return "The notify-only rule was revoked."
        case .identityMismatch: return "The saved root identity does not match inventory."
        case .policyChanged: return "The policy changed after this rule or inventory was captured."
        case .ruleChanged: return "The rule changed after inventory was captured."
        case .measurementUnknown: return "Required size, item count, or age evidence is unknown."
        case .ownerUnknown: return "Complete owner evidence is unknown."
        case .staleEvidence: return "The explicit inventory evidence is stale."
        case .activeOrUnknown: return "Producer activity is active or unknown."
        case .importedOrManualEvidence: return "The evidence did not come from the supported adapter."
        case .ageTooYoung: return "The cache is younger than the saved minimum age."
        case .capExceeded: return "The observed cache exceeds the saved byte or item cap."
        case .capabilityNotAllowlisted: return "The capability is not in the unattended allowlist."
        case .immutableScopeMissing: return "A supported immutable or quiescent scope is unavailable."
        case .frequencyLimited: return "The saved per-rule notification interval has not elapsed."
        case .clockDiscontinuity: return "Clock continuity cannot prove that the interval elapsed."
        case .unknownReview, .notSelected, .expiredReview:
            return "The maintenance review is no longer current."
        }
    }
}
