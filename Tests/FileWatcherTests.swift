//
//  FileWatcherTests.swift
//  LogViewerTests
//
//  Created on 2026-04-13.
//

import XCTest
@testable import LogViewer

@MainActor
final class FileWatcherTests: XCTestCase {

    var tempDirectory: URL!
    var testFile: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )

        // Create a test file
        testFile = tempDirectory.appendingPathComponent("test.log")
        try "Initial content\n".write(to: testFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        // Clean up temporary directory
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try await super.tearDown()
    }

    // MARK: - Basic Start/Stop Tests

    func testStartMonitoring() async throws {
        let watcher = FileWatcher()
        let expectation = expectation(description: "File change detected")

        watcher.start(path: testFile.path) {
            expectation.fulfill()
        }

        // Modify the file
        try await Task.sleep(for: .milliseconds(100))
        try "Modified content\n".write(to: testFile, atomically: false, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)

        watcher.stop()
    }

    func testStopMonitoring() async throws {
        let watcher = FileWatcher()
        var callbackCount = 0

        watcher.start(path: testFile.path) {
            callbackCount += 1
        }

        // Stop immediately
        watcher.stop()

        // Modify the file after stopping
        try await Task.sleep(for: .milliseconds(100))
        try "Modified content\n".write(to: testFile, atomically: false, encoding: .utf8)

        // Wait to ensure callback is not called
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertEqual(callbackCount, 0, "Callback should not be called after stop")
    }

    // MARK: - Debounce Tests

    func testDebounceRapidWrites() async throws {
        let watcher = FileWatcher()
        let expectation = expectation(description: "Single callback after debounce")
        var callbackCount = 0

        watcher.start(path: testFile.path) {
            callbackCount += 1
            expectation.fulfill()
        }

        // Perform rapid writes (within 500ms window)
        try await Task.sleep(for: .milliseconds(100))
        try "Write 1\n".write(to: testFile, atomically: false, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(100))
        try "Write 2\n".write(to: testFile, atomically: false, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(100))
        try "Write 3\n".write(to: testFile, atomically: false, encoding: .utf8)

        // Wait for debounce period plus buffer
        await fulfillment(of: [expectation], timeout: 2.0)

        // Wait a bit more to ensure no additional callbacks
        try await Task.sleep(for: .milliseconds(200))

        // Should only receive one callback despite 3 writes
        XCTAssertEqual(callbackCount, 1, "Should debounce to single callback")

        watcher.stop()
    }

    func testDebounceMultipleWindows() async throws {
        let watcher = FileWatcher()
        let expectation = expectation(description: "Multiple debounced callbacks")
        expectation.expectedFulfillmentCount = 2
        var callbackCount = 0

        watcher.start(path: testFile.path) {
            callbackCount += 1
            expectation.fulfill()
        }

        // First window of rapid writes
        try await Task.sleep(for: .milliseconds(100))
        try "Write 1\n".write(to: testFile, atomically: false, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(100))
        try "Write 2\n".write(to: testFile, atomically: false, encoding: .utf8)

        // Wait for debounce to trigger (500ms + buffer)
        try await Task.sleep(for: .milliseconds(700))

        // Second window of rapid writes
        try "Write 3\n".write(to: testFile, atomically: false, encoding: .utf8)

        try await Task.sleep(for: .milliseconds(100))
        try "Write 4\n".write(to: testFile, atomically: false, encoding: .utf8)

        // Wait for second debounce
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(callbackCount, 2, "Should have two debounced callbacks")

        watcher.stop()
    }

    // MARK: - File Deletion Tests

    func testFileDeletion() async throws {
        let watcher = FileWatcher()
        var callbackCount = 0

        watcher.start(path: testFile.path) {
            callbackCount += 1
        }

        // Delete the file
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: testFile)

        // Wait to see if any crashes occur
        try await Task.sleep(for: .milliseconds(800))

        // Should not crash
        watcher.stop()
    }

    func testFileReplacement() async throws {
        let watcher = FileWatcher()
        let expectation = expectation(description: "File replacement detected")

        watcher.start(path: testFile.path) {
            expectation.fulfill()
        }

        // Replace the file (like logrotate does)
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: testFile)
        try "Replaced content\n".write(to: testFile, atomically: false, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)

        watcher.stop()
    }

    // MARK: - Callback on Main Actor Tests

    func testCallbackOnMainActor() async throws {
        let watcher = FileWatcher()
        let expectation = expectation(description: "Callback on main actor")

        watcher.start(path: testFile.path) {
            // This should be on main actor
            XCTAssertTrue(Thread.isMainThread, "Callback should be on main thread")
            expectation.fulfill()
        }

        try await Task.sleep(for: .milliseconds(100))
        try "Modified\n".write(to: testFile, atomically: false, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)

        watcher.stop()
    }

    // MARK: - Edge Cases

    func testNonExistentFile() {
        let watcher = FileWatcher()
        let nonExistentPath = tempDirectory.appendingPathComponent("nonexistent.log").path

        // Should not crash when starting with non-existent file
        watcher.start(path: nonExistentPath) {
            // Should not be called
        }

        watcher.stop()
    }

    func testMultipleStartCalls() async throws {
        let watcher = FileWatcher()
        let expectation = expectation(description: "Only latest callback fires")
        var lastCallbackId = ""

        // Start with first callback
        watcher.start(path: testFile.path) {
            lastCallbackId = "first"
        }

        // Start again with second callback (should replace first)
        watcher.start(path: testFile.path) {
            lastCallbackId = "second"
            expectation.fulfill()
        }

        try await Task.sleep(for: .milliseconds(100))
        try "Modified\n".write(to: testFile, atomically: false, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(lastCallbackId, "second", "Should use latest callback")

        watcher.stop()
    }
}
