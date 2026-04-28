# Phase 95 — Apply defaultPermissionMode to New Sessions

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 94 complete: NotificationEngine guards on notificationsEnabled.

`AppSettings.defaultPermissionMode` is persisted and shown in General settings (Permissions
section picker) but `LiveSession.permissionMode` is hardcoded to `.ask`. New sessions always
start in Ask mode regardless of the user's preference.

---

## Edit: Merlin/Sessions/LiveSession.swift

Find the line that initializes `permissionMode`:

```swift
var permissionMode: PermissionMode = .ask {
```

Change the default value to read from `AppSettings`:

```swift
var permissionMode: PermissionMode = AppSettings.shared.defaultPermissionMode {
```

This is a stored property initializer on a `@MainActor` class. Since `AppSettings.shared`
is also `@MainActor`, the read is safe at the declaration site when the class is being
initialized on the main actor.

If the Swift compiler rejects the stored property initializer reading `AppSettings.shared`
(which can happen with strict concurrency on complex init chains), use a lazy property
or move the assignment into an explicit `init`:

```swift
    init(appState: AppState) {
        self.appState = appState
        self.permissionMode = AppSettings.shared.defaultPermissionMode
        // rest of init...
    }
```

Adjust to match the actual `LiveSession.init` signature — do not create a new initializer
if one already exists; update the existing one.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Sessions/LiveSession.swift
git commit -m "Phase 95 — LiveSession: initialize permissionMode from AppSettings.defaultPermissionMode"
```
