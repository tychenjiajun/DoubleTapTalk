#!/bin/bash
# DoubleTapTalk Packaging Script
# Creates a distributable .dmg for GitHub releases

set -e

APP_NAME="DoubleTapTalk"
VERSION="1.1.0"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_OUTPUT="$PROJECT_DIR/DoubleTapTalk-$VERSION.dmg"

# Direct path to Xcode
XCODE="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"

echo "=== DoubleTapTalk Packaging Script ==="
echo "Version: $VERSION"
echo "Project: $PROJECT_DIR"
echo ""

# Clean previous build
echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"
rm -f "$DMG_OUTPUT"

# Build the app
echo "Building DoubleTapTalk.app..."
"$XCODE" -project "$PROJECT_DIR/DoubleTapTalk.xcodeproj" \
  -scheme DoubleTapTalk \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  build

# Find the built app
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "DoubleTapTalk.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: DoubleTapTalk.app not found!"
    exit 1
fi

echo "Built app: $APP_PATH"

# Create dmg
echo "Creating DMG..."
create-dmg \
  --volname "DoubleTapTalk" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 425 178 \
  "$DMG_OUTPUT" \
  "$APP_PATH"

# Verify
if [ -f "$DMG_OUTPUT" ]; then
    echo ""
    echo "=== SUCCESS ==="
    echo "DMG created: $DMG_OUTPUT"
    ls -lh "$DMG_OUTPUT"
else
    echo "Error: Failed to create DMG!"
    exit 1
fi