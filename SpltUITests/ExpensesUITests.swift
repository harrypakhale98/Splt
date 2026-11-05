import XCTest

final class ExpensesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchInGroup(named name: String, member: String) -> XCUIApplication {
        let app = launchApp()
        createGroup(named: name, members: [member], in: app)
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

        let save = field("expense-save", in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save stays off until there is an amount and a title")

        typeAmount("42", in: app)

        let title = field("expense-title", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Gas")
        title.typeText("\n")
        XCTAssertTrue(save.isEnabled)

        save.tap()
        XCTAssertTrue(app.navigationBars["Road Trip"].waitForExistence(timeout: 10))

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gas'")).firstMatch
        reveal(row, in: app)
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
        XCTAssertTrue(field("expense-save", in: app).isEnabled)
    }
}

extension XCTestCase {
    /// Types an amount on the form's built-in number pad.
    @MainActor
    func typeAmount(_ amount: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for character in amount {
            let identifier = character == "." ? "key-decimal" : "key-\(character)"
            let key = app.buttons[identifier]
            XCTAssertTrue(key.waitForExistence(timeout: 5), "number pad key \(character) missing", file: file, line: line)
            key.tap()
        }
    }
}
