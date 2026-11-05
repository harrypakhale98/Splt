import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSwitchesThroughTabsAndOpensSettings() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch

        for name in ["Friends", "Groups", "Activity"] {
            tabBar.buttons[name].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5), "\(name) title missing")
        }

        XCTAssertFalse(tabBar.buttons["Account"].exists)
        openAccount(in: app)

        XCTAssertTrue(app.buttons["Edit Profile"].waitForExistence(timeout: 5))
        let currencyRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Default Currency'")).firstMatch
        XCTAssertTrue(currencyRow.waitForExistence(timeout: 5))

        app.swipeUp()
        XCTAssertTrue(app.switches["Haptics"].waitForExistence(timeout: 5))
        app.swipeDown()

        XCTAssertTrue(currencyRow.waitForExistence(timeout: 5))
        currencyRow.tap()
        XCTAssertTrue(app.navigationBars["Default Currency"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWelcomeTourOpensFromAccount() {
        let app = launchApp()
        openAccount(in: app)
        let tour = app.buttons["account.welcomeTour"]
        var attempts = 0
        while !tour.isHittable && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
        tour.tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRemindOpensAccountWhenNotificationsAreOff() {
        let app = launchApp("-sampledata")
        openTab("Friends", in: app)
        let friend = element(labelStartingWith: "Hana Sato", in: app)
        reveal(friend, in: app)
        friend.swipeLeft()
        app.buttons["Remind"].firstMatch.tap()
        let tomorrow = app.buttons["Tomorrow"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5))
        tomorrow.tap()
        let openSettings = app.buttons["Open Settings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        openSettings.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testPlaceholderActionOpensSheet() {
        let app = launchApp()
        app.tabBars.firstMatch.buttons["Activity"].tap()
        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Expense"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
    }
}
