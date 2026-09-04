import Foundation
import XCTest
import TidyCore

final class RunReportPresentationTests: XCTestCase {
    private func report(_ items: [ItemResult], disposition: RunDisposition = .completed,
                        available: Bool? = nil) -> RunReport {
        RunReport(tier: .safe, results: items, startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2), freeSpaceBeforeBytes: 100,
            freeSpaceAfterBytes: 110, disposition: disposition,
            coordinatorMeasurementsAvailable: available)
    }
    func testHistoricalAbsentMemoryIsNotMeasuredNotZero() throws {
        let old = try JSONDecoder().decode(RunReport.self, from: Data(#"{"tier":"safe","results":[{"id":"old","title":"Old","freedBytes":10,"succeeded":true}],"startedAt":0,"finishedAt":1,"freeSpaceBeforeBytes":100,"freeSpaceAfterBytes":110}"#.utf8))
        let presentation = RunReportPresentation(report: old)
        XCTAssertTrue(presentation.measurementsAvailable)
        XCTAssertEqual(presentation.memoryText, "Not measured")
        XCTAssertNil(presentation.admissionMessage)
    }
    func testExplicitZeroIsMeasuredAndMixedUnknownIsNot() {
        let zero = ItemResult(id: "zero", title: "Zero", freedBytes: 0,
            reclaimedMemoryBytes: 0, succeeded: true)
        let known = ItemResult(id: "known", title: "Known", freedBytes: 0,
            reclaimedMemoryBytes: 2048, succeeded: true)
        let unknown = ItemResult(id: "unknown", title: "Unknown", freedBytes: 0, succeeded: true)
        XCTAssertEqual(RunReportPresentation(report: report([zero])).memoryText, ByteFormat.human(0))
        XCTAssertEqual(RunReportPresentation(report: report([known])).memoryText, ByteFormat.human(2048))
        XCTAssertEqual(RunReportPresentation(report: report([unknown, known])).memoryText, "Not measured")
        XCTAssertEqual(RunReportPresentation(report: report([])).memoryText, "Not measured")
    }
    func testT02NoOpAndEveryDenialRemainUnmeasuredWithTheirOwnMessage() {
        let cases: [(RunDisposition, String)] = [
            (.noWork, "No items selected; nothing was run."),
            (.busy, "Another cleanup is running. Wait for it to finish, then try again."),
            (.recoveryBlocked, "An earlier operation may still be running. Cleanup is blocked pending reconciliation."),
            (.storageUnavailable, "Execution records could not be validated. Cleanup remains blocked."),
            (.stalePolicy, "Settings changed. Review the items again before confirming."),
            (.staleReview, "This confirmation is no longer valid. Review the items again."),
            (.invalidToken, "This confirmation is no longer valid. Review the items again."),
            (.unavailableSelection, "The selected action is unavailable. Nothing was run."),
            (.completed, "The operation finished, but measurements are unavailable.")
        ]
        let zero = ItemResult(id: "zero", title: "Zero", freedBytes: 0,
            reclaimedMemoryBytes: 0, succeeded: true)
        for (disposition, message) in cases {
            let presentation = RunReportPresentation(report: report([zero],
                disposition: disposition, available: false))
            XCTAssertFalse(presentation.measurementsAvailable)
            XCTAssertEqual(presentation.memoryText, "Not measured")
            XCTAssertEqual(presentation.admissionMessage, message)
        }
    }
}
