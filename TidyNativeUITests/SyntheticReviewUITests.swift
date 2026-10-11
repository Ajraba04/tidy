import XCTest

/// This suite launches the presentation-only fixture host. It has no production
/// environment, settings/journal store, discovery, service access or effect path.
final class SyntheticReviewUITests: XCTestCase {
    @MainActor
    func testEveryReviewTierKeepsSyntheticMutationsDisabled() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Manual fixtures: no discovery, persistence, settings write or cleanup."].waitForExistence(timeout: 10))
        for tier in ["Safe", "Normal", "Deep"] {
            let choice = app.radioButtons[tier]
            XCTAssertTrue(choice.exists, "Missing review surface \(tier)")
            choice.click()
            let clean = app.buttons["Clean Now"]
            XCTAssertTrue(clean.exists)
            XCTAssertFalse(clean.isEnabled, "Synthetic \(tier) must never offer an effect")
        }
    }

    @MainActor
    func testSettingsRowsExposeSeparateEditorAndMetadataElements() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        let settings = app.radioButtons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.click()

        let rowIdentifier = "settings.row.feature.headroom"
        let rows = app.descendants(matching: .any).matching(identifier: rowIdentifier)
        XCTAssertEqual(rows.count, 1, rows.debugDescription)
        XCTAssertEqual(rows.firstMatch.label, "Feature Headroom, feature.headroom")

        let editor = app.checkBoxes["settings.control.feature.headroom"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), editor.debugDescription)
        XCTAssertEqual(editor.label, "Feature Headroom, feature.headroom")

        let metadata = app.descendants(matching: .any)
            .matching(identifier: "settings.metadata.feature.headroom").firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 10), metadata.debugDescription)
        XCTAssertEqual(metadata.label, "Feature Headroom, feature.headroom")
        XCTAssertNotEqual(metadata.elementType, .staticText)
        XCTAssertNotEqual(metadata.identifier, editor.identifier)
        let lines = metadata.staticTexts.allElementsBoundByIndex
        XCTAssertEqual(lines.count, 7, metadata.debugDescription)
        XCTAssertTrue(lines.allSatisfy { !($0.value as? String ?? $0.label).isEmpty }, metadata.debugDescription)
        let expectedLines = [
            "Configure feature headroom with Tidy's safe default.",
            "Default: On", "Effective: On", "Source: Built-in", "Rule: On or off",
            "Changes apply to future policy planning and never start cleanup by themselves. Effect: This change invalidates the current cleanup plan."]
        for (index, text) in expectedLines.enumerated() {
            let child = metadata.staticTexts["settings.metadata.feature.headroom.primary.\(index)"]
            XCTAssertEqual(child.value as? String ?? child.label, text, metadata.debugDescription)
        }
        let availability = metadata.staticTexts["settings.metadata.feature.headroom.availability"]
        XCTAssertEqual(availability.value as? String ?? availability.label,
            "Available according to the policy layer and editor shown here. Resolution: restriction. Layers: global, profile.",
            metadata.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "settings.metadata.feature.buildPrep").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "settings.metadata.feature.projects").firstMatch.exists)

        editor.click()
        XCTAssertEqual(app.staticTexts["fixture.settings.submissions"].value as? String,
                       "Fixture submissions: 1")
    }
}
