import XCTest

final class LaunchTests: XCTestCase {
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Splt"].waitForExistence(timeout: 5))
    }
}
