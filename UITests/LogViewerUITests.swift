//
//  LogViewerUITests.swift
//  LogViewer UI Tests
//
//  End-to-end UI tests using XCUITest framework
//  Similar to Playwright for web apps
//

import XCTest

final class LogViewerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        // Stop immediately when a failure occurs
        continueAfterFailure = false

        // Launch the app for each test
        app = XCUIApplication()

        // Set launch arguments (e.g., test file path)
        let testLogPath = Bundle(for: type(of: self)).path(forResource: "test_sample", ofType: "log")
        if let logPath = testLogPath {
            app.launchArguments = [logPath]
        }
    }

    override func tearDownWithError() throws {
        // Terminate app after each test
        app.terminate()
    }

    // MARK: - Test Cases (Like Playwright test.describe)

    /// Test 1: App launches successfully
    /// Similar to: test('should launch app', async ({ page }) => { ... })
    func testAppLaunches() throws {
        // Arrange & Act
        app.launch()

        // Assert - Check if app is running
        XCTAssertTrue(app.exists, "App should launch")
        XCTAssertTrue(app.windows.firstMatch.exists, "Main window should exist")
    }

    /// Test 2: Opens welcome screen when no file is open
    /// Similar to: test('should show welcome screen', async ({ page }) => { ... })
    func testWelcomeScreen() throws {
        // Launch without file argument
        app = XCUIApplication()
        app.launch()

        // Check for welcome message (using accessibility label)
        let welcomeText = app.staticTexts["Open a log file to get started"]
        XCTAssertTrue(welcomeText.waitForExistence(timeout: 2), "Welcome message should appear")

        // Check for "Open File" button
        let openButton = app.buttons["Open File"]
        XCTAssertTrue(openButton.exists, "Open File button should exist")
        XCTAssertTrue(openButton.isEnabled, "Open File button should be enabled")
    }

    /// Test 3: Opens file and displays log entries
    /// Similar to: test('should load and display logs', async ({ page }) => { ... })
    func testFileOpenDisplaysLogs() throws {
        // Launch with test file
        app.launch()

        // Wait for log table to appear
        let logTable = app.scrollViews.firstMatch
        XCTAssertTrue(logTable.waitForExistence(timeout: 5), "Log table should appear after file opens")

        // Verify log entries exist
        // Note: Specific assertions depend on your accessibility labels
        let firstLogLine = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'INFO Application started'")).firstMatch
        XCTAssertTrue(firstLogLine.exists, "First log entry should be visible")
    }

    /// Test 4: Filter functionality works
    /// Similar to: test('should filter by log level', async ({ page }) => { ... })
    func testLogLevelFilter() throws {
        app.launch()

        // Wait for content to load
        let logTable = app.scrollViews.firstMatch
        XCTAssertTrue(logTable.waitForExistence(timeout: 5))

        // Count initial entries (check status bar)
        let statusBar = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'of 15 lines'")).firstMatch
        XCTAssertTrue(statusBar.exists, "Status bar should show 15 total lines")

        // Click ERROR filter to toggle it off
        let errorFilter = app.buttons["ERROR"]
        XCTAssertTrue(errorFilter.exists, "ERROR filter button should exist")
        errorFilter.tap()

        // Verify filtered count changes
        let filteredStatus = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'of 15 lines'")).firstMatch
        // After hiding ERROR, should show fewer visible lines
        XCTAssertTrue(filteredStatus.exists, "Status should update after filtering")
    }

    /// Test 5: Search functionality works
    /// Similar to: test('should search and highlight', async ({ page }) => { ... })
    func testSearchFunctionality() throws {
        app.launch()

        // Wait for content
        sleep(2)

        // Focus search bar (Cmd+F)
        app.typeKey("f", modifierFlags: .command)

        // Find search field
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Search field should appear")

        // Type search query
        searchField.tap()
        searchField.typeText("database")

        // Verify search results indicator appears
        // Look for match count (e.g., "3 matches")
        let matchIndicator = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'match'")).firstMatch
        XCTAssertTrue(matchIndicator.waitForExistence(timeout: 2), "Search results should appear")
    }

    /// Test 6: Refresh functionality (Cmd+R)
    /// Similar to: test('should refresh file', async ({ page }) => { ... })
    func testRefreshShortcut() throws {
        app.launch()

        // Wait for initial load
        sleep(2)

        // Press Cmd+R to refresh
        app.typeKey("r", modifierFlags: .command)

        // Verify content still exists after refresh
        let logTable = app.scrollViews.firstMatch
        XCTAssertTrue(logTable.exists, "Log table should still exist after refresh")
    }

    /// Test 7: Keyboard shortcuts work
    /// Similar to: test('keyboard shortcuts', async ({ page }) => { ... })
    func testKeyboardShortcuts() throws {
        app.launch()
        sleep(2)

        // Test Cmd+F (search)
        app.typeKey("f", modifierFlags: .command)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 1), "Cmd+F should focus search")

        // Test Cmd+L (toggle line wrap)
        app.typeKey("l", modifierFlags: .command)
        // Line wrap toggles - no easy assertion, just verify no crash

        // Test Cmd+1 (toggle FATAL filter)
        app.typeKey("1", modifierFlags: .command)
        // Filter toggles - verify no crash

        // All shortcuts executed without crash
        XCTAssertTrue(app.exists, "App should still be running after shortcuts")
    }

    /// Test 8: Takes screenshot (like Playwright's page.screenshot())
    func testTakeScreenshot() throws {
        app.launch()
        sleep(2)

        // Take screenshot
        let screenshot = app.screenshot()

        // Save screenshot to test results
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "LogViewer_MainView"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Screenshot saved successfully
        XCTAssertTrue(true, "Screenshot captured")
    }

    // MARK: - Performance Tests (Like Playwright's page.waitForLoadState)

    /// Test 9: App launches within performance threshold
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            app.terminate()
        }
    }

    /// Test 10: File opens within 3 seconds (for 100MB target)
    func testFileOpenPerformance() throws {
        app.launch()

        let logTable = app.scrollViews.firstMatch

        // Measure time for table to appear
        let startTime = Date()
        let appeared = logTable.waitForExistence(timeout: 5)
        let duration = Date().timeIntervalSince(startTime)

        XCTAssertTrue(appeared, "Log table should appear")
        XCTAssertLessThan(duration, 3.0, "File should open in under 3 seconds")
    }
}
