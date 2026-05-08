# Phase 187 — Version Bump to v1.6.0

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 186b complete: multi-project sidebar, project header popover, picker sheet.

No new tests. Bumps marketing version to 1.6.0 (build 5), regenerates project, confirms
clean build, commits, and tags.

---

## Edit: project.yml

**Find:**
```yaml
MARKETING_VERSION: "1.5.0"
```
**Replace with:**
```yaml
MARKETING_VERSION: "1.6.0"
```

**Find:**
```yaml
CURRENT_PROJECT_VERSION: 4
```
**Replace with:**
```yaml
CURRENT_PROJECT_VERSION: 5
```

---

## Edit: CLAUDE.md

**Find:**
```
**Current version: 1.5.0** (build 4, tag `v1.5.0`)
```
**Replace with:**
```
**Current version: 1.6.0** (build 5, tag `v1.6.0`)
```

---

## Regenerate Xcode project

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED, zero errors.

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    /tmp/merlin-derived/Build/Products/Debug/Merlin.app/Contents/Info.plist
```
Expected: `1.6.0`

---

## Commit and tag

```bash
cd ~/Documents/localProject/merlin
git add project.yml CLAUDE.md Merlin.xcodeproj/project.pbxproj
git commit -m "Bump version to 1.6.0 (build 5)"
git tag v1.6.0
```

Do NOT push until DMG is built and verified.

---

## Build release DMG

```bash
xcodebuild -scheme Merlin -configuration Release \
    -derivedDataPath /tmp/merlin-release \
    -destination 'platform=macOS' build 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10

hdiutil create -volname "Merlin 1.6.0" \
    -srcfolder /tmp/merlin-release/Build/Products/Release/Merlin.app \
    -ov -format UDZO \
    ~/Documents/localProject/merlin/dist/Merlin-2026-05-08-v1.6.0.dmg

echo "DMG size: $(du -sh ~/Documents/localProject/merlin/dist/Merlin-2026-05-08-v1.6.0.dmg)"
```

After DMG verified:
```bash
cd ~/Documents/localProject/merlin
git push && git push --tags
```
