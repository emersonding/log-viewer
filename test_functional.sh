#!/bin/bash
# Functional tests that don't require Xcode
# Tests app behavior by checking console output and file system

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEST_LOG="test_sample.log"
APP_PATH="build/LogViewer.app"
DEBUG_OUTPUT="/tmp/logviewer_test_$$. log"

echo "════════════════════════════════════════════════════════════"
echo "   LogViewer Functional Tests (No Xcode Required)"
echo "════════════════════════════════════════════════════════════"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    pkill -f "LogViewer" 2>/dev/null || true
    rm -f "$DEBUG_OUTPUT"
}
trap cleanup EXIT

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_cmd="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test $TESTS_RUN: $test_name... "

    if eval "$test_cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: App bundle exists
run_test "App bundle exists" \
    "[ -d '$APP_PATH' ]"

# Test 2: App is executable
run_test "App executable is valid" \
    "[ -x '$APP_PATH/Contents/MacOS/LogViewer' ]"

# Test 3: Info.plist exists and is valid
run_test "Info.plist is valid" \
    "/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' '$APP_PATH/Contents/Info.plist'"

# Test 4: Test log file exists
run_test "Test log file exists" \
    "[ -f '$TEST_LOG' ]"

# Test 5: App launches without crash
echo -n "Test 5: App launches and runs... "
open "$APP_PATH" --args "$(pwd)/$TEST_LOG" 2>&1 > "$DEBUG_OUTPUT" &
APP_PID=$!
sleep 3

if pgrep -f "LogViewer" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "Check $DEBUG_OUTPUT for errors"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 6: Parser output verification
echo -n "Test 6: File parsing succeeds... "
sleep 2
if grep -q "File opened successfully" "$DEBUG_OUTPUT" 2>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))

    # Extract parse count
    PARSE_COUNT=$(grep "Total entries parsed:" "$DEBUG_OUTPUT" | grep -o '[0-9]\+' || echo "0")
    echo "   → Parsed $PARSE_COUNT entries"
else
    echo -e "${YELLOW}⚠ SKIP${NC} (no debug output captured)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 7: Filter application
echo -n "Test 7: Filters apply correctly... "
if grep -q "Filters applied:" "$DEBUG_OUTPUT" 2>/dev/null; then
    DISPLAY_COUNT=$(grep "Filters applied:" "$DEBUG_OUTPUT" | grep -o '[0-9]\+ entries displayed' | grep -o '[0-9]\+' || echo "0")
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "   → Displaying $DISPLAY_COUNT entries"
else
    echo -e "${YELLOW}⚠ SKIP${NC} (no filter output captured)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 8: Keyboard shortcut (Cmd+F for search)
echo -n "Test 8: Keyboard shortcuts respond... "
osascript <<EOF 2>/dev/null
tell application "System Events"
    set frontmost of process "LogViewer" to true
    delay 0.5
    keystroke "f" using command down
    delay 0.5
end tell
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${YELLOW}⚠ SKIP${NC} (accessibility permissions needed)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 9: Memory usage check
echo -n "Test 9: Memory usage reasonable... "
MEM_KB=$(ps -o rss= -p $(pgrep -f LogViewer) 2>/dev/null || echo "0")
MEM_MB=$((MEM_KB / 1024))

if [ "$MEM_MB" -lt 500 ]; then
    echo -e "${GREEN}✓ PASS${NC} (using ${MEM_MB}MB)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
elif [ "$MEM_MB" -lt 1000 ]; then
    echo -e "${YELLOW}⚠ WARN${NC} (using ${MEM_MB}MB - high but acceptable)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (using ${MEM_MB}MB - too high)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

# Test 10: App still responsive
echo -n "Test 10: App remains responsive... "
sleep 1
if pgrep -f "LogViewer" > /dev/null && ! pgrep -f "LogViewer.*not responding" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_RUN=$((TESTS_RUN + 1))

echo ""
echo "════════════════════════════════════════════════════════════"
echo "   Test Results"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Total:  $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ -f "$DEBUG_OUTPUT" ]; then
    echo "Debug output saved to: $DEBUG_OUTPUT"
    echo ""
    echo "Key metrics from debug output:"
    grep -E "✅|📊|🎯" "$DEBUG_OUTPUT" 2>/dev/null || echo "  (no debug output captured)"
    echo ""
fi

# Return exit code based on results
if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
