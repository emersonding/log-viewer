#!/bin/bash
#
# LogViewer Test File Generator
# Generates sample log files for testing the LogViewer application.
#
# Usage: ./Tests/generate_test_logs.sh [output_dir]
# Default output directory: ./Tests/TestLogs/
#
# Generated files:
#   - small.log (100 lines, all log levels, mixed timestamps)
#   - medium.log (10,000 lines, realistic distribution)
#   - large.log (1M lines, ~100MB, for performance testing)
#   - huge.log (5M lines, ~500MB, for stress testing)
#   - binary.bin (binary file for error handling test)
#   - malformed.log (invalid UTF-8, missing timestamps, long lines)
#   - multiline.log (stack traces and continuation lines)
#

set -e

# Configuration
OUTPUT_DIR="${1:-.}/Tests/TestLogs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Generating test log files in: $OUTPUT_DIR"

# ============================================================================
# Helper Functions
# ============================================================================

# Generate a random ISO 8601 timestamp within a date range
# Args: offset_days (negative for past)
random_timestamp() {
    local offset_days=$1
    local base_date=$(date -u -v${offset_days}d +%s)
    local random_seconds=$((RANDOM * 3600 / 32768 + RANDOM * 60 / 32768))
    local timestamp_epoch=$((base_date + random_seconds))
    date -u -r $timestamp_epoch +"%Y-%m-%dT%H:%M:%SZ"
}

# Generate a syslog-style timestamp
syslog_timestamp() {
    local offset_days=$1
    local base_date=$(date -u -v${offset_days}d +%s)
    local random_seconds=$((RANDOM * 3600 / 32768 + RANDOM * 60 / 32768))
    local timestamp_epoch=$((base_date + random_seconds))
    date -u -r $timestamp_epoch +"%b %d %H:%M:%S"
}

# Generate a Unix epoch timestamp
unix_epoch_timestamp() {
    local offset_days=$1
    local base_date=$(date -u -v${offset_days}d +%s)
    local random_seconds=$((RANDOM * 3600 / 32768 + RANDOM * 60 / 32768))
    local timestamp_epoch=$((base_date + random_seconds))
    echo "$timestamp_epoch"
}

# Get a random log level
random_log_level() {
    local levels=("FATAL" "ERROR" "WARNING" "INFO" "DEBUG" "TRACE")
    echo "${levels[$((RANDOM % 6))]}"
}

# Get a sample log message
sample_message() {
    local messages=(
        "Request completed successfully"
        "User authentication failed"
        "Database connection timeout"
        "Memory usage exceeded threshold"
        "Cache invalidated"
        "Configuration reload started"
        "Network packet loss detected"
        "Disk space running low"
        "Scheduled job executed"
        "Error processing request"
        "Connection reset by peer"
        "Invalid input parameters"
        "Transaction committed"
        "Background task failed"
        "Resource not found"
    )
    echo "${messages[$((RANDOM % ${#messages[@]}))]}"
}

# ============================================================================
# Generate small.log (100 lines, all log levels, mixed timestamps)
# ============================================================================

echo "Generating small.log (100 lines)..."
> "$OUTPUT_DIR/small.log"

for i in {1..100}; do
    case $((i % 7)) in
        0)
            timestamp=$(random_timestamp -30)
            level="FATAL"
            ;;
        1)
            timestamp=$(random_timestamp -20)
            level="ERROR"
            ;;
        2)
            timestamp=$(random_timestamp -10)
            level="WARNING"
            ;;
        3)
            timestamp=$(random_timestamp -5)
            level="INFO"
            ;;
        4)
            timestamp=$(random_timestamp -2)
            level="DEBUG"
            ;;
        5)
            timestamp=$(random_timestamp -1)
            level="TRACE"
            ;;
        *)
            timestamp=$(syslog_timestamp -30)
            level=$(random_log_level)
            ;;
    esac

    message=$(sample_message)
    echo "$timestamp [$level] $message" >> "$OUTPUT_DIR/small.log"
done

# ============================================================================
# Generate medium.log (10,000 lines, realistic distribution)
# ============================================================================

echo "Generating medium.log (10,000 lines)..."
> "$OUTPUT_DIR/medium.log"

