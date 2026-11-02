import XCTest

/// Saves screenshots of the friend, settle, activity and search screens for reviewing their design. It runs only
/// when `SPLT_SHOTS_DIR` names a folder. `SPLT_SHOTS_DARK` picks the dark appearance and `SPLT_SHOTS_SIZE=xxxl` the
/// largest text.
final class FriendsDesignShotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPLT_SHOTS_DIR"] != nil, "set SPLT_SHOTS_DIR to run")
    }

    @MainActor
    func testFriendScreens() {
        let env = ProcessInfo.processInfo.environment
        let dark = env["SPLT_SHOTS_DARK"] != nil
        let large = env["SPLT_SHOTS_SIZE"] == "xxxl"
        let variant = (large ? "xxxl" : "default") + (dark ? "-dark" : "-light")
        let app = launchApp(
            "-sampledata", textSize: large ? "UICTContentSizeCategoryAccessibilityXXXL" : nil,
            extra: (dark ? ["-darkmode"] : []) + ["-slowfeedback"]
        )
        func shot(_ name: String) { snapshot(app, "friends/\(variant)/\(name)") }

        openTab("Friends", in: app)
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 10))
        shot("01-friends")

        let jonas = "00000000-0000-4000-8000-000000000012"
        if large {
            // the list is very long at the largest text size, so go straight to the friend
            app.open(URL(string: "splt://friend/\(jonas)")!)
        } else {
            let friend = element(labelStartingWith: "Jonas Weber", in: app)
            reveal(friend, in: app)
            friend.tap()
        }
        XCTAssertTrue(app.navigationBars["Jonas Weber"].waitForExistence(timeout: 10))
        shot("02-friend-hero")
        scroll(.up, in: app)
        shot("03-friend-timeline")
        scroll(.down, in: app)
        scroll(.down, in: app)

        if large {
            app.open(URL(string: "splt://settle/\(jonas)")!)
        } else {
            let settle = app.buttons["Settle Up"].firstMatch
            reveal(settle, in: app)
            settle.tap()
        }
        let record = app.buttons["Record Payment"]
        if !record.waitForExistence(timeout: 5) {
            let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS ':'")).firstMatch
            if choice.waitForExistence(timeout: 3) { choice.tap() }
        }
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        shot("04-settle")

        let partial = app.buttons["Partial"].firstMatch
        if partial.exists {
            partial.tap()
            shot("05-settle-partial")
            scroll(.up, in: app)
            shot("06-settle-details")
            scroll(.down, in: app)
        }
        record.tap()
        shot("07-ceremony")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.5))
        shot("08-settled")
        app.buttons["Done"].firstMatch.tap()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))
        shot("09-undo-banner")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        openTab("Activity", in: app)
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
        shot("10-activity")
        scroll(.up, in: app)
        shot("11-activity-scrolled")

        openTab("Search", in: app)
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 10))
        shot("12-search-empty")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
            field.typeText("dinners Sam paid in March")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
            shot("13-search-question")
            let clear = app.buttons["Clear text"].firstMatch
            if clear.exists { clear.tap() }
            field.typeText("Lisbon")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
            shot("14-search-results")
            if clear.exists { clear.tap() }
            field.typeText("zzzz")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
            shot("15-search-none")
        }
    }

    /// Only the friend hero, for a quick look after a change to it.
    @MainActor
    func testFriendHero() {
        let env = ProcessInfo.processInfo.environment
        let dark = env["SPLT_SHOTS_DARK"] != nil
        let large = env["SPLT_SHOTS_SIZE"] == "xxxl"
        let variant = (large ? "xxxl" : "default") + (dark ? "-dark" : "-light")
        XCUIDevice.shared.appearance = dark ? .dark : .light
        let app = launchApp(
            "-sampledata", textSize: large ? "UICTContentSizeCategoryAccessibilityXXXL" : nil,
            extra: dark ? ["-darkmode"] : []
        )
        app.open(URL(string: "splt://friend/00000000-0000-4000-8000-000000000012")!)
        XCTAssertTrue(app.navigationBars["Jonas Weber"].waitForExistence(timeout: 10))
        snapshot(app, "friends/\(variant)/hero")
    }
}
