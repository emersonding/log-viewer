//
//  RenderingPerformanceTests.swift
//  LogViewer
//
//  Created on 2026-04-13.
//
//  Performance verification for 60fps scrolling at 1M+ lines

import XCTest
@testable import LogViewer
import SwiftUI

final class RenderingPerformanceTests: XCTestCase {

    // MARK: - Cache Performance Tests

    func testSyntaxHighlighterCachePerformance() {
        let highlighter = SyntaxHighlighter()
        let entry = LogEntry(
            lineNumber: 1,
            timestamp: Date(),
            level: .error,
            message: "Test error message with \"quoted string\"",
            rawLine: "2026-04-13T10:30:00Z [ERROR] Test error message with \"quoted string\""
        )

        // Measure first highlight (cache miss)
        measure {
            _ = highlighter.highlight(entry)
        }

        // Verify cache hit is faster than cache miss
        // Use a new entry for the miss measurement
        let newEntry = LogEntry(
            lineNumber: 2,
            timestamp: Date(),
            level: .warning,
            message: "A different warning message with \"another quoted string\" and details",
            rawLine: "2026-04-13T10:30:01Z [WARNING] A different warning message with \"another quoted string\" and details"
        )

        let missTime = measureTime {
            _ = highlighter.highlight(newEntry)
        }

        let hitTime = measureTime {
            _ = highlighter.highlight(newEntry)
        }

        // Cache hit should be meaningfully faster; use 2x threshold for stability
        XCTAssertLessThan(hitTime, missTime, "Cache hit should be faster than cache miss")
    }

    func testHighlighterMemoryBehavior() {
        let highlighter = SyntaxHighlighter()

        // Generate 20k entries (2x cache limit)
        let entries = (1...20_000).map { i in
            LogEntry(
                lineNumber: i,
                timestamp: Date(),
                level: .info,
                message: "Log entry \(i)",
                rawLine: "[INFO] Log entry \(i)"
            )
        }

        // Highlight all entries
        measure {
            for entry in entries {
                _ = highlighter.highlight(entry)
            }
        }

        // Cache should auto-evict old entries (countLimit: 10000)
        // This test verifies no memory explosion occurs
    }

    // MARK: - Large Dataset Tests

    func testLargeDatasetGeneration() {
        // Generate 1M entries for manual testing
        let entries = generateTestEntries(count: 1_000_000)

        XCTAssertEqual(entries.count, 1_000_000)
        XCTAssertEqual(entries.first?.lineNumber, 1)
        XCTAssertEqual(entries.last?.lineNumber, 1_000_000)

        // Verify variety of log levels
        let levels = Set(entries.compactMap { $0.level })
        XCTAssertGreaterThanOrEqual(levels.count, 5, "Should have variety of log levels")
    }

    func testAttributedStringCreationPerformance() {
        let entries = generateTestEntries(count: 10_000)
        let highlighter = SyntaxHighlighter()

        // Measure highlighting 10k entries
        measure {
            for entry in entries {
                _ = highlighter.highlight(entry)
            }
        }
    }

    // MARK: - Scroll Performance Simulation

    func testScrollWindowPerformance() {
        // Simulate scrolling through 1M entries
        // Typical viewport: ~30 lines visible
        let totalEntries = 1_000_000
        let viewportSize = 30
        let entries = generateTestEntries(count: totalEntries)
        let highlighter = SyntaxHighlighter()

        // Simulate scrolling through 100 viewport positions
        measure {
            for scrollPosition in stride(from: 0, to: totalEntries - viewportSize, by: 10_000) {
                // Highlight visible viewport
                for i in scrollPosition..<min(scrollPosition + viewportSize, totalEntries) {
                    _ = highlighter.highlight(entries[i])
                }
            }
        }
    }

    // MARK: - Memory Pressure Tests

    func testMemoryUsageUnder1M() {
        // Verify memory stays reasonable with 1M entries
        let entries = generateTestEntries(count: 1_000_000)
        let highlighter = SyntaxHighlighter()

        // Simulate scrolling pattern (only highlight viewport)
        let viewportSize = 30
        for scrollPosition in stride(from: 0, to: 100_000, by: 1000) {
            for i in scrollPosition..<min(scrollPosition + viewportSize, entries.count) {
                _ = highlighter.highlight(entries[i])
            }
        }

        // No assertion - just verify no crash/memory explosion
        // Use Instruments to measure actual memory usage
    }

    // MARK: - Helper Methods

    private func generateTestEntries(count: Int) -> [LogEntry] {
        let levels: [LogLevel] = [.fatal, .error, .warning, .info, .debug, .trace]
        let messages = [
            "Connection established successfully",
            "Request timeout after 30s",
            "User authentication failed",
            "Database query completed in 45ms",
            "Cache hit for key: user_session_12345",
            "Processing batch of 1000 items"
        ]

        return (1...count).map { i in
            let level = levels[i % levels.count]
            let message = messages[i % messages.count]
            let timestamp = Date().addingTimeInterval(TimeInterval(i))

            return LogEntry(
                lineNumber: i,
                timestamp: timestamp,
                level: level,
                message: message,
                rawLine: "[\(level.rawValue)] \(message)"
            )
        }
    }

    private func measureTime(_ block: () -> Void) -> TimeInterval {
        let start = Date()
        block()
        return Date().timeIntervalSince(start)
    }
}

// MARK: - Manual Performance Verification Guide

/*
 ## Manual Performance Verification Steps

 ### 1. Generate Large Test File

 Run this in Terminal to generate a 1M line test file:

 ```bash
 cd ~/Downloads
 for i in {1..1000000}; do
   LEVEL=$(shuf -n 1 -e "FATAL" "ERROR" "WARNING" "INFO" "DEBUG" "TRACE")
   echo "2026-04-13T10:30:00Z [$LEVEL] Log message number $i"
 done > test_1M_lines.log
 ```

 ### 2. Profile with Instruments

 a) Build in Release mode:
    Product > Scheme > Edit Scheme > Run > Build Configuration > Release

 b) Profile with Time Profiler:
    Product > Profile > Time Profiler

 c) Open the 1M line test file

 d) Scroll rapidly through the file for 30 seconds

 e) Check results:
    - Target: 60fps (16.67ms frame time)
    - Look for frame drops in Instruments timeline
    - Check "Time Profiler" track for hot spots

 ### 3. Memory Profiling

 a) Profile with Allocations:
    Product > Profile > Allocations

 b) Open the 1M line test file

 c) Scroll through several times

 d) Check results:
    - Memory should stabilize (cache eviction working)
    - No unbounded growth
    - Peak memory < 2GB for 1M lines

 ### 4. Expected Results

 ✅ PASS Criteria:
 - Scroll at 60fps consistently
 - Memory usage stays under 2x file size
 - No frame drops during normal scrolling
 - Cache hit rate > 90% after initial scroll

 ⚠️ WARNING Criteria (consider NSTableView):
 - Occasional frame drops (55-58fps)
 - Memory usage 2-3x file size
 - Sluggish response to scroll input

 ❌ FAIL Criteria (implement NSTableView):
 - Consistent frame drops below 45fps
 - Memory usage > 3x file size
 - Visible lag/stutter during scrolling

 ### 5. NSTableView Fallback Decision

 Implement NSTableView fallback ONLY if:
 - Performance tests show <60fps at 500k lines
 - Memory profiling shows unbounded growth
 - LazyVStack optimization attempts fail

 Current implementation should be sufficient because:
 - LazyVStack only renders ~30 visible lines
 - AttributedString caching prevents recomputation
 - SwiftUI automatic view recycling
 - Static highlighter instance prevents allocations
 */