for i in {1..10000}; do
    # Weighted distribution: INFO 50%, DEBUG 30%, WARNING 12%, ERROR 6%, TRACE 1.5%, FATAL 0.5%
    rand=$((RANDOM % 200))

    if [ $rand -lt 100 ]; then
        level="INFO"
    elif [ $rand -lt 160 ]; then
        level="DEBUG"
    elif [ $rand -lt 184 ]; then
        level="WARNING"
    elif [ $rand -lt 196 ]; then
        level="ERROR"
    elif [ $rand -lt 199 ]; then
        level="TRACE"
    else
        level="FATAL"
    fi

    # Mix timestamp formats
    case $((i % 3)) in
        0)
            timestamp=$(random_timestamp -45)
            ;;
        1)
            timestamp=$(syslog_timestamp -30)
            ;;
        *)
            timestamp=$(unix_epoch_timestamp -15)
            ;;
    esac

    message=$(sample_message)
    echo "$timestamp [$level] $message" >> "$OUTPUT_DIR/medium.log"
done

# ============================================================================
# Generate large.log (1M lines, ~100MB)
# ============================================================================

echo "Generating large.log (1,000,000 lines, ~100MB)..."
> "$OUTPUT_DIR/large.log"

for i in {1..1000000}; do
    if [ $((i % 100000)) -eq 0 ]; then
        echo "  Progress: $i / 1,000,000 lines"
    fi

    # Weighted distribution
    rand=$((RANDOM % 200))
    if [ $rand -lt 100 ]; then
        level="INFO"
    elif [ $rand -lt 160 ]; then
        level="DEBUG"
    elif [ $rand -lt 184 ]; then
        level="WARNING"
    elif [ $rand -lt 196 ]; then
        level="ERROR"
    elif [ $rand -lt 199 ]; then
        level="TRACE"
    else
        level="FATAL"
    fi

    # Mix timestamp formats
    case $((i % 3)) in
        0)
            timestamp=$(random_timestamp -45)
            ;;
        1)
            timestamp=$(syslog_timestamp -30)
            ;;
        *)
            timestamp=$(unix_epoch_timestamp -15)
            ;;
    esac

    message=$(sample_message)
    echo "$timestamp [$level] $message" >> "$OUTPUT_DIR/large.log"
done

# ============================================================================
# Generate huge.log (5M lines, ~500MB)
# ============================================================================

echo "Generating huge.log (5,000,000 lines, ~500MB)..."
echo "  This may take 2-5 minutes..."
> "$OUTPUT_DIR/huge.log"

for i in {1..5000000}; do
    if [ $((i % 500000)) -eq 0 ]; then
        echo "  Progress: $i / 5,000,000 lines"
    fi

    # Weighted distribution
    rand=$((RANDOM % 200))
    if [ $rand -lt 100 ]; then
        level="INFO"
    elif [ $rand -lt 160 ]; then
        level="DEBUG"
    elif [ $rand -lt 184 ]; then
        level="WARNING"
    elif [ $rand -lt 196 ]; then
        level="ERROR"
    elif [ $rand -lt 199 ]; then
        level="TRACE"
    else
        level="FATAL"
    fi

    # Mix timestamp formats
    case $((i % 3)) in
        0)
            timestamp=$(random_timestamp -45)
            ;;
        1)
            timestamp=$(syslog_timestamp -30)
            ;;
        *)
            timestamp=$(unix_epoch_timestamp -15)
            ;;
    esac

    message=$(sample_message)
    echo "$timestamp [$level] $message" >> "$OUTPUT_DIR/huge.log"
done

# ============================================================================
# Generate binary.bin (binary file for error handling test)
# ============================================================================

echo "Generating binary.bin..."
# Create a file with binary content and embedded nulls
{
    echo -ne "Log file with binary content: \x00\x01\x02\x03\x04\x05"
    echo -ne "\xFF\xFE\xFD\xFC\xFB\xFA"
    echo -ne "\x00\x00\x00\x00"
    echo "Some text mixed with binary"
    echo -ne "\x00\x00\x00\x00"
    echo "More content"
} > "$OUTPUT_DIR/binary.bin"

# ============================================================================
# Generate malformed.log (invalid UTF-8, missing timestamps, long lines)
# ============================================================================

echo "Generating malformed.log..."
> "$OUTPUT_DIR/malformed.log"

# Line with missing timestamp
echo "This line has no timestamp or level" >> "$OUTPUT_DIR/malformed.log"

# Valid log line
echo "2026-04-13T10:30:00Z [INFO] Normal log line" >> "$OUTPUT_DIR/malformed.log"

