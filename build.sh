#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claude Monitor"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BUILD_DMG=false

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --dmg) BUILD_DMG=true ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

echo "Building Claude Monitor..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# --- Generate app icon ---
echo "Generating app icon..."
ICON_PNG="$SCRIPT_DIR/build_icon.png"
ICONSET="$SCRIPT_DIR/AppIcon.iconset"

# Compile and run icon generator
swiftc "$SCRIPT_DIR/icon_gen.swift" -o "$SCRIPT_DIR/icon_gen_tool" \
    -framework Cocoa -O -swift-version 6 2>&1
"$SCRIPT_DIR/icon_gen_tool" "$ICON_PNG"
rm -f "$SCRIPT_DIR/icon_gen_tool"

# Create iconset with required sizes
mkdir -p "$ICONSET"
sips -z 16 16     "$ICON_PNG" --out "$ICONSET/icon_16x16.png"      > /dev/null 2>&1
sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"   > /dev/null 2>&1
sips -z 32 32     "$ICON_PNG" --out "$ICONSET/icon_32x32.png"      > /dev/null 2>&1
sips -z 64 64     "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"   > /dev/null 2>&1
sips -z 128 128   "$ICON_PNG" --out "$ICONSET/icon_128x128.png"    > /dev/null 2>&1
sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "$ICON_PNG" --out "$ICONSET/icon_256x256.png"    > /dev/null 2>&1
sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "$ICON_PNG" --out "$ICONSET/icon_512x512.png"    > /dev/null 2>&1
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1

iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$ICON_PNG"
echo "App icon generated."

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Compile Swift
swiftc "$SCRIPT_DIR/ClaudeUsage.swift" \
    -o "$APP_BUNDLE/Contents/MacOS/ClaudeMonitor" \
    -framework Cocoa \
    -framework ServiceManagement \
    -O \
    -swift-version 6 \
    2>&1

# Ad-hoc code sign
echo "Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1
echo "Code signing complete."

echo ""
echo "Build complete: $APP_BUNDLE"
echo ""
echo "To run:  open '$APP_BUNDLE'"

# --- Optionally create DMG ---
if [ "$BUILD_DMG" = true ]; then
    echo ""
    echo "Creating DMG..."

    DMG_NAME="Claude Monitor"
    DMG_PATH="$SCRIPT_DIR/$DMG_NAME.dmg"
    DMG_TEMP="$SCRIPT_DIR/dmg_temp"

    rm -rf "$DMG_TEMP" "$DMG_PATH"
    mkdir -p "$DMG_TEMP"

    cp -R "$APP_BUNDLE" "$DMG_TEMP/"

    # Create a symbolic link to /Applications for drag-to-install
    ln -s /Applications "$DMG_TEMP/Applications"

    hdiutil create \
        -volname "$DMG_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov \
        -format UDZO \
        "$DMG_PATH" \
        > /dev/null 2>&1

    rm -rf "$DMG_TEMP"

    echo "DMG created: $DMG_PATH"
fi
