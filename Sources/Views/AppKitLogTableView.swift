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
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.gridStyleMask = []
        tableView.usesAutomaticRowHeights = true
        // rowHeight is the estimated height for scroll bar; actual height from Auto Layout
        tableView.rowHeight = 20

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
            let cellView: NSTableCellView
            let textField: NSTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let existingTF = reused.textField {
                cellView = reused
                textField = existingTF
            } else {
                let tf = NSTextField(labelWithString: "")
                tf.alignment = .right
                tf.textColor = .secondaryLabelColor
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.isSelectable = false
                tf.lineBreakMode = .byClipping
                tf.translatesAutoresizingMaskIntoConstraints = false
                tf.setContentHuggingPriority(.defaultHigh, for: .vertical)

                let cv = NSTableCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)

                NSLayoutConstraint.activate([
                    tf.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2),
                    tf.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -2),
                    tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                    tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
                ])

                cellView = cv
                textField = tf
            }

            textField.stringValue = String(lineNumber)
            textField.font = font
            return cellView
        }

        private func makeContentCell(tableView: NSTableView, entry: LogEntry, font: NSFont, fontSize: Double) -> NSView {
            let cellID = AppKitLogTableView.cellID
            let cellView: NSTableCellView
            let textField: NSTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let existingTF = reused.textField {
                cellView = reused
                textField = existingTF
            } else {
                let tf = NSTextField(wrappingLabelWithString: "")
                tf.identifier = NSUserInterfaceItemIdentifier("ContentTextField")
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.isSelectable = true
                tf.maximumNumberOfLines = 0
                tf.translatesAutoresizingMaskIntoConstraints = false

                let cv = NSTableCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)

                NSLayoutConstraint.activate([
                    tf.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2),
                    tf.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -2),
                    tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
                ])

                cellView = cv
                textField = tf
            }

            // Set preferred width so Auto Layout knows when to wrap
            let contentColumnWidth = tableView.tableColumn(withIdentifier: AppKitLogTableView.contentColumnID)?.width ?? 600
            textField.preferredMaxLayoutWidth = contentColumnWidth - 8 // minus padding

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

            return cellView
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
