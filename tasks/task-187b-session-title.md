# Task 187b — Session Title Auto-Labeling Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 187a complete: SessionTitleTests committed (failing).

Sessions start with title "New Session". After the first turn completes, the title is
auto-generated from the first user message (first 50 chars), matching Claude app and
Codex behavior. The live sidebar label updates immediately via a callback.

---

## Edit: Merlin/Engine/AgenticEngine.swift

**Step 1** — Add `onTitleUpdate` property near `onUsageUpdate`:

**Find:**
```swift
    var onUsageUpdate: ((Int) -> Void)?
```
**Replace with:**
```swift
    var onUsageUpdate: ((Int) -> Void)?
    var onTitleUpdate: ((String) -> Void)?
```

**Step 2** — Add `applyTitleUpdateIfNeeded(to:)` method. Add after the `onUsageUpdate`
property (or any convenient location near the top of the class, before the first func):

**Find:**
```swift
    var onUsageUpdate: ((Int) -> Void)?
    var onTitleUpdate: ((String) -> Void)?
```
**Replace with:**
```swift
    var onUsageUpdate: ((Int) -> Void)?
    var onTitleUpdate: ((String) -> Void)?

    /// Checks whether the session still has the default title and, if so,
    /// generates one from the first user message and fires `onTitleUpdate`.
    /// Mutates `session.title` in place so the caller can persist it.
    func applyTitleUpdateIfNeeded(to session: inout Session) {
        guard session.title == "New Session" || session.title.isEmpty else { return }
        let generated = Session.generateTitle(from: session.messages)
        guard generated != "New Session" else { return }
        session.title = generated
        onTitleUpdate?(generated)
    }
```

**Step 3** — Call `applyTitleUpdateIfNeeded` inside the existing save block.

**Find:**
```swift
        if contextOverride == nil, let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            try? sessionStore?.save(updated)
        }
```
**Replace with:**
```swift
        if contextOverride == nil, let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            applyTitleUpdateIfNeeded(to: &updated)
            try? sessionStore?.save(updated)
        }
```

---

## Edit: Merlin/Sessions/LiveSession.swift

Wire `onTitleUpdate` so the sidebar label updates when the engine generates a title.

**Find** (inside `init`, after the `onUsageUpdate` closure block):
```swift
        appState.engine.onUsageUpdate = { [weak appState] tokens in
            Task { @MainActor in
                appState?.updateContextUsage(tokens)
            }
        }
```
**Replace with:**
```swift
        appState.engine.onUsageUpdate = { [weak appState] tokens in
            Task { @MainActor in
                appState?.updateContextUsage(tokens)
            }
        }
        appState.engine.onTitleUpdate = { [weak self] newTitle in
            Task { @MainActor in
                self?.title = newTitle
            }
        }
```

---

## Edit: TestHelpers/EngineFactory.swift

Add `make(sessionStore:)` overload if it does not already exist.

**Find the existing `make()` method** and add an overload immediately after it:

```swift
    static func make(sessionStore: SessionStore) -> AgenticEngine {
        let engine = make()
        engine.sessionStore = sessionStore
        return engine
    }
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SessionTitle.*passed|SessionTitle.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; all SessionTitleTests pass.

## Manual verification
```bash
pkill -x Merlin 2>/dev/null; sleep 1
open ~/Documents/localProject/merlin/build/Debug/Merlin.app
```
1. Open a project and start a new session (shows "New Session" in sidebar).
2. Type any message and send it.
3. After the response completes, the sidebar label should update to the first ~50 chars
   of your message — no manual rename needed.
4. Send more messages — label does not change again (set on first turn only).
5. Prior Sessions in sidebar should also display the auto-generated title after a session
   is closed and re-listed.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-187b-session-title.md \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Sessions/LiveSession.swift \
        TestHelpers/EngineFactory.swift
git commit -m "Task 187b — Session title auto-labeling from first user message"
```
