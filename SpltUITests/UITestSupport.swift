import XCTest

extension XCTestCase {
    /// True once the element can really be tapped. Something that already exists behind a sheet that
    /// is still closing, or on a keyboard that is still sliding, would take the tap somewhere else.
    @MainActor
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element)
        return XCTWaiter.wait(for: [hittable], timeout: timeout) == .completed
    }

    /// Taps Done on the keyboard when it is up.
    @MainActor
    func tapKeyboardDone(in app: XCUIApplication) {
        let done = app.keyboards.buttons["Done"]
        guard done.waitForExistence(timeout: 3) else { return }
        if waitUntilHittable(done, timeout: 3) { done.tap() }
    }

    /// Launches the app on an empty store (`-uitesting`) or the sample trip (`-sampledata`).
    @MainActor
    func launchApp(
        _ mode: String = "-uitesting", textSize: String? = nil, extra: [String] = []
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [mode] + extra
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        XCTAssertTrue(anyTabButton("Groups", in: app).waitForExistence(timeout: 30), "the tabs never appeared")
        return app
    }

    /// The button for a tab, in the tab bar on most iPhones or in the side rail iPhone Duo shows instead.
    @MainActor
    func tabButton(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        return tabBar.exists ? tabBar.buttons[name] : anyTabButton(name, in: app)
    }

    /// A button with the tab's name that is not a back button, which finds the tab in either layout. The side
    /// rail's buttons sit in no tab bar, so they can only be told apart from a back button to that tab.
    @MainActor
    func anyTabButton(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'BackButton'", name)).firstMatch
    }

    /// A button in a sheet's navigation bar, such as Create. On iPhone Duo the bar hides while the form is scrolled
    /// down, which happens when a field low in the form takes the keyboard, so this scrolls back to the top first.
    @MainActor
    func toolbarButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[title]
        var attempts = 0
        while !button.exists && attempts < 6 {
            scroll(.down, in: app)
            attempts += 1
        }
        if attempts > 0 {
            // a tap while the bar is still sliding back in lands where the button is not yet
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))
            _ = waitUntilHittable(button, timeout: 5)
        }
        return button
    }

    /// Taps the back button, in the navigation bar on most iPhones or in the side rail iPhone Duo shows instead.
    @MainActor
    func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        (back.exists ? back : app.navigationBars.buttons.firstMatch).tap()
    }

    /// The first element with this accessibility identifier, whatever its type.
    @MainActor
    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first element whose label starts with this text.
    @MainActor
    func element(labelStartingWith text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// Labels of the buttons and segments the tree holds right now, for failure messages.
    @MainActor
    func visibleControls(in app: XCUIApplication) -> String {
        (app.buttons.allElementsBoundByIndex + app.segmentedControls.buttons.allElementsBoundByIndex)
            .map { "\($0.label)\($0.isHittable ? "" : "*")" }.joined(separator: " | ")
    }

    /// The first element whose label contains this text.
    @MainActor
    func element(labelContaining text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    func openAccount(in app: XCUIApplication) {
        let button = app.buttons["account.button"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Account button missing")
        button.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 10))
    }

    @MainActor
    func openTab(_ name: String, in app: XCUIApplication) {
        let button = tabButton(name, in: app)
        // On iOS 26 the Search tab shrinks the bar to a single button for the last tab, and tapping it
        // brings the full bar back.
        let collapsed = app.tabBars.firstMatch.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
        if !button.exists && collapsed.exists { collapsed.tap() }
        // the tab bar shrinks to the current tab while a list is scrolled down
        var attempts = 0
        while !button.exists && attempts < 8 {
            scroll(.down, in: app)
            attempts += 1
        }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(name) tab missing")
        button.tap()
    }

    /// Drags the content by about a screenful, up or down. It starts in the upper half so it still reaches the
    /// list when the keyboard covers the lower half, which a plain swipe would hit instead.
    @MainActor
    func scroll(_ direction: ScrollDirection, in app: XCUIApplication) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        switch direction {
        case .up: middle.press(forDuration: 0.05, thenDragTo: top)
        case .down: top.press(forDuration: 0.05, thenDragTo: middle)
        }
    }

    enum ScrollDirection {
        case up
        case down
    }

    /// Scrolls until the element can be tapped. Lists only build the rows near the visible area, so an element
    /// below the fold may not exist yet, and one scrolled past the top is above the screen.
    @MainActor
    func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let height = app.frame.height
        // far enough from the screen edges that the tab bar, keyboard and home indicator do not cover it
        func isComfortable() -> Bool {
            element.isHittable && element.frame.midY > height * 0.18 && element.frame.midY < height * 0.72
        }
        var attempts = 0
        while !isComfortable() && attempts < 14 {
            let isAbove = element.exists && element.frame.midY <= height * 0.18
            scroll(isAbove ? .down : .up, in: app)
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) never became tappable", file: file, line: line)
    }

    /// Picks Expenses, Balances or Spending on the group screen. The picker is a menu at accessibility text sizes.
    @MainActor
    func selectSegment(_ name: String, in app: XCUIApplication) {
        let direct = app.segmentedControls.buttons[name]
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show'")).firstMatch
        var attempts = 0
        while !direct.exists && !menu.exists && attempts < 8 {
            scroll(.up, in: app)
            attempts += 1
        }
        if direct.exists {
            reveal(direct, in: app)
            direct.tap()
            return
        }
        reveal(menu, in: app)
        menu.tap()
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "\(name) missing among: \(visibleControls(in: app))")
        option.tap()
    }

    /// Opens the Groups tab, then a group by name.
    @MainActor
    func openGroup(_ name: String, in app: XCUIApplication) {
        openTab("Groups", in: app)
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) is not listed")
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), "\(name) did not open")
    }

    /// Creates a group with the given members through the New Group sheet and leaves the group open.
    @MainActor
    func createGroup(named name: String, members: [String], in app: XCUIApplication) {
        openTab("Groups", in: app)
        app.buttons["Create Group"].firstMatch.tap()

        let groupName = app.textFields["Group Name"]
        XCTAssertTrue(groupName.waitForExistence(timeout: 5))
        groupName.tap()
        groupName.typeText(name)
        tapKeyboardDone(in: app)

        let memberField = app.textFields["Add by Name"]
        for member in members {
            reveal(memberField, in: app)
            memberField.tap()
            memberField.typeText("\(member)\n")
            XCTAssertTrue(app.staticTexts[member].waitForExistence(timeout: 5))
        }
        toolbarButton("Create", in: app).tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), "\(name) was not created")
    }

    /// Writes a screenshot to the folder named by `SPLT_SHOTS_DIR`. Does nothing when it is not set.
    @MainActor
    func snapshot(_ app: XCUIApplication, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SPLT_SHOTS_DIR"] else { return }
        // let a push or sheet animation finish before the picture is taken
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.7))
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: url)
    }
}
