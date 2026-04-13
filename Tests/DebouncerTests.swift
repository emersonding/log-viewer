//
//  DebouncerTests.swift
//  LogViewerTests
//
//  Created on 2026-04-13.
//

import XCTest
@testable import LogViewer

final class DebouncerTests: XCTestCase {

    // MARK: - Basic Trigger and Action

    func testDebouncerFiresActionAfterDelay() {
        let expectation = self.expectation(description: "Action should fire after delay")
        var actionCalled = false

        let debouncer = Debouncer(delay: 0.1) {
            actionCalled = true
            expectation.fulfill()
        }

        debouncer.trigger()

        XCTAssertFalse(actionCalled, "Action should not fire immediately")

        waitForExpectations(timeout: 0.5)
        XCTAssertTrue(actionCalled, "Action should have fired after delay")
    }

    // MARK: - Timer Reset

    func testDebouncerResetsTimerOnMultipleTriggers() {
        let expectation = self.expectation(description: "Action should fire once after final trigger")
        var callCount = 0

        let debouncer = Debouncer(delay: 0.2) {
            callCount += 1
            expectation.fulfill()
        }

        // Trigger multiple times rapidly
        debouncer.trigger()
        usleep(50_000) // 0.05s
        debouncer.trigger()
        usleep(50_000) // 0.05s
        debouncer.trigger()
        usleep(50_000) // 0.05s
        debouncer.trigger()

        // Should not have fired yet
        XCTAssertEqual(callCount, 0, "Action should not fire during trigger sequence")

        // Wait for action to fire
        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(callCount, 1, "Action should fire exactly once")
    }

    // MARK: - Delayed Subsequent Triggers

    func testDebouncerDelaysBetweenTriggerSequences() {
        let expectation1 = self.expectation(description: "First action sequence")
        var callCount = 0

        let debouncer = Debouncer(delay: 0.1) {
            callCount += 1
            expectation1.fulfill()
        }

        // First sequence
        debouncer.trigger()

        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(callCount, 1, "First action should have fired")

        // Second sequence
        let expectation2 = self.expectation(description: "Second action sequence")

        let debouncer2 = Debouncer(delay: 0.1) {
            callCount += 1
            expectation2.fulfill()
        }

        debouncer2.trigger()

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(callCount, 2, "Second action should have fired")
    }

    // MARK: - Thread Safety

    func testDebouncerIsThreadSafe() {
        let expectation = self.expectation(description: "Action fires safely from multiple threads")
        expectation.expectedFulfillmentCount = 1
        var callCount = 0
        let lock = NSLock()

        let debouncer = Debouncer(delay: 0.1) {
            lock.lock()
            callCount += 1
            lock.unlock()
            expectation.fulfill()
        }

        let queue1 = DispatchQueue(label: "com.test.queue1")
        let queue2 = DispatchQueue(label: "com.test.queue2")
        let queue3 = DispatchQueue(label: "com.test.queue3")

        queue1.async {
            debouncer.trigger()
        }

        usleep(20_000) // 0.02s

        queue2.async {
            debouncer.trigger()
        }

        usleep(20_000) // 0.02s

        queue3.async {
            debouncer.trigger()
        }

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(callCount, 1, "Action should fire exactly once despite multiple threads")
    }

    // MARK: - No Trigger Case

    func testDebouncerDoesNotFireWithoutTrigger() {
        var actionCalled = false

        let debouncer = Debouncer(delay: 0.1) {
            actionCalled = true
        }

        // Never call trigger

        usleep(200_000) // Wait longer than delay

        XCTAssertFalse(actionCalled, "Action should not fire without trigger")
    }

    // MARK: - Cancel Method

    func testDebouncerCancelPreventsAction() {
        var actionCalled = false

        let debouncer = Debouncer(delay: 0.2) {
            actionCalled = true
        }

        debouncer.trigger()
        usleep(50_000) // 0.05s
        debouncer.cancel()

        usleep(250_000) // Wait longer than original delay

        XCTAssertFalse(actionCalled, "Action should not fire after cancel")
    }

    // MARK: - Multiple Cancels

    func testDebouncerHandlesMultipleCancels() {
        var actionCalled = false

        let debouncer = Debouncer(delay: 0.1) {
            actionCalled = true
        }

        debouncer.trigger()
        debouncer.cancel()
        debouncer.cancel() // Should not crash

        usleep(200_000)

        XCTAssertFalse(actionCalled, "Action should not fire after multiple cancels")
    }

    // MARK: - Trigger After Cancel

    func testDebouncerCanTriggerAfterCancel() {
        let expectation = self.expectation(description: "Action should fire after cancel and re-trigger")
        var callCount = 0

        let debouncer = Debouncer(delay: 0.1) {
            callCount += 1
            expectation.fulfill()
        }

        debouncer.trigger()
        usleep(50_000) // 0.05s
        debouncer.cancel()
        usleep(50_000) // 0.05s
        debouncer.trigger() // Re-trigger

        waitForExpectations(timeout: 0.5)
        XCTAssertEqual(callCount, 1, "Action should fire once after re-trigger")
    }
}
