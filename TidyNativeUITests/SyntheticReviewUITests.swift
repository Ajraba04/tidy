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

        let metadata = app.staticTexts["settings.metadata.feature.headroom"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10), metadata.debugDescription)
        XCTAssertEqual(metadata.label, "Feature Headroom, feature.headroom")
        XCTAssertTrue(app.staticTexts["settings.metadata.feature.buildPrep"].exists)
        XCTAssertTrue(app.staticTexts["settings.metadata.feature.projects"].exists)

        editor.click()
        XCTAssertEqual(app.staticTexts["fixture.settings.submissions"].value as? String,
                       "Fixture submissions: 1")
    }
}
