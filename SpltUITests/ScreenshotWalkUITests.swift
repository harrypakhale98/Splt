import XCTest

/// Walks every main screen and saves a screenshot of each at the default and the largest accessibility text
/// size, for reviewing the layouts by eye. It runs only when `SPLT_SHOTS_DIR` names the folder to write to.
/// Set `SPLT_SHOTS_DARK` to run it in the dark appearance.
final class ScreenshotWalkUITests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPLT_SHOTS_DIR"] != nil, "set SPLT_SHOTS_DIR to run the walk")
    }

    @MainActor
    func testWalkDefaultSize() {
        walk(variant: "default", textSize: nil)
    }

    @MainActor
    func testWalkLargestText() {
        walk(variant: "xxxl", textSize: Self.largest)
    }

    @MainActor
    private func walk(variant: String, textSize: String?) {
        let dark = ProcessInfo.processInfo.environment["SPLT_SHOTS_DARK"] != nil
        let app = launchApp("-sampledata", textSize: textSize, extra: dark ? ["-darkmode"] : [])
        func shot(_ name: String) { snapshot(app, "\(variant)/\(name)") }

        openTab("Groups", in: app)
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 10))
        shot("01-groups")

        app.buttons["New Group"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 5))
        shot("02-create-group")
        app.buttons["Cancel"].firstMatch.tap()

        openGroup("Lisbon Trip", in: app)
        shot("03-group-expenses")
        selectSegment("Balances", in: app)
        shot("04-group-balances")
        selectSegment("Totals", in: app)
        shot("05-group-totals")
        selectSegment("Expenses", in: app)

        let expense = element(labelStartingWith: "Beach bar", in: app)
        reveal(expense, in: app)
        expense.tap()
        XCTAssertTrue(app.navigationBars["Beach bar in Cascais"].waitForExistence(timeout: 5), "expense detail did not open")
        shot("06-expense-detail")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["More"].firstMatch.tap()
        if app.buttons["Group Settings"].waitForExistence(timeout: 5) {
            app.buttons["Group Settings"].tap()
            shot("07-group-settings")
            app.buttons["Done"].firstMatch.tap()
        }

        app.buttons["Add Expense"].firstMatch.tap()
        if app.navigationBars["New Expense"].waitForExistence(timeout: 5) {
            shot("08-add-expense")
            for key in ["6", "0"] { app.buttons[key].firstMatch.tap() }
            // without the pad, so the whole split bar and its amounts are in the picture
            let hide = app.buttons["Hide number pad"].firstMatch
            if hide.waitForExistence(timeout: 2) { hide.tap() }
            shot("09-add-expense-split")
            app.buttons["Cancel"].tap()
            let discard = app.buttons["Discard Changes"].firstMatch
            if discard.waitForExistence(timeout: 5) { discard.tap() }
        }

        for _ in 0..<3 { scroll(.down, in: app) }
        let settle = app.buttons["Settle Up"].firstMatch
        if settle.waitForExistence(timeout: 5) {
            settle.tap()
            if app.navigationBars["Settle Up"].waitForExistence(timeout: 5) {
                shot("10-settle")
                dismissSheet(in: app)
            }
        }

        let backToGroups = app.navigationBars.buttons["Groups"]
        if backToGroups.exists {
            backToGroups.tap()
        } else if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }

        if visit("Friends", in: app) {
            shot("11-friends")
            let friend = element(labelStartingWith: "Jonas Weber", in: app)
            if friend.waitForExistence(timeout: 5) {
                reveal(friend, in: app)
                friend.tap()
                shot("12-friend-detail")
                visit("Friends", in: app)
            }
        }

        if visit("Activity", in: app) {
            shot("13-activity")
        }

        if visit("Search", in: app) {
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 10) {
                field.tap()
                field.typeText("dinner")
                shot("14-search")
                // leaving search brings the tab bar back
                dismissSheet(in: app)
            }
        }

        if visit("Groups", in: app) {
            openAccount(in: app)
            shot("15-account")
            app.swipeUp()
            shot("16-account-more")
        }
    }

    /// Opens a tab when its button can be found, scrolling to bring back a minimized tab bar. A tab
    /// that cannot be reached is noted and skipped, so one odd screen does not stop the rest of the walk.
    @MainActor
    @discardableResult
    private func visit(_ name: String, in app: XCUIApplication) -> Bool {
        let button = app.tabBars.firstMatch.buttons[name]
        var attempts = 0
        while !button.exists && attempts < 6 {
            scroll(attempts.isMultiple(of: 2) ? .down : .up, in: app)
            attempts += 1
        }
        guard button.exists else {
            XCTContext.runActivity(named: "Skipped the \(name) tab: no tab bar") { _ in }
            return false
        }
        button.tap()
        return true
    }

    @MainActor
    private func dismissSheet(in app: XCUIApplication) {
        for title in ["Cancel", "Close", "Done"] {
            let button = app.buttons[title].firstMatch
            if button.exists {
                button.tap()
                return
            }
        }
        app.swipeDown()
    }
}
