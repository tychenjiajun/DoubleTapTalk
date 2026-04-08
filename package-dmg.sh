#!/bin/bash

APP_NAME="DoubleTapTalk"
VERSION="1.0.0"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD_DIR=".build/release"

echo "=== Packaging ${APP_NAME} v${VERSION} ==="

# Clean up previous builds
rm -rf "${APP_BUNDLE}" "${DMG_NAME}" "/tmp/${APP_NAME}-temp"
mkdir -p "/tmp/${APP_NAME}-temp"

# Create app bundle structure
echo "Creating app bundle..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Create Info.plist (with proper entitlements for menu bar app)
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DoubleTapTalk</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.jiajun.doubletaptalk.app</string>
    <key>CFBundleName</key>
    <string>DoubleTapTalk</string>
    <key>CFBundleDisplayName</key>
    <string>DoubleTapTalk</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>DoubleTapTalk needs microphone access to record your voice</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>DoubleTapTalk needs accessibility access to simulate keyboard input</string>
</dict>
</plist>
PLIST

# Copy entitlements if exists
if [ -f "DoubleTapTalk.entitlements" ]; then
    cp DoubleTapTalk.entitlements "${APP_BUNDLE}/Contents/"
fi

echo "App bundle created: ${APP_BUNDLE}"
ls -la "${APP_BUNDLE}/Contents/"

# Sign the app (ad-hoc for development)
echo "Signing app..."
codesign --force --sign - "${APP_BUNDLE}" --entitlements "DoubleTapTalk.entitlements" 2>/dev/null || \
codesign --force --sign - "${APP_BUNDLE}"

# Create temporary directory for DMG
echo "Preparing DMG..."
mkdir -p "/tmp/${APP_NAME}-temp"
cp -R "${APP_BUNDLE}" "/tmp/${APP_NAME}-temp/"

# Create DMG
echo "Creating DMG: ${DMG_NAME}..."
hdiutil create -volname "${APP_NAME}" -srcfolder "/tmp/${APP_NAME}-temp" -ov -format UDZO "${DMG_NAME}"

# Clean up temp
rm -rf "/tmp/${APP_NAME}-temp"

echo ""
echo "=== SUCCESS ==="
echo "DMG created: $(pwd)/${DMG_NAME}"
ls -lh "${DMG_NAME}"
