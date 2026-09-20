import Foundation
import Testing
@testable import TidyCore

@Suite("Target-limited Build Prep")
struct BuildPrepTests {
    @Test func unknownAndAlreadyMetCapacityNeverSelectEffects() throws {
        let rank = try CandidateRanker.rank([PlanningFixtures.candidate("one")],
                                            policy: PlanningFixtures.policy())
        let unknown = try HeadroomPlanner.plan(ranking: rank, volumeID: PlanningFixtures.volume,
            strictAvailableBytes: nil, targetBytes: 1, byteCap: PlanningFixtures.gib,
            itemCap: 1, policyRevision: 1)
        #expect(unknown.selected.isEmpty)
        if case .unavailable = unknown.status {} else { Issue.record("Missing capacity promised readiness") }
        let enough = try HeadroomPlanner.plan(ranking: rank, volumeID: PlanningFixtures.volume,
            strictAvailableBytes: 10, targetBytes: 9, byteCap: PlanningFixtures.gib,
            itemCap: 1, policyRevision: 1)
        #expect(enough.status == .targetMet && enough.selected.isEmpty)
    }

    @Test func capsVolumesAndDeselectionPreserveAnExactReviewedSelection() throws {
        let g = PlanningFixtures.gib
        let candidates = [
            PlanningFixtures.candidate("oversized", path: "/fixture/tree", inode: 2, bytes: 8 * g),
            PlanningFixtures.candidate("child", path: "/fixture/tree/child", inode: 3, bytes: 2 * g),
            PlanningFixtures.candidate("external", inode: 4, bytes: 2 * g, volume: UUID())
        ]
        let rank = try CandidateRanker.rank(candidates, policy: PlanningFixtures.policy())
        let plan = try HeadroomPlanner.plan(ranking: rank, volumeID: PlanningFixtures.volume,
            strictAvailableBytes: 0, targetBytes: 4 * g, byteCap: 3 * g,
            itemCap: 2, policyRevision: 7)
        #expect(plan.selected.map { $0.candidate.record.id } == ["child"])
        #expect(plan.selectedBytes == 2 * g && plan.status == .insufficient)
        let deselected = HeadroomPlanner.removingSelection(["child"], from: plan)
        #expect(deselected.selected.isEmpty && deselected.selectedBytes == 0)
    }

    @Test func executionCursorRemeasuresAndNeverAddsUnreviewedWork() throws {
        let g = PlanningFixtures.gib
        let rank = try CandidateRanker.rank([
            PlanningFixtures.candidate("a", inode: 1), PlanningFixtures.candidate("b", inode: 2)
        ], policy: PlanningFixtures.policy())
        let plan = try HeadroomPlanner.plan(ranking: rank, volumeID: PlanningFixtures.volume,
            strictAvailableBytes: 0, targetBytes: 2 * g, byteCap: 2 * g,
            itemCap: 2, policyRevision: 1)
        var cursor = HeadroomPlanner.RunCursor(plan: plan)
        #expect(cursor.next(strictAvailableBytes: 0, policyRevision: 1, cancelled: false) != nil)
        #expect(cursor.next(strictAvailableBytes: 2 * g, policyRevision: 1, cancelled: false) == nil)
        #expect(cursor.dispatchedIDs == ["a"])
        var uncertain = HeadroomPlanner.RunCursor(plan: plan)
        #expect(uncertain.next(strictAvailableBytes: 0, policyRevision: 1,
                               cancelled: false, previousEffectCertain: false) == nil)
        var changed = HeadroomPlanner.RunCursor(plan: plan)
        #expect(changed.next(strictAvailableBytes: 0, policyRevision: 2, cancelled: false) == nil)
        var cancelled = HeadroomPlanner.RunCursor(plan: plan)
        #expect(cancelled.next(strictAvailableBytes: 0, policyRevision: 1, cancelled: true) == nil)
    }
}
