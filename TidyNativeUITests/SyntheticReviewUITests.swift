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
}
