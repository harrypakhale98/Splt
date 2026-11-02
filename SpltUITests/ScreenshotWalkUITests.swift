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
            app.swipeUp()
            shot("09-add-expense-split")
            app.buttons["Close"].tap()
        }

        for _ in 0..<3 { scroll(.down, in: app) }
        let settle = app.buttons["Settle Up"].firstMatch
        if settle.waitForExistence(timeout: 5) {
            settle.tap()
            if app.navigationBars["Settle Up"].waitForExistence(timeout: 5) {
                shot("10-settle")
                app.buttons["Cancel"].firstMatch.tap()
            }
        }

        let backToGroups = app.navigationBars.buttons["Groups"]
        if backToGroups.exists {
            backToGroups.tap()
        } else if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        openTab("Friends", in: app)
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 10))
        shot("11-friends")
        let friend = element(labelStartingWith: "Jonas Weber", in: app)
        reveal(friend, in: app)
        do {
            friend.tap()
            shot("12-friend-detail")
        }
        openTab("Friends", in: app)

        openTab("Activity", in: app)
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
        shot("13-activity")

        openTab("Search", in: app)
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 10) {
            field.tap()
            field.typeText("dinner")
            shot("14-search")
            // the search keyboard would otherwise cover the tab bar
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap() } else { app.swipeDown() }
        }

        openTab("Account", in: app)
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 10), "the Account screen did not open")
        shot("15-account")
        app.swipeUp()
        shot("16-account-more")
    }
}
