import XCTest

final class ExpensesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchInGroup(named name: String, member: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["Groups"].tap()
        app.buttons["Create Group"].firstMatch.tap()

        let groupName = app.textFields["Group Name"]
        XCTAssertTrue(groupName.waitForExistence(timeout: 5))
        groupName.tap()
        groupName.typeText(name)

        let memberField = app.textFields["Add by name"]
        memberField.tap()
        memberField.typeText("\(member)\n")
        XCTAssertTrue(app.staticTexts[member].waitForExistence(timeout: 5))
        app.buttons["Create"].tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
        return app
    }

    private func field(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testAddsAnExpenseAndOpensItsDetail() {
        let app = launchInGroup(named: "Road Trip", member: "Alex")

        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))

        let save = app.buttons["Save"]
        XCTAssertFalse(save.isEnabled, "Save stays off until there is an amount and a title")

        let amount = field("expense-amount", in: app)
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("42")

        app.buttons["Next"].tap()
        let title = field("expense-title", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Gas")
        XCTAssertTrue(save.isEnabled)

        save.tap()
        XCTAssertTrue(app.navigationBars["Road Trip"].waitForExistence(timeout: 10))

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gas'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.navigationBars["Gas"].waitForExistence(timeout: 5))
        let share = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'owes'")).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5) || app.staticTexts["Alex"].exists)
        XCTAssertTrue(app.buttons["Edit"].exists)
    }

    @MainActor
    func testDescribeItFillsTheForm() {
        let app = launchInGroup(named: "Lunch Crew", member: "Alex")

        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))

        let describe = field("expense-describe", in: app)
        XCTAssertTrue(describe.waitForExistence(timeout: 5))
        describe.tap()
        describe.typeText("Pizza 30 with Alex, I paid")
        app.buttons["Fill In"].tap()

        let amount = field("expense-amount", in: app)
        let filled = NSPredicate(format: "value BEGINSWITH '30'")
        expectation(for: filled, evaluatedWith: amount)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Save"].isEnabled)
    }
}
