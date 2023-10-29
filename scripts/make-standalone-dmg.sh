#!/usr/bin/env bash
set -euo pipefail

# make-standalone-dmg.sh - Create DMG with self-contained Homebridge.app

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script must be run on macOS (Darwin)." >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
STANDALONE_APP="$ROOT_DIR/build/Standalone/Homebridge.app"

VOL_NAME=${VOL_NAME:-Homebridge}
OUT_DIR=${OUT_DIR:-"$ROOT_DIR/build"}
VERSION=${VERSION:-2.0.0}
DMG_NAME=${DMG_NAME:-homebridge-standalone-${VERSION}.dmg}
SIGN_ID=${SIGN_ID:-}

DMG_STAGING="$OUT_DIR/dmg-standalone-root"

mkdir -p "$OUT_DIR"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Check if standalone app exists
if [ ! -d "$STANDALONE_APP" ]; then
  echo "Building standalone app first..."
  bash "$ROOT_DIR/build-standalone-app.sh"
fi

# Copy app into staging
cp -R "$STANDALONE_APP" "$DMG_STAGING/"

# Create Applications symlink in DMG root
( cd "$DMG_STAGING" && ln -s /Applications Applications ) || true

# Add README to DMG
cat > "$DMG_STAGING/README.txt" <<'EOF'
HOMEBRIDGE FOR macOS - Standalone Edition
==========================================

INSTALLATION:
Simply drag Homebridge.app to your Applications folder (or anywhere you like).

FIRST LAUNCH:
1. Double-click Homebridge.app
2. On first run, it will install Homebridge and dependencies (takes ~1 minute)
3. The web interface will open automatically at http://localhost:8581

FEATURES:
✓ No system installation required
✓ No sudo/admin privileges needed  
✓ Stores data in ~/Library/Application Support/Homebridge
✓ Works on latest macOS (including Sequoia and newer)

NOTES:
- The app bundles its own Node.js runtime
- All data is stored in your user folder
- To uninstall: delete the app and ~/Library/Application Support/Homebridge

For more information, visit: https://homebridge.io
EOF

# Optional codesign of app bundle
if [ -n "$SIGN_ID" ]; then
  echo "Codesigning app bundle with: $SIGN_ID"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$DMG_STAGING/Homebridge.app"
fi

TMP_DMG="$OUT_DIR/tmp-standalone.dmg"
FINAL_DMG="$OUT_DIR/$DMG_NAME"

rm -f "$TMP_DMG" "$FINAL_DMG"

echo "Creating temporary DMG..."
hdiutil create -volname "$VOL_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$TMP_DMG" >/dev/null

echo "Converting to compressed DMG..."
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
rm -f "$TMP_DMG"

echo "✓ Standalone DMG created: $FINAL_DMG"
ls -lh "$FINAL_DMG"
