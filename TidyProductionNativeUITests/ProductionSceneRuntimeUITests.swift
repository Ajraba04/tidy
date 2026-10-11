import XCTest

/// Native journeys through the production scene registrations, backed only by
/// the compile-scoped synthetic composition in TidyProductionRuntimeHost.
final class ProductionSceneRuntimeUITests: XCTestCase {
    @MainActor
    func testProductionManualServiceReviewRemainsUnavailableAndResetsChoices() throws {
        continueAfterFailure = false
        let app = launchReadyApp()
        let witness = URL(fileURLWithPath: try XCTUnwrap(app.staticTexts["runtime.synthetic.witness"].value as? String))
        let witnessBefore = try Data(contentsOf: witness)
        let controls = try XCTUnwrap(Self.foregroundVerificationControls(in: app))
        let openFixture = controls.buttons["runtime.open.manual.fixture"]
        XCTAssertTrue(Self.waitForHittability(openFixture), controls.debugDescription)
        XCTAssertTrue(openFixture.isHittable)
        openFixture.click()
        let developer = app.windows["Developer Workspace"]
        XCTAssertTrue(developer.waitForExistence(timeout: 10))
        let tab = developer.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Manual Operations")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), developer.debugDescription)
        tab.click()
        let selected = developer.checkBoxes["manualService.selected"]
        let acknowledged = developer.checkBoxes["manualService.acknowledged"]
        let dismiss = developer.buttons["manualService.dismiss"]
        func reveal(_ element: XCUIElement) {
            let viewport = developer.scrollViews.firstMatch
            for _ in 0..<12 {
                if element.isHittable && viewport.frame.contains(element.frame) { break }
                viewport.scroll(byDeltaX: 0, deltaY: -180)
            }
            XCTAssertTrue(element.isHittable, developer.debugDescription)
        }
        reveal(selected)
        XCTAssertEqual((selected.value as? NSNumber)?.intValue ?? Int(selected.value as? String ?? ""), 0)
        selected.click()
        reveal(acknowledged)
        XCTAssertEqual((acknowledged.value as? NSNumber)?.intValue ?? Int(acknowledged.value as? String ?? ""), 0)
        acknowledged.click()
        XCTAssertTrue(developer.descendants(matching: .any).matching(identifier: "manualService.unavailable").firstMatch.exists)
        XCTAssertFalse(developer.buttons["Execute"].exists)
        reveal(dismiss); dismiss.click()
        XCTAssertFalse(selected.exists)
        _ = try XCTUnwrap(Self.foregroundVerificationControls(in: app))
        XCTAssertTrue(Self.waitForHittability(openFixture), controls.debugDescription)
        XCTAssertTrue(openFixture.isHittable)
        openFixture.click()
        reveal(selected)
        XCTAssertEqual((selected.value as? NSNumber)?.intValue ?? Int(selected.value as? String ?? ""), 0)
        XCTAssertEqual((acknowledged.value as? NSNumber)?.intValue ?? Int(acknowledged.value as? String ?? ""), 0)
        XCTAssertEqual(try Data(contentsOf: witness), witnessBefore)
    }

