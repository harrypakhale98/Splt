import XCTest

final class GroupsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreatesAGroupWithAMember() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Groups"].tap()
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

        let member = app.textFields["Add by name"]
        member.tap()
        member.typeText("Alex\n")
        XCTAssertTrue(app.staticTexts["Alex"].waitForExistence(timeout: 5))

        app.buttons["Create"].tap()

        XCTAssertTrue(app.navigationBars["Weekend Away"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You are all settled up"].exists)
        XCTAssertTrue(app.buttons["Settle Up"].exists)

        app.navigationBars.buttons["Groups"].tap()
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekend Away"].exists)
        XCTAssertTrue(app.staticTexts["Settled up"].exists)
    }
}
