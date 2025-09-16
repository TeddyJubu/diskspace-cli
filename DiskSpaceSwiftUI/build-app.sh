APP_NAME="DiskSpaceSwiftUI"
APP_DIR="$HOME/Applications/$APP_NAME.app"
BUILD_DIR="$HOME/DiskSpaceSwiftUI/.build/release"
BIN="$BUILD_DIR/DiskSpaceSwiftUI"

set -e

if [ ! -x "$BIN" ]; then
  echo "Binary not found: $BIN" >&2
  exit 1
fi

# Create app bundle structure
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.teddy.$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST

# Copy binary
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "Built app: $APP_DIR"
