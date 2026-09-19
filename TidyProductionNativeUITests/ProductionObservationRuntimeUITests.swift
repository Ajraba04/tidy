import Darwin
import CoreFoundation
import Foundation
import XCTest

final class ProductionObservationRuntimeUITests: XCTestCase {
    @MainActor
    func testProductionHiddenOffObservationRemainsIdleForFixedWindow() throws {
        try runObservedScenario(argument: "--tidy-runtime-hidden-off",
            scenario: "hidden-off", finalTimeout: 135) { ready, final in
                XCTAssertEqual(boolean(ready, "timerRunning"), false)
                XCTAssertEqual(integer(ready, "timerScheduledCount"), 0)
                XCTAssertEqual(integer(ready, "timerCancelledCount"), 0)
                XCTAssertEqual(boolean(final, "timerRunning"), false)
                XCTAssertEqual(integer(final, "timerScheduledCount"), 0)
                XCTAssertEqual(integer(final, "timerCancelledCount"), 0)
            }
    }

    @MainActor
    func testProductionHiddenNoAuthorityKeepsTimerOffForFixedWindow() throws {
        try runObservedScenario(argument: "--tidy-runtime-hidden-no-authority",
            scenario: "hidden-no-authority", finalTimeout: 615) { ready, final in
                XCTAssertEqual(boolean(ready, "timerRunning"), false)
                XCTAssertEqual(integer(ready, "timerScheduledCount"), 0)
                XCTAssertEqual(integer(ready, "timerCancelledCount"), 0)
                XCTAssertEqual(boolean(final, "timerRunning"), false)
                XCTAssertEqual(integer(final, "timerScheduledCount"), 0)
                XCTAssertEqual(integer(final, "timerCancelledCount"), 0)
            }
    }

