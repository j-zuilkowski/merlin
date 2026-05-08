# Phase 184 — Version Bump to v1.5.0

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 183b complete: SessionSidebar Prior Sessions + archive/recall + timestamps.

This phase has no new tests. It bumps the marketing version to 1.5.0 (build 4),
regenerates the Xcode project, confirms a clean build, and tags the release.

---

## Edit: project.yml

**Find:**
```yaml
MARKETING_VERSION: 1.2.0
```
**Replace with:**
```yaml
MARKETING_VERSION: 1.5.0
```

**Find:**
```yaml
CURRENT_PROJECT_VERSION: 3
```
**Replace with:**
```yaml
CURRENT_PROJECT_VERSION: 4
```

---

## Edit: CLAUDE.md

**Find:**
```
**Current version: 1.2.0** (build 3, tag `v1.2.0`)
```
**Replace with:**
```
**Current version: 1.5.0** (build 4, tag `v1.5.0`)
```

---

## Regenerate Xcode project

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify clean build

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED, zero errors.

Confirm version string in built app:
```bash
xcodebuild -scheme Merlin build \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    /tmp/merlin-derived/Build/Products/Debug/Merlin.app/Contents/Info.plist
```
Expected output: `1.5.0`

---

## Commit and tag

```bash
cd ~/Documents/localProject/merlin
git add project.yml CLAUDE.md Merlin.xcodeproj/project.pbxproj
git commit -m "Bump version to 1.5.0 (build 4)"
git tag v1.5.0
```

Do NOT push the tag until the DMG is built and verified.

---

## Build release DMG (optional — run when ready to distribute)

```bash
xcodebuild -scheme Merlin -configuration Release \
    -derivedDataPath /tmp/merlin-release \
    -destination 'platform=macOS' build 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10

hdiutil create -volname "Merlin 1.5.0" \
    -srcfolder /tmp/merlin-release/Build/Products/Release/Merlin.app \
    -ov -format UDZO \
    ~/Documents/localProject/merlin/dist/Merlin-2026-05-08.dmg

echo "DMG size: $(du -sh ~/Documents/localProject/merlin/dist/Merlin-2026-05-08.dmg)"
```

After DMG verified:
```bash
cd ~/Documents/localProject/merlin
git push && git push --tags
```
