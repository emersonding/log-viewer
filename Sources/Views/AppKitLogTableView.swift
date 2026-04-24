//
//  AppKitLogTableView.swift
//  Lumen
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
    private static let levelColumnID = NSUserInterfaceItemIdentifier("level")
    private static let timestampColumnID = NSUserInterfaceItemIdentifier("timestamp")
    private static let contentColumnID = NSUserInterfaceItemIdentifier("content")
    private static let extractedFieldColumnPrefix = "field:"
    private static let extractedFieldColumnWidth: CGFloat = 130
    private static let contentColumnDefaultWidth: CGFloat = 700
    private static let cellID = NSUserInterfaceItemIdentifier("LogCell")
    private static let lineNumberCellID = NSUserInterfaceItemIdentifier("LineNumberCell")
    private static let levelCellID = NSUserInterfaceItemIdentifier("LevelCell")
    private static let timestampCellID = NSUserInterfaceItemIdentifier("TimestampCell")
    private static let fieldCellID = NSUserInterfaceItemIdentifier("FieldCell")

    private static func extractedFieldColumnID(_ fieldName: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(extractedFieldColumnPrefix + fieldName)
    }

    private static func extractedFieldName(from identifier: NSUserInterfaceItemIdentifier?) -> String? {
        guard let rawValue = identifier?.rawValue,
              rawValue.hasPrefix(extractedFieldColumnPrefix) else {
            return nil
        }
        return String(rawValue.dropFirst(extractedFieldColumnPrefix.count))
    }

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
        tableView.intercellSpacing = NSSize(width: 4, height: 0)
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.usesAutomaticRowHeights = true
        // rowHeight is the estimated height for scroll bar; actual height from Auto Layout
        tableView.rowHeight = 20

        // Line number column
        let lineNumberColumn = NSTableColumn(identifier: Self.lineNumberColumnID)
        lineNumberColumn.title = "#"
        lineNumberColumn.width = 60
        lineNumberColumn.minWidth = 40
        lineNumberColumn.maxWidth = 80
        lineNumberColumn.isEditable = false
        tableView.addTableColumn(lineNumberColumn)

        // Log level column
        let levelColumn = NSTableColumn(identifier: Self.levelColumnID)
        levelColumn.title = "Level"
        levelColumn.width = 90
        levelColumn.minWidth = 70
        levelColumn.maxWidth = 110
        levelColumn.isEditable = false
        tableView.addTableColumn(levelColumn)

        // Timestamp column (sortable)
        let timestampColumn = NSTableColumn(identifier: Self.timestampColumnID)
        timestampColumn.title = "Timestamp"
        timestampColumn.width = 160
        timestampColumn.minWidth = 120
        timestampColumn.maxWidth = 200
        timestampColumn.isEditable = false
        timestampColumn.sortDescriptorPrototype = NSSortDescriptor(key: "timestamp", ascending: true)
        tableView.addTableColumn(timestampColumn)

        // Content column (message only)
        let contentColumn = NSTableColumn(identifier: Self.contentColumnID)
        contentColumn.title = "Message"
        contentColumn.width = Self.contentColumnDefaultWidth
        contentColumn.minWidth = 1
        contentColumn.isEditable = false
        contentColumn.resizingMask = [.autoresizingMask, .userResizingMask]
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
        let currentFontSize = viewModel.settingsState.fontSize
        let currentFieldNames = viewModel.extractedFieldNames
        if coordinator.lastFilterChangeCounter != currentCounter ||
            coordinator.lastFontSize != currentFontSize ||
            coordinator.lastFieldNames != currentFieldNames {
            coordinator.lastFilterChangeCounter = currentCounter
            coordinator.lastFontSize = currentFontSize
            coordinator.lastFieldNames = currentFieldNames
            tableView.rowHeight = coordinator.computeRowHeight(fontSize: currentFontSize)
            coordinator.syncExtractedFieldColumns(tableView: tableView, fieldNames: currentFieldNames)

            // Keep a useful default message width, but still allow the user to shrink it manually.
            if let contentColumn = tableView.tableColumn(withIdentifier: Self.contentColumnID) {
                let fixedColumnsWidth = tableView.tableColumns
                    .filter { $0.identifier != Self.contentColumnID }
                    .reduce(CGFloat(16)) { $0 + $1.width }
                let availableWidth = scrollView.frame.width - fixedColumnsWidth
                if availableWidth > 0 && contentColumn.width < Self.contentColumnDefaultWidth {
                    contentColumn.width = max(Self.contentColumnDefaultWidth, availableWidth)
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
        var lastFontSize: Double = -1
        var lastFieldNames: [String] = []
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

        // Shared timestamp formatter — created once, reused for all rows
        private let timestampFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < viewModel.displayedEntries.count else { return nil }
            let entry = viewModel.displayedEntries[row]
            let fontSize = viewModel.settingsState.fontSize
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

            switch tableColumn?.identifier {
            case AppKitLogTableView.lineNumberColumnID:
                return makeLineNumberCell(tableView: tableView, lineNumber: entry.lineNumber, font: font)
            case AppKitLogTableView.levelColumnID:
                return makeLevelCell(tableView: tableView, level: entry.level, fontSize: fontSize)
            case AppKitLogTableView.timestampColumnID:
                return makeTimestampCell(tableView: tableView, timestamp: entry.timestamp, font: font)
            default:
                if let fieldName = AppKitLogTableView.extractedFieldName(from: tableColumn?.identifier) {
                    let value = viewModel.extractedFieldValue(named: fieldName, in: entry)
                    return makeFieldCell(tableView: tableView, value: value, font: font)
                }
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

        // MARK: - Sorting

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            viewModel.toggleTimestampSort()
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else {
                return
            }

            if let resizedColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
               resizedColumn.identifier != AppKitLogTableView.contentColumnID {
                return
            }
            updateVisibleContentWrapping(tableView: tableView)
        }

        // MARK: - Cell Construction

        private func configureCompressibleTextField(_ textField: NSTextField) {
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        private func enableSubviewClipping(_ view: NSView) {
            view.wantsLayer = true
            view.layer?.masksToBounds = true
        }

        func syncExtractedFieldColumns(tableView: NSTableView, fieldNames: [String]) {
            let savedDataSource = tableView.dataSource
            let savedDelegate = tableView.delegate

            tableView.dataSource = nil
            tableView.delegate = nil
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()

            let desiredFields = Set(fieldNames)
            for column in tableView.tableColumns {
                guard let fieldName = AppKitLogTableView.extractedFieldName(from: column.identifier),
                      !desiredFields.contains(fieldName) else {
                    continue
                }
                tableView.removeTableColumn(column)
            }

            for fieldName in fieldNames where tableView.tableColumn(withIdentifier: AppKitLogTableView.extractedFieldColumnID(fieldName)) == nil {
                let column = NSTableColumn(identifier: AppKitLogTableView.extractedFieldColumnID(fieldName))
                column.title = fieldName
                column.width = AppKitLogTableView.extractedFieldColumnWidth
                column.minWidth = 1
                column.maxWidth = CGFloat.greatestFiniteMagnitude
                column.isEditable = false
                column.resizingMask = .userResizingMask
                tableView.addTableColumn(column)
            }

            let desiredColumnIDs = [
                AppKitLogTableView.lineNumberColumnID,
                AppKitLogTableView.levelColumnID,
                AppKitLogTableView.timestampColumnID,
            ] + fieldNames.map { AppKitLogTableView.extractedFieldColumnID($0) } + [
                AppKitLogTableView.contentColumnID
            ]

            for (targetIndex, identifier) in desiredColumnIDs.enumerated() {
                guard let currentIndex = tableView.tableColumns.firstIndex(where: { $0.identifier == identifier }),
                      currentIndex != targetIndex else {
                    continue
                }
                tableView.moveColumn(currentIndex, toColumn: targetIndex)
            }

            tableView.dataSource = savedDataSource
            tableView.delegate = savedDelegate
        }

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
                configureCompressibleTextField(tf)

                let cv = NSTableCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)
                enableSubviewClipping(cv)

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

        private func makeLevelCell(tableView: NSTableView, level: LogLevel?, fontSize: Double) -> NSView {
            let cellID = AppKitLogTableView.levelCellID
            let cellView: NSTableCellView
            let textField: NSTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let existingTF = reused.textField {
                cellView = reused
                textField = existingTF
            } else {
                let tf = NSTextField(labelWithString: "")
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.isSelectable = false
                tf.lineBreakMode = .byClipping
                tf.alignment = .left
                tf.translatesAutoresizingMaskIntoConstraints = false
                configureCompressibleTextField(tf)

                let cv = NSTableCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)
                enableSubviewClipping(cv)

                NSLayoutConstraint.activate([
                    tf.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2),
                    tf.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -2),
                    tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
                ])

                cellView = cv
                textField = tf
            }

            if let level = level {
                let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
                textField.stringValue = level.rawValue
                textField.font = font
                textField.textColor = level.nsColor

                if level == .fatal {
                    textField.textColor = .white
                    textField.backgroundColor = .systemRed
                    textField.drawsBackground = true
                } else {
                    textField.drawsBackground = false
                }
            } else {
                textField.stringValue = ""
                textField.drawsBackground = false
            }

            return cellView
        }

        private func makeTimestampCell(tableView: NSTableView, timestamp: Date?, font: NSFont) -> NSView {
            let cellID = AppKitLogTableView.timestampCellID
            let cellView: NSTableCellView
            let textField: NSTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let existingTF = reused.textField {
                cellView = reused
                textField = existingTF
            } else {
                let tf = NSTextField(labelWithString: "")
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.isSelectable = false
                tf.lineBreakMode = .byClipping
                tf.textColor = .secondaryLabelColor
                tf.translatesAutoresizingMaskIntoConstraints = false
                configureCompressibleTextField(tf)

                let cv = NSTableCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)
                enableSubviewClipping(cv)

                NSLayoutConstraint.activate([
                    tf.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2),
                    tf.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -2),
                    tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
                ])

                cellView = cv
                textField = tf
            }

            if let timestamp = timestamp {
                textField.stringValue = timestampFormatter.string(from: timestamp)
            } else {
                textField.stringValue = ""
            }
            textField.font = font

            return cellView
        }

        private func makeFieldCell(tableView: NSTableView, value: String, font: NSFont) -> NSView {
            let cellID = AppKitLogTableView.fieldCellID
            let cellView: NSTableCellView
            let textField: NSTextField

            if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView,
               let existingTF = reused.textField {
                cellView = reused
                textField = existingTF
            } else {
                let tf = NSTextField(labelWithString: "")
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.isSelectable = true
                tf.maximumNumberOfLines = 1
                tf.lineBreakMode = .byClipping
                tf.usesSingleLineMode = true
                tf.translatesAutoresizingMaskIntoConstraints = false
                configureCompressibleTextField(tf)

                let cv = NSTableCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)
                enableSubviewClipping(cv)

                NSLayoutConstraint.activate([
                    tf.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2),
                    tf.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -2),
                    tf.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
                ])

                cellView = cv
                textField = tf
            }

            textField.stringValue = value
            textField.font = font
            textField.textColor = .labelColor

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
                tf.lineBreakMode = .byWordWrapping
                tf.usesSingleLineMode = false
                tf.translatesAutoresizingMaskIntoConstraints = false
                configureCompressibleTextField(tf)

                let cv = NSTableCellView()
                cv.identifier = cellID
                cv.textField = tf
                cv.addSubview(tf)
                enableSubviewClipping(cv)

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
            textField.preferredMaxLayoutWidth = max(1, contentColumnWidth - 8) // minus padding

            // Highlight message only (quoted strings + search)
            let attributed = highlighter.highlightMessageNS(entry, fontSize: fontSize)

            // Apply search highlighting on top if needed
            if isSearchMatch(entry) && !viewModel.searchState.query.isEmpty {
                let mutable = NSMutableAttributedString(attributedString: attributed)
                applySearchHighlight(to: mutable, entry: entry, text: entry.message)
                textField.attributedStringValue = mutable
            } else {
                textField.attributedStringValue = attributed
            }

            return cellView
        }

        private func updateVisibleContentWrapping(tableView: NSTableView) {
            guard let contentColumnIndex = tableView.tableColumns.firstIndex(where: { $0.identifier == AppKitLogTableView.contentColumnID }),
                  let contentColumn = tableView.tableColumn(withIdentifier: AppKitLogTableView.contentColumnID) else {
                return
            }

            let preferredWidth = max(1, contentColumn.width - 8)
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound, visibleRows.length > 0 else { return }

            let rowRange = visibleRows.location..<(visibleRows.location + visibleRows.length)
            for row in rowRange {
                guard let cellView = tableView.view(atColumn: contentColumnIndex, row: row, makeIfNecessary: false) as? NSTableCellView,
                      let textField = cellView.textField else {
                    continue
                }
                textField.preferredMaxLayoutWidth = preferredWidth
                textField.invalidateIntrinsicContentSize()
            }

            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: rowRange))
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

        private func applySearchHighlight(to mutable: NSMutableAttributedString, entry: LogEntry, text: String? = nil) {
            let query = viewModel.searchState.query
            let escapedPattern = NSRegularExpression.escapedPattern(for: query)
            let options: NSRegularExpression.Options = viewModel.searchState.isCaseSensitive ? [] : [.caseInsensitive]

            guard let regex = try? NSRegularExpression(pattern: escapedPattern, options: options) else { return }

            let searchText = text ?? entry.rawLine
            let matches = regex.matches(in: searchText, range: NSRange(searchText.startIndex..., in: searchText))

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
