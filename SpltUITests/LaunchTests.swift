import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSwitchesThroughTabsAndOpensSettings() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        for name in ["Friends", "Groups", "Activity"] {
            tabBar.buttons[name].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5), "\(name) title missing")
        }

        tabBar.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.switches["Haptics"].waitForExistence(timeout: 5))

        let currencyRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Default Currency'")).firstMatch
        XCTAssertTrue(currencyRow.exists)
        currencyRow.tap()
        XCTAssertTrue(app.navigationBars["Default Currency"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPlaceholderActionOpensSheet() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.firstMatch.buttons["Activity"].tap()
        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
    }
}
