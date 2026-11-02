import XCTest

/// The core journeys a person takes, end to end, on an empty store or the sample trip.
final class JourneyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Adds an expense paid by you and split between everyone. `prepare` runs once the split picker is set.
    @MainActor
    private func addExpense(
        _ app: XCUIApplication, amount: String, title: String, split: String? = nil,
        prepare: (@MainActor () -> Void)? = nil
    ) {
        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5), "form did not open")

        typeAmount(amount, in: app)

        let titleField = element("expense-title", in: app)
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "title field missing")
        titleField.tap()
        titleField.typeText(title)
        titleField.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "keyboard stayed open")

        if let split {
            let segment = app.segmentedControls["split-method"].buttons[split]
            XCTAssertTrue(segment.waitForExistence(timeout: 5), "\(split) missing from the split control")
            segment.tap()
            prepare?()
        }

        let save = element("expense-save", in: app)
        XCTAssertTrue(save.isEnabled, "\(title) should be ready to save")
        save.tap()
        XCTAssertTrue(app.navigationBars["Split Lab"].waitForExistence(timeout: 10), "form did not close after saving \(title)")
        let row = element(labelStartingWith: title, in: app)
        reveal(row, in: app)
        XCTAssertTrue(row.exists, "\(title) is not listed")
    }

    @MainActor
    func testSplitTypesUpdateBalances() {
        let app = launchApp()
        createGroup(named: "Split Lab", members: ["Alex", "Sam"], in: app)

        addExpense(app, amount: "30", title: "Equal")
        addExpense(app, amount: "60", title: "Percent", split: "Percent")
        addExpense(app, amount: "90", title: "Shared", split: "Shares")
        addExpense(app, amount: "120", title: "Adjusted", split: "Adjust")
        addExpense(app, amount: "30", title: "Exact", split: "Exact")

        // alex and sam each owe 10 + 20 + 30 + 40 + 10, so you are owed 110 by each of them
        selectSegment("Balances", in: app)
        let listView = app.segmentedControls.buttons["List"]
        reveal(listView, in: app)
        listView.tap()
        let alex = element(labelContaining: "Alex owes", in: app)
        reveal(alex, in: app)
        XCTAssertTrue(alex.label.contains("110.00"), "Alex should owe 110.00, got \(alex.label)")
        let sam = element(labelContaining: "Sam owes", in: app)
        reveal(sam, in: app)
        XCTAssertTrue(sam.label.contains("110.00"), "Sam should owe 110.00, got \(sam.label)")
    }

    @MainActor
    private func tapButton(_ title: String, in app: XCUIApplication) {
        let button = app.buttons[title]
        reveal(button, in: app)
        button.tap()
    }

    @MainActor
    func testSettleInAGroupAndUndo() {
        let app = launchApp("-uitesting", extra: ["-slowfeedback"])
        createGroup(named: "Split Lab", members: ["Alex"], in: app)
        addExpense(app, amount: "40", title: "Dinner")

        let settle = app.buttons["Settle Up"].firstMatch
        XCTAssertTrue(settle.waitForExistence(timeout: 5))
        settle.tap()

        let record = app.buttons["Record Payment"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()

        XCTAssertTrue(app.staticTexts["Payment Recorded"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["You are all settled up"].waitForExistence(timeout: 10))

        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        undo.tap()
        XCTAssertTrue(app.staticTexts["Payment undone"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["You are all settled up"].exists)
    }

    @MainActor
    func testSearchFindsExpensesAndGroups() {
        let app = launchApp("-sampledata")
        openTab("Search", in: app)

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Airbnb")
        XCTAssertTrue(element(labelStartingWith: "Airbnb in Alfama", in: app).waitForExistence(timeout: 10))

        field.clearAndType("Lisbon")
        XCTAssertTrue(app.staticTexts["Lisbon Trip"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testDeepLinkOpensAGroup() {
        let app = launchApp("-sampledata")
        let url = URL(string: "splt://group/00000000-0000-4000-8000-000000000101")!
        XCUIDevice.shared.system.open(url)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = springboard.buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }

        XCTAssertTrue(app.navigationBars["Lisbon Trip"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testRotatesToLandscapeAndKeepsLayout() {
        let app = launchApp("-sampledata")
        defer { XCUIDevice.shared.orientation = .portrait }

        openGroup("Lisbon Trip", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Lisbon Trip"].waitForExistence(timeout: 5), "title missing in landscape")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "tab bar missing in landscape")
        snapshot(app, "landscape-group")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "landscape group"
        attachment.lifetime = .keepAlways
        add(attachment)

        selectSegment("Balances", in: app)
        reveal(element(labelContaining: "owes", in: app), in: app)
        snapshot(app, "landscape-balances")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Lisbon Trip"].waitForExistence(timeout: 5), "title missing after rotating back")
    }
}

extension XCUIElement {
    /// Replaces the text of a search field.
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
