import Foundation

struct ProjectActivityResolution: Equatable, Sendable {
    let activity: ResourceActivity
    let recommendationEligible: Bool
    let reasons: [String]
}

enum ActivityResolver {
    static func inventory(projectID: String, pinnedProjectIDs: Set<String>,
                          currentProjectID: String?) -> ProjectActivityResolution {
        if pinnedProjectIDs.contains(projectID) {
            return ProjectActivityResolution(activity: .pinned,
                recommendationEligible: false,
                reasons: ["User pin protects this project."])
        }
        if currentProjectID == projectID {
            return ProjectActivityResolution(activity: .pinned,
                recommendationEligible: false,
                reasons: ["Current-project selection protects this project."])
        }
        return ProjectActivityResolution(activity: .unknown,
            recommendationEligible: false,
            reasons: [
                "No producer-backed activity proof was supplied.",
                "Dirty and untracked Git state were not inferred from filesystem absence."
            ])
    }

    /// Internal by design: only reviewed adapter evidence and a live producer
    /// exclusion lease can establish `inactiveConfirmed`. Public inventory and
    /// settings inputs cannot construct either proof type.
    static func resolve(resource: ResourceIdentity,
                        adapterID: String,
                        adapterVersion: String,
                        association: ResourceAssociationEvidence?,
                        lease: (any ProducerExclusionLease)?,
                        pinned: Bool,
                        current: Bool,
                        now: Date,
                        monotonicNow: ContinuousClock.Instant)
        -> ProjectActivityResolution {
        if pinned {
            return .init(activity: .pinned, recommendationEligible: false,
                         reasons: ["User pin protects this resource."])
        }
        if current {
            return .init(activity: .pinned, recommendationEligible: false,
                         reasons: ["Current-project selection protects this resource."])
        }
        guard let association else {
            return .init(activity: .unknown, recommendationEligible: false,
                         reasons: ["Ownership association is unavailable."])
        }
        guard let lease else {
            return .init(activity: .unknown, recommendationEligible: false,
                         reasons: ["Producer quiescence lease is unavailable."])
        }
        do {
            try ResourceAuthorityValidator.validateAssociation(association,
                resource: resource, adapterID: adapterID,
                adapterVersion: adapterVersion, now: now)
            try ResourceAuthorityValidator.validateRuntime(lease.proof,
                association: association, resource: resource,
                adapterID: adapterID, adapterVersion: adapterVersion,
                now: now, monotonicAcquiredAt: lease.acquiredAt,
                monotonicDeadline: lease.deadline, monotonicNow: monotonicNow)
            return .init(activity: .inactiveConfirmed, recommendationEligible: true,
                         reasons: ["Complete ownership and fresh producer quiescence proof."])
        } catch {
            return .init(activity: .unknown, recommendationEligible: false,
                         reasons: ["Ownership or runtime proof was incomplete, stale, or unsupported."])
        }
    }
}
