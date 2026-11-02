import XCTest

/// Walks every main screen and saves a screenshot of each, in light and dark and at the default and
/// largest accessibility text sizes, for reviewing the layouts by eye. It runs only when `SPLT_SHOTS_DIR`
/// names the folder to write to.
final class ScreenshotWalkUITests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPLT_SHOTS_DIR"] != nil, "set SPLT_SHOTS_DIR to run the walk")
    }

    override func tearDown() async throws {
        await MainActor.run { XCUIDevice.shared.appearance = .light }
    }

    @MainActor
    func testWalkLightDefaultSize() {
        walk(variant: "light", dark: false, textSize: nil)
    }

    @MainActor
    func testWalkDarkDefaultSize() {
        walk(variant: "dark", dark: true, textSize: nil)
    }

    @MainActor
    func testWalkLightLargestText() {
        walk(variant: "light-xxxl", dark: false, textSize: Self.largest)
    }

    @MainActor
    func testWalkDarkLargestText() {
        walk(variant: "dark-xxxl", dark: true, textSize: Self.largest)
    }

    @MainActor
    private func walk(variant: String, dark: Bool, textSize: String?) {
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = launchApp("-sampledata", textSize: textSize)
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
        if expense.waitForExistence(timeout: 5) {
            expense.tap()
            shot("06-expense-detail")
            app.navigationBars.buttons.firstMatch.tap()
        }

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

        let settle = app.buttons["Settle Up"].firstMatch
        if settle.waitForExistence(timeout: 5) {
            settle.tap()
            if app.navigationBars["Settle Up"].waitForExistence(timeout: 5) {
                shot("10-settle")
                app.buttons["Cancel"].firstMatch.tap()
            }
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
        }

        openTab("Account", in: app)
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 10))
        shot("15-account")
        app.swipeUp()
        shot("16-account-more")
    }
}
