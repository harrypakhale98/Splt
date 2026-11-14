import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Opens the welcome tour on an empty store. `launchApp` waits for the tabs, which the tour covers.
    @MainActor
    private func launchTour() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting", "-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 30), "the tour never opened")
        return app
    }

    /// A page of the tour by name. Its identifier lands on whatever the page is built from, such as a scroll view.
    @MainActor
    private func page(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["onboarding.page.\(name)"].firstMatch
    }

    @MainActor
    func testTheTourWalksFromYourNameToTheSampleSplit() {
        let app = launchTour()
        let next = app.buttons["onboarding.continue"]

        // there is no swipe forward, so a swipe leaves the welcome page where it is
        XCTAssertTrue(page("welcome", in: app).waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(page("welcome", in: app).exists)
        XCTAssertFalse(app.buttons["BackButton"].exists)

        next.tap()
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(waitUntilHittable(name))
        XCTAssertTrue(app.buttons["BackButton"].waitForExistence(timeout: 2), "the system back button should lead back to the welcome page")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + "Maya Lin")
        XCTAssertEqual(app.images["onboarding.avatar"].label, "Maya Lin")
        tapKeyboardDone(in: app)

        next.tap()
        let bar = app.otherElements["onboarding.demo.bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.skip"].exists, "the sample split has no Skip")
        XCTAssertEqual(next.label, "Start Splitting")

        let share = app.descendants(matching: .any)["onboarding.demo.share"]
        XCTAssertTrue(share.exists)
        let before = share.label
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertNotEqual(share.label, before, "dragging the divider should change Sam's share")

        goBack(in: app)
        XCTAssertTrue(waitUntilHittable(app.textFields["onboarding.name"]))
        goBack(in: app)
        XCTAssertTrue(waitUntilHittable(app.buttons["onboarding.skip"]))

        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(anyTabButton("Groups", in: app).waitForExistence(timeout: 10), "skipping should land on your groups")
    }

    @MainActor
    func testStartSplittingLandsOnYourGroups() {
        let app = launchTour()
        let next = app.buttons["onboarding.continue"]
        next.tap()
        XCTAssertTrue(waitUntilHittable(app.textFields["onboarding.name"]))
        next.tap()
        XCTAssertTrue(app.otherElements["onboarding.demo.bar"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(anyTabButton("Groups", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding.continue"].exists)
    }
}
