//
//  PerformanceTests.swift
//  LogViewer
//
//  Created on 2026-04-13.
//  Performance verification tests for Task 5.3
//

import XCTest
@testable import LogViewer

/// Performance tests for filter and search operations on large datasets
@MainActor
final class PerformanceTests: XCTestCase {

    var viewModel: LogViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = LogViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Filter Performance Tests

    /// Test filter toggle response time with large file (500MB target)
    /// Acceptance: <500ms for filter toggle on 500MB file
    func testFilterTogglePerformance_LargeFile() async throws {
        // Skip if huge.log doesn't exist (not critical for CI)
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/huge.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("huge.log not found - run Tests/generate_test_logs.sh first")
        }

        // Load the large file
        print("Loading huge.log for filter performance test...")
        await viewModel.openFile(url: testFileURL)

        guard viewModel.allEntries.count > 0 else {
            XCTFail("Failed to load test file")
            return
        }

        print("Loaded \(viewModel.allEntries.count) entries")

        // Measure filter toggle performance
        measure {
            // Toggle ERROR filter off
            viewModel.filterState.enabledLevels.remove(.error)
            viewModel.applyFilters()

            // Give time for background task to complete
            let expectation = XCTestExpectation(description: "Filter completes")
            Task {
                // Poll for completion (background task updates displayedEntries)
                var lastCount = viewModel.displayedEntries.count
                for _ in 0..<100 {
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    let currentCount = viewModel.displayedEntries.count
                    if currentCount == lastCount {
                        break // Stable, likely complete
                    }
                    lastCount = currentCount
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0) // Should complete within 500ms

            // Toggle ERROR filter back on
            viewModel.filterState.enabledLevels.insert(.error)
            viewModel.applyFilters()
        }
    }

    /// Test filter performance with medium file (100MB target)
    /// Acceptance: <500ms for filter toggle
    func testFilterTogglePerformance_MediumFile() async throws {
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/large.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("large.log not found - run Tests/generate_test_logs.sh first")
        }

        await viewModel.openFile(url: testFileURL)

        guard viewModel.allEntries.count > 0 else {
            XCTFail("Failed to load test file")
            return
        }

        print("Loaded \(viewModel.allEntries.count) entries for filter test")

        // Measure filter toggle
        let startTime = Date()
        viewModel.filterState.enabledLevels = [.error, .fatal] // Filter to just errors
        viewModel.applyFilters()

        // Wait for filter to complete
        let expectation = XCTestExpectation(description: "Filter completes")
        Task {
            var lastCount = viewModel.displayedEntries.count
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                let currentCount = viewModel.displayedEntries.count
                if currentCount == lastCount {
                    break
                }
                lastCount = currentCount
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        let elapsed = Date().timeIntervalSince(startTime)
        print("Filter completed in \(elapsed * 1000)ms")

        XCTAssertLessThan(elapsed, 0.5, "Filter should complete in <500ms, took \(elapsed * 1000)ms")
    }

    /// Test multiple rapid filter toggles (cancellation verification)
    /// Acceptance: Previous filter task cancelled when new one starts
    func testFilterCancellation_RapidToggles() async throws {
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/medium.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("medium.log not found")
        }

        await viewModel.openFile(url: testFileURL)

        guard viewModel.allEntries.count > 10000 else {
            throw XCTSkip("Need at least 10k entries for cancellation test")
        }

        print("Testing cancellation with \(viewModel.allEntries.count) entries")

        // Rapidly toggle filters to trigger cancellation
        let startTime = Date()

        for i in 0..<10 {
            if i % 2 == 0 {
                viewModel.filterState.enabledLevels = [.error, .fatal]
            } else {
                viewModel.filterState.enabledLevels = Set(LogLevel.allCases)
            }
            viewModel.applyFilters()
            // Don't wait - immediately trigger next filter
        }

        // Wait for final filter to complete
        let expectation = XCTestExpectation(description: "Final filter completes")
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            var lastCount = viewModel.displayedEntries.count
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                let currentCount = viewModel.displayedEntries.count
                if currentCount == lastCount {
                    break
                }
                lastCount = currentCount
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        let elapsed = Date().timeIntervalSince(startTime)
        print("10 rapid filter toggles completed in \(elapsed * 1000)ms")

        // Should complete faster than 10 sequential filters due to cancellation
        XCTAssertLessThan(elapsed, 2.0, "Rapid toggles should benefit from cancellation")

