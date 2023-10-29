#!/usr/bin/env bash
set -euo pipefail

# Simple local builder for the native Homebridge menubar app
# - Compiles HomebridgeApp/Sources/main.swift into a minimal .app bundle
# - Does NOT embed Node; the app will fallback to system node/npm
#
# Output: build/Homebridge.app

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_MAIN="$ROOT_DIR/HomebridgeApp/Sources/main.swift"
OUT_DIR="$ROOT_DIR/build"
APP_NAME="Homebridge"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RES_DIR="$CONTENTS_DIR/Resources"
PLIST="$CONTENTS_DIR/Info.plist"

mkdir -p "$MACOS_DIR" "$RES_DIR"

# Info.plist
cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Homebridge</string>
	<key>CFBundleIconFile</key>
	<string></string>
	<key>CFBundleIdentifier</key>
	<string>io.homebridge.macos</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Homebridge</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Compile
BIN="$MACOS_DIR/Homebridge"
echo "Compiling Swift app → $BIN"
# Prefer xcrun swiftc if available, else fallback to swiftc
if command -v xcrun >/dev/null 2>&1; then
  SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  if [ -n "$SDK" ]; then
    xcrun --sdk macosx swiftc -O -sdk "$SDK" -framework Cocoa -framework WebKit "$SRC_MAIN" -o "$BIN"
  else
    xcrun swiftc -O -framework Cocoa -framework WebKit "$SRC_MAIN" -o "$BIN"
  fi
else
  swiftc -O -framework Cocoa -framework WebKit "$SRC_MAIN" -o "$BIN"
fi

chmod +x "$BIN"

echo "\n✅ Built $APP_DIR"
echo "Tip: For packaging, you may still want a full bundle with Node embedded. This local build falls back to system node/npm."
