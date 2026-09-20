import Foundation
import Testing
@testable import TidyCore

final class PlanningFixtureLease: ProducerExclusionLease, @unchecked Sendable {
    let proof: RuntimeProducerProof
    let acquiredAt: ContinuousClock.Instant
    let deadline: ContinuousClock.Instant
    init(proof: RuntimeProducerProof, expired: Bool = false) {
        self.proof = proof
        let now = ContinuousClock().now
        acquiredAt = now.advanced(by: .seconds(expired ? -10 : -1))
        deadline = now.advanced(by: .seconds(expired ? -5 : 3))
    }
}

enum PlanningFixtures {
    static let volume = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let gib: Int64 = 1_073_741_824
    static func policy() throws -> EffectivePolicy {
        try PolicyResolver.resolve(.init(layers: [.global: .init(fields: [
            .init(rawValue: "feature.buildPrep"): .bool(true),
            .init(rawValue: "item.safe.xcode.derived-data.enabled"): .bool(true),
            .init(rawValue: "cleanup.minimumItemMiB"): .integer(1),
            .init(rawValue: "cleanup.costCeiling"): .choice("high"),
            .init(rawValue: "cleanup.inactiveDays"): .integer(7)
        ])], selectedVolumeID: volume, approvedVolumeIDs: [volume], capacityBytes: 100 * gib,
            logicalCPUCount: 4, lowPower: false, seriousThermal: false, critical: false,
            mandatoryExclusions: []))
    }

    static func candidate(_ id: String, path: String? = nil, inode: UInt64 = 1,
                          bytes: Int64? = gib, cost: CleanupCost = .low,
                          volume: UUID = volume, proof: Bool = true,
                          expired: Bool = false, incomplete: Bool = false,
                          manual: Bool = false, allocation: AllocationKnowledge = .exclusiveEstimate)
        -> CleanupCandidate {
        let now = Date()
        let resource = ResourceIdentity.filesystem(.init(volumeID: volume, device: 1,
            inode: inode, generation: 1, canonicalPath: path ?? "/fixture/\(id)",
            mode: 0o040700, size: 0, modifiedSeconds: 1, modifiedNanoseconds: 0,
            parentChain: [], manifest: nil))
        let record = InventoryRecord(id: id, adapterID: "fixture.completed-cache",
            adapterVersion: "1", resource: resource, ownerIDs: ["owner"], scopeID: "fixture",
            kind: "completed-cache", capability: .exactResourceMutation,
            allocatedBytes: bytes, confidence: .exact, activity: .inactiveConfirmed,
            observedAt: now, reason: "Synthetic completed object")
        let last = now.addingTimeInterval(-90 * 86_400)
        guard proof else {
            return .init(record: record, catalogID: "safe.xcode.derived-data", cost: cost,
                         lastActivityAt: last, manualRisk: manual, allocation: allocation)
        }
        let association = ResourceAssociationEvidence(adapterID: record.adapterID,
            adapterVersion: "1", resource: resource, producerIDs: ["producer"],
            ownerIDs: ["owner"], sharedOwnerIDs: [],
            completeness: incomplete ? .incomplete : .complete,
            observedAt: now, validUntil: now.addingTimeInterval(60), method: .producerManifest)
        let runtime = RuntimeProducerProof(adapterID: record.adapterID, adapterVersion: "1",
            resource: resource, producerIDs: ["producer"], ownerIDs: ["owner"],
            sharedOwnerIDs: [], completeness: .complete, observedAt: now,
            validUntil: now.addingTimeInterval(4), method: .producerExclusionLease)
        return .init(record: record, catalogID: "safe.xcode.derived-data", cost: cost,
            lastActivityAt: last, manualRisk: manual, allocation: allocation,
            association: association, lease: PlanningFixtureLease(proof: runtime, expired: expired))
    }
}

@Suite("Candidate eligibility and overlap")
struct CandidateRankerTests {
    @Test func requiresFreshCompleteEvidenceAndRespectsProtection() throws {
        let valid = PlanningFixtures.candidate("valid")
        let denied = [PlanningFixtures.candidate("missing", inode: 2, proof: false),
                      PlanningFixtures.candidate("stale", inode: 3, expired: true),
                      PlanningFixtures.candidate("shared-unknown", inode: 4, incomplete: true)]
        let policy = try PlanningFixtures.policy()
        #expect(try CandidateRanker.rank([valid] + denied, policy: policy).eligible.map {
            $0.candidate.record.id
        } == ["valid"])
        #expect(try CandidateRanker.rank([valid], policy: policy,
                                        pinnedOwnerIDs: ["owner"]).eligible.isEmpty)
        #expect(try CandidateRanker.rank([valid], policy: policy,
                                        currentOwnerID: "owner").eligible.isEmpty)
    }

    @Test func deterministicCostOrderingAndAliasesDoNotDoubleCount() throws {
        let candidates = [
            PlanningFixtures.candidate("large-costly", inode: 8, bytes: 8 * PlanningFixtures.gib, cost: .high),
            PlanningFixtures.candidate("parent", path: "/fixture/tree", inode: 2, bytes: 4 * PlanningFixtures.gib),
            PlanningFixtures.candidate("child", path: "/fixture/tree/child", inode: 3),
            PlanningFixtures.candidate("alias", path: "/fixture/alias", inode: 2),
            PlanningFixtures.candidate("z", inode: 4), PlanningFixtures.candidate("a", inode: 5)
        ]
        let result = try CandidateRanker.rank(candidates, policy: PlanningFixtures.policy())
        #expect(result.eligible.map { $0.candidate.record.id } == ["parent", "a", "z", "large-costly"])
        #expect(result.blocked.count == 2)
        let duplicate = try CandidateRanker.rank([candidates[0], candidates[0]],
                                                  policy: PlanningFixtures.policy())
        #expect(duplicate.eligible.isEmpty)
    }

    @Test func manualSharedUnknownAndInvalidSizesStayOutOfRecommendations() throws {
        let candidates = [PlanningFixtures.candidate("dependency", manual: true),
            PlanningFixtures.candidate("shared", allocation: .shared("extent")),
            PlanningFixtures.candidate("unknown", allocation: .unknown),
            PlanningFixtures.candidate("negative", bytes: -1),
            PlanningFixtures.candidate("missing-size", bytes: nil)]
        #expect(try CandidateRanker.rank(candidates, policy: PlanningFixtures.policy()).eligible.isEmpty)
    }
}
