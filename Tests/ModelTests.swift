//
//  ModelTests.swift
//  LogViewerTests
//
//  Created on 2026-04-13.
//

import XCTest
@testable import LogViewer

final class ModelTests: XCTestCase {

    // MARK: - LogEntry Tests

    func testLogEntryInitialization() {
        let entry = LogEntry(
            lineNumber: 42,
            timestamp: Date(),
            level: .error,
            message: "Test error",
            rawLine: "[ERROR] Test error"
        )

        XCTAssertEqual(entry.lineNumber, 42)
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.message, "Test error")
        XCTAssertNotNil(entry.id)
    }

    func testLogEntryOptionalFields() {
        let entry = LogEntry(
            lineNumber: 1,
            message: "Message without timestamp or level",
            rawLine: "Message without timestamp or level"
        )

        XCTAssertNil(entry.timestamp)
        XCTAssertNil(entry.level)
        XCTAssertEqual(entry.message, "Message without timestamp or level")
    }

    // MARK: - LogLevel Tests

    func testLogLevelColorFatal() {
        let level = LogLevel.fatal
        XCTAssertNotNil(level.color)
        XCTAssertNotNil(level.backgroundColor)
        XCTAssertNotNil(level.foregroundColor)
    }

    func testLogLevelColorError() {
        let level = LogLevel.error
        XCTAssertNotNil(level.color)
        XCTAssertNil(level.backgroundColor)
    }

    func testLogLevelColorWarning() {
        let level = LogLevel.warning
        XCTAssertNotNil(level.color)
        XCTAssertNil(level.backgroundColor)
    }

    func testLogLevelColorInfo() {
        let level = LogLevel.info
        XCTAssertNotNil(level.color)
        XCTAssertNil(level.backgroundColor)
    }

    func testLogLevelColorDebug() {
        let level = LogLevel.debug
        XCTAssertNotNil(level.color)
        XCTAssertNil(level.backgroundColor)
    }

    func testLogLevelColorTrace() {
        let level = LogLevel.trace
        XCTAssertNotNil(level.color)
        XCTAssertNil(level.backgroundColor)
    }

    func testLogLevelAllCases() {
        let levels = LogLevel.allCases
        XCTAssertEqual(levels.count, 6)
        XCTAssertTrue(levels.contains(.fatal))
        XCTAssertTrue(levels.contains(.error))
        XCTAssertTrue(levels.contains(.warning))
        XCTAssertTrue(levels.contains(.info))
        XCTAssertTrue(levels.contains(.debug))
        XCTAssertTrue(levels.contains(.trace))
    }

    // MARK: - FilterState Tests

    func testFilterStateDefaults() {
        let state = FilterState()

        XCTAssertEqual(state.enabledLevels.count, 6)
        XCTAssertTrue(state.enabledLevels.contains(.fatal))
        XCTAssertTrue(state.enabledLevels.contains(.error))
        XCTAssertTrue(state.enabledLevels.contains(.warning))
        XCTAssertTrue(state.enabledLevels.contains(.info))
        XCTAssertTrue(state.enabledLevels.contains(.debug))
        XCTAssertTrue(state.enabledLevels.contains(.trace))
        XCTAssertNil(state.timeRangeStart)
        XCTAssertNil(state.timeRangeEnd)
        XCTAssertTrue(state.isDefault)
    }

    func testFilterStateCustomLevels() {
        let state = FilterState(
            enabledLevels: [.error, .fatal],
            timeRangeStart: nil,
            timeRangeEnd: nil
        )

        XCTAssertEqual(state.enabledLevels.count, 2)
        XCTAssertTrue(state.enabledLevels.contains(.error))
        XCTAssertTrue(state.enabledLevels.contains(.fatal))
        XCTAssertFalse(state.enabledLevels.contains(.info))
        XCTAssertFalse(state.isDefault)
    }

    func testFilterStateWithTimeRange() {
        let now = Date()
        let hourAgo = now.addingTimeInterval(-3600)

        let state = FilterState(
            enabledLevels: Set(LogLevel.allCases),
            timeRangeStart: hourAgo,
            timeRangeEnd: now
        )

        XCTAssertNotNil(state.timeRangeStart)
        XCTAssertNotNil(state.timeRangeEnd)
        XCTAssertFalse(state.isDefault)
    }

    // MARK: - SearchState Tests

    func testSearchStateDefaults() {
        let state = SearchState()

        XCTAssertEqual(state.query, "")
        XCTAssertEqual(state.mode, .jumpToMatch)
        XCTAssertFalse(state.isCaseSensitive)
        XCTAssertTrue(state.matchingLineIDs.isEmpty)
        XCTAssertEqual(state.currentMatchIndex, 0)
        XCTAssertFalse(state.hasMatches)
        XCTAssertEqual(state.matchCount, 0)
    }

    func testSearchStateWithMatches() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let state = SearchState(
            query: "error",
            mode: .filterToMatch,
            isCaseSensitive: true,
            matchingLineIDs: [id1, id2, id3],
            currentMatchIndex: 1
        )

        XCTAssertEqual(state.query, "error")
        XCTAssertEqual(state.mode, .filterToMatch)
        XCTAssertTrue(state.isCaseSensitive)
        XCTAssertTrue(state.hasMatches)
        XCTAssertEqual(state.matchCount, 3)
        XCTAssertEqual(state.currentMatchIndex, 1)
    }

    // MARK: - SearchMode Tests

    func testSearchModeCodable() throws {
        let jumpMode = SearchMode.jumpToMatch
        let filterMode = SearchMode.filterToMatch

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let jumpData = try encoder.encode(jumpMode)
        let filterData = try encoder.encode(filterMode)

        let decodedJump = try decoder.decode(SearchMode.self, from: jumpData)
        let decodedFilter = try decoder.decode(SearchMode.self, from: filterData)

        XCTAssertEqual(decodedJump, .jumpToMatch)
        XCTAssertEqual(decodedFilter, .filterToMatch)
    }

    // MARK: - SettingsState Tests

    func testSettingsStateDefaults() {
        let state = SettingsState.default

        XCTAssertEqual(state.searchMode, .jumpToMatch)
        XCTAssertFalse(state.lineWrapDefault)
        XCTAssertEqual(state.fontSize, 12.0)
        XCTAssertTrue(state.autoRefreshEnabled)
        XCTAssertEqual(state.autoRefreshInterval, 2.0)
        XCTAssertNil(state.customTimestampPattern)
    }

    func testSettingsStateCodable() throws {
        let state = SettingsState(
            searchMode: .filterToMatch,
            lineWrapDefault: true,
            fontSize: 14.0,
            autoRefreshEnabled: false,
            autoRefreshInterval: 5.0,
            customTimestampPattern: "\\d{4}-\\d{2}-\\d{2}"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(SettingsState.self, from: data)

        XCTAssertEqual(decoded.searchMode, .filterToMatch)
        XCTAssertTrue(decoded.lineWrapDefault)
        XCTAssertEqual(decoded.fontSize, 14.0)
        XCTAssertFalse(decoded.autoRefreshEnabled)
        XCTAssertEqual(decoded.autoRefreshInterval, 5.0)
        XCTAssertEqual(decoded.customTimestampPattern, "\\d{4}-\\d{2}-\\d{2}")
    }

    // MARK: - LogViewModel Tests

    @MainActor
    func testLogViewModelInitialization() {
        let viewModel = LogViewModel()

        XCTAssertTrue(viewModel.allEntries.isEmpty)
        XCTAssertTrue(viewModel.displayedEntries.isEmpty)
        XCTAssertNotNil(viewModel.filterState)
        XCTAssertNotNil(viewModel.searchState)
        XCTAssertNotNil(viewModel.settingsState)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
}
