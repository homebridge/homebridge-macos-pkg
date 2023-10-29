#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script must be run on macOS (Darwin)." >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
APP1_SRC="$ROOT_DIR/Applications/Homebridge/Homebridge.app"
APP2_SRC="$ROOT_DIR/Applications/Homebridge/Uninstall Homebridge.app"

VOL_NAME=${VOL_NAME:-Homebridge}
OUT_DIR=${OUT_DIR:-"$ROOT_DIR/build"}
VERSION=${VERSION:-}
DMG_NAME=${DMG_NAME:-homebridge${VERSION:+-$VERSION}.dmg}
SIGN_ID=${SIGN_ID:-}

DMG_STAGING="$OUT_DIR/dmg-root"

mkdir -p "$OUT_DIR"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy apps into staging
if [ ! -d "$APP1_SRC" ]; then
  echo "Missing app bundle: $APP1_SRC" >&2
  exit 1
fi
cp -R "$APP1_SRC" "$DMG_STAGING/"

if [ -d "$APP2_SRC" ]; then
  cp -R "$APP2_SRC" "$DMG_STAGING/" || true
fi

# Create Applications symlink in DMG root
( cd "$DMG_STAGING" && ln -s /Applications Applications ) || true

# Add README to DMG
cat > "$DMG_STAGING/READ ME FIRST.txt" <<'EOF'
HOMEBRIDGE FOR macOS
====================

IMPORTANT: This DMG contains launcher apps only.

To install Homebridge, you need to run the installer package (.pkg) first, which:
- Installs Node.js runtime
- Sets up Homebridge service
- Configures automatic startup

INSTALLATION STEPS:
1. Download and run homebridge.pkg (the installer package)
2. After installation, use the Homebridge.app to open the web interface
3. The service will start automatically and run at http://localhost:8581

WHAT'S IN THIS DMG:
- Homebridge.app: Opens the web interface (requires service to be running)
- Uninstall Homebridge.app: Removes the Homebridge service

For more information, visit: https://homebridge.io
EOF

# Optional codesign of app bundles
if [ -n "$SIGN_ID" ]; then
  echo "Codesigning app bundles with: $SIGN_ID"
  for APP in "$DMG_STAGING"/*.app; do
    [ -e "$APP" ] || continue
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  done
fi

TMP_DMG="$OUT_DIR/tmp.dmg"
FINAL_DMG="$OUT_DIR/$DMG_NAME"

rm -f "$TMP_DMG" "$FINAL_DMG"

echo "Creating temporary DMG..."
hdiutil create -volname "$VOL_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$TMP_DMG" >/dev/null

echo "Converting to compressed DMG..."
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
rm -f "$TMP_DMG"

echo "DMG created: $FINAL_DMG"
