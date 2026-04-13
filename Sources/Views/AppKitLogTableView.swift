//
//  AppKitLogTableView.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import AppKit
import SwiftUI

/// NSViewRepresentable wrapping NSTableView for high-performance log display.
///
/// NSTableView with cell reuse and `reloadData()` handles millions of rows natively,
/// avoiding SwiftUI's identity diffing overhead that degrades with large datasets.
struct AppKitLogTableView: NSViewRepresentable {
    @Bindable var viewModel: LogViewModel

    // Column identifiers
    private static let lineNumberColumnID = NSUserInterfaceItemIdentifier("lineNumber")
    private static let contentColumnID = NSUserInterfaceItemIdentifier("content")
    private static let cellID = NSUserInterfaceItemIdentifier("LogCell")
    private static let lineNumberCellID = NSUserInterfaceItemIdentifier("LineNumberCell")

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.headerView = nil // No header row
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []
        tableView.usesAutomaticRowHeights = true
        tableView.rowHeight = context.coordinator.computeRowHeight(fontSize: viewModel.settingsState.fontSize)

        // Line number column
        let lineNumberColumn = NSTableColumn(identifier: Self.lineNumberColumnID)
        lineNumberColumn.title = ""
        lineNumberColumn.width = 60
        lineNumberColumn.minWidth = 40
        lineNumberColumn.maxWidth = 80
        lineNumberColumn.isEditable = false
        tableView.addTableColumn(lineNumberColumn)

        // Content column
        let contentColumn = NSTableColumn(identifier: Self.contentColumnID)
        contentColumn.title = ""
        contentColumn.minWidth = 200
        contentColumn.isEditable = false
        // Allow the content column to stretch
        contentColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(contentColumn)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView

        // Observe scroll position for auto-scroll detection
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.viewModel = viewModel

        guard let tableView = coordinator.tableView else { return }

        let newRowHeight = coordinator.computeRowHeight(fontSize: viewModel.settingsState.fontSize)
        if tableView.rowHeight != newRowHeight {
            tableView.rowHeight = newRowHeight
        }

        // Reload data when filterChangeCounter changes
        let currentCounter = viewModel.filterChangeCounter
        if coordinator.lastFilterChangeCounter != currentCounter {
            coordinator.lastFilterChangeCounter = currentCounter

            // Widen content column to fit scroll view width
            if let contentColumn = tableView.tableColumn(withIdentifier: Self.contentColumnID) {
                let lineNumWidth = tableView.tableColumn(withIdentifier: Self.lineNumberColumnID)?.width ?? 60
                let availableWidth = scrollView.frame.width - lineNumWidth - 4
                if availableWidth > contentColumn.minWidth {
                    contentColumn.width = availableWidth
                }
            }

            tableView.reloadData()
        }

