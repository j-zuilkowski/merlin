# Phase — Package Merlin as DMG

## Context
macOS non-sandboxed app. Bundle ID: `com.merlin.app`. Product name: `Merlin`.
No third-party packages. No tests. No sequence number — run this phase on demand
whenever a distributable build is needed.

This phase produces a drag-to-install `.dmg` at:
```
~/Documents/localProject/merlin/dist/Merlin-<version>.dmg
```

---

## Prerequisites

- Xcode installed and `xcodebuild` on PATH
- `create-dmg` installed (`brew install create-dmg`)
- App builds cleanly (`xcodebuild` exits 0)
- No signing is required for personal local-only distribution — ad-hoc signing is used

---

## Script: `scripts/package-dmg.sh`

Create this file (make it executable):

```bash
#!/bin/bash
# package-dmg.sh — build Merlin.app and wrap it in a DMG for distribution
# Usage: bash scripts/package-dmg.sh [version]
# Example: bash scripts/package-dmg.sh 1.0.0

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

if ! command -v create-dmg &>/dev/null; then
    echo "✗ create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

rm -f "$DMG_PATH"

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

rm -rf "$STAGING_DIR"

echo ""
echo "✓ DMG created: $DMG_PATH"
echo "  Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
echo "── Done ─────────────────────────────────────────────────"
```

---

## Run

```bash
cd ~/Documents/localProject/merlin
chmod +x scripts/package-dmg.sh

# With an explicit version string:
bash scripts/package-dmg.sh 1.0.0

# Without a version (uses today's date, e.g. Merlin-20260427.dmg):
bash scripts/package-dmg.sh
```

---

## Output

```
dist/
└── Merlin-1.0.0.dmg    ← drag-to-install disk image
```

The DMG contains `Merlin.app` and an `/Applications` symlink — standard drag-install layout.

---

## Notes

- **Ad-hoc signing** (`CODE_SIGN_IDENTITY="-"`) is used. macOS will show a Gatekeeper
  warning on first launch on another machine — right-click → Open to bypass. For personal
  use on the same machine this warning does not appear.
- **No notarization.** This is a personal non-distributed tool. If notarization is ever
  needed, add an Apple Developer account, enable hardened runtime, and use
  `xcrun notarytool submit` after the DMG step.
- **Version string** is stamped into `Info.plist` at package time so the running app
  reports the correct version in About > Merlin. The project's source `Info.plist` can
  keep `$(MARKETING_VERSION)` as a placeholder.
- `dist/` and `build/` are already in `.gitignore` (or should be) — DMG files are not
  committed to the repository.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add scripts/package-dmg.sh phases/phase-package-dmg.md
git commit -m "Add DMG packaging script (scripts/package-dmg.sh)"
```
