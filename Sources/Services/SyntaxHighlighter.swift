//
//  SyntaxHighlighter.swift
//  LogViewer
//
//  Created on 2026-04-13.
//

import Foundation
import SwiftUI

/// Syntax highlighter for log entries
/// Converts LogEntry to AttributedString with color coding
final class SyntaxHighlighter {

    // Cache for highlighted content to avoid recomputation
    private let cache = NSCache<NSString, NSAttributedString>()

    // Pre-compiled regex patterns — created once, reused on every highlight call
    private let timestampRegexes: [NSRegularExpression]
    private let quotedStringRegex: NSRegularExpression?
    private var levelRegexCache: [LogLevel: NSRegularExpression] = [:]

    init() {
        // Cache sized for visible rows + overscan buffer (~200 rows).
        // With highlight-on-demand, only rendered rows hit the highlighter,
        // so a smaller cache avoids memory waste on large files.
        cache.countLimit = 500

        // Pre-compile timestamp patterns
        let timestampPatterns = [
            "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:Z|[+-]\\d{2}:\\d{2})",
            "^[A-Z][a-z]{2}\\s+\\d{1,2}\\s+\\d{2}:\\d{2}:\\d{2}",
            "^\\d{10}(?:\\.\\d+)?"
        ]
        timestampRegexes = timestampPatterns.compactMap { try? NSRegularExpression(pattern: $0) }

        // Pre-compile quoted string pattern
        quotedStringRegex = try? NSRegularExpression(pattern: #"\"[^\"]*\"|'[^']*'"#)

        // Pre-compile level patterns
        for level in LogLevel.allCases {
            let pattern = "\\[?\(level.rawValue)\\]?"
            levelRegexCache[level] = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }

    /// Highlight a log entry with color coding
    /// - Parameter entry: The log entry to highlight
    /// - Returns: AttributedString with syntax highlighting applied
    func highlight(_ entry: LogEntry) -> AttributedString {
        // Check cache first
        let cacheKey = entry.id.uuidString as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return AttributedString(cached)
        }

        var result = AttributedString(entry.rawLine)

        // Apply timestamp highlighting
        if entry.timestamp != nil {
            highlightTimestamp(in: &result, rawLine: entry.rawLine)
        }

        // Apply log level highlighting
        if let level = entry.level {
            highlightLogLevel(in: &result, level: level, rawLine: entry.rawLine)
        }

        // Apply quoted string highlighting
        highlightQuotedStrings(in: &result, rawLine: entry.rawLine)

        // Cache the result
        let nsAttributed = NSAttributedString(result)
        cache.setObject(nsAttributed, forKey: cacheKey)

        return result
    }

    // MARK: - Private Highlighting Methods

    private func highlightTimestamp(in attributedString: inout AttributedString, rawLine: String) {
        let nsRange = NSRange(rawLine.startIndex..., in: rawLine)

        for regex in timestampRegexes {
            if let match = regex.firstMatch(in: rawLine, range: nsRange),
               let range = Range(match.range, in: rawLine),
               let swiftRange = Range<AttributedString.Index>(range, in: attributedString) {
                attributedString[swiftRange].font = .system(.body, design: .monospaced)
                attributedString[swiftRange].foregroundColor = Color.secondary
                break // Only highlight first match
            }
        }
    }

    private func highlightLogLevel(in attributedString: inout AttributedString, level: LogLevel, rawLine: String) {
        guard let regex = levelRegexCache[level] else { return }

        let nsRange = NSRange(rawLine.startIndex..., in: rawLine)
        if let match = regex.firstMatch(in: rawLine, range: nsRange),
           let range = Range(match.range, in: rawLine),
           let swiftRange = Range<AttributedString.Index>(range, in: attributedString) {
            if let foreground = level.foregroundColor {
                attributedString[swiftRange].foregroundColor = foreground
            }
            if let background = level.backgroundColor {
                attributedString[swiftRange].backgroundColor = background
            }
            attributedString[swiftRange].font = .system(.body, design: .default, weight: .bold)
        }
    }

    private func highlightQuotedStrings(in attributedString: inout AttributedString, rawLine: String) {
        guard let regex = quotedStringRegex else { return }

        let nsRange = NSRange(rawLine.startIndex..., in: rawLine)
        let matches = regex.matches(in: rawLine, range: nsRange)

        for match in matches {
            if let range = Range(match.range, in: rawLine),
               let swiftRange = Range<AttributedString.Index>(range, in: attributedString) {
                #if os(macOS)
                attributedString[swiftRange].foregroundColor = Color(nsColor: .systemTeal)
                #else
                attributedString[swiftRange].foregroundColor = .teal
                #endif
            }
        }
    }
}

// MARK: - LogEntry Extension for Caching

extension LogEntry {
    /// Cached highlighted content
    /// Note: This is a computed property that uses SyntaxHighlighter's internal cache
    var highlightedContent: AttributedString {
        let highlighter = SyntaxHighlighter()
        return highlighter.highlight(self)
    }
}
