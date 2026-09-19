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
        continueAfterFailure = false
        assertAuditIssueClassificationBoundaries()
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
            arrangeAuditWindows(control: control, subjectWindow: settings)
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
            try audit(app, subjectWindow: settings)
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
        if compact {
            arrangeAuditWindows(control: control, subjectWindow: clean)
        }
        capture(clean, name: "\(expected)-safe-clean")
        if compact {
            try audit(app, subjectWindow: clean)
        }
    }

    @MainActor
    private func arrangeAuditWindows(
        control: XCUIElement,
        subjectWindow: XCUIElement
    ) {
        let attestation = control.staticTexts["runtime.audit.arrangement"]
        XCTAssertTrue(attestation.exists, control.debugDescription)
        let previousAttestation = attestation.value as? String
        let controlSize = control.frame.size
        let subjectSize = subjectWindow.frame.size

        control.click()
        control.buttons["runtime.audit.arrange"].click()

        let detail = attestation.value as? String ?? "missing"
        let attachment = XCTAttachment(string: detail)
        attachment.name = "Audit window arrangement"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertNotEqual(detail, previousAttestation,
            "Audit window arrangement action did not update its attestation")
        XCTAssertTrue(detail.hasPrefix("arranged:onscreen"), detail)
        XCTAssertEqual(control.frame.size, controlSize,
            "Audit arrangement changed the control window size")
        XCTAssertEqual(subjectWindow.frame.size, subjectSize,
            "Audit arrangement changed the subject window size")
        XCTAssertFalse(control.frame.intersects(subjectWindow.frame),
            "Audit windows overlap: control=\(control.frame), subject=\(subjectWindow.frame)")
        subjectWindow.click()
    }

    @MainActor
    private func audit(_ app: XCUIApplication, subjectWindow: XCUIElement) throws {
        let capturedWindowFrame = subjectWindow.frame
        let capturedAppWindowFrames = app.windows.allElementsBoundByIndex
            .filter(\.exists)
            .map(\.frame)
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription]) { issue in
            let element = issue.element
            let elementFrame = element?.frame
            let liveWindowFrame = subjectWindow.frame
            let liveAppWindowFrames = app.windows.allElementsBoundByIndex
                .filter(\.exists)
                .map(\.frame)
            let windowFramesAreStable = liveWindowFrame == capturedWindowFrame
                && liveAppWindowFrames == capturedAppWindowFrames
            let isOffWindowContrast = windowFramesAreStable
                && Self.shouldIgnoreAuditIssue(
                    auditType: issue.auditType,
                    elementFrame: elementFrame,
                    subjectWindow: capturedWindowFrame,
                    appWindows: capturedAppWindowFrames)
            let geometry = "auditType=\(issue.auditType.rawValue); "
                + "capturedSubjectWindow=\(capturedWindowFrame); "
                + "liveSubjectWindow=\(liveWindowFrame); "
                + "capturedAppWindows=\(capturedAppWindowFrames); "
                + "liveAppWindows=\(liveAppWindowFrames); "
                + "elementFrame=\(String(describing: elementFrame))"
            print("Accessibility audit: \(issue.compactDescription); "
                + "identifier=\(element?.identifier ?? "none"); "
                + "label=\(element?.label ?? "none"); \(geometry)")
            if isOffWindowContrast {
                print("Ignoring off-window contrast audit false positive; \(geometry)")
            }
            let details = XCTAttachment(string: issue.detailedDescription + "\n" + geometry + "\n"
                + (element?.debugDescription ?? "No associated element"))
            details.name = isOffWindowContrast
                ? "Off-window contrast audit false positive"
                : "Accessibility audit issue"
            details.lifetime = .keepAlways
            self.add(details)
            if !windowFramesAreStable {
                XCTFail("App window geometry changed during accessibility audit; \(geometry)")
                return false
            }
            return isOffWindowContrast
        }
        XCTAssertEqual(subjectWindow.frame, capturedWindowFrame,
            "Subject window moved during accessibility audit")
        XCTAssertEqual(
            app.windows.allElementsBoundByIndex.filter(\.exists).map(\.frame),
            capturedAppWindowFrames,
            "App window geometry changed during accessibility audit")
    }

    private func assertAuditIssueClassificationBoundaries() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 500)
        let below = CGRect(x: 100, y: 601, width: 100, height: 20)
        XCTAssertTrue(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .sufficientElementDescription,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: [.contrast, .sufficientElementDescription],
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: XCUIAccessibilityAuditType(rawValue: UInt64(1) << 63),
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: nil,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: .zero,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: []))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window, .zero]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 100, y: 601, width: -100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: .zero,
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 120, y: 120, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 100, y: 599, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: CGRect(x: 100, y: 600, width: 100, height: 20),
            subjectWindow: window,
            appWindows: [window]))
        let otherWindow = CGRect(x: 80, y: 580, width: 440, height: 200)
        XCTAssertFalse(Self.shouldIgnoreAuditIssue(
            auditType: .contrast,
            elementFrame: below,
            subjectWindow: window,
            appWindows: [window, otherWindow]))
    }

    private static func shouldIgnoreAuditIssue(
        auditType: XCUIAccessibilityAuditType,
        elementFrame: CGRect?,
        subjectWindow: CGRect,
        appWindows: [CGRect]
    ) -> Bool {
        guard auditType == .contrast,
              let elementFrame,
              isValidAuditFrame(elementFrame),
              isValidAuditFrame(subjectWindow),
              !appWindows.isEmpty,
              appWindows.allSatisfy(isValidAuditFrame),
              appWindows.contains(subjectWindow) else { return false }
        return appWindows.allSatisfy { window in
            elementFrame.maxX < window.minX
                || elementFrame.minX > window.maxX
                || elementFrame.maxY < window.minY
                || elementFrame.minY > window.maxY
        }
    }

    private static func isValidAuditFrame(_ frame: CGRect) -> Bool {
        frame.size.width > 0 && frame.size.height > 0
            && [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
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
