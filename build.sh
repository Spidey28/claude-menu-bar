#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claude Monitor"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "Building Claude Monitor..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Compile Swift
swiftc "$SCRIPT_DIR/ClaudeUsage.swift" \
    -o "$APP_BUNDLE/Contents/MacOS/ClaudeMonitor" \
    -framework Cocoa \
    -O \
    -swift-version 6 \
    2>&1

echo "Build complete: $APP_BUNDLE"
echo ""
echo "To run:  open '$APP_BUNDLE'"
echo "To auto-start: Add to System Settings > General > Login Items"
