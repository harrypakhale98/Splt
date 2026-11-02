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

/// Walks the expense screens and saves pictures for design review. Opt in with `SPLT_SHOTS_DIR`.
final class ExpenseDesignShotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPLT_SHOTS_DIR"] != nil, "set SPLT_SHOTS_DIR to run")
    }

    @MainActor
    func testWalk() {
        let environment = ProcessInfo.processInfo.environment
        let dark = environment["SPLT_SHOTS_DARK"] != nil
        let big = environment["SPLT_SHOTS_XXXL"] != nil
        let variant = (dark ? "dark" : "light") + (big ? "-xxxl" : "")
        let app = launchApp(
            "-sampledata", textSize: big ? "UICTContentSizeCategoryAccessibilityXXXL" : nil, extra: dark ? ["-darkmode"] : []
        )
        func shot(_ name: String) { snapshot(app, "expenses/\(variant)/\(name)") }

        openTab("Groups", in: app)
        let group = element(labelStartingWith: "Lisbon Trip", in: app)
        reveal(group, in: app)
        XCTAssertTrue(group.exists, "Lisbon Trip is not listed")
        group.tap()
        XCTAssertTrue(app.buttons["Add Expense"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        shot("1-empty")

        typeAmount("126.40", in: app)
        if big { app.buttons["Done"].firstMatch.tap() }
        let title = element("expense-title", in: app)
        reveal(title, in: app)
        title.tap()
        title.typeText("Welcome dinner")
        title.typeText("\n")
        shot("2-filled")

        let segments = app.segmentedControls["split-method"]
        if segments.exists {
            segments.buttons["Percent"].tap()
            shot("3-percent")
            let bar = element("Split bar", in: app)
            if bar.exists {
                let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.5))
                let end = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
                start.press(forDuration: 0.1, thenDragTo: end)
                shot("4-dragged")
            }
            segments.buttons["Shares"].tap()
            shot("5-shares")
            segments.buttons["Exact"].tap()
            shot("5b-exact")
            segments.buttons["Adjust"].tap()
            shot("5c-adjust")
            segments.buttons["Items"].tap()
            shot("6-items")
        }
        app.buttons["Close"].firstMatch.tap()
        let discard = app.buttons["Discard Changes"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }

        let seafood = element(labelStartingWith: "Seafood", in: app)
        reveal(seafood, in: app)
        seafood.tap()
        _ = app.navigationBars["Seafood dinner"].waitForExistence(timeout: 5)
        shot("7-detail-itemized")
        app.swipeUp()
        shot("8-detail-lower")
    }
}