    @MainActor
    private func runObservedScenario(argument: String, scenario: String,
                                     finalTimeout: TimeInterval,
                                     validateTimers: ([String: Any], [String: Any]) -> Void) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "--tidy-runtime-cleanup-on-termination", argument]
        registerCleanup(app)
        app.launch()

        let settings = app.staticTexts["runtime.synthetic.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), app.debugDescription)
        let state = URL(fileURLWithPath: try XCTUnwrap(settings.value as? String))
            .deletingLastPathComponent()
        let diagnostic = app.staticTexts["runtime.observation.diagnostic"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(diagnostic.value as? String, "none")

        let readyURL = state.appendingPathComponent("runtime-ready.json")
        XCTAssertTrue(waitForFile(readyURL, timeout: 30), "Ready document did not appear")
        let ready = try document(at: readyURL)
        validateCommon(ready, scenario: scenario)

        let finalURL = state.appendingPathComponent("runtime-final.json")
        XCTAssertTrue(waitForFile(finalURL, timeout: finalTimeout),
                      "Final observation document did not appear")
        let final = try document(at: finalURL)
        validateCommon(final, scenario: scenario)
        XCTAssertEqual(integer(final, "pid"), integer(ready, "pid"))
        XCTAssertEqual(integer(final, "settingsRevision"), integer(ready, "settingsRevision"))
        XCTAssertGreaterThan(unsigned(final, "observedMonotonicNanoseconds"),
                             unsigned(ready, "observedMonotonicNanoseconds"))
        validateTimers(ready, final)
        XCTAssertEqual(diagnostic.value as? String, "none")

        let observed = state.appendingPathComponent("runtime-observation-observed")
        XCTAssertTrue(waitForFile(observed, timeout: 60),
                      "External observer did not publish hidden observation completion")
        try validateObservedToken(observed)
    }

    private func validateCommon(_ document: [String: Any], scenario: String) {
        XCTAssertEqual(integer(document, "schema"), 1)
        XCTAssertEqual(string(document, "scenario"), scenario)
        XCTAssertGreaterThan(integer(document, "pid"), 0)
        XCTAssertEqual(integer(document, "settingsRevision"), 1)
        XCTAssertEqual(string(document, "backgroundAuthority"), "unavailable")
        XCTAssertEqual(boolean(document, "applicationHidden"), true)
        XCTAssertEqual(integer(document, "sceneLeases"), 0)
        XCTAssertEqual(integer(document, "explicitWorkLeases"), 0)
        XCTAssertEqual(integer(document, "scanSessions"), 0)
        XCTAssertEqual(integer(document, "scanActiveWork"), 0)
        XCTAssertEqual(boolean(document, "allMutationsDenied"), true)
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: url.path)
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func document(at url: URL) throws -> [String: Any] {
        try validateDocumentFile(url)
        let value = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(Set(value.keys), Self.documentKeys)
        return value
    }

    private func integer(_ document: [String: Any], _ key: String) -> Int {
        guard let number = document[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)) else {
            XCTFail("Missing or non-integer field: \(key)")
            return Int.min
        }
        return number.intValue
    }

    private func unsigned(_ document: [String: Any], _ key: String) -> UInt64 {
        let value = integer(document, key)
        guard value >= 0 else {
            XCTFail("Negative unsigned field: \(key)")
            return 0
        }
        return UInt64(value)
    }

    private func boolean(_ document: [String: Any], _ key: String) -> Bool {
        guard let number = document[key] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            XCTFail("Missing or non-Boolean field: \(key)")
            return false
        }
        return number.boolValue
    }

    private func string(_ document: [String: Any], _ key: String) -> String {
        guard let value = document[key] as? String else {
            XCTFail("Missing or non-string field: \(key)")
            return "<missing>"
        }
        return value
    }

    private func validateDocumentFile(_ url: URL) throws {
        var info = stat()
        XCTAssertEqual(lstat(url.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(info.st_uid, geteuid())
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertEqual(info.st_nlink, 1)
    }

    private func validateObservedToken(_ url: URL) throws {
        var info = stat()
        XCTAssertEqual(lstat(url.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(info.st_uid, geteuid())
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertEqual(info.st_nlink, 1)
        XCTAssertEqual(try Data(contentsOf: url),
                       Data("TIDY_RUNTIME_OBSERVATION_OBSERVED_V1\n".utf8))
    }

    @MainActor
    private func registerCleanup(_ app: XCUIApplication) {
        addTeardownBlock {
            await MainActor.run { Self.terminateAndCleanup(app) }
        }
    }

    @MainActor
    private static func terminateAndCleanup(_ app: XCUIApplication) {
        app.activate()
        let homeElement = app.staticTexts["runtime.synthetic.home"]
        let homePath = homeElement.exists ? homeElement.value as? String : nil
        guard let homePath else {
            app.terminate()
            XCTFail("Observation host did not attest its synthetic home for cleanup")
            return
        }
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        let root = home.deletingLastPathComponent()
        let rootPath = root.path
        let canonical = rootPath.hasPrefix("/private/var/folders/")
            || rootPath.hasPrefix("/private/tmp/")
        guard home.lastPathComponent == "home",
              root.lastPathComponent.hasPrefix("tidy-production-runtime-"), canonical,
              !rootPath.hasPrefix(NSHomeDirectory() + "/") else {
            app.terminate()
            XCTFail("Refused unsafe observation cleanup target: \(rootPath)")
            return
        }
        let cleanup = app.buttons["runtime.fixture.cleanupAndQuit"]
        guard cleanup.waitForExistence(timeout: 10) else {
            app.terminate()
            XCTFail("Observation host did not expose fixture cleanup")
            return
        }
        cleanup.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: rootPath)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed,
                       "Observation host did not remove fixture root: \(rootPath)")
    }

    private static let documentKeys: Set<String> = [
        "schema", "scenario", "pid", "settingsRevision", "applicationHidden",
        "backgroundAuthority", "timerRunning", "sceneLeases", "explicitWorkLeases", "scanSessions",
        "scanActiveWork", "allMutationsDenied", "timerScheduledCount",
        "timerCancelledCount", "observedMonotonicNanoseconds",
    ]
}