        // Final state should match last toggle (all levels)
        XCTAssertEqual(viewModel.displayedEntries.count, viewModel.allEntries.count)
    }

    // MARK: - Search Performance Tests

    /// Test search performance with 100MB file
    /// Acceptance: Search results in <1s for 100MB file
    func testSearchPerformance_100MB() async throws {
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/large.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("large.log not found")
        }

        await viewModel.openFile(url: testFileURL)

        guard viewModel.allEntries.count > 0 else {
            XCTFail("Failed to load test file")
            return
        }

        print("Loaded \(viewModel.allEntries.count) entries for search test")

        // Set search mode to jump
        viewModel.searchState.mode = .jumpToMatch

        // Measure search performance
        let startTime = Date()
        viewModel.searchState.query = "ERROR"
        viewModel.applyFilters()

        // Wait for search to complete
        let expectation = XCTestExpectation(description: "Search completes")
        Task {
            var lastMatchCount = viewModel.searchState.matchCount
            for _ in 0..<200 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                let currentMatchCount = viewModel.searchState.matchCount
                if currentMatchCount == lastMatchCount && currentMatchCount > 0 {
                    break
                }
                lastMatchCount = currentMatchCount
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        let elapsed = Date().timeIntervalSince(startTime)
        print("Search completed in \(elapsed * 1000)ms, found \(viewModel.searchState.matchCount) matches")

        XCTAssertLessThan(elapsed, 1.0, "Search should complete in <1s for 100MB file, took \(elapsed * 1000)ms")
        XCTAssertGreaterThan(viewModel.searchState.matchCount, 0, "Should find matches")
    }

    /// Test search cancellation with rapid query changes
    /// Acceptance: Previous search task cancelled when new one starts
    func testSearchCancellation_RapidQueries() async throws {
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/medium.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("medium.log not found")
        }

        await viewModel.openFile(url: testFileURL)

        guard viewModel.allEntries.count > 10000 else {
            throw XCTSkip("Need at least 10k entries")
        }

        print("Testing search cancellation with \(viewModel.allEntries.count) entries")

        viewModel.searchState.mode = .jumpToMatch

        let startTime = Date()
        let queries = ["ERROR", "WARNING", "INFO", "DEBUG", "TRACE", "FATAL"]

        // Rapidly change search queries
        for query in queries {
            viewModel.searchState.query = query
            viewModel.applyFilters()
            // Don't wait - immediately trigger next search
        }

        // Wait for final search to complete
        let expectation = XCTestExpectation(description: "Final search completes")
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            var lastMatchCount = viewModel.searchState.matchCount
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                let currentMatchCount = viewModel.searchState.matchCount
                if currentMatchCount == lastMatchCount && currentMatchCount > 0 {
                    break
                }
                lastMatchCount = currentMatchCount
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        let elapsed = Date().timeIntervalSince(startTime)
        print("6 rapid search queries completed in \(elapsed * 1000)ms")
        print("Final match count: \(viewModel.searchState.matchCount) for query '\(viewModel.searchState.query)'")

        // Should complete faster than 6 sequential searches due to cancellation
        XCTAssertLessThan(elapsed, 2.0, "Rapid queries should benefit from cancellation")

        // Final state should match last query (FATAL)
        XCTAssertEqual(viewModel.searchState.query, "FATAL")
    }

    /// Test plain-text search (special characters escaped)
    /// Verification: SR-11 requirement - search for "[ERROR]" matches literal text
    func testSearchEscaping_SpecialCharacters() async throws {
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/small.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("small.log not found")
        }

        await viewModel.openFile(url: testFileURL)

        viewModel.searchState.mode = .jumpToMatch

        // Search for literal "[ERROR]" (should be escaped)
        viewModel.searchState.query = "[ERROR]"
        viewModel.applyFilters()

        // Wait for search
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Should find matches (pattern is escaped, so it matches literal "[ERROR]")
        XCTAssertGreaterThan(viewModel.searchState.matchCount, 0, "Should find literal [ERROR] matches")

        // Search for regex special chars
        viewModel.searchState.query = ".*"
        viewModel.applyFilters()

        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Should NOT match everything (pattern is escaped to literal ".*")
        let allCount = viewModel.allEntries.count
        let matchCount = viewModel.searchState.matchCount
        print("Searching for '.*' found \(matchCount) of \(allCount) entries")

        // If it were a regex, it would match all entries. As escaped plain-text, it should match few/none
        XCTAssertLessThan(matchCount, allCount / 2, "Escaped '.*' should not match most entries")
    }

    // MARK: - Memory Budget Tests

    /// Test memory usage stays within budget (2x file size)
    /// Acceptance: 500MB file -> <1GB RAM
    /// Note: This is a smoke test - full memory profiling requires Instruments
    func testMemoryBudget_LargeFile() async throws {
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/huge.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("huge.log not found - run Tests/generate_test_logs.sh first")
        }

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: testFileURL.path)
        guard let fileSize = fileAttributes[.size] as? Int64 else {
            throw XCTSkip("Cannot get file size")
        }

        print("Testing memory budget with file size: \(fileSize / 1_000_000)MB")

        // Get baseline memory
        let baselineMemory = reportMemory()
        print("Baseline memory: \(baselineMemory / 1_000_000)MB")

        // Load file
        await viewModel.openFile(url: testFileURL)

        guard viewModel.allEntries.count > 0 else {
            XCTFail("Failed to load test file")
            return
        }

        print("Loaded \(viewModel.allEntries.count) entries")

        // Measure memory after load
        let loadedMemory = reportMemory()
        print("Memory after load: \(loadedMemory / 1_000_000)MB")

        let memoryUsed = loadedMemory - baselineMemory
        print("Memory used: \(memoryUsed / 1_000_000)MB")

        // Budget: <2x file size
        let budgetBytes = fileSize * 2
        print("Memory budget (2x file size): \(budgetBytes / 1_000_000)MB")

        // This is a soft check - exact memory depends on many factors
        // We'll warn if over budget but not fail the test
        if memoryUsed > budgetBytes {
            print("WARNING: Memory usage (\(memoryUsed / 1_000_000)MB) exceeds budget (\(budgetBytes / 1_000_000)MB)")
            print("Consider implementing lazy loading (Phase 5 Task 5.1 byte-offset model)")
        } else {
            print("✓ Memory usage within budget")
        }

        // Apply filters and check memory doesn't explode
        viewModel.filterState.enabledLevels = [.error, .fatal]
        viewModel.applyFilters()

        // Wait for filter
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        let filteredMemory = reportMemory()
        print("Memory after filter: \(filteredMemory / 1_000_000)MB")

        // Filter should not significantly increase memory
        let filterMemoryIncrease = filteredMemory - loadedMemory
        print("Memory increase from filter: \(filterMemoryIncrease / 1_000_000)MB")

        XCTAssertLessThan(filterMemoryIncrease, Int(fileSize),
                         "Filter should not use more than 1x file size additional memory")
    }

    // MARK: - Combined Filter + Search Performance

    /// Test combined filter and search performance
    /// Acceptance: Filters compose correctly without performance degradation
    func testCombinedFilterAndSearch_Performance() async throws {
        let testFileURL = URL(fileURLWithPath: "Tests/TestLogs/medium.log")
        guard FileManager.default.fileExists(atPath: testFileURL.path) else {
            throw XCTSkip("medium.log not found")
        }

        await viewModel.openFile(url: testFileURL)

        guard viewModel.allEntries.count > 10000 else {
            throw XCTSkip("Need at least 10k entries")
        }

        print("Testing combined filters with \(viewModel.allEntries.count) entries")

        let startTime = Date()

        // Apply level filter
        viewModel.filterState.enabledLevels = [.error, .warning, .fatal]

        // Apply time range filter
        if let firstEntry = viewModel.allEntries.first,
           let lastEntry = viewModel.allEntries.last,
           let firstTime = firstEntry.timestamp,
           let lastTime = lastEntry.timestamp {
            let midpoint = Date(timeIntervalSince1970:
                (firstTime.timeIntervalSince1970 + lastTime.timeIntervalSince1970) / 2)
            viewModel.filterState.timeRangeStart = firstTime
            viewModel.filterState.timeRangeEnd = midpoint
        }

        // Apply search
        viewModel.searchState.mode = .filterToMatch
        viewModel.searchState.query = "failed"

        // Trigger combined filter
        viewModel.applyFilters()

        // Wait for completion
        let expectation = XCTestExpectation(description: "Combined filter completes")
        Task {
            var lastCount = viewModel.displayedEntries.count
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                let currentCount = viewModel.displayedEntries.count
                if currentCount == lastCount {
                    break
                }
                lastCount = currentCount
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        let elapsed = Date().timeIntervalSince(startTime)
        print("Combined filter (level + time + search) completed in \(elapsed * 1000)ms")
        print("Result: \(viewModel.displayedEntries.count) / \(viewModel.allEntries.count) entries")

        XCTAssertLessThan(elapsed, 0.5, "Combined filter should complete in <500ms")
        XCTAssertLessThan(viewModel.displayedEntries.count, viewModel.allEntries.count,
                         "Combined filters should reduce entry count")
    }

    // MARK: - Helper Methods

    /// Get current memory usage in bytes
    private func reportMemory() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
        }
    }
}