        // Scroll to current match when it changes
        if let matchID = viewModel.currentMatchID,
           matchID != coordinator.lastScrolledMatchID {
            coordinator.lastScrolledMatchID = matchID
            if let index = viewModel.displayedEntries.firstIndex(where: { $0.id == matchID }) {
                tableView.scrollRowToVisible(index)
                // Also select the row for visual feedback
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var viewModel: LogViewModel
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        var lastFilterChangeCounter: Int = -1
        var lastScrolledMatchID: UUID?

        private let highlighter = SyntaxHighlighter()

        init(viewModel: LogViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        func computeRowHeight(fontSize: Double) -> CGFloat {
            ceil(fontSize * 1.4) + 4.5
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            viewModel.displayedEntries.count
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < viewModel.displayedEntries.count else { return nil }
            let entry = viewModel.displayedEntries[row]
            let fontSize = viewModel.settingsState.fontSize
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

            if tableColumn?.identifier == AppKitLogTableView.lineNumberColumnID {
                return makeLineNumberCell(tableView: tableView, lineNumber: entry.lineNumber, font: font)
            } else {
                return makeContentCell(tableView: tableView, entry: entry, font: font, fontSize: fontSize)
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < viewModel.displayedEntries.count else { return nil }
            let entry = viewModel.displayedEntries[row]

            let rowView = LogTableRowView()
            rowView.entryBackgroundColor = backgroundColor(for: entry)
            return rowView
        }

        // MARK: - Cell Construction

        private func makeLineNumberCell(tableView: NSTableView, lineNumber: Int, font: NSFont) -> NSView {
            let cellID = AppKitLogTableView.lineNumberCellID
            let textField: NSTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
                textField = reused
            } else {
                textField = NSTextField(labelWithString: "")
                textField.identifier = cellID
                textField.alignment = .right
                textField.textColor = .secondaryLabelColor
                textField.isEditable = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.isSelectable = false
                textField.lineBreakMode = .byClipping
                textField.cell?.truncatesLastVisibleLine = true
            }

            textField.stringValue = String(lineNumber)
            textField.font = font
            return textField
        }

        private func makeContentCell(tableView: NSTableView, entry: LogEntry, font: NSFont, fontSize: Double) -> NSView {
            let cellID = AppKitLogTableView.cellID
            let textField: NSTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTextField {
                textField = reused
            } else {
                textField = NSTextField(labelWithString: "")
                textField.identifier = cellID
                textField.isEditable = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.isSelectable = true
                textField.lineBreakMode = .byWordWrapping
                textField.cell?.wraps = true
                textField.maximumNumberOfLines = 0
            }

            // Get syntax-highlighted NSAttributedString
            let attributed = highlighter.highlightNS(entry, fontSize: fontSize)

            // Apply search highlighting on top if needed
            if isSearchMatch(entry) && !viewModel.searchState.query.isEmpty {
                let mutable = NSMutableAttributedString(attributedString: attributed)
                applySearchHighlight(to: mutable, entry: entry)
                textField.attributedStringValue = mutable
            } else {
                textField.attributedStringValue = attributed
            }

            return textField
        }

        // MARK: - Search Match Helpers

        private func isSearchMatch(_ entry: LogEntry) -> Bool {
            guard viewModel.searchState.mode == .jumpToMatch,
                  !viewModel.searchState.query.isEmpty else {
                return false
            }
            return viewModel.searchState.matchingLineIDs.contains(entry.id)
        }

        private func isCurrentMatch(_ entry: LogEntry) -> Bool {
            guard let currentID = viewModel.currentMatchID else { return false }
            return entry.id == currentID
        }

        private func backgroundColor(for entry: LogEntry) -> NSColor {
            if isCurrentMatch(entry) {
                return NSColor.orange.withAlphaComponent(0.3)
            } else if isSearchMatch(entry) {
                return NSColor.yellow.withAlphaComponent(0.2)
            }
            return .clear
        }

        private func applySearchHighlight(to mutable: NSMutableAttributedString, entry: LogEntry) {
            let query = viewModel.searchState.query
            let escapedPattern = NSRegularExpression.escapedPattern(for: query)
            let options: NSRegularExpression.Options = viewModel.searchState.isCaseSensitive ? [] : [.caseInsensitive]

            guard let regex = try? NSRegularExpression(pattern: escapedPattern, options: options) else { return }

            let rawLine = entry.rawLine
            let matches = regex.matches(in: rawLine, range: NSRange(rawLine.startIndex..., in: rawLine))

            let bgColor: NSColor = isCurrentMatch(entry)
                ? NSColor.orange.withAlphaComponent(0.5)
                : NSColor.yellow.withAlphaComponent(0.4)

            for match in matches {
                mutable.addAttribute(.backgroundColor, value: bgColor, range: match.range)
            }
        }

        // MARK: - Scroll Tracking

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = scrollView,
                  let tableView = tableView else { return }

            let clipView = scrollView.contentView
            let documentHeight = tableView.frame.height
            let scrollPosition = clipView.bounds.origin.y + clipView.bounds.height
            let isNearBottom = scrollPosition >= (documentHeight - 50) || documentHeight <= clipView.bounds.height

            Task { @MainActor [weak self] in
                self?.viewModel.isScrolledToBottom = isNearBottom
            }
        }
    }
}

// MARK: - Custom Row View for Background Colors

private final class LogTableRowView: NSTableRowView {
    var entryBackgroundColor: NSColor = .clear

    override func drawBackground(in dirtyRect: NSRect) {
        if entryBackgroundColor != .clear {
            entryBackgroundColor.setFill()
            dirtyRect.fill()
        } else {
            super.drawBackground(in: dirtyRect)
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Use a subtle selection color that doesn't override search highlighting
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).setFill()
        dirtyRect.fill()
    }
}
