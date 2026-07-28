//
//  AppKitTableTests.swift
//  Lumen
//
//  Tests for AppKit NSTableView integration — cell configuration,
//  multiline display, and syntax highlighting in NSAttributedString.
//

import AppKit
import XCTest
@testable import Lumen

/// Minimal data source so NSTableView reports a row count without needing the
/// full SwiftUI coordinator.
@MainActor
private final class StaticRowCountDataSource: NSObject, NSTableViewDataSource {
    let rowCount: Int

    init(rowCount: Int) {
        self.rowCount = rowCount
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rowCount
    }
}

@MainActor
final class AppKitTableTests: XCTestCase {

    private var viewModel: LogViewModel!
    /// NSTableView holds its data source weakly, so the test must own it.
    private var tableDataSource: StaticRowCountDataSource?

    override func setUp() {
        super.setUp()
        viewModel = LogViewModel()
    }

    // MARK: - Multiline Entry Tests

    func testMultilineEntryPreservesAllLines() async {
        // Parse a multiline log with stack trace continuation
        let content = """
        2026-04-13T10:40:00Z [INFO] Application started
        2026-04-13T10:41:00Z [ERROR] Exception occurred
        Exception: NullPointerException
          at example.service.Process.execute(Process.swift:42)
          at example.service.Main.run(Main.swift:10)
        2026-04-13T10:42:00Z [INFO] Recovery complete
        """
        let data = content.data(using: .utf8)!
        let parser = LogParser()
        let entries = await parser.parse(data)

        // Should have 3 entries (INFO, ERROR with continuations, INFO)
        XCTAssertEqual(entries.count, 3)

        // The ERROR entry should contain all continuation lines
        let errorEntry = entries[1]
        XCTAssertEqual(errorEntry.level, .error)
        XCTAssertTrue(errorEntry.rawLine.contains("Exception: NullPointerException"))
        XCTAssertTrue(errorEntry.rawLine.contains("Process.swift:42"))
        XCTAssertTrue(errorEntry.rawLine.contains("Main.swift:10"))

        // Verify newlines are preserved in rawLine
        let lineCount = errorEntry.rawLine.components(separatedBy: "\n").count
        XCTAssertEqual(lineCount, 4, "ERROR entry should span 4 lines (header + 3 continuation)")
    }

    // MARK: - NSAttributedString Highlighting Tests

    func testHighlightNSPreservesMultilineContent() {
        let multilineRaw = """
        2026-04-13T10:41:00Z [ERROR] Exception occurred
        Exception: NullPointerException
          at example.service.Process.execute(Process.swift:42)
        """
        let entry = LogEntry(
            lineNumber: 1,
            timestamp: Date(),
            level: .error,
            message: "Exception occurred\nException: NullPointerException\n  at example.service.Process.execute(Process.swift:42)",
            rawLine: multilineRaw
        )

        let highlighter = SyntaxHighlighter()
        let nsAttr = highlighter.highlightNS(entry, fontSize: 12)

        // Full text should be preserved including newlines
        XCTAssertTrue(nsAttr.string.contains("NullPointerException"))
        XCTAssertTrue(nsAttr.string.contains("Process.swift:42"))

        let lineCount = nsAttr.string.components(separatedBy: "\n").count
        XCTAssertGreaterThanOrEqual(lineCount, 3, "NSAttributedString should contain all lines")
    }

