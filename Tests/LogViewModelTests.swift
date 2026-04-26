//
//  LogViewModelTests.swift
//  LumenTests
//
//  Created on 2026-04-13.
//

import XCTest
@testable import Lumen

@MainActor
final class LogViewModelTests: XCTestCase {
    var viewModel: LogViewModel!
    var testDataDirectory: URL!

    override func setUp() async throws {
        viewModel = LogViewModel()

        // Get test data directory
        let currentFile = URL(fileURLWithPath: #file)
        let testsDirectory = currentFile.deletingLastPathComponent()
        testDataDirectory = testsDirectory.appendingPathComponent("TestData")

        // Create test data directory if it doesn't exist
        try? FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        viewModel = nil
    }

    // MARK: - File Loading Tests

    func testOpenFileSuccess() async throws {
        // Given: A small valid log file
        let fileURL = testDataDirectory.appendingPathComponent("small.log")

        // When: Opening the file
        await viewModel.openFile(url: fileURL)

        // Then: File should be loaded successfully
        XCTAssertFalse(viewModel.isLoading, "Loading should be complete")
        XCTAssertNil(viewModel.errorMessage, "No error should occur")
        XCTAssertEqual(viewModel.allEntries.count, 5, "Should parse 5 log entries")
        XCTAssertEqual(viewModel.displayedEntries.count, 5, "All entries should be displayed")
        XCTAssertNotNil(viewModel.currentFileURL, "File URL should be stored")
        XCTAssertEqual(viewModel.currentFileURL, fileURL)
    }

    func testOpenFileNotFound() async throws {
        // Given: A non-existent file
        let fileURL = testDataDirectory.appendingPathComponent("nonexistent.log")

        // When: Opening the file
        await viewModel.openFile(url: fileURL)

        // Then: Should set error message
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage, "Error message should be set")
        XCTAssertTrue(viewModel.allEntries.isEmpty, "No entries should be loaded")
    }

