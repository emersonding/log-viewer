//
//  LogParserTests.swift
//  Lumen
//
//  Created on 2026-04-13.
//

import XCTest
@testable import Lumen

final class LogParserTests: XCTestCase {
    var parser: LogParser!

    override func setUp() {
        super.setUp()
        parser = LogParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Timestamp Parsing Tests

    func testParseISO8601Timestamp() async {
        let logData = """
        2026-04-13T10:30:00Z INFO Test message
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries[0].timestamp)
        XCTAssertEqual(entries[0].level, .info)
        XCTAssertEqual(entries[0].message, "Test message")
    }

    func testParseISO8601WithTimezone() async {
        let logData = """
        2026-04-13T10:30:00+08:00 ERROR Error with timezone
        2026-04-13T10:30:00-05:00 WARNING Warning with negative offset
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertNotNil(entries[0].timestamp)
        XCTAssertEqual(entries[0].level, .error)
        XCTAssertNotNil(entries[1].timestamp)
        XCTAssertEqual(entries[1].level, .warning)
    }

    func testParseSyslogTimestamp() async {
        let logData = """
        Apr 13 10:30:00 DEBUG Syslog format
        Jan  1 00:00:00 INFO New year message
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertNotNil(entries[0].timestamp)
        XCTAssertEqual(entries[0].level, .debug)
        XCTAssertNotNil(entries[1].timestamp)
        XCTAssertEqual(entries[1].level, .info)
    }

    func testParseUnixEpochTimestamp() async {
        let logData = """
        1713006600 TRACE Unix epoch integer
        1713006600.123456 DEBUG Unix epoch float
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertNotNil(entries[0].timestamp)
        XCTAssertEqual(entries[0].level, .trace)
        XCTAssertNotNil(entries[1].timestamp)
        XCTAssertEqual(entries[1].level, .debug)
    }

    // MARK: - Log Level Tests

    func testParseAllLogLevels() async {
        let logData = """
        2026-04-13T10:30:00Z FATAL Fatal error
        2026-04-13T10:30:01Z ERROR Error message
        2026-04-13T10:30:02Z WARNING Warning message
        2026-04-13T10:30:03Z INFO Info message
        2026-04-13T10:30:04Z DEBUG Debug message
        2026-04-13T10:30:05Z TRACE Trace message
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 6)
        XCTAssertEqual(entries[0].level, .fatal)
        XCTAssertEqual(entries[1].level, .error)
        XCTAssertEqual(entries[2].level, .warning)
        XCTAssertEqual(entries[3].level, .info)
        XCTAssertEqual(entries[4].level, .debug)
        XCTAssertEqual(entries[5].level, .trace)
    }

    func testParseLogLevelAliases() async {
        let logData = """
        2026-04-13T10:30:00Z WARN This is a warning
        2026-04-13T10:30:01Z CRITICAL This is critical
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].level, .warning) // WARN → WARNING
        XCTAssertEqual(entries[1].level, .fatal)   // CRITICAL → FATAL
    }

    func testParseNoLogLevel() async {
        let logData = """
        2026-04-13T10:30:00Z Just a message without level
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].level)
        XCTAssertEqual(entries[0].message, "Just a message without level")
    }

    func testParseNoTimestamp() async {
        let logData = """
        ERROR Message without timestamp
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].timestamp)
        XCTAssertEqual(entries[0].level, .error)
    }

    // MARK: - Multi-line Tests

    func testParseMultilineMessage() async {
        let logData = """
        2026-04-13T10:30:00Z ERROR Exception occurred:
          at function1()
          at function2()
          at function3()
        2026-04-13T10:30:01Z INFO Next message
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].message.contains("Exception occurred"))
        XCTAssertTrue(entries[0].message.contains("at function1()"))
        XCTAssertTrue(entries[0].message.contains("at function2()"))
        XCTAssertTrue(entries[0].message.contains("at function3()"))
        XCTAssertEqual(entries[1].message, "Next message")
    }

    func testParseStackTrace() async {
        let logData = """
        2026-04-13T10:30:00Z FATAL Uncaught exception:
        java.lang.NullPointerException: null
            at com.example.MyClass.method(MyClass.java:42)
            at com.example.Main.main(Main.java:15)
        2026-04-13T10:30:01Z INFO Recovery attempt
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].level, .fatal)
        XCTAssertTrue(entries[0].message.contains("Uncaught exception"))
        XCTAssertTrue(entries[0].message.contains("NullPointerException"))
        XCTAssertTrue(entries[0].message.contains("MyClass.java:42"))
    }

    // MARK: - Line Number Tests

    func testLineNumbersPreserved() async {
        let logData = """
        2026-04-13T10:30:00Z INFO Line 1
        2026-04-13T10:30:01Z INFO Line 2
        2026-04-13T10:30:02Z INFO Line 3
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].lineNumber, 1)
        XCTAssertEqual(entries[1].lineNumber, 2)
        XCTAssertEqual(entries[2].lineNumber, 3)
    }

    func testLineNumbersWithMultiline() async {
        let logData = """
        2026-04-13T10:30:00Z INFO First message
        continuation line
        2026-04-13T10:30:01Z INFO Second message
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].lineNumber, 1)
        XCTAssertEqual(entries[1].lineNumber, 3)
    }

    // MARK: - Edge Cases

    func testParseEmptyInput() async {
        let logData = Data()

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 0)
    }

    func testParseInvalidUTF8() async {
        // Create data with invalid UTF-8 sequences
        var invalidData = "2026-04-13T10:30:00Z INFO Valid start ".data(using: .utf8)!
        invalidData.append(contentsOf: [0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        invalidData.append(" valid end\n".data(using: .utf8)!)

        let entries = await parser.parse(invalidData)

        XCTAssertEqual(entries.count, 1)
        // Should contain replacement character U+FFFD
        XCTAssertTrue(entries[0].message.contains("Valid start"))
        XCTAssertTrue(entries[0].message.contains("valid end"))
    }

    func testParseBlankLines() async {
        let logData = """
        2026-04-13T10:30:00Z INFO First


        2026-04-13T10:30:01Z INFO Second
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        // Blank lines should be skipped
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].message, "First")
        XCTAssertEqual(entries[1].message, "Second")
    }

    func testParseMixedFormats() async {
        let logData = """
        2026-04-13T10:30:00Z INFO ISO format
        Apr 13 10:30:01 DEBUG Syslog format
        1713006602 TRACE Unix epoch
        ERROR No timestamp
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 4)
        XCTAssertNotNil(entries[0].timestamp)
        XCTAssertNotNil(entries[1].timestamp)
        XCTAssertNotNil(entries[2].timestamp)
        XCTAssertNil(entries[3].timestamp)
    }

    func testParseJSONLogLineWithEmbeddedMetadata() async {
        let logData = #"""
        {"timestamp":"2026-04-13T10:30:00Z","level":"error","message":"Request failed","request":{"id":"abc123","duration_ms":42},"success":false,"sample":null}
        """#.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries[0].timestamp)
        XCTAssertEqual(entries[0].level, .error)
        XCTAssertEqual(entries[0].message, "Request failed")
        XCTAssertEqual(entries[0].fields["request.id"]?.displayValue, "abc123")
        XCTAssertEqual(entries[0].fields["request.duration_ms"]?.displayValue, "42")
        XCTAssertEqual(entries[0].fields["success"]?.displayValue, "false")
        XCTAssertEqual(entries[0].fields["sample"]?.displayValue, "null")
        XCTAssertEqual(entries[0].fields["request"]?.displayValue, "")
    }

    func testParseJSONAliasesAndNestedMessage() async {
        let logData = #"""
        {"time":1713006600123,"severity":"warn","error":{"message":"Nested message"}}
        {"ts":"1713006600","lvl":3,"msg":"Numeric severity"}
        """#.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertNotNil(entries[0].timestamp)
        XCTAssertEqual(entries[0].level, .warning)
        XCTAssertEqual(entries[0].message, "Nested message")
        XCTAssertNotNil(entries[1].timestamp)
        XCTAssertEqual(entries[1].level, .error)
        XCTAssertEqual(entries[1].message, "Numeric severity")
    }

    func testParseJSONLinesWithoutTimestampOrLevelAreSeparateEntries() async {
        let logData = #"""
        {"message":"First","request":{"id":"one"}}
        {"message":"Second","request":{"id":"two"}}
        """#.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 2)
        XCTAssertNil(entries[0].timestamp)
        XCTAssertNil(entries[0].level)
        XCTAssertEqual(entries[0].message, "First")
        XCTAssertEqual(entries[1].message, "Second")
    }

    func testParseJSONArrayIndexesAsFieldPaths() async {
        let logData = #"""
        {"message":"Has items","items":[{"id":"first"},true,3]}
        """#.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["items"]?.displayValue, "")
        XCTAssertEqual(entries[0].fields["items[0]"]?.displayValue, "")
        XCTAssertEqual(entries[0].fields["items[0].id"]?.displayValue, "first")
        XCTAssertEqual(entries[0].fields["items[1]"]?.displayValue, "true")
        XCTAssertEqual(entries[0].fields["items[2]"]?.displayValue, "3")
    }

    func testParseInvalidJSONFallsThroughToPlainText() async {
        let logData = #"""
        {"valid":"json","level":"info","message":"good"}
        {broken json
        {"also_valid":"yes","msg":"works"}
        """#.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 3)
        guard entries.count == 3 else { return }
        XCTAssertEqual(entries[0].level, .info)
        XCTAssertEqual(entries[0].message, "good")
        XCTAssertEqual(entries[1].message, "{broken json")
        XCTAssertEqual(entries[2].message, "works")
    }

    func testParseJSONLogsFromFixtureFile() async throws {
        let fixtureURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("TestData/sample.jsonl")
        let data = try Data(contentsOf: fixtureURL)

        let entries = await parser.parse(data)

        XCTAssertEqual(entries.count, 10, "Should parse all 10 JSONL lines")

        // Line 1: standard fields + bool + number leaf
        let e1 = entries[0]
        XCTAssertEqual(e1.level, .info)
        XCTAssertEqual(e1.message, "Service started successfully")
        XCTAssertNotNil(e1.timestamp)
        XCTAssertEqual(e1.fields["service"]?.displayValue, "api-gateway")
        XCTAssertEqual(e1.fields["pid"]?.displayValue, "1234")
        XCTAssertEqual(e1.fields["success"]?.displayValue, "true")
        XCTAssertEqual(e1.fields["env"]?.displayValue, "production")

        // Line 2: time (ms epoch) + severity alias + msg alias + nested objects + array
        let e2 = entries[1]
        XCTAssertEqual(e2.level, .error)
        XCTAssertEqual(e2.message, "Connection refused")
        XCTAssertNotNil(e2.timestamp)
        XCTAssertEqual(e2.fields["host"]?.displayValue, "db-primary")
        XCTAssertEqual(e2.fields["retry"]?.displayValue, "")
        XCTAssertEqual(e2.fields["retry.count"]?.displayValue, "3")
        XCTAssertEqual(e2.fields["retry.max"]?.displayValue, "5")
        XCTAssertEqual(e2.fields["retry.strategy"]?.displayValue, "exponential")
        XCTAssertEqual(e2.fields["tags"]?.displayValue, "")
        XCTAssertEqual(e2.fields["tags[0]"]?.displayValue, "database")
        XCTAssertEqual(e2.fields["tags[1]"]?.displayValue, "critical")

        // Line 3: ts (string epoch) + warn alias
        let e3 = entries[2]
        XCTAssertEqual(e3.level, .warning)
        XCTAssertEqual(e3.message, "High memory usage detected")
        XCTAssertNotNil(e3.timestamp)
        XCTAssertEqual(e3.fields["percentage"]?.displayValue, "50.5")

        // Line 4: @timestamp + loglevel + log aliases
        let e4 = entries[3]
        XCTAssertEqual(e4.level, .debug)
        XCTAssertEqual(e4.message, "Cache miss for key user:42")
        XCTAssertNotNil(e4.timestamp)
        XCTAssertEqual(e4.fields["cache.hit"]?.displayValue, "false")
        XCTAssertEqual(e4.fields["cache.key"]?.displayValue, "user:42")
        XCTAssertEqual(e4.fields["duration_ms"]?.displayValue, "1.5")

        // Line 5: datetime + lvl (numeric 7=debug) + null value
        let e5 = entries[4]
        XCTAssertEqual(e5.level, .debug)
        XCTAssertEqual(e5.message, "Tracing request flow")
        XCTAssertNotNil(e5.timestamp)
        XCTAssertEqual(e5.fields["trace_id"]?.displayValue, "abc-def-123")
        XCTAssertEqual(e5.fields["parent_span"]?.displayValue, "null")

        // Line 6: error.message nested message extraction
        let e6 = entries[5]
        XCTAssertEqual(e6.level, .error)
        XCTAssertEqual(e6.message, "NullPointerException at UserService.getProfile")
        XCTAssertEqual(e6.fields["error.code"]?.displayValue, "NPE001")
        XCTAssertEqual(e6.fields["user_id"]?.displayValue, "usr_789")

        // Line 7: date + event alias
        let e7 = entries[6]
        XCTAssertEqual(e7.level, .info)
        XCTAssertEqual(e7.message, "Scheduled job completed")
        XCTAssertNotNil(e7.timestamp)
        XCTAssertEqual(e7.fields["job.files_deleted"]?.displayValue, "47")

        // Line 8: priority (numeric 4=warning) + nested rate_limit
        let e8 = entries[7]
        XCTAssertEqual(e8.level, .warning)
        XCTAssertEqual(e8.message, "Rate limit approaching threshold")
        XCTAssertEqual(e8.fields["rate_limit.current"]?.displayValue, "950")
        XCTAssertEqual(e8.fields["rate_limit.window_sec"]?.displayValue, "60")
        XCTAssertEqual(e8.fields["action_taken"]?.displayValue, "throttle")

        // Line 9: FATAL level
        let e9 = entries[8]
        XCTAssertEqual(e9.level, .fatal)
        XCTAssertEqual(e9.message, "Out of memory - shutting down")

        // Line 10: TRACE level with deep nesting
        let e10 = entries[9]
        XCTAssertEqual(e10.level, .trace)
        XCTAssertEqual(e10.message, "Entering function")
        XCTAssertEqual(e10.fields["metadata.caller"]?.displayValue, "middleware")
        XCTAssertEqual(e10.fields["metadata.line"]?.displayValue, "88")
        XCTAssertEqual(e10.fields["args.algorithm"]?.displayValue, "RS256")
        XCTAssertEqual(e10.fields["args"]?.displayValue, "")
    }

    func testParseCaseInsensitiveLogLevels() async {
        let logData = """
        2026-04-13T10:30:00Z error lowercase error
        2026-04-13T10:30:01Z Error Mixed case error
        2026-04-13T10:30:02Z ERROR Uppercase error
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].level, .error)
        XCTAssertEqual(entries[1].level, .error)
        XCTAssertEqual(entries[2].level, .error)
    }

    func testRawLinePreserved() async {
        let logData = """
        2026-04-13T10:30:00Z INFO   Preserve   extra   spaces
        """.data(using: .utf8)!

        let entries = await parser.parse(logData)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].rawLine, "2026-04-13T10:30:00Z INFO   Preserve   extra   spaces")
    }

    // MARK: - Performance Tests

    func testLargeFileYielding() async {
        // Generate 100k lines to test yielding behavior
        var largeLog = ""
        for i in 1...100000 {
            largeLog += "2026-04-13T10:30:00Z INFO Message \(i)\n"
        }
        let logData = largeLog.data(using: .utf8)!

        let startTime = Date()
        let entries = await parser.parse(logData)
        let duration = Date().timeIntervalSince(startTime)

        XCTAssertEqual(entries.count, 100000)
        // Should complete in reasonable time (< 5 seconds for 100k lines)
        XCTAssertLessThan(duration, 5.0)
    }
}