    func testHighlightNSAppliesLevelColor() {
        let entry = LogEntry(
            lineNumber: 1,
            timestamp: Date(),
            level: .error,
            message: "Test error",
            rawLine: "2026-04-13T10:00:00Z [ERROR] Test error"
        )

        let highlighter = SyntaxHighlighter()
        let nsAttr = highlighter.highlightNS(entry, fontSize: 12)

        // Check that foreground color attribute exists for the ERROR keyword
        var foundErrorColor = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if let color = value as? NSColor {
                let substring = (nsAttr.string as NSString).substring(with: range)
                if substring.contains("ERROR") && color == .systemRed {
                    foundErrorColor = true
                }
            }
        }
        XCTAssertTrue(foundErrorColor, "ERROR keyword should have systemRed foreground color")
    }

    func testHighlightNSAppliesBoldToLevel() {
        let entry = LogEntry(
            lineNumber: 1,
            timestamp: nil,
            level: .warning,
            message: "Test warning",
            rawLine: "[WARNING] Test warning"
        )

        let highlighter = SyntaxHighlighter()
        let nsAttr = highlighter.highlightNS(entry, fontSize: 12)

        // Check that the WARNING keyword has a bold font
        var foundBold = false
        nsAttr.enumerateAttribute(.font, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if let font = value as? NSFont {
                let substring = (nsAttr.string as NSString).substring(with: range)
                if substring.contains("WARNING") {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.boldFontMask) {
                        foundBold = true
                    }
                }
            }
        }
        XCTAssertTrue(foundBold, "WARNING keyword should have bold font")
    }

    func testHighlightNSCachesResult() {
        let entry = LogEntry(
            lineNumber: 1,
            timestamp: nil,
            level: .info,
            message: "Cached",
            rawLine: "[INFO] Cached"
        )

        let highlighter = SyntaxHighlighter()
        let first = highlighter.highlightNS(entry, fontSize: 12)
        let second = highlighter.highlightNS(entry, fontSize: 12)

        // Both should produce identical content (cache hit)
        XCTAssertEqual(first.string, second.string)
    }

    func testHighlightNSCacheIncludesFontSize() {
        let entry = LogEntry(
            lineNumber: 1,
            timestamp: nil,
            level: .info,
            message: "Cached",
            rawLine: "[INFO] Cached"
        )

        let highlighter = SyntaxHighlighter()
        let small = highlighter.highlightMessageNS(entry, fontSize: 12)
        let large = highlighter.highlightMessageNS(entry, fontSize: 18)

        let smallFont = small.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let largeFont = large.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        XCTAssertEqual(smallFont?.pointSize, 12)
        XCTAssertEqual(largeFont?.pointSize, 18)
    }

    // MARK: - Row Copy

    private func loadCopyFixture() {
        viewModel.displayedEntries = (1...3).map { index in
            LogEntry(
                lineNumber: index,
                level: .info,
                message: "message \(index)",
                rawLine: "[INFO] message \(index)"
            )
        }
    }

    func testCopyTextForSingleRow() {
        loadCopyFixture()

        XCTAssertEqual(viewModel.copyText(forRows: IndexSet(integer: 1)), "[INFO] message 2")
    }

    func testCopyTextJoinsRowsInDisplayOrder() {
        loadCopyFixture()

        // Selection order is irrelevant — output follows display order.
        let text = viewModel.copyText(forRows: IndexSet([2, 0]))

        XCTAssertEqual(text, "[INFO] message 1\n[INFO] message 3")
    }

    func testCopyTextReturnsNilForEmptySelection() {
        loadCopyFixture()

        XCTAssertNil(viewModel.copyText(forRows: IndexSet()))
    }

    func testCopyTextIgnoresOutOfRangeRows() {
        loadCopyFixture()

        // Stale selections can outlive a filter change that shrank the table.
        XCTAssertEqual(viewModel.copyText(forRows: IndexSet([0, 99])), "[INFO] message 1")
        XCTAssertNil(viewModel.copyText(forRows: IndexSet(integer: 99)))
    }

    func testCopyTextPreservesMultilineRawLine() {
        let raw = "[ERROR] boom\n  at Frame.one\n  at Frame.two"
        viewModel.displayedEntries = [
            LogEntry(lineNumber: 1, level: .error, message: "boom", rawLine: raw)
        ]

        XCTAssertEqual(viewModel.copyText(forRows: IndexSet(integer: 0)), raw)
    }

    // MARK: - Table View Clipboard Plumbing

    /// Builds a table view backed by `viewModel`, matching the wiring in
    /// `AppKitLogTableView.makeNSView`.
    private func makeCopyableTable(rowCount: Int) -> CopyableLogTableView {
        let tableView = CopyableLogTableView()
        tableView.allowsMultipleSelection = true
        tableView.copyProvider = { [weak viewModel] rows in
            viewModel?.copyText(forRows: rows)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        tableView.addTableColumn(column)
        let dataSource = StaticRowCountDataSource(rowCount: rowCount)
        tableDataSource = dataSource
        tableView.dataSource = dataSource
        tableView.reloadData()
        return tableView
    }

    func testTableViewCopyWritesSelectedRowsToPasteboard() {
        loadCopyFixture()
        let tableView = makeCopyableTable(rowCount: viewModel.displayedEntries.count)
        tableView.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)

        NSPasteboard.general.clearContents()
        tableView.copy(nil)

        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            "[INFO] message 1\n[INFO] message 3"
        )
    }

    func testTableViewCopyLeavesPasteboardIntactWithoutSelection() {
        loadCopyFixture()
        let tableView = makeCopyableTable(rowCount: viewModel.displayedEntries.count)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("untouched", forType: .string)
        tableView.copy(nil)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "untouched")
    }

    func testTableViewValidatesCopyOnlyWhenRowsAreSelected() {
        loadCopyFixture()
        let tableView = makeCopyableTable(rowCount: viewModel.displayedEntries.count)
        let copyItem = NSMenuItem(title: "Copy", action: #selector(CopyableLogTableView.copy(_:)), keyEquivalent: "c")

        XCTAssertFalse(tableView.validateUserInterfaceItem(copyItem))

        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        XCTAssertTrue(tableView.validateUserInterfaceItem(copyItem))
    }

    func testTableViewAllowsMultipleSelection() {
        loadCopyFixture()
        let tableView = makeCopyableTable(rowCount: viewModel.displayedEntries.count)
        tableView.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)

        XCTAssertEqual(tableView.selectedRowIndexes.count, 2)
    }

    // MARK: - Filter Change Counter

    func testFilterChangeCounterIncrements() {
        viewModel.allEntries = [
            LogEntry(lineNumber: 1, level: .info, message: "test", rawLine: "[INFO] test")
        ]

        let before = viewModel.filterChangeCounter
        viewModel.applyFilters()
        let after = viewModel.filterChangeCounter

        XCTAssertGreaterThan(after, before, "filterChangeCounter should increment on applyFilters()")
    }
}
