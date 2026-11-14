import XCTest

/// A real double tap on buttons that store something. Each test counts what was stored afterwards.
final class DoubleSubmitUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func rows(labelBeginningWith text: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text))
    }

    /// Fills in the new group sheet up to the Create button.
    @MainActor
    private func fillNewGroup(_ title: String, in app: XCUIApplication) {
        openTab("Groups", in: app)
        let empty = app.buttons["Create Group"].firstMatch
        (empty.waitForExistence(timeout: 2) ? empty : app.buttons["New Group"].firstMatch).tap()
        let name = app.textFields["Group Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(title)
    }

    @MainActor
    private func backToRoot(from title: String, in app: XCUIApplication) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "\(title) did not open")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        goBack(in: app)
        // a stray second push would leave another copy of the screen behind it
        XCTAssertFalse(app.navigationBars[title].waitForExistence(timeout: 2), "\(title) was pushed twice")
    }

    /// Two groups, one made with a single tap: both must show the same number of matching elements.
    @MainActor
    func testADoubleTapOnCreateMakesOneGroup() {
        let app = launchApp()
        fillNewGroup("Single", in: app)
        app.buttons["Create"].tap()
        backToRoot(from: "Single", in: app)
        fillNewGroup("Double", in: app)
        app.buttons["Create"].doubleTap()
        backToRoot(from: "Double", in: app)
        let single = rows(labelBeginningWith: "Single", in: app)
        let double = rows(labelBeginningWith: "Double", in: app)
        XCTAssertTrue(double.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(double.count, single.count)
    }

    @MainActor
    private func addFriend(_ name: String, doubleTap: Bool, in app: XCUIApplication) {
        openTab("Friends", in: app)
        app.buttons["Add Friend"].firstMatch.tap()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        let add = app.buttons["Add"].firstMatch
        if doubleTap { add.doubleTap() } else { add.tap() }
    }

    @MainActor
    func testADoubleTapOnAddFriendAddsOneFriend() {
        let app = launchApp()
        addFriend("Single", doubleTap: false, in: app)
        backToRoot(from: "Single", in: app)
        addFriend("Double", doubleTap: true, in: app)
        XCTAssertFalse(app.alerts["Couldn't Add Friend"].waitForExistence(timeout: 2))
        backToRoot(from: "Double", in: app)
        let single = rows(labelBeginningWith: "Single", in: app)
        let double = rows(labelBeginningWith: "Double", in: app)
        XCTAssertTrue(double.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(double.count, single.count)
    }

    @MainActor
    func testADoubleTapOnAddMemberAddsOnePerson() {
        let app = launchApp()
        createGroup(named: "Members", members: ["Alex"], in: app)
        app.buttons["More"].firstMatch.tap()
        let settings = app.buttons["Group Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), visibleControls(in: app))
        settings.tap()
        let field = app.textFields["Add by Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        reveal(field, in: app)
        field.tap()
        field.typeText("Zed")
        app.buttons["Add Member"].firstMatch.doubleTap()
        XCTAssertTrue(app.staticTexts["Zed"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Zed'")).count, 1)
    }

    @MainActor
    func testADoubleTapOnSendPostsOneComment() {
        let app = launchApp("-sampledata")
        openTab("Groups", in: app)
        let group = element(labelStartingWith: "Lisbon Trip", in: app)
        reveal(group, in: app)
        group.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'paid'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        reveal(row, in: app)
        row.tap()
        let field = app.textFields["Add a comment"].firstMatch
        reveal(field, in: app)
        field.tap()
        field.typeText("Only once")
        app.buttons["Send comment"].doubleTap()
        let posted = app.staticTexts.matching(NSPredicate(format: "label == 'Only once'"))
        XCTAssertTrue(posted.firstMatch.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        XCTAssertEqual(posted.count, 1)
    }

    @MainActor
    func testADoubleTapOnMergeMergesOnce() {
        let app = launchApp()
        addFriend("Target", doubleTap: false, in: app)
        backToRoot(from: "Target", in: app)
        addFriend("Placeholder", doubleTap: false, in: app)
        XCTAssertTrue(app.navigationBars["Placeholder"].waitForExistence(timeout: 10))
        element(labelStartingWith: "More", in: app).tap()
        let merge = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Merge With'")).firstMatch
        XCTAssertTrue(merge.waitForExistence(timeout: 5), visibleControls(in: app))
        merge.tap()
        let target = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Target'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), visibleControls(in: app))
        target.tap()
        let confirm = app.buttons["Merge into Target"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.doubleTap()
        XCTAssertFalse(app.alerts["Couldn't Merge"].waitForExistence(timeout: 3))
    }
}