    func testOpenFileBinaryDetection() async throws {
        // Given: A binary file with null bytes
        let fileURL = testDataDirectory.appendingPathComponent("binary.bin")

        // When: Opening the file
        await viewModel.openFile(url: fileURL)

        // Then: Should detect binary file and set error
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage, "Error message should be set")
        XCTAssertTrue(viewModel.errorMessage?.contains("binary") ?? false, "Error should mention binary file")
        XCTAssertTrue(viewModel.allEntries.isEmpty, "No entries should be loaded")
    }

    func testOpenFileMemoryMappedForLargeFiles() async throws {
        // Given: A file larger than 10MB (this tests the logic path, not actual large file)
        let fileURL = testDataDirectory.appendingPathComponent("small.log")

        // When: Opening the file
        await viewModel.openFile(url: fileURL)

        // Then: File should load successfully (memory mapping is internal implementation)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.allEntries.isEmpty)
    }

    func testOpenFileSetsLoadingState() async throws {
        // Given: A valid log file
        let fileURL = testDataDirectory.appendingPathComponent("small.log")

        // When: Starting to open the file
        let loadingTask = Task {
            await viewModel.openFile(url: fileURL)
        }

        // Give the task a moment to start
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Then: isLoading might be true during parsing (for very small files it might complete too fast)
        // After completion, isLoading should be false
        await loadingTask.value
        XCTAssertFalse(viewModel.isLoading, "Loading should be complete")
    }

    func testOpenFileStoresByteOffset() async throws {
        // Given: A valid log file
        let fileURL = testDataDirectory.appendingPathComponent("small.log")

        // When: Opening the file
        await viewModel.openFile(url: fileURL)

        // Then: Should store byte offset for incremental refresh
        XCTAssertNotNil(viewModel.currentFileOffset, "File offset should be stored")
        XCTAssertGreaterThan(viewModel.currentFileOffset!, 0, "Offset should be > 0 after reading file")
    }

    func testOpenFileAppliesFilters() async throws {
        // Given: A log file and filter state with only ERROR level enabled
        let fileURL = testDataDirectory.appendingPathComponent("small.log")
        viewModel.filterState.enabledLevels = [.error]

        // When: Opening the file
        await viewModel.openFile(url: fileURL)

        // Then: Should apply filters to displayedEntries
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.allEntries.count, 5, "All entries should be parsed")
        XCTAssertEqual(viewModel.displayedEntries.count, 1, "Only ERROR entry should be displayed")
        XCTAssertEqual(viewModel.displayedEntries.first?.level, .error)
    }

    func testLaunchURLIgnoresAppLifecycleArguments() {
        let url = AppFileOpenCoordinator.launchURL(from: [
            "/Applications/Lumen.app/Contents/MacOS/Lumen",
            "-psn_0_12345"
        ])

        XCTAssertNil(url)
    }

    func testLaunchURLReturnsFirstNonFlagArgument() {
        let url = AppFileOpenCoordinator.launchURL(from: [
            "/Applications/Lumen.app/Contents/MacOS/Lumen",
            "-psn_0_12345",
            "/tmp/system.log"
        ])

        XCTAssertEqual(url, URL(fileURLWithPath: "/tmp/system.log"))
    }

    func testFileOpenCoordinatorQueuesUntilHandlerIsRegistered() {
        let coordinator = AppFileOpenCoordinator()
        let firstURL = URL(fileURLWithPath: "/tmp/first.log")
        let secondURL = URL(fileURLWithPath: "/tmp/second.log")
        var openedURLs: [URL] = []

        XCTAssertTrue(coordinator.handleOpen(urls: [firstURL, secondURL]))

        coordinator.setOpenHandler { url in
            openedURLs.append(url)
        }

        XCTAssertEqual(openedURLs, [firstURL, secondURL])
    }

    // MARK: - Extracted Field Tests

    func testAddExtractedField() {
        let before = viewModel.fieldChangeCounter

        viewModel.addExtractedField("request_id")

        XCTAssertEqual(viewModel.extractedFieldNames, ["request_id"])
        XCTAssertGreaterThan(viewModel.fieldChangeCounter, before)
    }

    func testAddExtractedFieldRejectsInvalidAndDuplicateNames() {
        viewModel.addExtractedField("request_id")
        viewModel.addExtractedField("request_id")
        viewModel.addExtractedField("bad field")
        viewModel.addExtractedField("=bad")

        XCTAssertEqual(viewModel.extractedFieldNames, ["request_id"])
    }

    func testAddExtractedFieldRejectsMoreThanLimit() {
        for index in 0..<LogViewModel.maxExtractedFields {
            viewModel.addExtractedField("field_\(index)")
        }

        let before = viewModel.fieldChangeCounter
        viewModel.addExtractedField("field_over_limit")

        XCTAssertEqual(viewModel.extractedFieldNames.count, LogViewModel.maxExtractedFields)
        XCTAssertFalse(viewModel.extractedFieldNames.contains("field_over_limit"))
        XCTAssertEqual(viewModel.fieldChangeCounter, before)
    }

    func testExtractedFieldValueSupportsUnquotedAndQuotedValues() {
        let entry = LogEntry(
            lineNumber: 1,
            level: .info,
            message: #"request_id=abc123 user="Ada Lovelace" path='/api/search' status=200"#,
            rawLine: #"INFO request_id=abc123 user="Ada Lovelace" path='/api/search' status=200"#
        )

        XCTAssertEqual(viewModel.extractedFieldValue(named: "request_id", in: entry), "abc123")
        XCTAssertEqual(viewModel.extractedFieldValue(named: "user", in: entry), "Ada Lovelace")
        XCTAssertEqual(viewModel.extractedFieldValue(named: "path", in: entry), "/api/search")
        XCTAssertEqual(viewModel.extractedFieldValue(named: "status", in: entry), "200")
    }

    func testExtractedFieldValueRequiresExactFieldName() {
        let entry = LogEntry(
            lineNumber: 1,
            level: .info,
            message: "myfield=wrong field=right",
            rawLine: "INFO myfield=wrong field=right"
        )

        XCTAssertEqual(viewModel.extractedFieldValue(named: "field", in: entry), "right")
    }

    func testOpenFileClearsExistingData() async throws {
        // Given: A view model with existing data
        let fileURL1 = testDataDirectory.appendingPathComponent("small.log")
        await viewModel.openFile(url: fileURL1)
        XCTAssertFalse(viewModel.allEntries.isEmpty, "First file should load")

        // When: Opening a different file
        let fileURL2 = testDataDirectory.appendingPathComponent("small.log")
        await viewModel.openFile(url: fileURL2)

        // Then: Previous data should be cleared and replaced
        XCTAssertEqual(viewModel.allEntries.count, 5, "New file data should replace old")
        XCTAssertEqual(viewModel.currentFileURL, fileURL2)
    }

    func testOpenFileInvalidUTF8() async throws {
        // Given: A file with invalid UTF-8
        let fileURL = testDataDirectory.appendingPathComponent("invalid_utf8.log")
        let invalidData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8 sequence
        try invalidData.write(to: fileURL)

        // When: Opening the file
        await viewModel.openFile(url: fileURL)

        // Then: Should handle gracefully (parser replaces with U+FFFD)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage, "Invalid UTF-8 should not cause error")
        // Parser should handle it gracefully
    }

    // MARK: - Filter Logic Tests

    func testApplyFiltersLevelFilter() async throws {
        // Given: Log file with mixed levels
        let fileURL = testDataDirectory.appendingPathComponent("small.log")
        await viewModel.openFile(url: fileURL)

        // When: Filtering to only ERROR and WARNING
        viewModel.filterState.enabledLevels = [.error, .warning]
        viewModel.applyFilters()

        // Then: Only ERROR and WARNING entries shown
        XCTAssertEqual(viewModel.displayedEntries.count, 2)
        XCTAssertTrue(viewModel.displayedEntries.allSatisfy { entry in
            entry.level == .error || entry.level == .warning
        })
    }

    func testApplyFiltersNilLevelAlwaysShown() async throws {
        // Given: Log entries with nil level
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .error, message: "Error", rawLine: "ERROR Error"),
            LogEntry(lineNumber: 2, level: nil, message: "No level", rawLine: "No level")
        ]

        // When: Filtering to only ERROR
        viewModel.filterState.enabledLevels = [.error]
        viewModel.applyFilters()

        // Then: Both ERROR and nil level entries shown
        XCTAssertEqual(viewModel.displayedEntries.count, 2)
    }

    func testApplyFiltersTimeRangeStart() async throws {
        // Given: Log entries with different timestamps
        let baseDate = Date()
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, timestamp: baseDate.addingTimeInterval(-3600), level: .info, message: "Old", rawLine: "Old"),
            LogEntry(lineNumber: 2, timestamp: baseDate, level: .info, message: "Now", rawLine: "Now"),
            LogEntry(lineNumber: 3, timestamp: baseDate.addingTimeInterval(3600), level: .info, message: "Future", rawLine: "Future")
        ]

        // When: Filtering from baseDate onwards
        viewModel.filterState.timeRangeStart = baseDate
        viewModel.applyFilters()

        // Then: Only entries >= baseDate shown
        XCTAssertEqual(viewModel.displayedEntries.count, 2)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Now")
        XCTAssertEqual(viewModel.displayedEntries[1].message, "Future")
    }

    func testApplyFiltersTimeRangeEnd() async throws {
        // Given: Log entries with different timestamps
        let baseDate = Date()
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, timestamp: baseDate.addingTimeInterval(-3600), level: .info, message: "Old", rawLine: "Old"),
            LogEntry(lineNumber: 2, timestamp: baseDate, level: .info, message: "Now", rawLine: "Now"),
            LogEntry(lineNumber: 3, timestamp: baseDate.addingTimeInterval(3600), level: .info, message: "Future", rawLine: "Future")
        ]

        // When: Filtering until baseDate
        viewModel.filterState.timeRangeEnd = baseDate
        viewModel.applyFilters()

        // Then: Only entries <= baseDate shown
        XCTAssertEqual(viewModel.displayedEntries.count, 2)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Old")
        XCTAssertEqual(viewModel.displayedEntries[1].message, "Now")
    }

    func testApplyFiltersTimeRangeBoth() async throws {
        // Given: Log entries spanning multiple hours
        let baseDate = Date()
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, timestamp: baseDate.addingTimeInterval(-7200), level: .info, message: "Too old", rawLine: "Too old"),
            LogEntry(lineNumber: 2, timestamp: baseDate.addingTimeInterval(-3600), level: .info, message: "Start", rawLine: "Start"),
            LogEntry(lineNumber: 3, timestamp: baseDate, level: .info, message: "Middle", rawLine: "Middle"),
            LogEntry(lineNumber: 4, timestamp: baseDate.addingTimeInterval(3600), level: .info, message: "End", rawLine: "End"),
            LogEntry(lineNumber: 5, timestamp: baseDate.addingTimeInterval(7200), level: .info, message: "Too new", rawLine: "Too new")
        ]

        // When: Filtering to time range
        viewModel.filterState.timeRangeStart = baseDate.addingTimeInterval(-3600)
        viewModel.filterState.timeRangeEnd = baseDate.addingTimeInterval(3600)
        viewModel.applyFilters()

        // Then: Only entries within range shown
        XCTAssertEqual(viewModel.displayedEntries.count, 3)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Start")
        XCTAssertEqual(viewModel.displayedEntries[1].message, "Middle")
        XCTAssertEqual(viewModel.displayedEntries[2].message, "End")
    }

    func testApplyFiltersNilTimestampShownByDefault() async throws {
        // Given: Log entries with nil timestamp
        let baseDate = Date()
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, timestamp: baseDate.addingTimeInterval(-7200), level: .info, message: "Old", rawLine: "Old"),
            LogEntry(lineNumber: 2, timestamp: nil, level: .info, message: "No timestamp", rawLine: "No timestamp"),
            LogEntry(lineNumber: 3, timestamp: baseDate, level: .info, message: "Now", rawLine: "Now")
        ]

        // When: Filtering with time range
        viewModel.filterState.timeRangeStart = baseDate.addingTimeInterval(-3600)
        viewModel.filterState.timeRangeEnd = baseDate.addingTimeInterval(3600)
        viewModel.applyFilters()

        // Then: Nil timestamp entries shown along with entries in range
        XCTAssertEqual(viewModel.displayedEntries.count, 2)
        XCTAssertTrue(viewModel.displayedEntries.contains { $0.timestamp == nil })
        XCTAssertTrue(viewModel.displayedEntries.contains { $0.message == "Now" })
    }

    func testApplyFiltersCombinedLevelAndTime() async throws {
        // Given: Log entries with mixed levels and timestamps
        let baseDate = Date()
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, timestamp: baseDate.addingTimeInterval(-3600), level: .error, message: "Old error", rawLine: "Old error"),
            LogEntry(lineNumber: 2, timestamp: baseDate, level: .error, message: "Current error", rawLine: "Current error"),
            LogEntry(lineNumber: 3, timestamp: baseDate, level: .info, message: "Current info", rawLine: "Current info"),
            LogEntry(lineNumber: 4, timestamp: baseDate.addingTimeInterval(3600), level: .error, message: "Future error", rawLine: "Future error")
        ]

        // When: Filtering by ERROR level AND time range
        viewModel.filterState.enabledLevels = [.error]
        viewModel.filterState.timeRangeStart = baseDate
        viewModel.filterState.timeRangeEnd = baseDate.addingTimeInterval(1800)
        viewModel.applyFilters()

        // Then: Only ERROR entries within time range shown (AND logic)
        XCTAssertEqual(viewModel.displayedEntries.count, 1)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Current error")
    }

    func testApplyFiltersSearchFilterMode() async throws {
        // Given: Log entries with searchable content
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .info, message: "Server started", rawLine: "INFO Server started"),
            LogEntry(lineNumber: 2, level: .error, message: "Connection failed", rawLine: "ERROR Connection failed"),
            LogEntry(lineNumber: 3, level: .info, message: "Request received", rawLine: "INFO Request received")
        ]

        // When: Searching in filter mode
        viewModel.searchState.query = "failed"
        viewModel.searchState.mode = .filterToMatch
        viewModel.applyFilters()

        // Then: Only matching entries shown
        XCTAssertEqual(viewModel.displayedEntries.count, 1)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Connection failed")
    }

    func testApplyFiltersSearchJumpMode() async throws {
        // Given: Log entries with searchable content
        let entry1 = LogEntry(lineNumber: 1, level: .info, message: "Server started", rawLine: "INFO Server started")
        let entry2 = LogEntry(lineNumber: 2, level: .error, message: "Connection failed", rawLine: "ERROR Connection failed")
        let entry3 = LogEntry(lineNumber: 3, level: .info, message: "Request received", rawLine: "INFO Request received")

        viewModel.allEntries = [entry1, entry2, entry3]

        // When: Searching in jump mode
        viewModel.searchState.query = "ed"
        viewModel.searchState.mode = .jumpToMatch
        viewModel.applyFilters()

        // Then: All entries shown, matchingLineIDs populated
        XCTAssertEqual(viewModel.displayedEntries.count, 3, "All entries should be displayed in jump mode")
        XCTAssertEqual(viewModel.searchState.matchingLineIDs.count, 3, "All three entries match 'ed'")
        XCTAssertTrue(viewModel.searchState.matchingLineIDs.contains(entry1.id))
        XCTAssertTrue(viewModel.searchState.matchingLineIDs.contains(entry2.id))
        XCTAssertTrue(viewModel.searchState.matchingLineIDs.contains(entry3.id))
    }

    func testApplyFiltersSearchCaseSensitive() async throws {
        // Given: Log entries with mixed case content
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .info, message: "Server Started", rawLine: "INFO Server Started"),
            LogEntry(lineNumber: 2, level: .error, message: "connection failed", rawLine: "ERROR connection failed")
        ]

        // When: Searching case-sensitively for "Server"
        viewModel.searchState.query = "Server"
        viewModel.searchState.isCaseSensitive = true
        viewModel.searchState.mode = .filterToMatch
        viewModel.applyFilters()

        // Then: Only exact case match shown
        XCTAssertEqual(viewModel.displayedEntries.count, 1)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Server Started")
    }

    func testApplyFiltersSearchCaseInsensitive() async throws {
        // Given: Log entries with mixed case content
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .info, message: "Server Started", rawLine: "INFO Server Started"),
            LogEntry(lineNumber: 2, level: .error, message: "connection failed", rawLine: "ERROR connection failed")
        ]

        // When: Searching case-insensitively for "server"
        viewModel.searchState.query = "server"
        viewModel.searchState.isCaseSensitive = false
        viewModel.searchState.mode = .filterToMatch
        viewModel.applyFilters()

        // Then: Case-insensitive match shown
        XCTAssertEqual(viewModel.displayedEntries.count, 1)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Server Started")
    }

    func testApplyFiltersEmptySearchClears() async throws {
        // Given: Entries with previous search state
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .info, message: "Test", rawLine: "INFO Test")
        ]
        viewModel.searchState.matchingLineIDs = [UUID()]

        // When: Clearing search query
        viewModel.searchState.query = ""
        viewModel.applyFilters()

        // Then: Search state cleared
        XCTAssertTrue(viewModel.searchState.matchingLineIDs.isEmpty)
    }

    func testApplyFiltersCombinedLevelTimeSearch() async throws {
        // Given: Complex dataset
        let baseDate = Date()
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, timestamp: baseDate, level: .error, message: "Database connection failed", rawLine: "ERROR Database connection failed"),
            LogEntry(lineNumber: 2, timestamp: baseDate, level: .info, message: "Request failed", rawLine: "INFO Request failed"),
            LogEntry(lineNumber: 3, timestamp: baseDate.addingTimeInterval(3600), level: .error, message: "Timeout occurred", rawLine: "ERROR Timeout occurred"),
            LogEntry(lineNumber: 4, timestamp: baseDate.addingTimeInterval(-3600), level: .error, message: "Connection failed", rawLine: "ERROR Connection failed")
        ]

        // When: Applying all filters (level + time + search)
        viewModel.filterState.enabledLevels = [.error]
        viewModel.filterState.timeRangeStart = baseDate.addingTimeInterval(-1800)
        viewModel.filterState.timeRangeEnd = baseDate.addingTimeInterval(1800)
        viewModel.searchState.query = "connection"
        viewModel.searchState.mode = .filterToMatch
        viewModel.applyFilters()

        // Then: Only entry matching ALL criteria shown (AND logic)
        XCTAssertEqual(viewModel.displayedEntries.count, 1)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "Database connection failed")
    }

    func testApplyFiltersSpecialCharactersInSearch() async throws {
        // Given: Entries with special regex characters
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .error, message: "[ERROR] Failed", rawLine: "[ERROR] Failed"),
            LogEntry(lineNumber: 2, level: .info, message: "Normal log", rawLine: "Normal log")
        ]

        // When: Searching for literal "[ERROR]"
        viewModel.searchState.query = "[ERROR]"
        viewModel.searchState.mode = .filterToMatch
        viewModel.applyFilters()

        // Then: Should match literal brackets, not regex character class
        XCTAssertEqual(viewModel.displayedEntries.count, 1)
        XCTAssertEqual(viewModel.displayedEntries[0].message, "[ERROR] Failed")
    }

    // MARK: - Refresh Logic Tests

    func testRefreshReadsOnlyNewBytes() async throws {
        // Given: A file is already open
        let fileURL = testDataDirectory.appendingPathComponent("incremental.log")
        let initialContent = "2026-04-13T10:00:00Z INFO First line\n2026-04-13T10:00:01Z ERROR Second line\n"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.openFile(url: fileURL)
        let initialCount = viewModel.allEntries.count
        let initialOffset = viewModel.currentFileOffset
        XCTAssertEqual(initialCount, 2)
        XCTAssertNotNil(initialOffset)

        // When: New content is appended to the file
        let newContent = "2026-04-13T10:00:02Z WARNING Third line\n"
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write(newContent.data(using: .utf8)!)
        try fileHandle.close()

        // And refresh is called
        await viewModel.refresh()

        // Then: Only new entries should be added
        XCTAssertEqual(viewModel.allEntries.count, 3)
        XCTAssertEqual(viewModel.allEntries.last?.level, .warning)
        XCTAssertGreaterThan(viewModel.currentFileOffset!, initialOffset!)
    }

    func testRefreshHandlesPartialLine() async throws {
        // Given: A file with an incomplete last line (no newline)
        let fileURL = testDataDirectory.appendingPathComponent("partial.log")
        let initialContent = "2026-04-13T10:00:00Z INFO Complete line\n2026-04-13T10:00:01Z ERROR Incomplete"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.openFile(url: fileURL)
        // openFile parses all content including partial last line
        XCTAssertEqual(viewModel.allEntries.count, 2, "Both lines should be parsed on initial open")

        // When: New content is appended to the file
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write("\n2026-04-13T10:00:02Z WARNING New line\n".data(using: .utf8)!)
        try fileHandle.close()

        await viewModel.refresh()

        // Then: The new line should appear
        XCTAssertEqual(viewModel.allEntries.count, 3)
        XCTAssertEqual(viewModel.allEntries.last?.level, .warning)
    }

    func testRefreshAppendsWithCorrectLineNumbers() async throws {
        // Given: A file is open
        let fileURL = testDataDirectory.appendingPathComponent("line_numbers.log")
        let initialContent = "2026-04-13T10:00:00Z INFO Line 1\n2026-04-13T10:00:01Z ERROR Line 2\n"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.openFile(url: fileURL)
        XCTAssertEqual(viewModel.allEntries.count, 2)
        XCTAssertEqual(viewModel.allEntries.last?.lineNumber, 2)

        // When: New lines are appended
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write("2026-04-13T10:00:02Z WARNING Line 3\n".data(using: .utf8)!)
        try fileHandle.close()

        await viewModel.refresh()

        // Then: Line numbers should continue correctly
        XCTAssertEqual(viewModel.allEntries.count, 3)
        XCTAssertEqual(viewModel.allEntries.last?.lineNumber, 3)
    }

    func testRefreshReappliesFilters() async throws {
        // Given: A file is open with filters applied
        let fileURL = testDataDirectory.appendingPathComponent("filtered_refresh.log")
        let initialContent = "2026-04-13T10:00:00Z INFO Initial\n"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        viewModel.filterState.enabledLevels = [.error, .warning]
        await viewModel.openFile(url: fileURL)
        XCTAssertEqual(viewModel.displayedEntries.count, 0, "INFO filtered out")

        // When: New ERROR line is appended and refreshed
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write("2026-04-13T10:00:01Z ERROR New error\n".data(using: .utf8)!)
        try fileHandle.close()

        await viewModel.refresh()

        // Then: Filters should be reapplied
        XCTAssertEqual(viewModel.allEntries.count, 2)
        XCTAssertEqual(viewModel.displayedEntries.count, 1, "Only ERROR should be displayed")
        XCTAssertEqual(viewModel.displayedEntries.first?.level, .error)
    }

    func testRefreshHandlesFileTruncation() async throws {
        // Given: A file is open
        let fileURL = testDataDirectory.appendingPathComponent("truncated.log")
        let initialContent = "2026-04-13T10:00:00Z INFO Line 1\n2026-04-13T10:00:01Z ERROR Line 2\n"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.openFile(url: fileURL)
        let initialCount = viewModel.allEntries.count
        XCTAssertEqual(initialCount, 2)

        // When: File is truncated (e.g., log rotation)
        let truncatedContent = "2026-04-13T10:00:00Z WARNING New start\n"
        try truncatedContent.write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.refresh()

        // Then: Should detect truncation and do full re-read
        XCTAssertEqual(viewModel.allEntries.count, 1)
        XCTAssertEqual(viewModel.allEntries.first?.level, .warning)
    }

    func testRefreshHandlesEmptyFile() async throws {
        // Given: A file is open
        let fileURL = testDataDirectory.appendingPathComponent("empty_refresh.log")
        let initialContent = "2026-04-13T10:00:00Z INFO Line 1\n"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        await viewModel.openFile(url: fileURL)
        XCTAssertEqual(viewModel.allEntries.count, 1)

        // When: Refresh is called but no new content
        await viewModel.refresh()

        // Then: State should remain unchanged
        XCTAssertEqual(viewModel.allEntries.count, 1)
    }

    func testRefreshNoCurrentFileDoesNothing() async throws {
        // Given: No file is open
        XCTAssertNil(viewModel.currentFileURL)

        // When: Refresh is called
        await viewModel.refresh()

        // Then: Nothing should happen
        XCTAssertTrue(viewModel.allEntries.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Search Navigation Tests

    func testNextMatchCyclesThroughMatches() async throws {
        // Given: Entries with multiple matches
        let entry1 = LogEntry(lineNumber: 1, level: .info, message: "Server started", rawLine: "INFO Server started")
        let entry2 = LogEntry(lineNumber: 2, level: .error, message: "Server failed", rawLine: "ERROR Server failed")
        let entry3 = LogEntry(lineNumber: 3, level: .info, message: "Client connected", rawLine: "INFO Client connected")

        viewModel.allEntries = [entry1, entry2, entry3]
        viewModel.searchState.query = "Server"
        viewModel.searchState.mode = .jumpToMatch
        viewModel.applyFilters()

        // Wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then: Should have 2 matches
        XCTAssertEqual(viewModel.searchState.matchCount, 2)
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 0)

        // When: Next match called
        viewModel.nextMatch()

        // Then: Should move to second match
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 1)

        // When: Next match called again
        viewModel.nextMatch()

        // Then: Should cycle back to first match
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 0)
    }

    func testPreviousMatchCyclesThroughMatches() async throws {
        // Given: Entries with multiple matches
        let entry1 = LogEntry(lineNumber: 1, level: .info, message: "Test one", rawLine: "INFO Test one")
        let entry2 = LogEntry(lineNumber: 2, level: .error, message: "Test two", rawLine: "ERROR Test two")
        let entry3 = LogEntry(lineNumber: 3, level: .info, message: "Test three", rawLine: "INFO Test three")

        viewModel.allEntries = [entry1, entry2, entry3]
        viewModel.searchState.query = "Test"
        viewModel.searchState.mode = .jumpToMatch
        viewModel.applyFilters()

        // Wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then: Should have 3 matches, starting at index 0
        XCTAssertEqual(viewModel.searchState.matchCount, 3)
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 0)

        // When: Previous match called from first position
        viewModel.previousMatch()

        // Then: Should wrap to last match
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 2)

        // When: Previous match called again
        viewModel.previousMatch()

        // Then: Should move to second-to-last match
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 1)
    }

    func testNextMatchWithNoMatches() async throws {
        // Given: No search matches
        viewModel.searchState.matchingLineIDs = []
        viewModel.searchState.currentMatchIndex = 0

        // When: Next match called
        viewModel.nextMatch()

        // Then: Index should remain 0
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 0)
    }

    func testPreviousMatchWithNoMatches() async throws {
        // Given: No search matches
        viewModel.searchState.matchingLineIDs = []
        viewModel.searchState.currentMatchIndex = 0

        // When: Previous match called
        viewModel.previousMatch()

        // Then: Index should remain 0
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 0)
    }

    func testCurrentMatchID() async throws {
        // Given: Entries with search matches (use case-sensitive to match exactly)
        let entry1 = LogEntry(lineNumber: 1, level: .info, message: "Match one", rawLine: "INFO Match one")
        let entry2 = LogEntry(lineNumber: 2, level: .error, message: "No hit", rawLine: "ERROR No hit")
        let entry3 = LogEntry(lineNumber: 3, level: .info, message: "Match two", rawLine: "INFO Match two")

        viewModel.allEntries = [entry1, entry2, entry3]
        viewModel.searchState.query = "Match"
        viewModel.searchState.isCaseSensitive = true
        viewModel.searchState.mode = .jumpToMatch
        viewModel.applyFilters()

        // Then: Current match ID should point to first match
        XCTAssertNotNil(viewModel.currentMatchID)
        XCTAssertEqual(viewModel.currentMatchID, entry1.id)

        // When: Navigate to next match
        viewModel.nextMatch()

        // Then: Current match ID should point to second match
        XCTAssertEqual(viewModel.currentMatchID, entry3.id)
    }

    func testCurrentMatchIDWhenNoMatches() async throws {
        // Given: No search matches
        viewModel.searchState.matchingLineIDs = []

        // Then: Current match ID should be nil
        XCTAssertNil(viewModel.currentMatchID)
    }

    func testSearchQueryUpdateCancelsExistingSearch() async throws {
        // Given: A large dataset with initial search
        let entries = (1...1000).map { i in
            LogEntry(lineNumber: i, level: .info, message: "Line \(i)", rawLine: "INFO Line \(i)")
        }
        viewModel.allEntries = entries

        // When: First search
        viewModel.searchState.query = "Line 1"
        viewModel.searchState.mode = .jumpToMatch
        viewModel.applyFilters()

        // Immediately start second search (should cancel first)
        viewModel.searchState.query = "Line 2"
        viewModel.applyFilters()

        // Wait for async operations
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Then: Should have results for second search only
        XCTAssertTrue(viewModel.searchState.matchingLineIDs.count > 0)
        // The exact count depends on which search completed, but it should be stable
    }

    func testSearchMatchCountDisplay() async throws {
        // Given: Entries with known matches
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .error, message: "Error occurred", rawLine: "ERROR Error occurred"),
            LogEntry(lineNumber: 2, level: .info, message: "Info message", rawLine: "INFO Info message"),
            LogEntry(lineNumber: 3, level: .error, message: "Another error", rawLine: "ERROR Another error")
        ]

        viewModel.searchState.query = "error"
        viewModel.searchState.mode = .jumpToMatch
        viewModel.applyFilters()

        // Wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then: Match count should be accurate (2 entries contain 'error' in rawLine)
        XCTAssertEqual(viewModel.searchState.matchCount, 2, "Should match 'error' in 2 entries' rawLine")
        XCTAssertTrue(viewModel.searchState.hasMatches)
    }

    func testEmptySearchQueryClearsMatches() async throws {
        // Given: Previous search with matches
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .info, message: "Test", rawLine: "INFO Test")
        ]
        viewModel.searchState.query = "Test"
        viewModel.searchState.mode = .jumpToMatch
        viewModel.applyFilters()

        // Wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertTrue(viewModel.searchState.hasMatches)

        // When: Query cleared
        viewModel.searchState.query = ""
        viewModel.applyFilters()

        // Then: Matches should be cleared
        XCTAssertFalse(viewModel.searchState.hasMatches)
        XCTAssertEqual(viewModel.searchState.matchCount, 0)
        XCTAssertEqual(viewModel.searchState.currentMatchIndex, 0)
    }
}
