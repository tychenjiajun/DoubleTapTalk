#!/bin/bash
# DoubleTapTalk Installation Script

set -e

APP_NAME="DoubleTapTalk"
BUILD_PATH="build/DerivedData/Build/Products/Release/${APP_NAME}.app"

echo "=== ${APP_NAME} Installer ==="
echo ""

# Check if build exists
if [ ! -d "$BUILD_PATH" ]; then
    echo "Build not found at $BUILD_PATH"
    echo "Please build first:"
    echo "  xcodegen generate"
    echo "  xcodebuild -project ${APP_NAME}.xcodeproj -scheme ${APP_NAME} -configuration Release -derivedDataPath build/DerivedData build"
    exit 1
fi

echo "Building app..."
xcodegen generate > /dev/null 2>&1
xcodebuild -project ${APP_NAME}.xcodeproj -scheme ${APP_NAME} -configuration Release -derivedDataPath build/DerivedData build > /dev/null 2>&1
echo "✓ Build complete"
echo ""

echo "Installing to /Applications..."
sudo cp -R "$BUILD_PATH" /Applications/
echo "✓ Installed successfully"
echo ""

echo "=== Next Steps ==="
echo "1. Grant Accessibility permission for hotkey detection:"
echo "   System Settings > Privacy & Security > Accessibility > Add ${APP_NAME}"
echo ""
echo "2. Grant Microphone permission for recording:"
echo "   System Settings > Privacy & Security > Microphone > Enable ${APP_NAME}"
echo ""
echo "3. Launch ${APP_NAME} from /Applications"
echo ""
echo "Usage: Double-tap Control key to start/stop recording"
