#!/bin/bash

BUILD_CONFIG="debug"
ARCH="x86_64"

detect_platform() {
    case "$(uname -s)" in
        Darwin*)    PLATFORM="macos";;
        Linux*)     PLATFORM="linux";;
        CYGWIN*|MINGW*|MSYS*) PLATFORM="windows";;
        *)          PLATFORM="unknown"
    esac
    echo $PLATFORM
}

PLATFORM=$(detect_platform)

if [ "$PLATFORM" = "unknown" ]; then
    echo "Error: Unsupported platform"
    exit 1
fi

if [ "$PLATFORM" = "windows" ]; then
    PROJECT_PATH="Z:/oneplay-private/rtsp-desktop-client"
else
    PROJECT_PATH="$HOME/oneplay-private/rtsp-desktop-client"
fi

if [ ! -d "$PROJECT_PATH" ]; then
    echo "Error: Project directory not found at $PROJECT_PATH"
    exit 1
fi

cd "$PROJECT_PATH" || {
    echo "Error: Cannot navigate to project directory"
    exit 1
}

echo "Setting up app directory..."
if [ "$PLATFORM" = "windows" ]; then
    rmdir /Q /S .\app 2>/dev/null
    mkdir app
else
    rm -rf ./app
    mkdir -p app
fi

echo "Copying resources..."
if [ "$PLATFORM" = "windows" ]; then
    xcopy "third-party/signaling/rtsp/header" "app" /E /H /C /I /Y
    xcopy "third-party/moonlight/app" "app" /E /H /C /I /Y
    xcopy "custom" "app" /E /H /C /I /Y
else
    cp -R "third-party/signaling/rtsp/header/"* "app/" 2>/dev/null
    cp -R "third-party/moonlight/app/"* "app/" 2>/dev/null
    cp -R "custom/"* "app/" 2>/dev/null || true
fi

SOURCE_ROOT="$PWD"
BUILD_ROOT="$SOURCE_ROOT/build"
BUILD_FOLDER="$BUILD_ROOT/build-$ARCH-$BUILD_CONFIG"
DEPLOY_FOLDER="$BUILD_ROOT/deploy-$ARCH-$BUILD_CONFIG"
INSTALLER_FOLDER="$BUILD_ROOT/installer-$ARCH-$BUILD_CONFIG"
SYMBOLS_FOLDER="$BUILD_ROOT/symbols-$ARCH-$BUILD_CONFIG"

if [ -f "$SOURCE_ROOT/app/version.txt" ]; then
    VERSION=$(cat "$SOURCE_ROOT/app/version.txt")
else
    VERSION="1.0.0"
fi

echo "Cleaning output directories..."
if [ "$PLATFORM" = "windows" ]; then
    rmdir /s /q "$DEPLOY_FOLDER" 2>/dev/null
    rmdir /s /q "$BUILD_FOLDER" 2>/dev/null
    rmdir /s /q "$INSTALLER_FOLDER" 2>/dev/null
    rmdir /s /q "$SYMBOLS_FOLDER" 2>/dev/null
else
    rm -rf "$DEPLOY_FOLDER"
    rm -rf "$BUILD_FOLDER"
    rm -rf "$INSTALLER_FOLDER"
    rm -rf "$SYMBOLS_FOLDER"
fi

mkdir -p "$BUILD_ROOT"
mkdir -p "$DEPLOY_FOLDER"
mkdir -p "$BUILD_FOLDER"
mkdir -p "$INSTALLER_FOLDER"
mkdir -p "$SYMBOLS_FOLDER"

echo "Configuring the project..."
pushd "$BUILD_FOLDER" > /dev/null

if [ "$PLATFORM" = "windows" ]; then
    qmake "$SOURCE_ROOT/moonlight-qt.pro"
    if [ $? -ne 0 ]; then
        echo "qmake configuration failed!"
        exit 1
    fi
    
    echo "Compiling Moonlight in $BUILD_CONFIG configuration..."
    "$SOURCE_ROOT/scripts/jom.exe" $BUILD_CONFIG
    if [ $? -ne 0 ]; then
        echo "Build failed!"
        exit 1
    fi
    
    echo "Saving PDBs..."
    find "$BUILD_FOLDER" -name "*.pdb" -exec cp {} "$SYMBOLS_FOLDER/" \;
    if [ -d "$SOURCE_ROOT/third-party/moonlight/libs/windows/lib/$ARCH" ]; then
        cp "$SOURCE_ROOT/third-party/moonlight/libs/windows/lib/$ARCH/"*.pdb "$SYMBOLS_FOLDER/" 2>/dev/null || true
    fi
    
    if command -v 7z &> /dev/null; then
        7z a "$SYMBOLS_FOLDER/MoonlightDebuggingSymbols-$ARCH-$VERSION.zip" "$SYMBOLS_FOLDER/"*.pdb
    fi
    
