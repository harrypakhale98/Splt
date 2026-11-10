import XCTest

/// Runs the system accessibility audit on every main screen. Each finding fails the test with the
/// screen, the kind of issue and the element, so nothing is waved through.
///
/// Contrast, Dynamic Type and clipped text are left out of the automatic audit. On the iOS 26 and later
/// simulators it reports stock controls and system text styles for them (form labels, bar buttons, search
/// prompts), so the results cannot be acted on. Those three are reviewed on screenshots instead, in
/// `ScreenshotWalkUITests`, at the default and the largest text size, in light and dark.
final class AccessibilityAuditUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private static let audited: XCUIAccessibilityAuditType = [
        .sufficientElementDescription, .hitRegion, .trait
    ]

    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) {
        do {
            try app.performAccessibilityAudit(for: Self.audited) { issue in
                // an element drawn outside the screen is a scroll container's cell, not something to read
                if let frame = issue.element?.frame, !app.frame.contains(frame) { return true }
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id '\($0.identifier)' \($0.frame) in \(app.frame)" } ?? "no element"
                let nearby = issue.element?.label.isEmpty == true
                    ? " controls: " + app.buttons.allElementsBoundByIndex.map { "\($0.label)@\(Int($0.frame.minY))" }.joined(separator: ", ")
                    : ""
                XCTFail("\(screen): \(issue.compactDescription) [\(element)]\(nearby)")
                return true
            }
        } catch {
            XCTFail("\(screen): audit could not run: \(error)")
        }
    }

    @MainActor
    func testTabScreens() {
        let app = launchApp("-sampledata")

        openTab("Groups", in: app)
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 10))
        audit(app, "Groups")

        openTab("Friends", in: app)
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 10))
        audit(app, "Friends")

        openTab("Activity", in: app)
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
        audit(app, "Activity")

        openAccount(in: app)
        audit(app, "Account")
        app.buttons["Close"].firstMatch.tap()

        openTab("Search", in: app)
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 10))
        audit(app, "Search")
    }

    @MainActor
    func testGroupScreens() {
        let app = launchApp("-sampledata")
        openGroup("Lisbon Trip", in: app)
        audit(app, "Group expenses")

        selectSegment("Balances", in: app)
        XCTAssertTrue(element(labelContaining: "owes", in: app).waitForExistence(timeout: 5), "balances did not show")
        audit(app, "Group balances")

        selectSegment("Totals", in: app)
        audit(app, "Group totals")

        selectSegment("Expenses", in: app)
        let row = element(labelStartingWith: "Beach bar", in: app)
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Beach bar in Cascais"].waitForExistence(timeout: 5), "expense detail did not open")
        audit(app, "Expense detail")
    }

    @MainActor
    func testSheetsAndFriendScreens() {
        let app = launchApp("-sampledata")

        openTab("Friends", in: app)
        let friend = element(labelStartingWith: "Jonas Weber", in: app)
        reveal(friend, in: app)
        friend.tap()
        XCTAssertTrue(app.buttons["Settle Up"].firstMatch.waitForExistence(timeout: 5))
        audit(app, "Friend detail")

        app.buttons["Settle Up"].firstMatch.tap()
        let record = app.buttons["Record Payment"]
        if !record.waitForExistence(timeout: 3) {
            let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch
            if choice.waitForExistence(timeout: 3) { choice.tap() }
        }
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        audit(app, "Settle up")
        app.buttons["Cancel"].firstMatch.tap()
    }

    @MainActor
    func testFormScreens() {
        let app = launchApp()

        createGroup(named: "Audit Crew", members: ["Alex"], in: app)
        audit(app, "Empty group")

        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        audit(app, "Add expense")
    }

    @MainActor
    func testEmptyTabs() {
        let app = launchApp()

        for name in ["Groups", "Friends", "Activity", "Search"] {
            openTab(name, in: app)
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
            audit(app, "Empty \(name)")
        }

        openTab("Groups", in: app)
        app.buttons["Create Group"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForExistence(timeout: 5))
        let keyboardDone = app.keyboards.buttons["Done"]
        if keyboardDone.waitForExistence(timeout: 3) { keyboardDone.tap() }
        audit(app, "New group")
    }
}
