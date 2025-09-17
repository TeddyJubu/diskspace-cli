#!/bin/bash

# Script to clear macOS icon caches and refresh app icons
# Use this when the app icon doesn't update after rebuilding

set -e

echo "🗑️  Clearing macOS icon caches..."

# Step 1: Reset Launch Services database
echo "1. Resetting Launch Services database..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user

# Step 2: Clear icon service caches
echo "2. Clearing icon service caches..."
sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null || true

# Step 3: Clear dock icon cache
echo "3. Clearing dock icon cache..."
rm -rf ~/Library/Caches/com.apple.dock.iconcache 2>/dev/null || true

# Step 4: Touch app bundle to update modification time
echo "4. Updating app bundle modification time..."
APP_PATH="/Users/teddyburtonburger/Applications/DiskSpaceSwiftUI.app"
if [ -d "$APP_PATH" ]; then
    touch "$APP_PATH"
    touch "$APP_PATH/Contents/Info.plist"
    touch "$APP_PATH/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    echo "   ✓ Updated: $APP_PATH"
else
    echo "   ⚠️  App not found at: $APP_PATH"
    echo "   💡 Build the app first with: ./build-app.sh"
fi

# Step 5: Re-register the app
echo "5. Re-registering app with system..."
if [ -d "$APP_PATH" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
    echo "   ✓ App registered"
fi

# Step 6: Restart Dock and Finder
echo "6. Restarting Dock and Finder..."
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo ""
echo "✅ Icon cache cleared successfully!"
echo ""
echo "🔄 Dock and Finder are restarting..."
echo "⏳ Wait a few seconds, then check your Dock and Applications folder"
echo ""
echo "💡 If the icon still doesn't appear:"
echo "   1. Try logging out and back in"
echo "   2. Or restart your Mac"
echo "   3. Make sure the app has Full Disk Access permissions"

# Optional: Open the app after clearing cache
read -p "🚀 Open the app now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sleep 3  # Wait for Dock to restart
    if [ -d "$APP_PATH" ]; then
        open "$APP_PATH"
        echo "✓ App launched"
    fi
fi