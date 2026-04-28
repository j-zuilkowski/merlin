#!/bin/bash
# package-dmg.sh — build Merlin.app and wrap it in a DMG for distribution
# Usage: bash scripts/package-dmg.sh [version]
# Example: bash scripts/package-dmg.sh 4.0

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Merlin"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build/Release"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Merlin"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

VERSION="${1:-$(date +%Y%m%d)}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$DIST_DIR/.dmg-staging"
TMP_DMG="$DIST_DIR/.tmp-${APP_NAME}.dmg"

echo "── Merlin DMG Packager ──────────────────────────────────"
echo "  Version:  $VERSION"
echo "  App:      $APP_PATH"
echo "  Output:   $DMG_PATH"
echo ""

# ── 1. Build ─────────────────────────────────────────────────

echo "→ Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$PROJECT_DIR/build/DerivedData" \
    SYMROOT="$PROJECT_DIR/build" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES \
    ENABLE_HARDENED_RUNTIME=NO \
    2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED'

if [ ! -d "$APP_PATH" ]; then
    echo "✗ Build failed — $APP_PATH not found."
    exit 1
fi
echo "✓ Build succeeded: $APP_PATH"

# ── 2. Stamp version into Info.plist ─────────────────────────

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $VERSION" \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
echo "✓ Version stamped: $VERSION"

# ── 3. Prepare dist dir ──────────────────────────────────────

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"

# ── 4. Create DMG ────────────────────────────────────────────

rm -f "$DMG_PATH"

if command -v create-dmg &>/dev/null; then
    ln -s /Applications "$STAGING_DIR/Applications"
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 540 380 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 140 185 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 400 185 \
        "$DMG_PATH" \
        "$STAGING_DIR"
else
    ln -s /Applications "$STAGING_DIR/Applications"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "$TMP_DMG"
    mv "$TMP_DMG" "$DMG_PATH"
fi

rm -rf "$STAGING_DIR"

echo ""
echo "✓ DMG created: $DMG_PATH"
echo "  Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
echo "── Done ─────────────────────────────────────────────────"
