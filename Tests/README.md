# Lumen Test Files

This directory contains test utilities and generated test log files for the Lumen application.

## Test File Generator

### Overview

The `generate_test_logs.sh` script generates sample log files of various sizes and characteristics for testing the Lumen application's parsing, filtering, search, and performance capabilities.

### Usage

```bash
# Generate test files in default location (Tests/TestLogs/)
./Tests/generate_test_logs.sh

# Generate test files in custom location
./Tests/generate_test_logs.sh /path/to/output
```

### Generated Files

The script generates 8 test log files:

#### 1. **small.log** (100 lines, ~2KB)
- **Purpose:** Quick unit tests, basic functionality verification
- **Content:** All 6 log levels (FATAL, ERROR, WARNING, INFO, DEBUG, TRACE)
- **Timestamps:** Mixed formats (ISO 8601, syslog, Unix epoch)
- **Use Case:** Default test file, quick parsing tests

#### 2. **medium.log** (10,000 lines, ~500KB)
- **Purpose:** Integration tests, filter/search accuracy
- **Content:** Realistic log level distribution (INFO 50%, DEBUG 30%, WARNING 12%, ERROR 6%, TRACE 1.5%, FATAL 0.5%)
- **Timestamps:** All three formats mixed throughout
- **Use Case:** Standard test dataset for filter and search operations

#### 3. **large.log** (1,000,000 lines, ~100MB)
- **Purpose:** Performance testing on modern hardware
- **Content:** Same distribution as medium.log
- **Timestamps:** All formats mixed
- **Use Case:** Verify parsing speed (<3s on M1 Mac), memory efficiency, scrolling performance

#### 4. **huge.log** (5,000,000 lines, ~500MB)
- **Purpose:** Stress testing, memory budget validation
- **Content:** Same distribution as medium.log
- **Timestamps:** All formats mixed
- **Use Case:** Verify handling of maximum file size, memory usage <2x file size (<1GB RAM)
- **Warning:** Generation takes 2-5 minutes. File size is substantial; ensure adequate disk space.

#### 5. **field_values.log** (small, key-value examples)
- **Purpose:** Manual verification of custom extracted field columns
- **Content:** Plain-text log messages with `field=value`, `field="quoted value"`, `field='quoted value'`, dotted field names, and hyphenated field names
- **Use Case:** Open this file, add fields like `request_id`, `user`, `status`, `error.code`, `trace-id`, `cache.hit`, or `queue`, and verify the table displays extracted values

#### 6. **binary.bin** (small, ~50 bytes)
- **Purpose:** Error handling test for binary files
- **Content:** Mix of text and binary data including null bytes (`\x00`) and high bytes (`\xFF\xFE`)
- **Expected Behavior:** Lumen should detect binary content and show error instead of attempting to parse
- **Use Case:** Verify binary file detection (first 8KB check for null bytes)

#### 7. **malformed.log** (~1KB)
- **Purpose:** Edge case and error handling
- **Content:**
  - Lines without timestamps or log levels
  - Lines with unusual timestamp formats
  - Very long lines (>100KB simulated via repeated text)
  - Invalid UTF-8 byte sequences mixed with valid UTF-8
  - Incomplete line without newline terminator
- **Expected Behavior:** Parser should handle gracefully, replace invalid UTF-8 with U+FFFD, truncate long lines with indicator
- **Use Case:** Verify robustness against malformed input

#### 8. **multiline.log** (stack traces, ~500 bytes)
- **Purpose:** Multi-line entry detection and grouping
- **Content:**
  - Stack traces (lines without leading timestamps that follow an error entry)
  - JSON payloads spanning multiple lines
  - Function call stacks
  - Database query results
- **Expected Behavior:** Parser should group continuation lines (without timestamp) with preceding entry
- **Use Case:** Verify multi-line entry detection and proper grouping during display

### Timestamp Formats Tested

The script generates timestamps in three formats to test parser robustness:

1. **ISO 8601** (most common): `2026-04-13T10:30:00Z`
   - Full UTC format with timezone indicator
   - Includes timezone offsets (e.g., `2026-04-13T10:30:00+02:00`)

2. **Syslog** (legacy systems): `Apr 13 10:30:00`
   - Short month name
   - No year (assumes current year in parser)
   - Local timezone assumed

3. **Unix Epoch** (numeric): `1681380600`
   - Seconds since 1970-01-01 00:00:00 UTC
   - Also tested with fractional seconds (floats)

### Log Levels Distribution

For realistic testing, the generator uses weighted distributions:

