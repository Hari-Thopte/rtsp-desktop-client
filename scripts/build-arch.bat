#!/bin/bash

BUILD_CONFIG="$1"
ARCH="$2"

BUILD_CONFIG=$(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')

if [[ "$BUILD_CONFIG" != "debug" && "$BUILD_CONFIG" != "release" ]]; then
    echo "Invalid build configuration - expected 'release' or 'debug'"
    echo "Usage: $0 (release|debug) (arm64|x86_64|universal)"
    exit 1
fi

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" && "$ARCH" != "universal" ]]; then
    echo "Invalid build architecture - expected 'arm64', 'x86_64', or 'universal'"
    echo "Usage: $0 (release|debug) (arm64|x86_64|universal)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$SOURCE_ROOT/build"
BUILD_FOLDER="$BUILD_ROOT/build-$ARCH-$BUILD_CONFIG"
DEPLOY_FOLDER="$BUILD_ROOT/deploy-$ARCH-$BUILD_CONFIG"
APP_BUNDLE="$DEPLOY_FOLDER/Moonlight.app"

VERSION=$(cat "$SOURCE_ROOT/app/version.txt")

echo "Cleaning output directories"
rm -rf "$DEPLOY_FOLDER"
rm -rf "$BUILD_FOLDER"
mkdir -p "$BUILD_ROOT"
mkdir -p "$DEPLOY_FOLDER"
mkdir -p "$BUILD_FOLDER"

echo "Building dependencies"
cd "$SOURCE_ROOT/third-party/signaling"
if [[ "$BUILD_CONFIG" == "debug" ]]; then
    ./build-mac.sh Debug
else
    ./build-mac.sh Release
fi
cd "$SOURCE_ROOT"

echo "Copying application resources"
rm -rf "$SOURCE_ROOT/app"
mkdir -p "$SOURCE_ROOT/app"
cp -R "third-party/signaling/rtsp/header/"* "$SOURCE_ROOT/app/"
cp -R "third-party/moonlight/app/"* "$SOURCE_ROOT/app/"
cp -R "custom/"* "$SOURCE_ROOT/app/" 2>/dev/null || true

echo "Configuring the project"
cd "$BUILD_FOLDER"

QT_PATH="/usr/local/opt/qt"
export PATH="$QT_PATH/bin:$PATH"

if [[ "$ARCH" == "universal" ]]; then
    qmake "$SOURCE_ROOT/moonlight-qt.pro" CONFIG+="$BUILD_CONFIG" CONFIG+="x86_64 arm64"
else
    qmake "$SOURCE_ROOT/moonlight-qt.pro" CONFIG+="$BUILD_CONFIG" CONFIG+="$ARCH"
fi

if [ $? -ne 0 ]; then
    echo "qmake configuration failed!"
    exit 1
fi

echo "Compiling Moonlight in $BUILD_CONFIG configuration"
make -j$(sysctl -n hw.ncpu)

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo "Creating macOS application bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_FOLDER/app/$BUILD_CONFIG/Moonlight" "$APP_BUNDLE/Contents/MacOS/"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Moonlight</string>
    <key>CFBundleIdentifier</key>
    <string>com.moonlight-stream.Moonlight</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
</dict>
</plist>
EOF

echo "Deploying Qt dependencies"
if command -v macdeployqt &> /dev/null; then
    macdeployqt "$APP_BUNDLE" -verbose=2
else
    echo "Warning: macdeployqt not found. Qt dependencies may be missing."
    echo "Install with: brew install qt"
fi

echo "Copying additional libraries"
cp "$SOURCE_ROOT/third-party/moonlight/libs/macos/lib/$ARCH/"*.dylib "$APP_BUNDLE/Contents/MacOS/" 2>/dev/null || true

mkdir -p "$APP_BUNDLE/Contents/Resources/SDL_GameControllerDB"
cp "$SOURCE_ROOT/app/SDL_GameControllerDB/gamecontrollerdb.txt" "$APP_BUNDLE/Contents/Resources/"

echo "Creating DMG package"
DMG_PATH="$BUILD_ROOT/Moonlight-$VERSION-$ARCH-$BUILD_CONFIG.dmg"
hdiutil create -volname "Moonlight $VERSION" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

echo "Build completed successfully!"
echo "Application: $APP_BUNDLE"
echo "DMG: $DMG_PATH"