# Line with no level
echo "2026-04-13T10:31:00Z Processing request..." >> "$OUTPUT_DIR/malformed.log"

# Very long line (simulate a stack trace or large JSON)
long_line="2026-04-13T10:32:00Z [ERROR] Request failed: "
for i in {1..50}; do
    long_line="${long_line}Lorem ipsum dolor sit amet consectetur adipiscing elit. "
done
echo "$long_line" >> "$OUTPUT_DIR/malformed.log"

# Invalid UTF-8 sequences (using printf to embed actual bytes)
echo "2026-04-13T10:33:00Z [WARNING] Data with invalid UTF-8:" >> "$OUTPUT_DIR/malformed.log"
printf '2026-04-13T10:34:00Z [DEBUG] Mixed valid and invalid: %s\n' "$(printf 'Valid\xC3\xA9\xFF\xFEInvalid')" >> "$OUTPUT_DIR/malformed.log"

# Line with unusual timestamp format
echo "13-Apr-2026 10:35:00 [ERROR] Unusual timestamp format" >> "$OUTPUT_DIR/malformed.log"

# Line with no newline at end (simulate incomplete line from concurrent writer)
echo -n "2026-04-13T10:36:00Z [INFO] Incomplete line without newline" >> "$OUTPUT_DIR/malformed.log"

# ============================================================================
# Generate multiline.log (stack traces and continuation lines)
# ============================================================================

echo "Generating multiline.log..."
> "$OUTPUT_DIR/multiline.log"

echo "2026-04-13T10:40:00Z [INFO] Application started successfully" >> "$OUTPUT_DIR/multiline.log"

echo "2026-04-13T10:41:00Z [ERROR] Unhandled exception occurred" >> "$OUTPUT_DIR/multiline.log"
echo "Exception: NullPointerException" >> "$OUTPUT_DIR/multiline.log"
echo "  at com.example.service.ProcessData.execute(ProcessData.swift:42)" >> "$OUTPUT_DIR/multiline.log"
echo "  at com.example.controller.DataController.handleRequest(DataController.swift:156)" >> "$OUTPUT_DIR/multiline.log"
echo "  at com.example.api.Router.dispatch(Router.swift:89)" >> "$OUTPUT_DIR/multiline.log"

echo "2026-04-13T10:42:00Z [WARNING] Slow query detected" >> "$OUTPUT_DIR/multiline.log"
echo "Query: SELECT * FROM users WHERE active = true" >> "$OUTPUT_DIR/multiline.log"
echo "Execution time: 2345ms" >> "$OUTPUT_DIR/multiline.log"
echo "Rows affected: 150000" >> "$OUTPUT_DIR/multiline.log"

echo "2026-04-13T10:43:00Z [DEBUG] JSON response:" >> "$OUTPUT_DIR/multiline.log"
echo '{' >> "$OUTPUT_DIR/multiline.log"
echo '  "status": "success",' >> "$OUTPUT_DIR/multiline.log"
echo '  "data": {' >> "$OUTPUT_DIR/multiline.log"
echo '    "user_id": 12345,' >> "$OUTPUT_DIR/multiline.log"
echo '    "username": "john_doe",' >> "$OUTPUT_DIR/multiline.log"
echo '    "roles": ["admin", "user"]' >> "$OUTPUT_DIR/multiline.log"
echo '  }' >> "$OUTPUT_DIR/multiline.log"
echo '}' >> "$OUTPUT_DIR/multiline.log"

echo "2026-04-13T10:44:00Z [TRACE] Function call stack:" >> "$OUTPUT_DIR/multiline.log"
echo "  main() -> parseArguments() -> processInput() -> validateData()" >> "$OUTPUT_DIR/multiline.log"
echo "  validateData() -> applyRules() -> execute()" >> "$OUTPUT_DIR/multiline.log"

echo "2026-04-13T10:45:00Z [INFO] Final status: All processing complete" >> "$OUTPUT_DIR/multiline.log"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "Test log generation complete!"
echo ""
echo "Generated files:"
ls -lh "$OUTPUT_DIR"/ | awk 'NR>1 {printf "  %s (%s)\n", $9, $5}'
echo ""
echo "Summary:"
wc -l "$OUTPUT_DIR"/*.log | tail -1
echo ""
echo "These files are ready for testing the LogViewer application."
echo "Use them in unit tests and performance benchmarks."
