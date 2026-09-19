import XCTest

/// These exercise SwiftUI presentation environments in the actual production
/// scenes. They do not claim system preference delivery or human AT acceptance.
final class ProductionAppearanceRuntimeUITests: XCTestCase {
    @MainActor
    func testProductionLightAppearanceKeepsSettingsAndCleanupUsable() throws {
        try verifyAppearance(dark: false, increased: false, reducedMotion: false)
    }

    @MainActor
    func testProductionDarkAppearanceKeepsSettingsAndCleanupUsable() throws {
        try verifyAppearance(dark: true, increased: false, reducedMotion: false)
    }

    @MainActor
    func testProductionLightIncreasedContrastAndReducedMotion() throws {
        try verifyAppearance(dark: false, increased: true, reducedMotion: true)
    }

    @MainActor
    func testProductionDarkIncreasedContrastAndReducedMotion() throws {
        try verifyAppearance(dark: true, increased: true, reducedMotion: true)
    }

    @MainActor
    func testProductionCompactSettingsAndCleanupPassAutomatedAccessibilityAudit() throws {
        try verifyAppearance(dark: false, increased: false, reducedMotion: false,
                             compact: true)
    }

    @MainActor
    private func verifyAppearance(dark: Bool, increased: Bool,
                                  reducedMotion: Bool, compact: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
            "--tidy-runtime-cleanup-on-termination",
            dark ? "--tidy-runtime-appearance-dark" : "--tidy-runtime-appearance-light"]
        if increased { app.launchArguments.append("--tidy-runtime-increased-contrast") }
        if reducedMotion { app.launchArguments.append("--tidy-runtime-reduce-motion") }
        if compact { app.launchArguments.append("--tidy-runtime-compact") }
        addTeardownBlock { @MainActor in self.cleanup(app) }
        app.launch()

        let control = app.windows["Tidy Production Runtime Verification"]
        let attestation = control.staticTexts["runtime.appearance.environment"]
        XCTAssertTrue(attestation.waitForExistence(timeout: 15), app.debugDescription)
        let expected = "\(dark ? "dark" : "light") "
            + "\(increased ? "increased" : "standard") "
            + "motion:\(reducedMotion ? "reduced" : "normal")"
        XCTAssertEqual(attestation.value as? String, expected)
        XCTAssertEqual(control.staticTexts["runtime.synthetic.isolation"].value as? String,
                       "isolated")
        XCTAssertEqual(control.staticTexts["runtime.authorization"].value as? String,
                       "all-denied")

        control.buttons["runtime.open.settings"].click()
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        if compact {
            let geometry = control.staticTexts["runtime.settings.geometry"]
            XCTAssertTrue(geometry.waitForExistence(timeout: 5))
            let description = geometry.value as? String ?? "missing"
            let geometryAttachment = XCTAttachment(string: description)
            geometryAttachment.name = "Settings window size constraints"
            geometryAttachment.lifetime = .keepAlways
            add(geometryAttachment)
            // A fixed host-only AppKit input sets the real production window's
            // content size. This tests compact layout, not a synthetic drag.
            control.click()
            control.buttons["runtime.settings.compact"].click()
            settings.click()
            XCTAssertLessThanOrEqual(settings.frame.width, 500,
                "Settings could not resize to its compact width: \(description)")
        }
        let editor = settings.checkBoxes["settings.control.feature.headroom"]
        let metadata = settings.staticTexts["settings.metadata.feature.headroom"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), settings.debugDescription)
        XCTAssertTrue(editor.isEnabled)
        XCTAssertTrue(editor.isHittable)
        XCTAssertTrue(metadata.exists)
        XCTAssertFalse((metadata.value as? String ?? "").isEmpty)
        XCTAssertTrue(settings.frame.contains(editor.frame))
        XCTAssertTrue(settings.frame.contains(metadata.frame))
        XCTAssertGreaterThanOrEqual(metadata.frame.height, 120,
                                   "The seven-line metadata block collapsed")
        let row = settings.descendants(matching: .any)["settings.row.feature.headroom"]
        XCTAssertGreaterThanOrEqual(row.frame.height, metadata.frame.height + editor.frame.height)
        let settingsViewport = settings.scrollViews.firstMatch
        XCTAssertTrue(settingsViewport.frame.contains(metadata.frame),
            "The settings metadata is clipped by its scroll viewport: "
                + "viewport=\(settingsViewport.frame), metadata=\(metadata.frame)")
        capture(settings, name: "\(expected)-settings")
        if compact {
            try audit(app)
        }

        let search = settings.textFields["settings.search"]
        XCTAssertEqual(search.label, "Search settings")
        search.click()
        search.typeText(String(repeating: "long-query-", count: 8))
        XCTAssertEqual(search.value as? String, String(repeating: "long-query-", count: 8))
        let noMatches = settings.staticTexts["No settings match"]
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10), settings.debugDescription)
        XCTAssertTrue(settingsViewport.frame.contains(noMatches.frame),
                      "The no-results explanation is clipped by its scroll viewport")
        capture(settings, name: "\(expected)-long-search")
        settings.typeKey("w", modifierFlags: .command)
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)

        control.click()
        control.buttons["runtime.open.clean.safe"].click()
        let clean = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "clean")).firstMatch
        XCTAssertTrue(clean.waitForExistence(timeout: 10), app.debugDescription)
        let cleanNow = clean.buttons["Clean Now"]
        XCTAssertTrue(cleanNow.waitForExistence(timeout: 45), clean.debugDescription)
        XCTAssertFalse(cleanNow.isEnabled)
        XCTAssertTrue(clean.frame.contains(cleanNow.frame))
        capture(clean, name: "\(expected)-safe-clean")
        if compact {
            try audit(app)
        }
    }

    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription]) { issue in
            let element = issue.element
            print("Accessibility audit: \(issue.compactDescription); "
                + "identifier=\(element?.identifier ?? "none"); "
                + "label=\(element?.label ?? "none"); frame=\(String(describing: element?.frame))")
            let details = XCTAttachment(string: issue.detailedDescription + "\n"
                + (element?.debugDescription ?? "No associated element"))
            details.name = "Accessibility audit issue"
            details.lifetime = .keepAlways
            self.add(details)
            return false
        }
    }

    @MainActor
    private func capture(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func cleanup(_ app: XCUIApplication) {
        let control = app.windows["Tidy Production Runtime Verification"]
        let homePath = control.staticTexts["runtime.synthetic.home"].value as? String
        guard let homePath else {
            app.terminate()
            XCTFail("Runtime appearance host did not attest its fixture home")
            return
        }
        let root = URL(fileURLWithPath: homePath).deletingLastPathComponent()
        guard root.lastPathComponent.hasPrefix("tidy-production-runtime-"),
              root.path.hasPrefix("/private/var/folders/")
                || root.path.hasPrefix("/private/tmp/"),
              !root.path.hasPrefix(NSHomeDirectory() + "/") else {
            app.terminate()
            XCTFail("Runtime appearance host supplied an unsafe fixture root")
            return
        }
        control.click()
        control.buttons["runtime.fixture.cleanupAndQuit"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !FileManager.default.fileExists(atPath: root.path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
    }
}
