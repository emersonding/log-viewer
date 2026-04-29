//
//  LogParser.swift
//  Lumen
//
//  Created on 2026-04-13.
//

import Foundation

/// Parses raw log data into structured LogEntry objects.
///
/// Supports chunk-based streaming for large files: data is processed in 1MB chunks
/// with periodic yielding between chunks to keep the UI responsive.
actor LogParser {
    /// Default chunk size for processing: 1MB
    private let chunkSize = 1_048_576

    // Pre-compiled regexes for performance
    private let syslogTimestampRegex = try! NSRegularExpression(pattern: #"^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d+"#)
    private let epochTimestampRegex = try! NSRegularExpression(pattern: #"^\d{10,13}(\.\d+)?"#)
    private let logLevelRegex = try! NSRegularExpression(pattern: #"^\[?(FATAL|CRITICAL|ERROR|WARN|WARNING|INFO|DEBUG|TRACE)\]?"#, options: .caseInsensitive)
    private let spaceDatetimeExtractRegex = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)"#)
    private let syslogExtractRegex = try! NSRegularExpression(pattern: #"^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})"#)
    private let epochExtractRegex = try! NSRegularExpression(pattern: #"^(\d{10,13}(?:\.\d+)?)"#)
    private let jsonTimestampFieldNames = ["timestamp", "time", "ts", "datetime", "date", "@timestamp"]
    private let jsonLevelFieldNames = ["level", "severity", "log_level", "loglevel", "lvl", "priority"]
    private let jsonMessageFieldNames = ["message", "msg", "log", "event"]
    private var timestampCache: [String: Date] = [:]

    // Cached date formatters for performance
    private let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFormatterWithoutFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private let syslogDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm:ss yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private let spaceDatetimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private let spaceDatetimeWithFracFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parse raw data into an array of LogEntry objects.
    /// - Parameters:
    ///   - data: Raw log file data
    ///   - progress: Optional callback reporting parse progress (0.0 to 1.0)
    /// - Returns: Array of parsed log entries
    func parse(_ data: Data, progress: (@Sendable (Double) -> Void)? = nil) async -> [LogEntry] {
        let totalBytes = data.count

        guard totalBytes > 0 else {
            progress?(1.0)
            return []
        }

        // For small files (< chunkSize), use the fast single-pass path
        if totalBytes <= chunkSize {
            let content = decodeUTF8(data)
            let entries = parseContent(content, startLineNumber: 1)
            progress?(1.0)
            return entries
        }

        // Chunk-based streaming for large files
        return await parseInChunks(data: data, totalBytes: totalBytes, progress: progress)
    }

    // MARK: - Chunk-Based Parsing

    /// Parse data in chunks, yielding between each chunk for responsiveness.
    private func parseInChunks(
        data: Data,
        totalBytes: Int,
        progress: (@Sendable (Double) -> Void)?
    ) async -> [LogEntry] {
        var entries: [LogEntry] = []
        // Pre-allocate with estimate (~100 bytes per line)
        entries.reserveCapacity(totalBytes / 100)

        var currentEntry: PendingEntry?
        var lineNumber = 1
        var bytesProcessed = 0
        var lineBuffer = ""

        while bytesProcessed < totalBytes {
            let chunkEnd = min(bytesProcessed + chunkSize, totalBytes)
            let chunkData = data.subdata(in: bytesProcessed..<chunkEnd)
            var chunkString = decodeUTF8(chunkData)

            // Prepend any leftover partial line from previous chunk
            if !lineBuffer.isEmpty {
                chunkString = lineBuffer + chunkString
                lineBuffer = ""
            }

            // If not the last chunk, handle split at line boundary
            if chunkEnd < totalBytes {
                if let lastNewline = chunkString.lastIndex(where: { $0 == "\n" || $0 == "\r" }) {
                    let nextIndex = chunkString.index(after: lastNewline)
                    if nextIndex < chunkString.endIndex {
                        lineBuffer = String(chunkString[nextIndex...])
                        chunkString = String(chunkString[...lastNewline])
                    }
                } else {
                    // No newline in this chunk; buffer entirely and continue
                    lineBuffer = chunkString
                    bytesProcessed = chunkEnd
                    progress?(Double(bytesProcessed) / Double(totalBytes))
                    await Task.yield()
                    continue
                }
            }

            // Parse lines in this chunk
            let lines = chunkString.components(separatedBy: .newlines)

            for line in lines {
                // Skip blank lines
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    lineNumber += 1
                    continue
                }

                if isNewLogEntry(line) {
                    if let pending = currentEntry {
                        entries.append(pending.toLogEntry())
                    }
                    currentEntry = parseLine(line, lineNumber: lineNumber)
                    lineNumber += 1
                } else {
                    if var pending = currentEntry {
                        pending.appendContinuation(line)
                        currentEntry = pending
                    } else {
                        currentEntry = PendingEntry(
                            lineNumber: lineNumber,
                            timestamp: nil,
                            level: nil,
                            message: line,
                            rawLine: line
                        )
                    }
                    lineNumber += 1
                }
            }

            bytesProcessed = chunkEnd
            progress?(Double(bytesProcessed) / Double(totalBytes))

            // Yield between chunks to avoid blocking
            await Task.yield()
        }

        // Handle any remaining buffered content
        if !lineBuffer.isEmpty {
            let lines = lineBuffer.components(separatedBy: .newlines)
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    lineNumber += 1
                    continue
                }

                if isNewLogEntry(line) {
                    if let pending = currentEntry {
                        entries.append(pending.toLogEntry())
                    }
                    currentEntry = parseLine(line, lineNumber: lineNumber)
                    lineNumber += 1
                } else {
                    if var pending = currentEntry {
                        pending.appendContinuation(line)
                        currentEntry = pending
                    } else {
                        currentEntry = PendingEntry(
                            lineNumber: lineNumber,
                            timestamp: nil,
                            level: nil,
                            message: line,
                            rawLine: line
                        )
                    }
                    lineNumber += 1
                }
            }
        }

        // Flush the last entry
        if let pending = currentEntry {
            entries.append(pending.toLogEntry())
        }

        progress?(1.0)
        return entries
    }

    // MARK: - Single-Pass Parsing (small files)

    /// Parse content string in a single pass. Used for small files and refresh payloads.
    private func parseContent(_ content: String, startLineNumber: Int) -> [LogEntry] {
        guard !content.isEmpty else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var entries: [LogEntry] = []
        var currentEntry: PendingEntry?
        var lineNumber = startLineNumber

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                lineNumber += 1
                continue
            }

            if isNewLogEntry(line) {
                if let pending = currentEntry {
                    entries.append(pending.toLogEntry())
                }
                currentEntry = parseLine(line, lineNumber: lineNumber)
                lineNumber += 1
            } else {
                if var pending = currentEntry {
                    pending.appendContinuation(line)
                    currentEntry = pending
                } else {
                    currentEntry = PendingEntry(
                        lineNumber: lineNumber,
                        timestamp: nil,
                        level: nil,
                        message: line,
                        rawLine: line
                    )
                }
                lineNumber += 1
            }
        }

        if let pending = currentEntry {
            entries.append(pending.toLogEntry())
        }

        return entries
    }

    // MARK: - UTF-8 Decoding

    /// Decode data to string, replacing invalid UTF-8 with U+FFFD.
    private func decodeUTF8(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: - Private Helper Methods

    /// Determines if a line starts a new log entry
    private func isNewLogEntry(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // JSON/JSONL logs are newline-delimited; even malformed JSON lines should
        // start a new entry so they can fall back to plain-text parsing per line.
        if trimmed.first == "{" {
            return true
        }

        // Check for timestamp patterns
        if hasTimestamp(trimmed) {
            return true
        }

        // Check for log level at the start
        if hasLogLevelAtStart(trimmed) {
            return true
        }

        return false
    }

    /// Checks if line starts with a timestamp
    private func hasTimestamp(_ line: String) -> Bool {
        let nsRange = NSRange(line.startIndex..., in: line)

        // ISO 8601: starts with 4-digit year
        if hasISODatePrefix(line) {
            return true
        }

        // Syslog: starts with month abbreviation
        if syslogTimestampRegex.firstMatch(in: line, range: nsRange) != nil {
            return true
        }

        // Unix epoch: starts with 10-13 digit number (possibly with decimal)
        if epochTimestampRegex.firstMatch(in: line, range: nsRange) != nil {
            return true
        }

        return false
    }

    /// Checks if line starts with a log level keyword
    private func hasLogLevelAtStart(_ line: String) -> Bool {
        let nsRange = NSRange(line.startIndex..., in: line)
        return logLevelRegex.firstMatch(in: line, range: nsRange) != nil
    }

    /// Parse a single line into a PendingEntry
    private func parseLine(_ line: String, lineNumber: Int) -> PendingEntry {
        if let entry = parseJSONLine(line, lineNumber: lineNumber) {
            return entry
        }

        var remaining = line

        // Extract timestamp
        let timestamp = extractTimestamp(&remaining)

        // Extract log level
        let level = extractLogLevel(&remaining)

        // What's left is the message
        let message = remaining.trimmingCharacters(in: .whitespaces)

        return PendingEntry(
            lineNumber: lineNumber,
            timestamp: timestamp,
            level: level,
            message: message,
            rawLine: line,
            fields: [:]
        )
    }

    private func parseJSONLine(_ line: String, lineNumber: Int) -> PendingEntry? {
        guard let trimmed = jsonCandidateString(from: line),
              let object = parseJSONObject(trimmed) else {
            return nil
        }

        var fields: [String: LogFieldValue] = [:]
        for (key, value) in object {
            flattenJSONValue(value, path: key, fields: &fields)
        }

        return PendingEntry(
            lineNumber: lineNumber,
            timestamp: extractJSONTimestamp(from: object),
            level: extractJSONLogLevel(from: object),
            message: extractJSONMessage(from: object) ?? trimmed,
            rawLine: line,
            fields: fields
        )
    }

    private func parseJSONObject(_ line: String) -> [String: Any]? {
        guard line.first == "{", line.last == "}", let data = line.data(using: .utf8) else {
            return nil
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        return dictionary
    }

    private func jsonCandidateString(from line: String) -> String? {
        guard let first = line.first else { return nil }

        if first == "{" {
            return line.last == "}" ? line : line.trimmingCharacters(in: .whitespaces)
        }

        guard first.isWhitespace else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "{", trimmed.last == "}" else { return nil }
        return trimmed
    }

    private func extractJSONTimestamp(from object: [String: Any]) -> Date? {
        for fieldName in jsonTimestampFieldNames {
            guard let value = jsonValue(in: object, matching: fieldName),
                  let timestamp = parseJSONTimestampValue(value) else {
                continue
            }
            return timestamp
        }

        return nil
    }

    private func parseJSONTimestampValue(_ value: Any) -> Date? {
        if let string = value as? String {
            var remaining = string
            if let timestamp = extractTimestamp(&remaining) {
                return timestamp
            }
            return dateOnlyFormatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let number = value as? NSNumber, !isJSONBool(number) {
            let timestamp = number.doubleValue > 10_000_000_000 ? number.doubleValue / 1000 : number.doubleValue
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }

    private func extractJSONLogLevel(from object: [String: Any]) -> LogLevel? {
        for fieldName in jsonLevelFieldNames {
            guard let value = jsonValue(in: object, matching: fieldName),
                  let level = parseJSONLogLevelValue(value) else {
                continue
            }
            return level
        }

        return nil
    }

    private func parseJSONLogLevelValue(_ value: Any) -> LogLevel? {
        if let string = value as? String {
            return logLevel(for: string)
        }

        if let number = value as? NSNumber, !isJSONBool(number) {
            switch number.intValue {
            case 0...2:
                return .fatal
            case 3:
                return .error
            case 4:
                return .warning
            case 5...6:
                return .info
            case 7:
                return .debug
            default:
                return nil
            }
        }

        return nil
    }

    private func extractJSONMessage(from object: [String: Any]) -> String? {
        for fieldName in jsonMessageFieldNames {
            guard let value = jsonValue(in: object, matching: fieldName),
                  let string = value as? String else {
                continue
            }
            return string
        }

        return jsonStringValue(at: "error.message", in: object)
    }

    private func jsonValue(in object: [String: Any], matching fieldName: String) -> Any? {
        object.first { key, _ in
            key.caseInsensitiveCompare(fieldName) == .orderedSame
        }?.value
    }

    private func jsonStringValue(at path: String, in object: [String: Any]) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = object

        for part in parts {
            guard let dictionary = current as? [String: Any],
                  let next = jsonValue(in: dictionary, matching: part) else {
                return nil
            }
            current = next
        }

        return current as? String
    }

    private func flattenJSONValue(_ value: Any, path: String, fields: inout [String: LogFieldValue]) {
        if let dictionary = value as? [String: Any] {
            fields[path] = .nonLeaf
            for (key, nestedValue) in dictionary {
                flattenJSONValue(nestedValue, path: "\(path).\(key)", fields: &fields)
            }
            return
        }

        if let array = value as? [Any] {
            fields[path] = .nonLeaf
            for (index, nestedValue) in array.enumerated() {
                flattenJSONValue(nestedValue, path: "\(path)[\(index)]", fields: &fields)
            }
            return
        }

        fields[path] = logFieldValue(from: value)
    }

    private func logFieldValue(from value: Any) -> LogFieldValue {
        if value is NSNull {
            return .null
        }

        if let string = value as? String {
            return .string(string)
        }

        if let number = value as? NSNumber {
            if isJSONBool(number) {
                return .bool(number.boolValue)
            }
            return .number(number.stringValue)
        }

        return .string(String(describing: value))
    }

    private func isJSONBool(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Extract timestamp from the beginning of a string
    private func extractTimestamp(_ line: inout String) -> Date? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Try ISO 8601 format (with T separator)
        if let isoDate = tryParseISO8601(trimmed, consumedLength: &line) {
            return isoDate
        }

        // Try space-separated datetime (2026-04-13 10:00:00)
        if let spaceDate = tryParseSpaceDatetime(trimmed, consumedLength: &line) {
            return spaceDate
        }

        // Try syslog format
        if let syslogDate = tryParseSyslog(trimmed, consumedLength: &line) {
            return syslogDate
        }

        // Try Unix epoch
        if let epochDate = tryParseEpoch(trimmed, consumedLength: &line) {
            return epochDate
        }

        return nil
    }

    /// Try to parse ISO 8601 timestamp
    private func tryParseISO8601(_ line: String, consumedLength: inout String) -> Date? {
        guard hasISODatePrefix(line) else {
            return nil
        }

        let endIndex = line.firstIndex(where: { $0.isWhitespace }) ?? line.endIndex
        let timestampString = String(line[..<endIndex])

        if let cachedDate = timestampCache[timestampString] {
            consumedLength = String(line[endIndex...])
            return cachedDate
        }

        var date = isoFormatterWithFractional.date(from: timestampString)

        // Try without fractional seconds if that fails
        if date == nil {
            date = isoFormatterWithoutFractional.date(from: timestampString)
        }

        if date != nil {
            // Remove the timestamp from the line
            consumedLength = String(line[endIndex...])
            if timestampCache.count < 1024 {
                timestampCache[timestampString] = date
            }
        }

        return date
    }

    private func hasISODatePrefix(_ line: String) -> Bool {
        var bytes = line.utf8.makeIterator()
        guard let b0 = bytes.next(),
              let b1 = bytes.next(),
              let b2 = bytes.next(),
              let b3 = bytes.next(),
              let b4 = bytes.next(),
              let b5 = bytes.next(),
              let b6 = bytes.next(),
              let b7 = bytes.next(),
              let b8 = bytes.next(),
              let b9 = bytes.next() else {
            return false
        }

        return isASCIIDigit(b0)
            && isASCIIDigit(b1)
            && isASCIIDigit(b2)
            && isASCIIDigit(b3)
            && b4 == 45
            && isASCIIDigit(b5)
            && isASCIIDigit(b6)
            && b7 == 45
            && isASCIIDigit(b8)
            && isASCIIDigit(b9)
    }

    private func isASCIIDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }

    /// Try to parse space-separated datetime (e.g., "2026-04-13 10:00:00" or "2026-04-13 10:00:00.123")
    private func tryParseSpaceDatetime(_ line: String, consumedLength: inout String) -> Date? {
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = spaceDatetimeExtractRegex.firstMatch(in: line, range: nsRange),
              let range = Range(match.range, in: line) else {
            return nil
        }

        let timestampString = String(line[range])

        // Try with fractional seconds first, then without
        var date = spaceDatetimeWithFracFormatter.date(from: timestampString)
        if date == nil {
            date = spaceDatetimeFormatter.date(from: timestampString)
        }

        if date != nil {
            consumedLength = String(line[range.upperBound...])
        }

        return date
    }

    /// Try to parse syslog timestamp (e.g., "Apr 13 10:30:00")
    private func tryParseSyslog(_ line: String, consumedLength: inout String) -> Date? {
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = syslogExtractRegex.firstMatch(in: line, range: nsRange),
              let range = Range(match.range, in: line) else {
            return nil
        }

        let timestampString = String(line[range])

        // Syslog doesn't include year, assume current year
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let fullTimestamp = "\(timestampString) \(currentYear)"

        if let date = syslogDateFormatter.date(from: fullTimestamp) {
            consumedLength = String(line[range.upperBound...])
            return date
        }

        return nil
    }

    /// Try to parse Unix epoch timestamp
    private func tryParseEpoch(_ line: String, consumedLength: inout String) -> Date? {
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = epochExtractRegex.firstMatch(in: line, range: nsRange),
              let range = Range(match.range, in: line) else {
            return nil
        }

        let epochString = String(line[range])

        if let epochValue = Double(epochString) {
            // Unix epoch is in seconds, but could be milliseconds if > 10 digits
            let timestamp = epochValue > 10000000000 ? epochValue / 1000 : epochValue
            let date = Date(timeIntervalSince1970: timestamp)
            consumedLength = String(line[range.upperBound...])
            return date
        }

        return nil
    }

    /// Extract log level from the beginning of a string.
    /// Handles both bare keywords (ERROR) and bracketed ([ERROR]) formats.
    private func extractLogLevel(_ line: inout String) -> LogLevel? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)

        guard let match = logLevelRegex.firstMatch(in: trimmed, range: nsRange),
              let fullRange = Range(match.range, in: trimmed),
              let keywordNSRange = Range(match.range(at: 1), in: trimmed) else {
            // No log level found, leave line as-is
            line = trimmed
            return nil
        }

        // Use capture group 1 (the keyword without brackets) for level lookup
        let keyword = String(trimmed[keywordNSRange]).uppercased()

        let level = logLevel(for: keyword)
        // Consume the full match (including brackets) from the remaining line
        line = String(trimmed[fullRange.upperBound...])
        return level
    }

    private func logLevel(for value: String) -> LogLevel? {
        let keyword = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let levelMap: [String: LogLevel] = [
            "FATAL": .fatal,
            "CRITICAL": .fatal,
            "ERROR": .error,
            "ERR": .error,
            "WARN": .warning,
            "WARNING": .warning,
            "INFO": .info,
            "INFORMATION": .info,
            "NOTICE": .info,
            "DEBUG": .debug,
            "TRACE": .trace
        ]

        if let level = levelMap[keyword] {
            return level
        }

        guard let numericLevel = Int(keyword) else { return nil }
        switch numericLevel {
        case 0...2:
            return .fatal
        case 3:
            return .error
        case 4:
            return .warning
        case 5...6:
            return .info
        case 7:
            return .debug
        default:
            return nil
        }
    }
}

// MARK: - Helper Structures

/// Temporary structure for building a log entry while parsing continuation lines
private struct PendingEntry {
    let lineNumber: Int
    let timestamp: Date?
    let level: LogLevel?
    var message: String
    var rawLine: String
    var fields: [String: LogFieldValue] = [:]

    mutating func appendContinuation(_ line: String) {
        message += "\n" + line
        rawLine += "\n" + line
    }

    func toLogEntry() -> LogEntry {
        LogEntry(
            lineNumber: lineNumber,
            timestamp: timestamp,
            level: level,
            message: message,
            rawLine: rawLine,
            fields: fields
        )
    }
}
