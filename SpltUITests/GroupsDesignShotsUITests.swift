import XCTest

/// Saves screenshots of the group screens for reviewing their design. It runs only when `SPLT_SHOTS_DIR`
/// names a folder. `SPLT_SHOTS_DARK` picks the dark appearance and `SPLT_SHOTS_SIZE=xxxl` the largest text.
final class GroupsDesignShotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPLT_SHOTS_DIR"] != nil, "set SPLT_SHOTS_DIR to run")
    }

    @MainActor
    func testGroupScreens() {
        let env = ProcessInfo.processInfo.environment
        let dark = env["SPLT_SHOTS_DARK"] != nil
        let large = env["SPLT_SHOTS_SIZE"] == "xxxl"
        let variant = (large ? "xxxl" : "default") + (dark ? "-dark" : "-light")
        let app = launchApp(
            "-sampledata", textSize: large ? "UICTContentSizeCategoryAccessibilityXXXL" : nil,
            extra: dark ? ["-darkmode"] : []
        )
        func shot(_ name: String) { snapshot(app, "groups/\(variant)/\(name)") }

        openTab("Groups", in: app)
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 10))
        let row = app.staticTexts["Lisbon Trip"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Lisbon Trip"].waitForExistence(timeout: 10))
        shot("01-hero")
        scroll(.up, in: app)
        shot("02-expenses")
        scroll(.down, in: app)
        scroll(.down, in: app)

        selectSegment("Balances", in: app)
        shot("03-orbit")
        let orbit = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'would settle'")).firstMatch
        if orbit.waitForExistence(timeout: 3) {
            let frame = orbit.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX + frame.width * 0.28, dy: frame.minY + frame.height * 0.28)).tap()
            shot("04-orbit-focus")
        }
        let toggle = app.switches["Simplify Debts"]
        if toggle.exists || app.switches.firstMatch.exists {
            reveal(app.switches.firstMatch, in: app)
            app.switches.firstMatch.tap()
            shot("05-orbit-direct")
        }
        let list = app.segmentedControls.buttons["List"]
        if list.exists {
            list.tap()
            shot("06-balances-list")
        }

        for _ in 0..<4 { scroll(.down, in: app) }
        selectSegment("Totals", in: app)
        shot("07-totals")
        scroll(.up, in: app)
        shot("08-totals-charts")
        for _ in 0..<3 { scroll(.down, in: app) }

        let recap = app.buttons["Watch the Recap"].firstMatch
        if recap.waitForExistence(timeout: 3) {
            recap.tap()
            shot("09-recap-1")
            app.swipeLeft()
            shot("10-recap-2")
            app.swipeLeft()
            shot("11-recap-3")
            app.swipeLeft()
            shot("12-recap-4")
            app.swipeLeft()
            shot("13-recap-5")
        }
    }
}
