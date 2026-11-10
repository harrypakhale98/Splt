import XCTest

final class SettleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSettlesUpWithAFriendAndUndoesIt() {
        let app = launchApp("-sampledata", extra: ["-slowfeedback"])
        openTab("Friends", in: app)
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 5))

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Jonas Weber'")).firstMatch
        reveal(row, in: app)
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


        // the banner keeps the undo after the sheet closes
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        undo.tap()
        XCTAssertTrue(app.staticTexts["Payment undone"].waitForExistence(timeout: 10))
    }
}