| Level | Percentage | Typical Use Case |
|-------|-----------|------------------|
| INFO | 50% | Standard operational messages |
| DEBUG | 30% | Development and troubleshooting |
| WARNING | 12% | Non-critical issues requiring attention |
| ERROR | 6% | Failed operations needing investigation |
| TRACE | 1.5% | Highly detailed execution tracing |
| FATAL | 0.5% | Application-critical failures |

### Performance Testing

Use these files with Instruments and XCTest to verify performance requirements:

```swift
// Example XCTest performance measurement
func testLargeFileParsing() {
    let url = URL(fileURLWithPath: "Tests/TestLogs/large.log")
    let data = try! Data(contentsOf: url)

    measure {
        let entries = LogParser().parse(data) // Async, tested synchronously
    }
}
```

**Performance Targets:**
- **large.log (100MB, 1M lines):** Parse in <3 seconds on M1 Mac
- **huge.log (500MB, 5M lines):** Parse in <10 seconds on M1 Mac
- **Memory budget:** <2x file size (e.g., 500MB file → <1GB RAM)

### Running the Script

#### Prerequisites
- Bash 4.0+ (macOS has Bash 3.2; use Homebrew for Bash 4+)
- Standard Unix utilities: `date`, `echo`, `mkdir`, `sed` (all available on macOS)
- ~650MB free disk space for all files (optional: skip huge.log generation to save ~500MB)

#### Execution
```bash
# Make script executable (one-time)
chmod +x Tests/generate_test_logs.sh

# Generate all test files (takes 2-5 minutes)
./Tests/generate_test_logs.sh

# Generate in custom directory
./Tests/generate_test_logs.sh ~/Downloads/LumenTests
```

#### Output
The script prints a summary of generated files:
```
Test log generation complete!

Generated files:
  small.log (2.1K)
  medium.log (513K)
  large.log (103M)
  huge.log (517M)
  binary.bin (50B)
  malformed.log (1.2K)
  multiline.log (483B)

Summary:
 5001101 total lines
```

### Integration with Tests

#### Unit Tests
```swift
// Use small.log for quick unit tests
let testBundle = Bundle(for: type(of: self))
let url = testBundle.url(forResource: "small", withExtension: "log")!
let data = try! Data(contentsOf: url)
let parser = LogParser()
let entries = await parser.parse(data)
```

#### Performance Tests
```swift
// Use large.log for performance benchmarking
func testLargeFileParsing() {
    let url = URL(fileURLWithPath: "Tests/TestLogs/large.log")
    let data = try! Data(contentsOf: url)

    measure(options: .init(invocationsPerIteration: 1, iterationCount: 1)) {
        let parser = LogParser()
        let entries = await parser.parse(data)
    }
}
```

#### Edge Case Tests
```swift
// Use malformed.log and multiline.log for edge cases
func testMalformedInput() {
    let url = URL(fileURLWithPath: "Tests/TestLogs/malformed.log")
    let data = try! Data(contentsOf: url)
    let parser = LogParser()
    let entries = await parser.parse(data)

    // Verify invalid UTF-8 replaced with U+FFFD
    // Verify long lines truncated
    // Verify entries without timestamps have nil timestamp
}

func testBinaryDetection() {
    let url = URL(fileURLWithPath: "Tests/TestLogs/binary.bin")
    let data = try! Data(contentsOf: url)
    // First 8KB check should detect null bytes and mark as binary
    XCTAssertTrue(isBinaryFile(data: data))
}
```

### Cleanup

To remove generated test files:
```bash
rm -rf Tests/TestLogs/
```

Or selectively:
```bash
rm Tests/TestLogs/huge.log  # Free up ~500MB
```

### Customization

To generate custom test files, edit `generate_test_logs.sh`:

1. **Change line counts:** Modify the `{1..N}` range in for loops
2. **Adjust distributions:** Change the weighted random selection in the distribution logic
3. **Add custom timestamps:** Extend the timestamp generation functions
4. **Add new message types:** Expand the `sample_message()` function

### Troubleshooting

**Issue:** Script fails with `date: invalid date` on Linux
- **Solution:** The script uses macOS-specific `date -v` syntax. On Linux, install `GNU coreutils` or rewrite date calculations.

**Issue:** Script takes too long
- **Solution:** Comment out the huge.log generation section (lines for 5M lines) to save ~3 minutes.

**Issue:** Disk space exhausted during generation
- **Solution:** Run `./Tests/generate_test_logs.sh /path/to/external/drive` or skip huge.log generation.

### Notes

- All timestamps are randomly generated within date ranges to provide realistic variety
- Files are deterministic only within the same system due to random number generation
- For reproducible tests, consider seeding RANDOM or using fixed test data
- The script is idempotent; running it multiple times will overwrite existing files

---

**Last Updated:** 2026-04-13
**Phase:** Task 2.5 (Core Services)
