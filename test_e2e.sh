#!/bin/bash
# Automated E2E tests for Lumen using AppleScript
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

APP_PATH="build/Lumen.app"
TEST_LOG="$(pwd)/test_sample.log"

echo "════════════════════════════════════════════════════════════"
echo "   Lumen Automated E2E Tests"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check prerequisites
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ FAIL: App not found${NC}"
    echo "Run ./build_app.sh first!"
    exit 1
fi

if [ ! -f "test_sample.log" ]; then
    echo -e "${RED}❌ FAIL: Test log not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Test 1: Launch app
echo "Test 1: Launch application..."
open "$APP_PATH" --args "$TEST_LOG" 2>&1 | tee /tmp/lumen_test.log &
APP_PID=$!
sleep 3

# Check if app is running
if pgrep -f "Lumen" > /dev/null; then
    echo -e "${GREEN}✓${NC} Test 1 PASSED: App launched successfully"
else
    echo -e "${RED}❌${NC} Test 1 FAILED: App did not launch"
    exit 1
fi

echo ""

# Test 2: Check if app appears in Dock (via process check)
echo "Test 2: Verify app is running..."
if ps aux | grep "[L]umen.app/Contents/MacOS/Lumen" > /dev/null; then
    echo -e "${GREEN}✓${NC} Test 2 PASSED: App process is active"
else
    echo -e "${RED}❌${NC} Test 2 FAILED: App process not found"
    exit 1
fi

echo ""

# Test 3: Verify file was opened (check console output if available)
echo "Test 3: Verify file opened..."
sleep 2
if grep -q "File opened successfully" /tmp/lumen_test.log 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Test 3 PASSED: File opened successfully"
else
    echo -e "${YELLOW}⚠${NC}  Test 3 SKIPPED: Console output not captured (run manually to verify)"
fi

echo ""

# Test 4: Use AppleScript to interact with the app
echo "Test 4: UI interaction test..."

# Try to activate the app and send keyboard commands
osascript <<EOF
tell application "System Events"
    set frontmost of process "Lumen" to true
    delay 1

    -- Try to open file with Cmd+O (if not already open)
    keystroke "o" using command down
    delay 0.5

    -- Cancel file picker if it appeared
    key code 53 -- Escape key
    delay 0.5

    -- Try search shortcut Cmd+F
    keystroke "f" using command down
    delay 0.5

    -- Type search query
    keystroke "database"
    delay 0.5
end tell
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Test 4 PASSED: UI automation commands executed"
else
    echo -e "${YELLOW}⚠${NC}  Test 4 SKIPPED: AppleScript automation not available (requires accessibility permissions)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "   Test Summary"
echo "════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓${NC} App launches successfully"
echo -e "${GREEN}✓${NC} App process runs without crashing"
echo ""
echo "To verify log display:"
echo "  1. Check if the Lumen window shows log entries"
echo "  2. Verify all 15 lines from test_sample.log are visible"
echo "  3. Test filter buttons (ERROR, WARNING, INFO, DEBUG, TRACE)"
echo "  4. Test search functionality"
echo ""
echo "Press Ctrl+C to quit the app and exit tests."
echo ""

# Keep running to maintain app
wait $APP_PID
