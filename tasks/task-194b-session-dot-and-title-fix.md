# Phase 194b — Session Dot & Title Fix Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 194a complete: failing tests in place.

Two root causes fixed in this phase:

**Bug A — Activity dot never clears for non-active sessions**
Fix: `LiveSessionRow` gains `@ObservedObject var appState: AppState` with a custom
`init(session:isActive:)` that extracts `session.appState`. SwiftUI will then subscribe
to `appState.objectWillChange` and redraw the row whenever `toolActivityState` changes.

**Bug B — Sessions never get auto-named**
Fix (three-part):
1. `AgenticEngine` gets `var sessionID: UUID?`. The turn-end save block reads the session
   record by `sessionID` directly instead of via `sessionStore.activeSession`.
2. `SessionManager.newSession()` and `restore()` set `engine.sessionID = session.id`
   immediately after creating the `LiveSession`.
3. `SessionStore.save(_:)` no longer writes `activeSessionID = session.id`. That pointer
   is now only moved by deliberate UI actions (`create()`, `delete()`).

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Add `sessionID` property

After the `onTitleUpdate` property (around line 80), add:

```swift
    /// The UUID of the session record this engine saves into.
    /// Set by SessionManager immediately after creating the LiveSession.
    /// Used to look up the correct store record at turn-end, independent of
    /// SessionStore.activeSessionID which may be clobbered by concurrent saves.
    var sessionID: UUID?
```

### 2. Replace `sessionStore.activeSession` lookup at turn-end

Find this block (around line 1052):
```swift
        if contextOverride == nil, let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            applyTitleUpdateIfNeeded(to: &updated)
            try? sessionStore?.save(updated)
        }
```

Replace with:
```swift
        if contextOverride == nil,
           let id = sessionID,
           let store = sessionStore,
           let session = store.sessions.first(where: { $0.id == id }) {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            applyTitleUpdateIfNeeded(to: &updated)
            try? store.save(updated)
        }
```

---

## Edit: Merlin/Sessions/SessionManager.swift

### Set `engine.sessionID` in `newSession()` and `restore()`

`newSession()` — after `liveSessions.append(session)`:
```swift
    @discardableResult
    func newSession(mode: PermissionMode = AppSettings.shared.defaultPermissionMode) async -> LiveSession {
        let session = LiveSession(projectRef: projectRef, sessionStore: sessionStore)
        session.permissionMode = mode
        session.appState.engine.sessionID = session.id   // ← add this line
        liveSessions.append(session)
        activeSessionID = session.id
        return session
    }
```

`restore()` — after `liveSessions.append(live)`:
```swift
    @discardableResult
    func restore(session: Session) async -> LiveSession {
        let live = LiveSession(
            projectRef: projectRef,
            initialMessages: session.messages,
            sessionStore: sessionStore
        )
        live.title = session.title
        live.appState.engine.sessionID = live.id   // ← add this line
        liveSessions.append(live)
        activeSessionID = live.id
        return live
    }
```

---

## Edit: Merlin/Sessions/SessionStore.swift

### Remove `activeSessionID = session.id` from `save(_:)`

Find in `save(_:)` (around line 87):
```swift
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        activeSessionID = session.id    // ← DELETE this line
```

After the edit `save(_:)` ends at the telemetry block with no `activeSessionID` mutation.
`activeSessionID` is now only written by:
- `create()` (new session from store) — keeps existing behaviour
- `delete(_:)` (cleanup when the active session is removed) — keeps existing behaviour
- External callers that set it explicitly (e.g. `SessionStore.activeSessionID = s1.id` in tests)

---

## Edit: Merlin/Views/SessionSidebar.swift

### Make `LiveSessionRow` observe `appState` directly

Replace the entire `LiveSessionRow` struct:

```swift
private struct LiveSessionRow: View {
    @ObservedObject var session: LiveSession
    @ObservedObject var appState: AppState
    let isActive: Bool

    init(session: LiveSession, isActive: Bool) {
        self.session = session
        self.appState = session.appState
        self.isActive = isActive
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    PermissionModeBadge(mode: session.permissionMode)
                    if appState.toolActivityState != .idle {
                        Circle()
                            .fill(.purple)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
```

The call site in `ProjectSection` already passes `session` and `isActive` — no change needed there:
```swift
LiveSessionRow(session: session,
               isActive: session.id == coordinator.activeSession?.id)
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, all 4 task-194a tests pass:
- `test_agenticEngine_has_sessionID_property` ✓
- `test_newSession_sets_engine_sessionID` ✓
- `test_restore_sets_engine_sessionID` ✓
- `test_sessionStore_save_does_not_clobber_activeSessionID` ✓

Also verify zero warnings:
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep 'warning:' | grep -v '^$' | head -20
```

## Commit

```bash
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Sessions/SessionManager.swift \
        Merlin/Sessions/SessionStore.swift \
        Merlin/Views/SessionSidebar.swift
git commit -m "Phase 194b — Fix session dot (observe appState directly) and auto-title (sessionID lookup)"
```

## Incidental Fixes

- `Merlin/Views/Chat/ConversationWebView.swift`: renamed the `WKNavigationDelegate`
  parameter from `action` to `navigationAction` in
  `webView(_:decidePolicyFor:decisionHandler:)` so the method exactly matches the
  protocol requirement selector and removes the "nearly matches optional requirement"
  warning.
- `Merlin/Views/ChatView.swift`: changed detached-file-search call from
  `findFiles(...)` to `Self.findFiles(...)` and made `findFiles` a `static` helper.
  This removes the main-actor isolation warning caused by calling an actor-isolated
  instance method from a detached task.