    @MainActor
    func testProductionDiagnosticExportSavesOnlyMetadataInSyntheticHome() throws {
        continueAfterFailure = false
        let app = launchReadyApp()
        let home = try XCTUnwrap(app.staticTexts["runtime.synthetic.home"].value as? String)
        let directory = URL(fileURLWithPath: home)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: home))
        func newExports() -> [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: home))?.filter {
                !before.contains($0) && $0.hasPrefix("tidy-diagnostics-") && $0.hasSuffix(".json")
            } ?? []
        }
        app.buttons["runtime.open.settings"].click()
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.descendants(matching: .any)
            .matching(identifier: "settings.section.experience").firstMatch.click()
        settings.buttons["settings.diagnostics.export"].click()
        let save = app.windows.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(home)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            newExports().count == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        let destination = directory.appendingPathComponent(try XCTUnwrap(newExports().first))
        let data = try Data(contentsOf: destination)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["settingsRevision"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(home))
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue((settings.staticTexts["settings.diagnostics.status"].value as? String
            ?? settings.staticTexts["settings.diagnostics.status"].label).localizedCaseInsensitiveContains("exported"))
    }

    @MainActor
    func testProductionOptionalDataReviewCancelClearAndDiagnosticPanel() throws {
        continueAfterFailure = false
        let app = launchReadyApp()
        app.buttons["runtime.open.settings"].click()
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        func clickVisible(_ element: XCUIElement) {
            let viewport = settings.scrollViews.firstMatch
            for _ in 0..<8 {
                if element.isHittable && viewport.frame.contains(element.frame) { break }
                let delta: CGFloat = element.frame.maxY > viewport.frame.maxY ? -140 : 140
                viewport.scroll(byDeltaX: 0, deltaY: delta)
            }
            XCTAssertTrue(viewport.frame.contains(element.frame), element.debugDescription)
            element.click()
        }
        let experience = settings.descendants(matching: .any)
            .matching(identifier: "settings.section.experience").firstMatch
        XCTAssertTrue(experience.waitForExistence(timeout: 5), settings.debugDescription)
        experience.click()
        let review = settings.buttons["settings.data.review.completedReports"]
        XCTAssertTrue(review.waitForExistence(timeout: 5), settings.debugDescription)
        clickVisible(review)
        let cancel = settings.buttons["settings.data.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), settings.debugDescription)
        clickVisible(cancel)
        XCTAssertTrue(waitForAbsence(cancel))
        clickVisible(review)
        let confirm = settings.buttons["settings.data.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        clickVisible(confirm)
        let status = settings.staticTexts["settings.data.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue((status.value as? String ?? status.label).contains("cleared"), status.debugDescription)
        let export = settings.buttons["settings.diagnostics.export"]
        clickVisible(export)
        // Native panel cancellation must return to the unchanged Settings scene.
        let panelCancel = app.windows.buttons["Cancel"].firstMatch
        XCTAssertTrue(panelCancel.waitForExistence(timeout: 5), app.debugDescription)
        panelCancel.click()
        XCTAssertTrue(export.isEnabled)
        settings.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForAbsence(settings))
        app.buttons["runtime.open.settings"].click()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertFalse(settings.buttons["settings.data.confirm"].exists)
        XCTAssertEqual(app.staticTexts["runtime.synthetic.isolation"].value as? String, "isolated")
        XCTAssertEqual(app.staticTexts["runtime.authorization"].value as? String, "all-denied")
    }

    @MainActor
    func testProductionRuntimeStartsWithSyntheticStorageAttestation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "--tidy-runtime-cleanup-on-termination"]
        registerCleanup(app)
        app.launch()

        let attestation = app.staticTexts["runtime.synthetic.attestation"]
        if !attestation.waitForExistence(timeout: 10) {
            let diagnostic = app.staticTexts["runtime.bootstrap.diagnostic"]
            XCTFail("Runtime bootstrap did not become ready: "
                    + (diagnostic.exists ? String(describing: diagnostic.value)
                       : app.debugDescription))
            return
        }
        XCTAssertEqual(attestation.value as? String,
                       "home:ready settings:ready journal:ready witness:unchanged")

        let home = app.staticTexts["runtime.synthetic.home"]
        XCTAssertTrue(home.exists)
        let path = try XCTUnwrap(home.value as? String)
        XCTAssertTrue(path.hasPrefix("/private/var/folders/"), path)
        XCTAssertTrue(path.contains("/tidy-production-runtime-"), path)
        XCTAssertFalse(path.hasPrefix(NSHomeDirectory() + "/"), path)
        XCTAssertEqual(app.staticTexts["runtime.synthetic.isolation"].value as? String,
                       "isolated")
        XCTAssertEqual(app.staticTexts["runtime.authorization"].value as? String,
                       "all-denied")
        let pid = (app.staticTexts["runtime.process.pid"].value as? String ?? "")
            .replacingOccurrences(of: ",", with: "")
        XCTAssertNotNil(Int(pid))
    }

    @MainActor
    func testProductionSettingsAndSafeCleanSupportTwoWindowsKeyboardAndAX() throws {
        continueAfterFailure = false
        let app = launchReadyApp()

        app.buttons["runtime.open.settings"].click()
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), app.debugDescription)

        let row = app.descendants(matching: .any)["settings.row.feature.headroom"]
        let editor = app.checkBoxes["settings.control.feature.headroom"]
        let metadata = app.descendants(matching: .any)
            .matching(identifier: "settings.metadata.feature.headroom").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), row.debugDescription)
        XCTAssertTrue(editor.exists)
        XCTAssertTrue(metadata.exists)
        XCTAssertNotEqual(metadata.elementType, .staticText)
        XCTAssertNotEqual(metadata.identifier, editor.identifier)
        XCTAssertEqual(metadata.staticTexts.count, 7)

        let search = app.textFields["settings.search"]
        XCTAssertTrue(search.exists)
        let longQuery = String(repeating: "long-text-", count: 8)
        search.click()
        search.typeText(longQuery)
        XCTAssertEqual(search.value as? String, longQuery)

        settingsWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForAbsence(settingsWindow))

        let controlWindow = app.windows["Tidy Production Runtime Verification"]
        controlWindow.click()
        controlWindow.buttons["runtime.open.settings"].click()
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))

        controlWindow.click()
        controlWindow.buttons["runtime.open.clean.safe"].click()
        let cleanWindow = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "clean")).firstMatch
        XCTAssertTrue(cleanWindow.waitForExistence(timeout: 10), app.debugDescription)
        let cleanNow = app.buttons["Clean Now"]
        XCTAssertTrue(cleanNow.waitForExistence(timeout: 45), app.debugDescription)
        XCTAssertFalse(cleanNow.isEnabled)

        XCTAssertTrue(settingsWindow.exists)
        XCTAssertGreaterThanOrEqual(app.windows.count, 3)
    }

    @MainActor
    func testProductionFullHomeScanTraversesOnlySyntheticHomeAndPreservesWitness() throws {
        continueAfterFailure = false
        let app = launchReadyApp()

        let witnessElement = app.staticTexts["runtime.synthetic.witness"]
        let witnessPath = try XCTUnwrap(witnessElement.value as? String)
        let witnessURL = URL(fileURLWithPath: witnessPath)
        let original = try Data(contentsOf: witnessURL)
        XCTAssertEqual(original, Data("runtime-witness\n".utf8))
        let homePath = try XCTUnwrap(
            app.staticTexts["runtime.synthetic.home"].value as? String)

        openFullHomeScan(in: app)
        let complete = app.descendants(matching: .any)["scan.phase.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 45), app.debugDescription)
        let visibleValues = app.staticTexts.allElementsBoundByIndex.compactMap {
            $0.value as? String
        }
        let rankedPath = try XCTUnwrap(visibleValues.first {
            $0.contains("/SyntheticWorkspace")
        }, visibleValues.joined(separator: "\n"))
        let fixtureName = URL(fileURLWithPath: homePath).deletingLastPathComponent()
            .lastPathComponent
        XCTAssertTrue(rankedPath.contains("/\(fixtureName)/home/SyntheticWorkspace"),
                      rankedPath)
        XCTAssertEqual(try Data(contentsOf: witnessURL), original)
        XCTAssertEqual(app.staticTexts["runtime.authorization"].value as? String,
                       "all-denied")
    }

    @MainActor
    func testProductionFullHomeScanCancelSurvivesCloseAndReopen() throws {
        continueAfterFailure = false
        let app = launchReadyApp(scenarioArgument: "--tidy-runtime-cancel-queued")

        let witnessPath = try XCTUnwrap(
            app.staticTexts["runtime.synthetic.witness"].value as? String)
        let witnessURL = URL(fileURLWithPath: witnessPath)
        let original = try Data(contentsOf: witnessURL)

        let blocker = app.staticTexts["runtime.cancel.blocker"]
        XCTAssertTrue(blocker.waitForExistence(timeout: 15), app.debugDescription)
        let blockerReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "ready permits:"),
            object: blocker)
        XCTAssertEqual(XCTWaiter.wait(for: [blockerReady], timeout: 15), .completed,
                       String(describing: blocker.value))

        openFullHomeScan(in: app)
        let scanWindow = app.windows["Scan Report"]
        let cancel = scanWindow.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), scanWindow.debugDescription)
        cancel.click()
        let cancelled = app.descendants(matching: .any)["scan.phase.cancelled"]
        XCTAssertTrue(cancelled.waitForExistence(timeout: 10), app.debugDescription)

        let controlWindow = app.windows["Tidy Production Runtime Verification"]
        controlWindow.click()
        controlWindow.buttons["runtime.cancel.release"].click()
        let blockerReleased = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "released "),
            object: blocker)
        XCTAssertEqual(XCTWaiter.wait(for: [blockerReleased], timeout: 15), .completed,
                       String(describing: blocker.value))
        let releasedState = try XCTUnwrap(blocker.value as? String)
        XCTAssertTrue(releasedState.contains("serviceActive:false"), releasedState)
        XCTAssertTrue(releasedState.contains("registry:1/0/1"), releasedState)
        XCTAssertTrue(releasedState.contains("scheduler:0/0/0"), releasedState)
        XCTAssertTrue(releasedState.contains("leases:0"), releasedState)
        XCTAssertTrue(releasedState.contains("watch:false"), releasedState)
        XCTAssertTrue(releasedState.contains("witness:unchanged"), releasedState)

        app.menuBars.menuBarItems["Window"].click()
        let scanWindowMenuItem = app.menuItems["Scan Report"]
        XCTAssertTrue(scanWindowMenuItem.waitForExistence(timeout: 5))
        scanWindowMenuItem.click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForAbsence(scanWindow))
        app.buttons["runtime.open.scan"].click()
        XCTAssertTrue(scanWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(cancelled.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(try Data(contentsOf: witnessURL), original)
    }

    @MainActor
    func testProductionFreshDefaultsQuickScanKeepsSettingsAbsent() throws {
        continueAfterFailure = false
        let app = launchReadyApp(scenarioArgument: "--tidy-runtime-fresh-defaults")

        XCTAssertEqual(app.staticTexts["runtime.scenario"].value as? String,
                       "fresh-defaults")
        XCTAssertEqual(app.staticTexts["runtime.synthetic.attestation"].value as? String,
                       "home:ready settings:absent journal:ready witness:unchanged")
        let settingsPath = try XCTUnwrap(
            app.staticTexts["runtime.synthetic.settings"].value as? String)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsPath))
        let homePath = try XCTUnwrap(
            app.staticTexts["runtime.synthetic.home"].value as? String)

        app.buttons["runtime.open.scan"].click()
        let scanWindow = app.windows["Scan Report"]
        XCTAssertTrue(scanWindow.waitForExistence(timeout: 10))
        let runScan = scanWindow.buttons["Run Scan"]
        XCTAssertTrue(runScan.waitForExistence(timeout: 10), scanWindow.debugDescription)
        runScan.click()
        XCTAssertTrue(app.descendants(matching: .any)["scan.phase.complete"]
            .waitForExistence(timeout: 45), app.debugDescription)

        let privateQuickRoot = homePath + "/Library/Caches/typescript"
        let systemQuickRoot = homePath.hasPrefix("/private/")
            ? String(homePath.dropFirst("/private".count)) + "/Library/Caches/typescript"
            : privateQuickRoot
        let privateElement = app.staticTexts[privateQuickRoot]
        let quickRoot = privateElement.waitForExistence(timeout: 3)
            ? privateElement : app.staticTexts[systemQuickRoot]
        XCTAssertTrue(quickRoot.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsPath))
        XCTAssertEqual(app.staticTexts["runtime.authorization"].value as? String,
                       "all-denied")
    }

    @MainActor
    func testProductionFutureSettingsRecoveryPreservesBytesAndWithholdsControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "--tidy-runtime-cleanup-on-termination",
                               "--tidy-runtime-future-settings"]
        registerCleanup(app)
        app.launch()

        XCTAssertTrue(app.staticTexts["Settings Recovery Required"]
            .waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(app.staticTexts["runtime.scenario"].value as? String,
                       "future-settings")
        XCTAssertEqual(app.staticTexts["runtime.synthetic.attestation"].value as? String,
                       "home:ready settings:preserved journal:ready witness:unchanged")
        let settingsPath = try XCTUnwrap(
            app.staticTexts["runtime.synthetic.settings"].value as? String)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: settingsPath)),
                       Data(#"{"schemaVersion":999,"revision":0,"config":{}}"#.utf8))
        XCTAssertEqual(app.staticTexts["runtime.authorization"].value as? String,
                       "all-denied")
        XCTAssertFalse(app.buttons["runtime.open.scan"].exists)
        XCTAssertFalse(app.buttons["Run Scan"].exists)
        XCTAssertFalse(app.buttons["Clean Now"].exists)
    }

    @MainActor
    private func launchReadyApp(scenarioArgument: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "--tidy-runtime-cleanup-on-termination"]
        if let scenarioArgument { app.launchArguments.append(scenarioArgument) }
        registerCleanup(app)
        app.launch()
        XCTAssertTrue(app.staticTexts["runtime.synthetic.attestation"]
            .waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    @MainActor
    private func registerCleanup(_ app: XCUIApplication) {
        addTeardownBlock {
            await MainActor.run { Self.terminateAndCleanup(app) }
        }
    }

    @MainActor
    private func openFullHomeScan(in app: XCUIApplication) {
        app.buttons["runtime.open.scan"].click()
        XCTAssertTrue(app.descendants(matching: .any)["scan.phase.idle"]
            .waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Full Home Scan…"].click()
        let confirm = app.windows["Scan Report"].sheets.buttons["Scan Full Home"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        confirm.click()
    }

    @MainActor
    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private static func waitForHittability(_ element: XCUIElement,
                                          timeout: TimeInterval = 5) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: element)
        return XCTWaiter.wait(for: [ready], timeout: timeout) == .completed
    }

    @MainActor
    private static func foregroundVerificationControls(in app: XCUIApplication) -> XCUIElement? {
        app.activate()
        let windowMenu = app.menuBars.menuBarItems["Window"]
        guard waitForHittability(windowMenu) else {
            XCTFail("The supported Window menu was not hittable: \(app.debugDescription)")
            return nil
        }
        windowMenu.click()
        let title = "Tidy Production Runtime Verification"
        let controlsItem = app.menuItems[title]
        guard waitForHittability(controlsItem) else {
            XCTFail("The verification window's Window menu item was not hittable: \(app.debugDescription)")
            return nil
        }
        controlsItem.click()
        let controls = app.windows[title]
        guard controls.waitForExistence(timeout: 5), waitForHittability(controls) else {
            XCTFail("The verification control window was not visible after menu selection: \(app.debugDescription)")
            return nil
        }
        XCTAssertTrue(controls.isHittable)
        return controls
    }

    @MainActor
    private static func terminateAndCleanup(_ app: XCUIApplication) {
        let homeElement = app.staticTexts["runtime.synthetic.home"]
        let homePath = homeElement.exists ? homeElement.value as? String : nil
        guard let homePath else {
            app.terminate()
            XCTFail("Dedicated runtime host did not attest its synthetic home for cleanup")
            return
        }
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        let root = home.deletingLastPathComponent()
        let rootPath = root.path
        let isCanonicalTemporary = rootPath.hasPrefix("/private/var/folders/")
            || rootPath.hasPrefix("/private/tmp/")
        guard home.lastPathComponent == "home",
              root.lastPathComponent.hasPrefix("tidy-production-runtime-"),
              isCanonicalTemporary,
              !rootPath.hasPrefix(NSHomeDirectory() + "/") else {
            app.terminate()
            XCTFail("Refused unsafe fixture cleanup target: \(rootPath)")
            return
        }
        if let controls = foregroundVerificationControls(in: app) {
            let cleanup = controls.buttons["runtime.fixture.cleanupAndQuit"]
            guard cleanup.exists else {
                app.terminate()
                XCTFail("Dedicated runtime host did not expose fixture cleanup")
                return
            }
            if waitForHittability(cleanup) {
                XCTAssertTrue(cleanup.isHittable)
                cleanup.click()
            } else {
                XCTFail("Dedicated runtime fixture cleanup was not hittable: \(controls.debugDescription)")
                app.terminate()
            }
        } else {
            app.terminate()
        }
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: rootPath)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed,
                       "Dedicated host did not remove fixture root: \(rootPath)")
    }
}
