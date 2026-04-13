# XCUITest - Playwright for macOS Apps

XCUITest is Apple's UI testing framework - the equivalent of Playwright for native macOS/iOS apps.

## Comparison: Playwright vs XCUITest

| Task | Playwright (Web) | XCUITest (macOS/iOS) |
|------|------------------|----------------------|
| **Launch** | `await page.goto('url')` | `app.launch()` |
| **Click button** | `await page.click('button')` | `app.buttons["Open File"].tap()` |
| **Type text** | `await page.fill('input', 'text')` | `textField.typeText("database")` |
| **Assert visible** | `await expect(element).toBeVisible()` | `XCTAssertTrue(element.exists)` |
| **Screenshot** | `await page.screenshot()` | `let screenshot = app.screenshot()` |
| **Wait for element** | `await page.waitForSelector('.table')` | `element.waitForExistence(timeout: 5)` |
| **Find by text** | `page.locator('text=Submit')` | `app.staticTexts["Submit"]` |
| **Keyboard shortcut** | `await page.keyboard.press('Cmd+F')` | `app.typeKey("f", modifierFlags: .command)` |

## Prerequisites

**XCUITest requires Xcode.** You cannot run it with just `swift test`.

### Install Xcode

```bash
# Option 1: From App Store
open "macappstore://apps.apple.com/app/xcode/id497799835"

# Option 2: Command Line Tools only (won't work for UI tests)
xcode-select --install
```

## Running UI Tests

### Option 1: From Xcode (Recommended)

```bash
# 1. Open project in Xcode
open Package.swift

# 2. Wait for dependencies to resolve

# 3. Select "LogViewer" scheme at top
# 4. Press Cmd+U to run all tests
# 5. Or click the ▶️ next to specific test function
```

### Option 2: From Command Line (If Xcode installed)

```bash
# Run all UI tests
xcodebuild test \
  -scheme LogViewer \
  -destination 'platform=macOS' \
  -only-testing:LogViewerUITests

# Run specific test
xcodebuild test \
  -scheme LogViewer \
  -destination 'platform=macOS' \
  -only-testing:LogViewerUITests/LogViewerUITests/testFileOpenDisplaysLogs
```

### Option 3: Swift Package Manager (Limited)

```bash
# This will run unit tests, but NOT UI tests
swift test

# UI tests require the app to be packaged and launched
# SPM can't do this - you need Xcode
```

## Test Structure

Each test follows the **Arrange-Act-Assert** pattern (like Playwright):

```swift
func testSearchFunctionality() throws {
    // Arrange - Launch app and get to starting state
    app.launch()
    sleep(2) // Wait for load (better: use waitForExistence)

    // Act - Perform user action
    app.typeKey("f", modifierFlags: .command) // Cmd+F
    let searchField = app.searchFields.firstMatch
    searchField.tap()
    searchField.typeText("database")

    // Assert - Verify expected outcome
    let matchIndicator = app.staticTexts
        .containing(NSPredicate(format: "label CONTAINS 'match'"))
        .firstMatch
    XCTAssertTrue(
        matchIndicator.waitForExistence(timeout: 2),
        "Search results should appear"
    )
}
```

## Finding UI Elements

XCUITest finds elements using **Accessibility Identifiers** (similar to `data-testid` in Playwright):

### In Code (Add accessibility labels to your views):

```swift
// ContentView.swift
Button("Open File") {
    openFilePicker()
}
.accessibilityIdentifier("openFileButton") // ← Add this
.accessibilityLabel("Open log file")       // ← For VoiceOver + tests
```

### In Tests (Find by identifier):

```swift
// LogViewerUITests.swift
let openButton = app.buttons["openFileButton"] // By identifier
// or
let openButton = app.buttons["Open File"] // By visible text
```

## Common XCUITest Patterns

### 1. Wait for Element

```swift
// Wait up to 5 seconds for element to appear
let table = app.tables.firstMatch
XCTAssertTrue(table.waitForExistence(timeout: 5))
```

### 2. Find Element by Text

```swift
let errorText = app.staticTexts
    .containing(NSPredicate(format: "label CONTAINS 'ERROR'"))
    .firstMatch
```

### 3. Verify Element Count

```swift
let logLines = app.tables.cells.count
XCTAssertEqual(logLines, 15, "Should show 15 log entries")
```

### 4. Take Screenshot

```swift
let screenshot = app.screenshot()
let attachment = XCTAttachment(screenshot: screenshot)
attachment.name = "error_state"
attachment.lifetime = .keepAlways
add(attachment)
```

### 5. Test Keyboard Shortcuts

```swift
app.typeKey("f", modifierFlags: .command) // Cmd+F
app.typeKey("g", modifierFlags: [.command, .shift]) // Shift+Cmd+G
```

## Debugging Tips

### 1. Print UI Hierarchy

```swift
// Add this in your test to see all elements
print(app.debugDescription)
```

### 2. Slow Down Tests (for watching)

```swift
override func setUp() {
    app.launchArguments += ["-UITestingSlowAnimations"]
}
```

### 3. Enable Verbose Logging

```bash
xcodebuild test -verbose
```

### 4. View Test Results

After running tests in Xcode:
1. Open **Report Navigator** (Cmd+9)
2. Click latest test run
3. See screenshots, logs, and failures

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: UI Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v3

    - name: Run UI Tests
      run: |
        xcodebuild test \
          -scheme LogViewer \
          -destination 'platform=macOS' \
          -only-testing:LogViewerUITests

    - name: Upload Screenshots
      if: failure()
      uses: actions/upload-artifact@v3
      with:
        name: test-screenshots
        path: ~/Library/Logs/DiagnosticReports/
```

## Performance Testing

XCUITest includes performance metrics (like Playwright's `page.waitForLoadState`):

```swift
func testLaunchPerformance() throws {
    measure(metrics: [XCTApplicationLaunchMetric()]) {
        app.launch()
        app.terminate()
    }
}
```

## Comparison to Your Current test_e2e.sh

| Feature | test_e2e.sh (AppleScript) | XCUITest |
|---------|---------------------------|----------|
| Launch app | ✅ | ✅ |
| Click buttons | ⚠️ Limited | ✅ Full control |
| Type text | ⚠️ Limited | ✅ Full control |
| Assert UI state | ❌ No | ✅ Yes |
| Screenshots | ❌ No | ✅ Yes |
| CI/CD support | ⚠️ Limited | ✅ Full support |
| Requires Xcode | ❌ No | ✅ Yes |

## Next Steps

1. **Install Xcode** (if not already installed)
2. **Open Package.swift in Xcode**
3. **Add accessibility identifiers** to your SwiftUI views:
   ```swift
   .accessibilityIdentifier("searchField")
   .accessibilityLabel("Search log entries")
   ```
4. **Run tests** with Cmd+U
5. **View results** in Report Navigator (Cmd+9)

## Resources

- [Apple XCUITest Documentation](https://developer.apple.com/documentation/xctest/user_interface_tests)
- [WWDC: Testing in Xcode](https://developer.apple.com/videos/play/wwdc2019/413/)
- [UI Testing Cheat Sheet](https://www.hackingwithswift.com/articles/148/xcode-ui-testing-cheat-sheet)
