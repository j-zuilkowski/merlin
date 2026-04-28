# Phase 84 — FloatingWindowManager: Menu Item + Keyboard Shortcut

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 83 complete: voice dictation button in ChatView.

`FloatingWindowManager.shared` exists but nothing opens it. Add a "Pop Out Session"
menu item and keyboard shortcut (⌘⇧P) to `MerlinCommands`. The command opens the
currently focused session in a floating NSWindow via `FloatingWindowManager`.

---

## Edit: Merlin/App/MerlinCommands.swift

Read the current `MerlinCommands.swift` file first. Add a `CommandMenu("Window")` block
(or insert into an existing window menu) with:

```swift
CommandMenu("Window") {
    Button("Pop Out Session") {
        guard let session = focusedSession else { return }
        let s = Session(id: session.id, title: session.title, createdAt: session.createdAt)
        FloatingWindowManager.shared.open(session: s, alwaysOnTop: true)
    }
    .keyboardShortcut("p", modifiers: [.command, .shift])
    .disabled(focusedSession == nil)
}
```

Where `focusedSession` is the `@FocusedObject var appState: AppState?` already used in
`MerlinCommands`. Construct a lightweight `Session` from the session manager's active session.

If `MerlinCommands` doesn't currently expose a reference to the active `LiveSession`, add:

```swift
    @FocusedObject private var sessionManager: SessionManager?
```

and use `sessionManager?.activeSession` to get the current `LiveSession`, then construct:

```swift
    let s = Session(
        id: activeSession.id,
        title: activeSession.title,
        createdAt: activeSession.createdAt
    )
    FloatingWindowManager.shared.open(session: s, alwaysOnTop: true)
```

Check `Session.swift` for its init signature and use the correct parameter labels.

---

## Edit: Merlin/Views/WorkspaceView.swift

Add `SessionManager` as a focused object so it's available to commands. In the existing
`.focusedObject(appState)` chain (inside `ContentView` or the workspace body), also add:

```swift
.focusedObject(sessionManager)
```

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
git add Merlin/App/MerlinCommands.swift \
        Merlin/Views/WorkspaceView.swift
git commit -m "Phase 84 — FloatingWindowManager: Pop Out Session command (⌘⇧P) in MerlinCommands"
```
