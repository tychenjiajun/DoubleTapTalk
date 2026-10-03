#!/bin/bash
# DoubleTapTalk Installation Script

set -e

APP_NAME="DoubleTapTalk"
BUNDLE_ID="com.jiajun.doubletaptalk"
BUILD_PATH="build/DerivedData/Build/Products/Release/${APP_NAME}.app"
INSTALLED="/Applications/${APP_NAME}.app"
SIGN_IDENTITY="DoubleTapTalk Local Signing"
ENTITLEMENTS="DoubleTapTalk.entitlements"

echo "=== ${APP_NAME} Installer ==="
echo ""

# A stable signing identity is what keeps the Accessibility/Microphone grants
# alive across rebuilds. Ad-hoc signing silently invalidates them every time.
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "Signing identity missing — creating it..."
    "$(dirname "$0")/scripts/setup-signing-identity.sh"
fi

echo "Building app..."
xcodegen generate > /dev/null 2>&1
xcodebuild -project ${APP_NAME}.xcodeproj -scheme ${APP_NAME} -configuration Release \
    -derivedDataPath build/DerivedData build > /dev/null 2>&1
echo "✓ Build complete"
echo ""

if [ ! -d "$BUILD_PATH" ]; then
    echo "Build not found at $BUILD_PATH"
    exit 1
fi

# Re-sign with the stable identity: xcodebuild's own signature must be replaced
# so the Designated Requirement is the certificate, not the build's cdhash.
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$BUILD_PATH" >/dev/null
codesign --verify --strict "$BUILD_PATH"

# Stop every running copy — including stale ones launched straight out of
# DerivedData, which is what silently ends up handling (or dropping) hotkeys.
echo "Stopping running instances..."
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
sleep 1

echo "Installing to $INSTALLED..."
rm -rf "$INSTALLED"
cp -R "$BUILD_PATH" "$INSTALLED"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$INSTALLED" >/dev/null
codesign --verify --strict "$INSTALLED"
echo "✓ Installed and signed with: $SIGN_IDENTITY"
echo "  DR: $(codesign -d -r- "$INSTALLED" 2>&1 | grep designated | sed 's/^# //')"
echo ""

echo "Launching $INSTALLED..."
open "$INSTALLED"

echo ""
echo "=== Next Steps ==="
echo "Grant these once (they now survive rebuilds):"
echo "  System Settings > Privacy & Security > Accessibility  — add ${APP_NAME}"
echo "  System Settings > Privacy & Security > Microphone     — enable ${APP_NAME}"
echo ""
echo "If the toggle is already ON but the app still reports no permission, the"
echo "entry is stale. Run: tccutil reset Accessibility ${BUNDLE_ID}"
echo "then relaunch and re-add the app."
echo ""
echo "Usage: Double-tap Control key to start/stop recording"