import XCTest

final class GroupsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreatesAGroupWithAMember() {
        let app = launchApp()
        openTab("Groups", in: app)
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Groups Yet"].exists)

        app.buttons["Create Group"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Create"].isEnabled)

        let name = app.textFields["Group Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Weekend Away")
        XCTAssertTrue(app.buttons["Create"].isEnabled)
        let keyboardDone = app.keyboards.buttons["Done"]
        if keyboardDone.waitForExistence(timeout: 3) { keyboardDone.tap() }

        let member = app.textFields["Add by Name"]
        reveal(member, in: app)
        member.tap()
        member.typeText("Alex\n")
        XCTAssertTrue(app.staticTexts["Alex"].waitForExistence(timeout: 5))

        app.buttons["Create"].tap()

        XCTAssertTrue(app.navigationBars["Weekend Away"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["All settled up"].exists)
        XCTAssertFalse(app.buttons["Settle Up"].exists)

        app.navigationBars.buttons["Groups"].tap()
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekend Away"].exists)
        XCTAssertTrue(app.staticTexts["Settled up"].exists)
    }
}
