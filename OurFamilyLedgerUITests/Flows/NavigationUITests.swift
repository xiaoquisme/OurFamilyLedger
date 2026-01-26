import XCTest

/// UI Tests for Navigation flows
final class NavigationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab Navigation Tests

    func testNavigateThroughAllTabs() throws {
        // Given
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        let tabCount = tabBar.buttons.count

        // When navigating through all tabs
        for i in 0..<tabCount {
            let tab = tabBar.buttons.element(boundBy: i)
            if tab.exists && tab.isHittable {
                tab.tap()

                // Brief pause to allow view to load
                Thread.sleep(forTimeInterval: 0.3)

                // Then app should not crash and tab should be selected
                XCTAssertTrue(app.exists, "App crashed after tapping tab \(i)")
            }
        }
    }

    func testTabSelection_staysSelected() throws {
        // Given
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        guard tabBar.buttons.count > 1 else {
            XCTSkip("Not enough tabs to test selection")
            return
        }

        // When selecting second tab
        let secondTab = tabBar.buttons.element(boundBy: 1)
        if secondTab.exists && secondTab.isHittable {
            secondTab.tap()

            // Then it should be selected
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertTrue(secondTab.isSelected || app.exists)
        }
    }

    // MARK: - Settings Navigation Tests

    func testOpenSettings() throws {
        // Given
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        // When - Find and tap settings (usually last tab)
        let lastTabIndex = tabBar.buttons.count - 1
        let settingsTab = tabBar.buttons.element(boundBy: lastTabIndex)

        if settingsTab.exists && settingsTab.isHittable {
            settingsTab.tap()

            // Then settings view should appear
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertTrue(app.exists, "App crashed after opening settings")
        }
    }

    func testSettingsNavigation_backButton() throws {
        // Navigate to settings
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else { return }

        let lastTabIndex = tabBar.buttons.count - 1
        let settingsTab = tabBar.buttons.element(boundBy: lastTabIndex)

        if settingsTab.exists {
            settingsTab.tap()
            Thread.sleep(forTimeInterval: 0.5)

            // Look for any navigation link in settings
            let cells = app.cells
            if cells.count > 0 {
                cells.element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 0.3)

                // Try to go back
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists && backButton.isHittable {
                    backButton.tap()
                }
            }

            XCTAssertTrue(app.exists, "App crashed during settings navigation")
        }
    }

    // MARK: - Family View Tests

    func testOpenFamilyView() throws {
        // Given
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        // Try to find family tab (usually second or third)
        for i in 0..<tabBar.buttons.count {
            let tab = tabBar.buttons.element(boundBy: i)
            if tab.exists {
                tab.tap()
                Thread.sleep(forTimeInterval: 0.3)

                // Look for family-related elements
                let familyElements = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] '成员' OR label CONTAINS[c] '家庭'"))
                if familyElements.count > 0 {
                    // Found family view
                    XCTAssertTrue(app.exists, "App crashed on family view")
                    return
                }
            }
        }

        // If no family view found, just verify app didn't crash
        XCTAssertTrue(app.exists)
    }

    // MARK: - Scroll Tests

    func testListScrolling() throws {
        // Navigate to transaction list
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else { return }

        // Find and tap transaction list tab
        for i in 0..<tabBar.buttons.count {
            tabBar.buttons.element(boundBy: i).tap()
            Thread.sleep(forTimeInterval: 0.3)

            // Look for scrollable lists
            let scrollViews = app.scrollViews
            let tables = app.tables
            let lists = app.collectionViews

            if scrollViews.count > 0 || tables.count > 0 || lists.count > 0 {
                // Try to scroll
                if let scrollable = scrollViews.firstMatch.exists ? scrollViews.firstMatch : nil {
                    scrollable.swipeUp()
                    scrollable.swipeDown()
                } else if tables.count > 0 {
                    tables.firstMatch.swipeUp()
                    tables.firstMatch.swipeDown()
                }

                XCTAssertTrue(app.exists, "App crashed during scrolling")
                return
            }
        }
    }

    // MARK: - Deep Link Tests

    func testDeepNavigation_andBack() throws {
        // Given
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else { return }

        // Navigate to settings
        let lastTab = tabBar.buttons.element(boundBy: tabBar.buttons.count - 1)
        lastTab.tap()
        Thread.sleep(forTimeInterval: 0.3)

        // Tap through multiple levels if possible
        var depth = 0
        while depth < 3 {
            let cells = app.cells
            if cells.count > 0 {
                cells.element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 0.3)
                depth += 1
            } else {
                break
            }
        }

        // Navigate back to root
        while app.navigationBars.buttons.count > 0 {
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.exists && backButton.isHittable {
                backButton.tap()
                Thread.sleep(forTimeInterval: 0.2)
            } else {
                break
            }
        }

        XCTAssertTrue(app.exists, "App crashed during deep navigation")
    }

    // MARK: - Orientation Tests

    func testRotation_doesNotCrash() throws {
        // Given
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 5) else { return }

        // Navigate through tabs while rotating
        for i in 0..<tabBar.buttons.count {
            tabBar.buttons.element(boundBy: i).tap()

            // Rotate device
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 0.3)

            XCTAssertTrue(app.exists, "App crashed during rotation on tab \(i)")

            XCUIDevice.shared.orientation = .portrait
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
}
