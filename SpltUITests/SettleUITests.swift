import XCTest

final class SettleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSettlesUpWithAFriendAndUndoesIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-sampledata", "-slowfeedback"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Friends"].tap()
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 5))

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Jonas Weber'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let settle = app.buttons["Settle Up"].firstMatch
        XCTAssertTrue(settle.waitForExistence(timeout: 5))
        settle.tap()

        // a friend with balances in several groups is asked which one to settle first
        let record = app.buttons["Record Payment"]
        if !record.waitForExistence(timeout: 3) {
            let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 3))
            choice.tap()
        }
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Settle Up"].exists)
        record.tap()

        XCTAssertTrue(app.staticTexts["Payment Recorded"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        // the banner keeps the undo after the sheet closes
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        undo.tap()
        XCTAssertTrue(app.staticTexts["Payment undone"].waitForExistence(timeout: 10))
    }
}
