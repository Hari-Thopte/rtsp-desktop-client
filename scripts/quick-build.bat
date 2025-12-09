#!/bin/bash

BUILD_CONFIG="debug"
ARCH="x86_64"
WITH_GRPC=false

detect_platform() {
    case "$(uname -s)" in
        Darwin*)    PLATFORM="macos";;
        Linux*)     PLATFORM="linux";;
        CYGWIN*|MINGW*|MSYS*) PLATFORM="windows";;
        *)          PLATFORM="unknown"
    esac
    echo $PLATFORM
}

check_grpc() {
    echo "Checking for gRPC dependencies..."
    
    if [ "$PLATFORM" = "windows" ]; then
        if [ -d "/c/vcpkg/installed/x64-windows" ]; then
            VCPKG_ROOT="/c/vcpkg"
        elif [ -d "$VCPKG_ROOT/installed/x64-windows" ]; then
            echo "Using VCPKG_ROOT: $VCPKG_ROOT"
        else
            echo "Warning: vcpkg not found. gRPC support may be limited."
            return 1
        fi
    elif [ "$PLATFORM" = "macos" ]; then
        if brew list grpc &>/dev/null; then
            echo "gRPC found via Homebrew"
            return 0
        elif [ -d "/usr/local/grpc" ]; then
            echo "gRPC found at /usr/local/grpc"
            return 0
        fi
    elif [ "$PLATFORM" = "linux" ]; then
        if [ -f "/usr/include/grpc/grpc.h" ]; then
            echo "gRPC found in system"
            return 0
        elif [ -d "/usr/local/include/grpc" ]; then
            echo "gRPC found at /usr/local"
            return 0
        fi
    fi
    
    echo "gRPC not found. Building without gRPC support."
    return 1
}

setup_grpc() {
    if [ "$WITH_GRPC" = false ]; then
        return
    fi
    
    echo "Setting up gRPC..."
    
    if [ "$PLATFORM" = "windows" ]; then
        if [ -n "$VCPKG_ROOT" ]; then
            GRPC_INCLUDE="$VCPKG_ROOT/installed/x64-windows/include"
            GRPC_LIB="$VCPKG_ROOT/installed/x64-windows/lib"
            GRPC_BIN="$VCPKG_ROOT/installed/x64-windows/bin"
            
            export PATH="$GRPC_BIN:$PATH"
            export CPATH="$GRPC_INCLUDE:$CPATH"
            export LIBRARY_PATH="$GRPC_LIB:$LIBRARY_PATH"
        fi
        
    elif [ "$PLATFORM" = "macos" ]; then
        GRPC_INCLUDE="/usr/local/include"
        GRPC_LIB="/usr/local/lib"
        
        if brew list grpc &>/dev/null; then
            GRPC_INCLUDE="$(brew --prefix grpc)/include"
            GRPC_LIB="$(brew --prefix grpc)/lib"
        fi
        
        export CPATH="$GRPC_INCLUDE:$CPATH"
        export LIBRARY_PATH="$GRPC_LIB:$LIBRARY_PATH"
        export DYLD_LIBRARY_PATH="$GRPC_LIB:$DYLD_LIBRARY_PATH"
        
    elif [ "$PLATFORM" = "linux" ]; then
        GRPC_INCLUDE="/usr/include"
        GRPC_LIB="/usr/lib"
        
        if [ -d "/usr/local/include/grpc" ]; then
            GRPC_INCLUDE="/usr/local/include"
            GRPC_LIB="/usr/local/lib"
        fi
        
        export CPATH="$GRPC_INCLUDE:$CPATH"
        export LIBRARY_PATH="$GRPC_LIB:$LIBRARY_PATH"
        export LD_LIBRARY_PATH="$GRPC_LIB:$LD_LIBRARY_PATH"
    fi
    
    echo "gRPC include: $GRPC_INCLUDE"
    echo "gRPC lib: $GRPC_LIB"
}

install_grpc_deps() {
    if [ "$WITH_GRPC" = false ]; then
        return
    fi
    
    echo "Installing gRPC dependencies for $PLATFORM..."
    
    if [ "$PLATFORM" = "windows" ]; then
        echo "Installing gRPC via vcpkg..."
        if command -v vcpkg &> /dev/null; then
            vcpkg install grpc:x64-windows
            vcpkg install protobuf:x64-windows
            vcpkg install protobuf[zlib]:x64-windows
        else
            echo "Error: vcpkg not found. Install from https://github.com/microsoft/vcpkg"
            exit 1
        fi
        
    elif [ "$PLATFORM" = "macos" ]; then
        echo "Installing gRPC via Homebrew..."
        brew install grpc protobuf
        
    elif [ "$PLATFORM" = "linux" ]; then
        echo "Installing gRPC via package manager..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y libgrpc++-dev libprotobuf-dev protobuf-compiler-grpc
        elif command -v yum &> /dev/null; then
            sudo yum install -y grpc-devel protobuf-devel
        elif command -v pacman &> /dev/null; then
            sudo pacman -S grpc protobuf
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y grpc-devel protobuf-devel
        else
            echo "Error: Unsupported Linux package manager"
            exit 1
        fi
    fi
}

