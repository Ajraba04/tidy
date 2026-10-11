import Foundation
import XCTest
import TidyCore

@MainActor
final class NotificationNavigationTests: XCTestCase {
    func testClosedAssistanceWindowRoutesEveryDestinationOnce() async throws {
        try await withModel { model, receive, services in
            var opened: [AssistanceNavigation] = []
            model.bindNavigationHandler { opened.append($0) }
            let volume = UUID()
            let destinations: [AssistanceNavigation] = [
                .headroomReview,
                .budgetReview(.appleDerivedData, volumeID: volume),
                .maintenance(.reviewCache)
            ]
            // No AssistanceView is mounted or marked visible in this fixture.
            for destination in destinations { receive(destination) }
            XCTAssertEqual(opened, destinations)
            XCTAssertNil(model.requestedNavigation)
            model.bindNavigationHandler { opened.append($0) }
            XCTAssertEqual(opened, destinations, "Rebinding must not replay a consumed click")
            XCTAssertNil(services.activeScanSessionID)
            XCTAssertFalse(services.hasActiveConfirmedExecution)
            XCTAssertNil(model.notificationBroker, "Injected callback must not create a real broker")
            XCTAssertNotEqual(model.authoritySnapshot?.permits(.notifications), true)
        }
    }

    func testPendingClicksAreDrainedInOrderWhenAppOwnerArrives() async throws {
        try await withModel { model, receive, _ in
            let destinations: [AssistanceNavigation] = [
                .headroomReview, .maintenance(.reviewCache), .headroomReview
            ]
            for destination in destinations { receive(destination) }
            var opened: [AssistanceNavigation] = []
            model.bindNavigationHandler { opened.append($0) }
            XCTAssertEqual(opened, destinations)
            XCTAssertNil(model.requestedNavigation)
        }
    }

    func testBudgetClickPreservesExactCategoryAndUnavailableVolume() async throws {
        try await withModel { model, receive, _ in
            let requestedVolume = UUID(), otherVolume = UUID()
            model.installBudgetInventory([otherVolume: []])
            var opened: [AssistanceNavigation] = []
            model.bindNavigationHandler { opened.append($0) }
            let destination = AssistanceNavigation.budgetReview(.appleDerivedData,
                                                               volumeID: requestedVolume)
            receive(destination)
            XCTAssertEqual(opened, [destination])
            XCTAssertEqual(model.selectedSection, .budgets)
            XCTAssertEqual(model.reviewedBudgetID, .appleDerivedData)
            XCTAssertEqual(model.budgetVolumeID, requestedVolume)
            XCTAssertTrue(model.budgetMeasurements.isEmpty)
            // An unrelated fresh inventory must not replace the reviewed volume.
            model.installBudgetInventory([otherVolume: []])
            XCTAssertEqual(model.budgetVolumeID, requestedVolume)
            XCTAssertEqual(model.reviewedBudgetID, .appleDerivedData)
            model.clearBudgetMeasurements()
            XCTAssertEqual(model.budgetVolumeID, requestedVolume)
            XCTAssertEqual(model.reviewedBudgetID, .appleDerivedData)
        }
    }

    func testReentrantNavigationIsDeliveredOnceAfterCurrentClick() async throws {
        try await withModel { model, receive, _ in
            var opened: [AssistanceNavigation] = []
            model.bindNavigationHandler { destination in
                opened.append(destination)
                if destination == .headroomReview { receive(.maintenance(.reviewCache)) }
            }
            receive(.headroomReview)
            XCTAssertEqual(opened, [.headroomReview, .maintenance(.reviewCache)])
            XCTAssertNil(model.requestedNavigation)
        }
    }

    func testUnboundBacklogRetainsOnlyLatestSixteenDestinations() async throws {
        try await withModel { model, receive, _ in
            let destinations: [AssistanceNavigation] = (0..<100).map { _ in
                .budgetReview(.appleDerivedData, volumeID: UUID())
            }
            for destination in destinations { receive(destination) }
            let retained = Array(destinations.suffix(16))
            XCTAssertEqual(model.requestedNavigation, retained.first)
            var opened: [AssistanceNavigation] = []
            model.bindNavigationHandler { opened.append($0) }
            XCTAssertEqual(opened, retained, "Overflow drops oldest clicks and preserves exact newer destinations")
            XCTAssertNil(model.requestedNavigation)
        }
    }

    func testReentrantBurstYieldsBeforeDeliveringEveryClick() async throws {
        try await withModel { model, receive, _ in
            let completed = expectation(description: "Reentrant navigation completes across actor turns")
            var opened: [AssistanceNavigation] = []
            model.bindNavigationHandler { destination in
                opened.append(destination)
                if opened.count < 40 {
                    receive(.headroomReview)
                } else {
                    completed.fulfill()
                }
            }
            receive(.headroomReview)
            XCTAssertGreaterThan(opened.count, 0)
            XCTAssertLessThan(opened.count, 40, "One synchronous pass must yield during a reentrant burst")
            await fulfillment(of: [completed], timeout: 2)
            XCTAssertEqual(opened, Array(repeating: .headroomReview, count: 40))
            XCTAssertNil(model.requestedNavigation)
        }
    }

    private func withModel(
        _ body: (AssistanceModel, @escaping @MainActor (AssistanceNavigation) -> Void,
                 AppExecutionServices) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tidy-NotificationNavigation-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let services = await AppExecutionServices.bootstrap(paths: AppStoragePaths(
            home: root, settings: root.appendingPathComponent("config.json"),
            journal: root.appendingPathComponent("execution", isDirectory: true)))
        var receive: (@MainActor (AssistanceNavigation) -> Void)?
        let model = AssistanceModel(services: services, notificationBrokerFactory: { _, callback in
            receive = callback
            return nil
        })
        model.prepareNotificationControls()
        try await body(model, XCTUnwrap(receive), services)
    }
}