else
    if [ "$PLATFORM" = "macos" ]; then
        QT_PATH="/usr/local/opt/qt"
        if [ -d "$QT_PATH" ]; then
            export PATH="$QT_PATH/bin:$PATH"
        else
            QT_PATH=$(brew --prefix qt 2>/dev/null || echo "")
            if [ -n "$QT_PATH" ]; then
                export PATH="$QT_PATH/bin:$PATH"
            else
                echo "Warning: Qt not found"
            fi
        fi
        qmake "$SOURCE_ROOT/moonlight-qt.pro" CONFIG+="$BUILD_CONFIG" CONFIG+="$ARCH"
    else
        qmake "$SOURCE_ROOT/moonlight-qt.pro" CONFIG+="$BUILD_CONFIG"
    fi
    
    if [ $? -ne 0 ]; then
        echo "qmake configuration failed!"
        exit 1
    fi
    
    echo "Compiling Moonlight in $BUILD_CONFIG configuration..."
    make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")
    if [ $? -ne 0 ]; then
        echo "Build failed!"
        exit 1
    fi
    
    if [ "$PLATFORM" = "macos" ]; then
        find "$BUILD_FOLDER" -name "*.dSYM" -exec cp -R {} "$SYMBOLS_FOLDER/" \; 2>/dev/null || true
    fi
fi

popd > /dev/null

if [ "$PLATFORM" = "windows" ]; then
    echo "Copying DLL dependencies..."
    if [ -d "$SOURCE_ROOT/third-party/moonlight/libs/windows/lib/$ARCH" ]; then
        cp "$SOURCE_ROOT/third-party/moonlight/libs/windows/lib/$ARCH/"*.dll "$DEPLOY_FOLDER/" 2>/dev/null || true
    fi
    
    echo "Deploying Qt dependencies..."
    if command -v windeployqt.exe &> /dev/null; then
        windeployqt.exe --dir "$DEPLOY_FOLDER" --$BUILD_CONFIG --qmldir "$SOURCE_ROOT/app/gui" --no-opengl-sw --no-compiler-runtime --no-qmltooling --no-virtualkeyboard --no-sql "$BUILD_FOLDER/app/$BUILD_CONFIG/Moonlight.exe"
    fi
    
    echo "Copying application binary..."
    if [ -f "$BUILD_FOLDER/app/$BUILD_CONFIG/Moonlight.exe" ]; then
        cp "$BUILD_FOLDER/app/$BUILD_CONFIG/Moonlight.exe" "$DEPLOY_FOLDER/"
    fi
    
elif [ "$PLATFORM" = "macos" ]; then
    echo "Creating macOS application bundle..."
    APP_BUNDLE="$DEPLOY_FOLDER/Moonlight.app"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    
    BINARY_NAME="Moonlight"
    if [ -f "$BUILD_FOLDER/app/$BUILD_CONFIG/$BINARY_NAME" ]; then
        cp "$BUILD_FOLDER/app/$BUILD_CONFIG/$BINARY_NAME" "$APP_BUNDLE/Contents/MacOS/"
    fi
    
    cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BINARY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.moonlight-stream.Moonlight</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
    
    if command -v macdeployqt &> /dev/null; then
        macdeployqt "$APP_BUNDLE" -verbose=2
    fi
    
    if [ -d "$SOURCE_ROOT/third-party/moonlight/libs/macos/lib/$ARCH" ]; then
        cp "$SOURCE_ROOT/third-party/moonlight/libs/macos/lib/$ARCH/"*.dylib "$APP_BUNDLE/Contents/MacOS/" 2>/dev/null || true
    fi
    
    echo "Creating DMG package..."
    DMG_PATH="$BUILD_ROOT/Moonlight-$VERSION-$ARCH-$BUILD_CONFIG.dmg"
    if command -v hdiutil &> /dev/null; then
        hdiutil create -volname "Moonlight $VERSION" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"
    fi
    
else
    echo "Creating Linux deployment..."
    if [ -f "$BUILD_FOLDER/app/$BUILD_CONFIG/Moonlight" ]; then
        cp "$BUILD_FOLDER/app/$BUILD_CONFIG/Moonlight" "$DEPLOY_FOLDER/"
    fi
    
    if [ -d "$SOURCE_ROOT/third-party/moonlight/libs/linux/lib/$ARCH" ]; then
        cp "$SOURCE_ROOT/third-party/moonlight/libs/linux/lib/$ARCH/"*.so "$DEPLOY_FOLDER/" 2>/dev/null || true
    fi
fi

if [ -f "$SOURCE_ROOT/app/SDL_GameControllerDB/gamecontrollerdb.txt" ]; then
    if [ "$PLATFORM" = "macos" ]; then
        mkdir -p "$APP_BUNDLE/Contents/Resources/SDL_GameControllerDB"
        cp "$SOURCE_ROOT/app/SDL_GameControllerDB/gamecontrollerdb.txt" "$APP_BUNDLE/Contents/Resources/"
    else
        cp "$SOURCE_ROOT/app/SDL_GameControllerDB/gamecontrollerdb.txt" "$DEPLOY_FOLDER/"
    fi
fi

echo "Build completed successfully on $PLATFORM!"
if [ "$PLATFORM" = "windows" ]; then
    echo "Deployment folder: $DEPLOY_FOLDER"
elif [ "$PLATFORM" = "macos" ]; then
    echo "Application bundle: $APP_BUNDLE"
    if [ -f "$DMG_PATH" ]; then
        echo "DMG package: $DMG_PATH"
    fi
else
    echo "Deployment folder: $DEPLOY_FOLDER"
fi