generate_grpc_code() {
    if [ "$WITH_GRPC" = false ]; then
        return
    fi
    
    echo "Generating gRPC code from proto files..."
    
    PROTO_DIR="$SOURCE_ROOT/proto"
    GEN_DIR="$SOURCE_ROOT/src/generated"
    
    if [ ! -d "$PROTO_DIR" ]; then
        echo "No proto directory found at $PROTO_DIR"
        return
    fi
    
    mkdir -p "$GEN_DIR"
    
    if command -v protoc &> /dev/null; then
        for proto_file in "$PROTO_DIR"/*.proto; do
            if [ -f "$proto_file" ]; then
                echo "Generating code for $(basename "$proto_file")..."
                
                if [ "$PLATFORM" = "windows" ]; then
                    protoc -I="$PROTO_DIR" --cpp_out="$GEN_DIR" "$proto_file"
                    protoc -I="$PROTO_DIR" --grpc_out="$GEN_DIR" --plugin=protoc-gen-grpc="$(which grpc_cpp_plugin.exe 2>/dev/null || echo grpc_cpp_plugin)" "$proto_file"
                else
                    protoc -I="$PROTO_DIR" --cpp_out="$GEN_DIR" "$proto_file"
                    protoc -I="$PROTO_DIR" --grpc_out="$GEN_DIR" --plugin=protoc-gen-grpc="$(which grpc_cpp_plugin)" "$proto_file"
                fi
            fi
        done
    else
        echo "Warning: protoc not found. Cannot generate gRPC code."
    fi
}

PLATFORM=$(detect_platform)

for arg in "$@"; do
    case $arg in
        --grpc)
            WITH_GRPC=true
            shift
            ;;
        --config=*)
            BUILD_CONFIG="${arg#*=}"
            shift
            ;;
        --arch=*)
            ARCH="${arg#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$WITH_GRPC" = true ]; then
    check_grpc
    if [ $? -ne 0 ]; then
        read -p "gRPC not found. Install it now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_grpc_deps
        else
            echo "Building without gRPC support"
            WITH_GRPC=false
        fi
    fi
fi

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

setup_grpc

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

generate_grpc_code

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

QMAKE_ARGS="$SOURCE_ROOT/moonlight-qt.pro"
if [ "$WITH_GRPC" = true ]; then
    QMAKE_ARGS="$QMAKE_ARGS CONFIG+=with_grpc"
    
    if [ "$PLATFORM" = "windows" ] && [ -n "$VCPKG_ROOT" ]; then
        QMAKE_ARGS="$QMAKE_ARGS INCLUDEPATH+=\"$VCPKG_ROOT/installed/x64-windows/include\""
        QMAKE_ARGS="$QMAKE_ARGS LIBS+=\"-L$VCPKG_ROOT/installed/x64-windows/lib\""
    fi
fi

if [ "$PLATFORM" = "windows" ]; then
    qmake $QMAKE_ARGS
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
        qmake $QMAKE_ARGS CONFIG+="$BUILD_CONFIG" CONFIG+="$ARCH"
    else
        qmake $QMAKE_ARGS CONFIG+="$BUILD_CONFIG"
    fi
    
    if [ $? -ne 0 ]; then
        echo "qmake configuration failed!"
        exit 1
    fi
    
    echo "Compiling Moonlight in $BUILD_CONFIG configuration..."
    CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")
    make -j$CORES
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
    
    if [ "$WITH_GRPC" = true ] && [ -n "$GRPC_BIN" ]; then
        echo "Copying gRPC DLLs..."
        cp "$GRPC_BIN/"*.dll "$DEPLOY_FOLDER/" 2>/dev/null || true
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
    
    if [ "$WITH_GRPC" = true ] && [ -n "$GRPC_LIB" ]; then
        echo "Copying gRPC libraries..."
        cp "$GRPC_LIB/"libgrpc*.dylib "$APP_BUNDLE/Contents/Frameworks/" 2>/dev/null || true
        cp "$GRPC_LIB/"libprotobuf*.dylib "$APP_BUNDLE/Contents/Frameworks/" 2>/dev/null || true
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
    
    if [ "$WITH_GRPC" = true ] && [ -n "$GRPC_LIB" ]; then
        echo "Copying gRPC libraries..."
        cp "$GRPC_LIB/"libgrpc++.so* "$DEPLOY_FOLDER/" 2>/dev/null || true
        cp "$GRPC_LIB/"libprotobuf.so* "$DEPLOY_FOLDER/" 2>/dev/null || true
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
echo "gRPC support: $WITH_GRPC"
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
