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

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Maya Chen'")).firstMatch
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
        XCTAssertTrue(waitUntilHittable(undo), "the undo banner never came out from behind the closing sheet")
        undo.tap()
        XCTAssertTrue(app.staticTexts["Payment undone"].waitForExistence(timeout: 10))
    }

    /// A second tap on Record Payment or on Undo must not store or reverse anything twice. Undoing
    /// one payment puts the friend's balance back exactly, so any stray payment would show here.
    @MainActor
    func testDoubleTapsRecordAndUndoOnlyOnce() {
        let app = launchApp("-sampledata", extra: ["-slowfeedback"])
        openTab("Friends", in: app)
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 5))

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Maya Chen'")).firstMatch
        reveal(row, in: app)
        let before = row.label
        row.tap()

        let settle = app.buttons["Settle Up"].firstMatch
        XCTAssertTrue(settle.waitForExistence(timeout: 5))
        settle.tap()
        let record = app.buttons["Record Payment"]
        if !record.waitForExistence(timeout: 3) {
            let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 3))
            choice.tap()
        }
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.doubleTap()

        // the sheet closes by itself and the banner keeps the undo
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(waitUntilHittable(undo), "the undo banner never came out from behind the closing sheet")
        undo.doubleTap()
        XCTAssertTrue(app.staticTexts["Payment undone"].waitForExistence(timeout: 10))

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 5))
        reveal(row, in: app)
        XCTAssertEqual(row.label, before)
    }
}
