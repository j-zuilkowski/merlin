# Phase 189 — Crash Fix: ChatView EnvironmentObject + Version Bump to v1.6.1

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 188 complete: v1.6.0 (build 5) released.

**Crash in v1.6.0:** `EXC_BREAKPOINT` / `EnvironmentObject.error()` in `ChatView.currentMode`
(ChatView.swift:104) on first session activation. `ChatView` declared
`@EnvironmentObject private var sessionManager: SessionManager` — a hard trap if the object
is absent. After the v1.6 `WorkspaceCoordinator` refactor, `SessionManager` was no longer
injected as an `@EnvironmentObject`. Fix: change to `@FocusedObject` (optional, nil-safe)
and expose the active `SessionManager` via `.focusedObject()` in `WorkspaceView`.

The code changes are documented as a `## Fixes` addendum in
`phases/phase-186b-multiproject-ui.md`. This phase covers only the version bump and tag.

No new tests — the crash manifested at runtime, not at compile time. The fix is verified
by confirming the app launches and activates sessions without trapping.

---

## Edit: project.yml

**Find:** `MARKETING_VERSION: "1.6.0"`
**Replace:** `MARKETING_VERSION: "1.6.1"`

**Find:** `CURRENT_PROJECT_VERSION: 5`
**Replace:** `CURRENT_PROJECT_VERSION: 6`

---

## Edit: CLAUDE.md

**Find:** `**Current version: 1.6.0** (build 5, tag \`v1.6.0\`)`
**Replace:** `**Current version: 1.6.1** (build 6, tag \`v1.6.1\`)`

---

## Regenerate Xcode project
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
xcodebuild -scheme Merlin -configuration Release \
    -derivedDataPath /tmp/merlin-release \
    -destination 'platform=macOS' build 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10

/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    /tmp/merlin-release/Build/Products/Release/Merlin.app/Contents/Info.plist
```
Expected: BUILD SUCCEEDED; version string `1.6.1`.

---

## Commit and tag
```bash
cd ~/Documents/localProject/merlin
git add project.yml CLAUDE.md
git commit -m "Bump version to 1.6.1 (build 6) — patch fix for ChatView crash"
git tag v1.6.1
```

---

## Build release DMG
```bash
xcodebuild -scheme Merlin -configuration Release \
    -derivedDataPath /tmp/merlin-release \
    -destination 'platform=macOS' build 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10

hdiutil create -volname "Merlin 1.6.1" \
    -srcfolder /tmp/merlin-release/Build/Products/Release/Merlin.app \
    -ov -format UDZO \
    ~/Documents/localProject/merlin/dist/Merlin-2026-05-08-v1.6.1.dmg

echo "DMG: $(du -sh ~/Documents/localProject/merlin/dist/Merlin-2026-05-08-v1.6.1.dmg)"
```

Install:
```bash
pkill -x Merlin 2>/dev/null; sleep 1
hdiutil attach ~/Documents/localProject/merlin/dist/Merlin-2026-05-08-v1.6.1.dmg -nobrowse -quiet
cp -R "/Volumes/Merlin 1.6.1/Merlin.app" /Applications/
hdiutil detach "/Volumes/Merlin 1.6.1" -quiet
open /Applications/Merlin.app
```
