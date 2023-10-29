#!/usr/bin/env bash
set -euo pipefail

# build-standalone-app-native.sh - Build Homebridge.app (native Swift UI)

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

APP_NAME="Homebridge.app"
APP_BUNDLE="build/App/$APP_NAME"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

echo "=== Building Homebridge.app (Swift UI) ==="
echo ""

# Clean and create structure
rm -rf "build/App"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

# Step 1: Download and bundle Node.js (v24 series)
echo "Step 1: Downloading Node.js v24..."
NODE_VERSION=${NODE_VERSION:-$(curl -s https://nodejs.org/dist/index.json | python3 -c "import sys, json; a=json.load(sys.stdin); print(next((x['version'] for x in a if x['version'].startswith('v24')), 'v24.0.0'))" || echo "v24.0.0")}

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
	NODE_ARCH="arm64"
else
	NODE_ARCH="x64"
fi

NODE_TARBALL="node-${NODE_VERSION}-darwin-${NODE_ARCH}.tar.gz"
if [ ! -f "$NODE_TARBALL" ]; then
	curl -fSL -o "$NODE_TARBALL" "https://nodejs.org/dist/${NODE_VERSION}/${NODE_TARBALL}"
fi

echo "Extracting Node.js to app bundle..."
mkdir -p "$FRAMEWORKS/node"
tar xzf "$NODE_TARBALL" -C "$FRAMEWORKS/node" --strip-components=1

# Step 2: Compile Swift UI
echo "Step 2: Compiling native Swift UI..."
if [ ! -f "HomebridgeApp/Sources/main.swift" ]; then
	echo "Error: HomebridgeApp/Sources/main.swift not found"
	exit 1
fi

swiftc -o "$MACOS/Homebridge" \
	-framework Cocoa \
	-framework WebKit \
	-framework Security \
	HomebridgeApp/Sources/main.swift

# Step 3: Create Info.plist
echo "Step 3: Creating Info.plist..."
cat > "$CONTENTS/Info.plist" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Homebridge</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>io.homebridge.standalone</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Homebridge</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.14</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST_EOF

# Step 4: Copy official Homebridge icon
echo "Step 4: Adding app icon..."
if [ -f "assets/icons/Homebridge.icns" ]; then
	cp "assets/icons/Homebridge.icns" "$RESOURCES/AppIcon.icns"
elif [ -f "Applications/Homebridge/Homebridge.app/Contents/Resources/applet.icns" ]; then
	cp "Applications/Homebridge/Homebridge.app/Contents/Resources/applet.icns" "$RESOURCES/AppIcon.icns"
fi

# Step 5: Create PkgInfo
echo "Step 5: Creating PkgInfo..."
echo "APPL????" > "$CONTENTS/PkgInfo"

# Step 6: Create helper scripts
echo "Step 6: Creating helper scripts..."
mkdir -p "$RESOURCES/Scripts"

cat > "$RESOURCES/Scripts/install-homebridge.sh" <<'INSTALL_EOF'
#!/usr/bin/env bash
set -euo pipefail

USER_DATA_DIR="$HOME/Library/Application Support/Homebridge"
NODE_DIR="/Applications/Homebridge.app/Contents/Frameworks/node"
NODE_BIN="$NODE_DIR/bin/node"

mkdir -p "$USER_DATA_DIR"
cd "$USER_DATA_DIR"

echo '╔════════════════════════════════════════════╗'
echo '║  Installing Homebridge...                 ║'
echo '║  This will take about 1 minute            ║'
echo '╚════════════════════════════════════════════╝'
echo ''

export PATH="$NODE_DIR/bin:$PATH"

# Clean install
rm -rf node_modules package-lock.json package.json

"$NODE_DIR/bin/npm" init -y >/dev/null 2>&1 || true
"$NODE_DIR/bin/npm" install --no-fund --no-audit homebridge@latest homebridge-config-ui-x@latest

echo "$($NODE_BIN -v)" > .node-version

echo ''
echo '✅ Installation complete!'
INSTALL_EOF

chmod +x "$RESOURCES/Scripts/install-homebridge.sh"

# Refresh icon cache
touch "$APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✓ App created: $APP_BUNDLE"
echo ""
echo "To test:"
echo "  open \"$APP_BUNDLE\""
echo ""
echo "Features:"
echo "  - Native macOS UI with service control"
echo "  - Configurable UI port and Node version"
echo "  - Start/Stop service buttons"
echo "  - View logs and open data folder"
echo "  - No Terminal required for normal operation"
