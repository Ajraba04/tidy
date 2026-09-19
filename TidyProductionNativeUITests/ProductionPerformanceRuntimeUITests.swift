import Darwin
import CoreFoundation
import Foundation
import XCTest

final class ProductionPerformanceRuntimeUITests: XCTestCase {
    @MainActor
    func testFixed50kProductionScanWithExternalObservation() throws {
        try runObservedScenario(argument: "--tidy-runtime-performance-50k",
            scenario: "performance-50k", finalName: "runtime-performance.json",
            finalTimeout: 180, finalKeys: Self.performanceKeys) { document in
                XCTAssertEqual(integer(document, "fixtureDirectories"), 500)
                XCTAssertEqual(integer(document, "fixtureFiles"), 50_000)
                XCTAssertEqual(integer(document, "fixtureLogicalBytes"), 0)
                XCTAssertGreaterThanOrEqual(integer(document, "fixtureAllocatedBytes"), 0)
                let request = unsigned(document, "requestNanoseconds")
                let registry = unsigned(document, "firstRegistryProgressNanoseconds")
                let renderable = unsigned(document, "firstRenderableUsefulResultNanoseconds")
                let terminal = unsigned(document, "terminalNanoseconds")
                let settled = unsigned(document, "workersSettledNanoseconds")
                XCTAssertLessThanOrEqual(request, registry)
                XCTAssertLessThanOrEqual(registry, renderable)
                XCTAssertLessThanOrEqual(renderable, terminal)
                XCTAssertLessThanOrEqual(terminal, settled)
                XCTAssertLessThanOrEqual(renderable - request, 1_000_000_000)
                XCTAssertLessThanOrEqual(settled - request, 10_000_000_000)
                XCTAssertEqual(string(document, "terminal"), "complete")
                XCTAssertEqual(boolean(document, "completeCoverage"), true)
                XCTAssertGreaterThanOrEqual(integer(document, "processedEntries"), 50_000)
                XCTAssertGreaterThanOrEqual(integer(document, "metadataVisits"), 50_000)
                XCTAssertEqual(integer(document, "registrySessions"), 1)
                XCTAssertEqual(integer(document, "registryActiveWork"), 0)
                XCTAssertEqual(integer(document, "retainedTerminalStates"), 1)
                XCTAssertEqual(boolean(document, "allMutationsDenied"), true)
                XCTAssertEqual(boolean(document, "witnessUnchanged"), true)
                XCTAssertEqual(boolean(document, "settled"), true)
                XCTAssertEqual(boolean(document, "passed"), true)
            }
    }

    @MainActor
    func testTwentyActiveCancelCyclesWithExternalObservation() throws {
        try runObservedScenario(argument: "--tidy-runtime-active-cancel-20",
            scenario: "active-cancel-20", finalName: "runtime-cycles.json",
            finalTimeout: 600, finalKeys: Self.cycleKeys) { document in
                XCTAssertEqual(integer(document, "cycleCount"), 20)
                XCTAssertEqual(integer(document, "cancelRequested"), 20)
                XCTAssertEqual(integer(document, "terminalCancelled"), 20)
                XCTAssertEqual(integer(document, "completedBeforeCancel"), 0)
                XCTAssertEqual(integer(document, "otherTerminal"), 0)
                XCTAssertLessThanOrEqual(unsigned(document, "maxCancelToTerminalNanoseconds"),
                                         500_000_000)
                XCTAssertLessThanOrEqual(unsigned(document, "maxCancelToSettledNanoseconds"),
                                         500_000_000)
                XCTAssertEqual(integer(document, "registrySessions"), 20)
                XCTAssertEqual(integer(document, "registryActiveWork"), 0)
                XCTAssertEqual(integer(document, "retainedTerminalStates"), 20)
                XCTAssertEqual(integer(document, "schedulerActive"), 0)
                XCTAssertEqual(integer(document, "schedulerQueued"), 0)
                XCTAssertEqual(integer(document, "schedulerLiveSessions"), 0)
                XCTAssertEqual(integer(document, "explicitLeases"), 0)
                XCTAssertEqual(boolean(document, "indexWatchActive"), false)
                XCTAssertEqual(boolean(document, "allMutationsDenied"), true)
                XCTAssertEqual(boolean(document, "witnessUnchanged"), true)
                XCTAssertEqual(boolean(document, "settled"), true)
                XCTAssertEqual(boolean(document, "passed"), true)
            }
    }

