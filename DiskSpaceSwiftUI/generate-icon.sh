#!/bin/bash

# Script to generate AppIcon.icns from AppIcons directory
# This ensures the app uses the proper icon from the AppIcons assets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPICONS_DIR="$SCRIPT_DIR/AppIcons/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="$SCRIPT_DIR/AppIcon.iconset"
ICNS_FILE="$SCRIPT_DIR/AppIcon.icns"

echo "🎨 Generating AppIcon.icns from AppIcons directory..."

# Check if AppIcons directory exists
if [ ! -d "$APPICONS_DIR" ]; then
  echo "❌ Error: AppIcons directory not found at $APPICONS_DIR"
  exit 1
fi

# Clean up any existing iconset
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

echo "📋 Copying icons with proper naming for ICNS generation..."

# Copy icons with the correct naming convention for macOS ICNS
cp "$APPICONS_DIR/16.png" "$ICONSET_DIR/icon_16x16.png"
cp "$APPICONS_DIR/32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$APPICONS_DIR/32.png" "$ICONSET_DIR/icon_32x32.png"
cp "$APPICONS_DIR/64.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$APPICONS_DIR/128.png" "$ICONSET_DIR/icon_128x128.png"
cp "$APPICONS_DIR/256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$APPICONS_DIR/256.png" "$ICONSET_DIR/icon_256x256.png"
cp "$APPICONS_DIR/512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$APPICONS_DIR/512.png" "$ICONSET_DIR/icon_512x512.png"
cp "$APPICONS_DIR/1024.png" "$ICONSET_DIR/icon_512x512@2x.png"

echo "🔧 Generating ICNS file..."

# Generate the ICNS file
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"

# Clean up the temporary iconset directory
rm -rf "$ICONSET_DIR"

# Verify the ICNS file was created
if [ -f "$ICNS_FILE" ]; then
  SIZE=$(stat -f%z "$ICNS_FILE")
  # Format size in human readable format (macOS compatible)
  if [ $SIZE -gt 1048576 ]; then
    SIZE_STR="$(echo "scale=1; $SIZE/1048576" | bc)MB"
  elif [ $SIZE -gt 1024 ]; then
    SIZE_STR="$(echo "scale=1; $SIZE/1024" | bc)KB"
  else
    SIZE_STR="${SIZE}B"
  fi
  echo "✅ Successfully generated AppIcon.icns ($SIZE_STR)"
  echo "📁 Location: $ICNS_FILE"
  
  # Touch the ICNS file to update modification time
  touch "$ICNS_FILE"
  
  echo "💡 Run './build-app.sh' to rebuild the app with the new icon"
else
  echo "❌ Error: Failed to generate AppIcon.icns"
  exit 1
fi

echo "🎉 Icon generation complete!"