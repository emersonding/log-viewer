#!/bin/bash
set -e

echo "🔨 Building LogViewer..."

# Build the executable
swift build -c release

# Create .app bundle structure
APP_NAME="LogViewer.app"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME"

echo "📦 Creating app bundle..."

# Clean and create directories
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp .build/release/LogViewer "$APP_DIR/Contents/MacOS/LogViewer"

# Copy Info.plist
cp Info.plist "$APP_DIR/Contents/Info.plist"

# Set executable permissions
chmod +x "$APP_DIR/Contents/MacOS/LogViewer"

# Verify the bundle is valid
echo "🔍 Verifying app bundle..."

# Check executable exists and is runnable
if [ ! -x "$APP_DIR/Contents/MacOS/LogViewer" ]; then
    echo "❌ FAIL: Executable not found or not executable"
    exit 1
fi

# Check Info.plist has literal CFBundleExecutable (not Xcode variables)
BUNDLE_EXEC=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_DIR/Contents/Info.plist" 2>/dev/null)
if [ "$BUNDLE_EXEC" != "LogViewer" ]; then
    echo "❌ FAIL: CFBundleExecutable is '$BUNDLE_EXEC', expected 'LogViewer'"
    echo "   Info.plist may contain unresolved Xcode variables like \$(EXECUTABLE_NAME)"
    exit 1
fi

# Smoke test: launch app, verify it starts, then kill it
echo "🚀 Smoke test: launching app..."
open "$APP_DIR" 2>&1
sleep 2
if pgrep -f "$APP_DIR/Contents/MacOS/LogViewer" > /dev/null; then
    echo "✅ Smoke test passed: app launches and runs"
    pkill -f "$APP_DIR/Contents/MacOS/LogViewer" 2>/dev/null || true
else
    echo "❌ FAIL: App did not start. Check Console.app for crash logs."
    exit 1
fi

echo ""
echo "✅ App bundle created at: $APP_DIR"
echo ""
echo "To run the app:"
echo "  open $APP_DIR"
echo ""
echo "To install it to Applications:"
echo "  cp -r $APP_DIR /Applications/"