    @MainActor
    private func runObservedScenario(argument: String, scenario: String,
                                     finalName: String, finalTimeout: TimeInterval,
                                     finalKeys: Set<String>,
                                     validate: ([String: Any]) -> Void) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "--tidy-runtime-cleanup-on-termination", argument]
        registerCleanup(app)
        app.launch()

        let settings = app.staticTexts["runtime.synthetic.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 120), app.debugDescription)
        let settingsPath = try XCTUnwrap(settings.value as? String)
        let state = URL(fileURLWithPath: settingsPath).deletingLastPathComponent()
        let readyURL = state.appendingPathComponent("runtime-performance-ready.json")
        XCTAssertTrue(waitForFile(readyURL, timeout: 180), app.debugDescription)
        let ready = try document(at: readyURL, expectedKeys: Self.readyKeys)
        XCTAssertEqual(integer(ready, "schema"), 1)
        XCTAssertEqual(string(ready, "scenario"), scenario)
        let displayedPID = (app.staticTexts["runtime.process.pid"].value as? String ?? "")
            .replacingOccurrences(of: ",", with: "")
        XCTAssertEqual(integer(ready, "pid"), try XCTUnwrap(Int(displayedPID)))
        XCTAssertEqual(integer(ready, "fixtureFiles"), 50_000)
        XCTAssertEqual(integer(ready, "fixtureLogicalBytes"), 0)
        XCTAssertEqual(integer(ready, "registrySessions"), 0)
        XCTAssertEqual(integer(ready, "registryActiveWork"), 0)
        XCTAssertEqual(integer(ready, "schedulerActive"), 0)
        XCTAssertEqual(integer(ready, "schedulerQueued"), 0)
        XCTAssertEqual(integer(ready, "schedulerLiveSessions"), 0)
        XCTAssertEqual(integer(ready, "explicitLeases"), 0)
        XCTAssertEqual(boolean(ready, "indexWatchActive"), false)
        XCTAssertEqual(boolean(ready, "allMutationsDenied"), true)
        XCTAssertEqual(boolean(ready, "witnessUnchanged"), true)
        XCTAssertEqual(boolean(ready, "settled"), true)

        let finalURL = state.appendingPathComponent(finalName)
        let errorURL = state.appendingPathComponent("runtime-performance-error.json")
        XCTAssertTrue(waitForEither(finalURL, errorURL, timeout: finalTimeout),
                      "Neither final nor error document appeared")
        let failureMessage: String?
        if FileManager.default.fileExists(atPath: errorURL.path) {
            let error = try document(at: errorURL, expectedKeys: Self.errorKeys)
            failureMessage = string(error, "message")
        } else {
            let final = try document(at: finalURL, expectedKeys: finalKeys)
            XCTAssertEqual(integer(final, "schema"), 1)
            XCTAssertEqual(string(final, "scenario"), scenario)
            XCTAssertEqual(integer(final, "pid"), integer(ready, "pid"))
            validate(final)
            failureMessage = nil
        }

        let observedURL = state.appendingPathComponent("runtime-performance-observed")
        XCTAssertTrue(waitForFile(observedURL, timeout: 60),
                      "External observer did not publish its completion token")
        try validateObservedToken(observedURL)
        if let failureMessage { XCTFail("Runtime performance failed: \(failureMessage)") }
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: url.path)
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForEither(_ first: URL, _ second: URL, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: first.path)
                || FileManager.default.fileExists(atPath: second.path)
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func document(at url: URL, expectedKeys: Set<String>) throws -> [String: Any] {
        try validateDocumentFile(url)
        let data = try Data(contentsOf: url)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(value.keys), expectedKeys)
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
        XCTAssertEqual(try Data(contentsOf: url), Data("TIDY_RUNTIME_OBSERVED_V1\n".utf8))
    }

    @MainActor
    private func registerCleanup(_ app: XCUIApplication) {
        addTeardownBlock {
            await MainActor.run { Self.terminateAndCleanup(app) }
        }
    }

    @MainActor
    private static func terminateAndCleanup(_ app: XCUIApplication) {
        let homeElement = app.staticTexts["runtime.synthetic.home"]
        let homePath = homeElement.exists ? homeElement.value as? String : nil
        guard let homePath else {
            app.terminate()
            XCTFail("Performance host did not attest its synthetic home for cleanup")
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
            XCTFail("Refused unsafe performance cleanup target: \(rootPath)")
            return
        }
        let cleanup = app.buttons["runtime.fixture.cleanupAndQuit"]
        guard cleanup.exists else {
            app.terminate()
            XCTFail("Performance host did not expose fixture cleanup")
            return
        }
        cleanup.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: rootPath)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed,
                       "Performance host did not remove fixture root: \(rootPath)")
    }

    private static let readyKeys: Set<String> = [
        "schema", "scenario", "pid", "fixtureFiles", "fixtureLogicalBytes",
        "fixtureAllocatedBytes", "registrySessions", "registryActiveWork",
        "schedulerActive", "schedulerQueued", "schedulerLiveSessions",
        "explicitLeases", "indexWatchActive", "allMutationsDenied",
        "witnessUnchanged", "settled",
    ]
    private static let performanceKeys: Set<String> = [
        "schema", "scenario", "pid", "fixtureDirectories", "fixtureFiles",
        "fixtureLogicalBytes", "fixtureAllocatedBytes", "requestNanoseconds",
        "firstRegistryProgressNanoseconds", "firstRenderableUsefulResultNanoseconds",
        "terminalNanoseconds", "workersSettledNanoseconds", "terminal",
        "completeCoverage", "processedEntries", "metadataVisits", "schedulerWorkers",
        "registrySessions", "registryActiveWork", "retainedTerminalStates",
        "allMutationsDenied", "witnessUnchanged", "settled", "passed",
    ]
    private static let cycleKeys: Set<String> = [
        "schema", "scenario", "pid", "cycleCount", "cancelRequested",
        "terminalCancelled", "completedBeforeCancel", "otherTerminal",
        "maxCancelToTerminalNanoseconds", "maxCancelToSettledNanoseconds",
        "registrySessions", "registryActiveWork", "retainedTerminalStates",
        "schedulerActive", "schedulerQueued", "schedulerLiveSessions",
        "explicitLeases", "indexWatchActive", "allMutationsDenied",
        "witnessUnchanged", "settled", "passed",
    ]
    private static let errorKeys: Set<String> = ["schema", "scenario", "pid", "message"]
}
