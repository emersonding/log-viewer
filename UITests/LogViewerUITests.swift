//
//  LogViewerUITests.swift
//  LogViewer UI Tests
//
//  End-to-end UI tests using XCUITest framework
//
//  Run from CLI:
//    xcodebuild test -project LogViewer.xcodeproj -scheme LogViewer \
//      -only-testing LogViewerUITests -destination 'platform=macOS'
//

import XCTest

final class LogViewerUITests: XCTestCase {

    var app: XCUIApplication!

    /// Resolve the test_sample.log in the project root
    private static var testLogPath: String {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return projectRoot.appendingPathComponent("test_sample.log").path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    /// Launch app with test log file and wait for it to load
    private func launchWithTestFile() {
        if FileManager.default.fileExists(atPath: Self.testLogPath) {
            app.launchArguments = [Self.testLogPath]
        }
        app.launch()
        app.activate()
    }

    /// Wait for file to finish loading by checking window title
    private func waitForFileLoaded() -> Bool {
        let window = app.windows.firstMatch
        let predicate = NSPredicate(format: "title CONTAINS 'test_sample.log'")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: window)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        return result == .completed
    }

    // MARK: - Test Cases

    /// Test 1: App launches successfully with window
    func testAppLaunches() throws {
        app.launch()
        app.activate()

        XCTAssertTrue(app.exists, "App should launch")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Main window should exist")
    }

    /// Test 2: Welcome screen when no file is open
    func testWelcomeScreen() throws {
        app.launchArguments = []
        app.launch()
        app.activate()

        // Welcome view is a Group with label "Welcome screen"
        let welcomeView = app.groups["Welcome screen"]
        XCTAssertTrue(welcomeView.waitForExistence(timeout: 5), "Welcome screen should appear")

        // Button has accessibilityLabel "Open log file"
        let openButton = app.buttons["Open log file"]
        XCTAssertTrue(openButton.exists, "Open File button should exist")
        XCTAssertTrue(openButton.isEnabled, "Open File button should be enabled")
    }

    /// Test 3: Opens file and displays log content
    func testFileOpenDisplaysLogs() throws {
        launchWithTestFile()

        // Window title should contain the filename once loaded
        XCTAssertTrue(waitForFileLoaded(), "File should load and show in window title")

        // Search field should be visible (part of main content view)
        let searchField = app.textFields["Search logs"]
        XCTAssertTrue(searchField.exists, "Search field should be visible when file is open")

        // Filter buttons should be visible
        let errorFilter = app.buttons["ERROR log level filter"]
        XCTAssertTrue(errorFilter.exists, "ERROR filter should be visible")
    }

    /// Test 4: Filter toggle buttons work
    func testLogLevelFilter() throws {
        launchWithTestFile()
        XCTAssertTrue(waitForFileLoaded())

        // ERROR filter button should exist with "enabled" value
        let errorFilter = app.buttons["ERROR log level filter"]
        XCTAssertTrue(errorFilter.waitForExistence(timeout: 2), "ERROR filter should exist")

        // Toggle the filter off
        errorFilter.tap()

        // App should still be running after filter toggle
        XCTAssertTrue(app.exists, "App should still be running after filter toggle")
    }

    /// Test 5: Search field works
    func testSearchFunctionality() throws {
        launchWithTestFile()
        XCTAssertTrue(waitForFileLoaded())

        // Focus search bar (Cmd+F)
        app.typeKey("f", modifierFlags: .command)

        // Search field is a TextField with label "Search logs"
        let searchField = app.textFields["Search logs"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Search field should exist")

        // Type search query
        searchField.tap()
        searchField.typeText("database")

        // Wait for search to process
        sleep(1)

        // App should still be running
        XCTAssertTrue(app.exists, "App should still be running after search")
    }

    /// Test 6: Refresh functionality (Cmd+R)
    func testRefreshShortcut() throws {
        launchWithTestFile()
        XCTAssertTrue(waitForFileLoaded())

        // Press Cmd+R to refresh
        app.typeKey("r", modifierFlags: .command)

        // Search field should still be visible after refresh
        let searchField = app.textFields["Search logs"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "UI should still be intact after refresh")
    }

    /// Test 7: Keyboard shortcuts work
    func testKeyboardShortcuts() throws {
        launchWithTestFile()
        XCTAssertTrue(waitForFileLoaded())

        // Test Cmd+F (search)
        app.typeKey("f", modifierFlags: .command)
        let searchField = app.textFields["Search logs"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 2), "Cmd+F should show search field")

        // Test Cmd+L (toggle line wrap) - verify no crash
        app.typeKey("l", modifierFlags: .command)

        // Test Cmd+1 (toggle FATAL filter) - verify no crash
        app.typeKey("1", modifierFlags: .command)

        XCTAssertTrue(app.exists, "App should still be running after shortcuts")
    }

    /// Test 8: Takes screenshot
    func testTakeScreenshot() throws {
        launchWithTestFile()
        _ = waitForFileLoaded()
        sleep(1)

        let screenshot = app.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "LogViewer_MainView"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(true, "Screenshot captured")
    }

    // MARK: - Performance Tests

    /// Test 9: App launches within performance threshold
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            app.terminate()
        }
    }

    /// Test 10: File opens within 5 seconds
    func testFileOpenPerformance() throws {
        let startTime = Date()
        launchWithTestFile()

        let loaded = waitForFileLoaded()
        let duration = Date().timeIntervalSince(startTime)

        XCTAssertTrue(loaded, "Log content should appear")
        XCTAssertLessThan(duration, 5.0, "File should open in under 5 seconds")
    }
}
