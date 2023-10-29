#!/usr/bin/env bash
set -euo pipefail

# make-pkg-native.sh - Build .pkg using native macOS tools (pkgbuild/productbuild)
# This doesn't require the Packages app

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

VERSION=${VERSION:-1.0.0}
PKG_ID=${PKG_ID:-io.homebridge.server}
OUT_DIR=${OUT_DIR:-"$ROOT_DIR/build"}
SIGN_ID=${SIGN_ID:-}

mkdir -p "$OUT_DIR"

COMPONENT_PKG="$OUT_DIR/homebridge-component.pkg"
FINAL_PKG="$OUT_DIR/homebridge-${VERSION}.pkg"

echo "Building component package..."

# Build the component package from the staged files
pkgbuild \
  --root "$ROOT_DIR" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --scripts "$ROOT_DIR/scripts" \
  --install-location "/" \
  "$COMPONENT_PKG"

echo "Building product package..."

# Create a simple distribution.xml if it doesn't exist
DIST_XML="$OUT_DIR/distribution.xml"
cat > "$DIST_XML" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Homebridge</title>
    <organization>io.homebridge</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" hostArchitectures="x86_64,arm64"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="10.14"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="$PKG_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$PKG_ID" visible="false">
        <pkg-ref id="$PKG_ID"/>
    </choice>
    <pkg-ref id="$PKG_ID" version="$VERSION" onConclusion="none">homebridge-component.pkg</pkg-ref>
</installer-gui-script>
EOF

# Build the product archive
if [ -n "$SIGN_ID" ]; then
  echo "Signing package with: $SIGN_ID"
  productbuild \
    --distribution "$DIST_XML" \
    --package-path "$OUT_DIR" \
    --sign "$SIGN_ID" \
    "$FINAL_PKG"
else
  productbuild \
    --distribution "$DIST_XML" \
    --package-path "$OUT_DIR" \
    "$FINAL_PKG"
fi

# Cleanup
rm -f "$COMPONENT_PKG" "$DIST_XML"

echo "✓ Package created: $FINAL_PKG"
ls -lh "$FINAL_PKG"
