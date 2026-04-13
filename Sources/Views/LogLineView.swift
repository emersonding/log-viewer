//
//  LogLineView.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import SwiftUI

/// Individual log line view with line number gutter and syntax highlighting
struct LogLineView: View {
    let entry: LogEntry
    let isLineWrapEnabled: Bool
    let fontSize: Double
    let isSearchMatch: Bool
    let isCurrentMatch: Bool
    let searchQuery: String
    let isCaseSensitive: Bool

    private let maxLineLength = 100_000 // 100KB truncation threshold
    private let lineNumberWidth: CGFloat = 60
    private let gutterPadding: CGFloat = 8

    // Shared syntax highlighter instance
    private static let highlighter = SyntaxHighlighter()

    var body: some View {
        HStack(alignment: .top, spacing: gutterPadding) {
            // Line number gutter
            Text(String(entry.lineNumber))
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: lineNumberWidth, alignment: .trailing)
                .padding(.trailing, gutterPadding)
                .accessibilityLabel("Line \(entry.lineNumber)")

            // Log content with syntax highlighting
            logContentView
                .font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled) // Enable text selection for Cmd+C
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(rowBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(entry.rawLine)
    }

    @ViewBuilder
    private var logContentView: some View {
        if shouldTruncateLine {
            // Long line truncation
            Text(truncatedContent)
                .fixedSize(horizontal: !isLineWrapEnabled, vertical: false)
        } else {
            // Normal rendering with search highlights
            if isSearchMatch && !searchQuery.isEmpty {
                highlightedTextWithSearch
                    .fixedSize(horizontal: !isLineWrapEnabled, vertical: false)
            } else {
                // Standard syntax highlighting
                Text(Self.highlighter.highlight(entry))
                    .fixedSize(horizontal: !isLineWrapEnabled, vertical: false)
            }
        }
    }

    /// Background color for the row
    private var rowBackground: Color {
        if isCurrentMatch {
            // Orange background for current search match
            return Color.orange.opacity(0.3)
        } else if isSearchMatch {
            // Yellow background for other search matches
            return Color.yellow.opacity(0.2)
        } else {
            return Color.clear
        }
    }

    /// Check if line should be truncated
    private var shouldTruncateLine: Bool {
        return entry.rawLine.utf8.count > maxLineLength
    }

    /// Truncated content with indicator
    private var truncatedContent: AttributedString {
        let truncatedText = String(entry.rawLine.prefix(maxLineLength))
        var result = AttributedString(truncatedText + " [...truncated]")

        // Apply truncation indicator styling
        if let range = result.range(of: " [...truncated]") {
            result[range].foregroundColor = .red
            result[range].font = .system(size: fontSize, weight: .bold, design: .monospaced)
        }

        return result
    }

    /// Syntax highlighted text with search match highlighting
    private var highlightedTextWithSearch: Text {
        // Get base syntax highlighted AttributedString
        var attributed = Self.highlighter.highlight(entry)

        // Apply search highlighting on top
        if !searchQuery.isEmpty {
            applySearchHighlight(to: &attributed)
        }

        return Text(attributed)
    }

    /// Apply yellow/orange background to search matches
    private func applySearchHighlight(to attributedString: inout AttributedString) {
        // Escape the search query for plain-text search
        let escapedPattern = NSRegularExpression.escapedPattern(for: searchQuery)

        let options: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: escapedPattern, options: options) else {
            return
        }

        let rawLine = entry.rawLine
        let matches = regex.matches(in: rawLine, range: NSRange(rawLine.startIndex..., in: rawLine))

        // Apply background color to each match
        let backgroundColor = isCurrentMatch ? Color.orange.opacity(0.5) : Color.yellow.opacity(0.4)

        for match in matches {
            if let range = Range(match.range, in: rawLine),
               let attributedRange = Range<AttributedString.Index>(range, in: attributedString) {
                attributedString[attributedRange].backgroundColor = backgroundColor
            }
        }
    }

    /// Accessibility label for the log line
    private var accessibilityLabel: String {
        var components: [String] = []

        // Line number
        components.append("Line \(entry.lineNumber)")

        // Log level
        if let level = entry.level {
            components.append("\(level.rawValue) level")
        }

        // Timestamp
        if let timestamp = entry.timestamp {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            components.append(formatter.string(from: timestamp))
        }

        // Search match status
        if isCurrentMatch {
            components.append("Current search match")
        } else if isSearchMatch {
            components.append("Search match")
        }

        return components.joined(separator: ", ")
    }
}

// MARK: - Preview

struct LogLineView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LogLineView(
                entry: LogEntry(
                    lineNumber: 42,
                    timestamp: Date(),
                    level: .error,
                    message: "Test error message",
                    rawLine: "[ERROR] Test error message"
                ),
                isLineWrapEnabled: false,
                fontSize: 12,
                isSearchMatch: false,
                isCurrentMatch: false,
                searchQuery: "",
                isCaseSensitive: false
            )

            LogLineView(
                entry: LogEntry(
                    lineNumber: 100,
                    timestamp: Date(),
                    level: .info,
                    message: "Connection established successfully",
                    rawLine: "[INFO] Connection established successfully"
                ),
                isLineWrapEnabled: false,
                fontSize: 12,
                isSearchMatch: true,
                isCurrentMatch: false,
                searchQuery: "Connection",
                isCaseSensitive: false
            )

            LogLineView(
                entry: LogEntry(
                    lineNumber: 200,
                    timestamp: Date(),
                    level: .warning,
                    message: "Connection timeout warning",
                    rawLine: "[WARNING] Connection timeout warning"
                ),
                isLineWrapEnabled: false,
                fontSize: 12,
                isSearchMatch: true,
                isCurrentMatch: true,
                searchQuery: "Connection",
                isCaseSensitive: false
            )
        }
    }
}
