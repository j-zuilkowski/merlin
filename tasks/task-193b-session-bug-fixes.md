# Task 193b — Session Bug Fixes Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 193a complete: failing tests in `SessionBugFixTests`.

Four bugs to fix:
1. Status dot stays active after engine finishes — `toolActivityState` not reset by engine
2. New session view doesn't switch — SwiftUI reuses `ContentView` instance across sessions
3. Sessions never auto-name — new `LiveSession` not registered in `SessionStore`
4. Compact Context ineffective — force-compact with no tool-exchange groups leaves context unchanged

Version bump: 1.8.0 → 1.8.1

---

## Edit 1: Merlin/App/AppState.swift

### Add Combine subscriber to reset `toolActivityState` when engine finishes

In `AppState.init`, find the line where `engine` is assigned:
```swift
engine = AgenticEngine(
    slotAssignments: AppSettings.shared.slotAssignments,
    ...
)
```

Immediately after that block (before `engine.currentProjectPath = ...`), add:

```swift
// Reset toolActivityState whenever the engine stops running so the sidebar
// dot clears even if ChatView was torn down before its send loop completed.
engine.$isRunning
    .filter { !$0 }
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        guard let self, self.toolActivityState != .idle else { return }
        self.toolActivityState = .idle
    }
    .store(in: &cancellables)
```

`cancellables` is already declared as `private var cancellables: Set<AnyCancellable> = []`
(or similar). If it doesn't exist yet, add the declaration alongside the other private stored
properties near the top of the class:

```swift
private var cancellables: Set<AnyCancellable> = []
```

No other changes to this file. Make sure `import Combine` is at the top (it likely already is).

---

## Edit 2: Merlin/Views/WorkspaceView.swift

### Force view recreation when the active session changes

In `sessionContent(session:)`, find:

```swift
ContentView()
    .environmentObject(session.skillsRegistry)
    .environmentObject(session.appState)
    .environmentObject(session.appState.registry)
```

Add `.id(session.id)` immediately after `ContentView()`:

```swift
ContentView()
    .id(session.id)
    .environmentObject(session.skillsRegistry)
    .environmentObject(session.appState)
    .environmentObject(session.appState.registry)
```

This forces SwiftUI to fully recreate the view tree (resetting all `@State`) whenever the
active session changes. Without it, SwiftUI reuses the same `ContentView` instance and only
updates the EnvironmentObjects, leaving `@State` (message list, scroll position, input field)
stale from the previous session.

No other changes to this file.

---

## Edit 3: Merlin/Sessions/LiveSession.swift

### Register the new session in SessionStore immediately on init

In `LiveSession.init`, find the block that injects the shared session store:

```swift
// Replace per-AppState store with the shared project-level store if provided.
if let sessionStore {
    appState.sessionStore = sessionStore
    appState.engine.sessionStore = sessionStore
}
```

Add the registration immediately after the store is wired up:

```swift
// Replace per-AppState store with the shared project-level store if provided.
if let sessionStore {
    appState.sessionStore = sessionStore
    appState.engine.sessionStore = sessionStore
}

// Register this LiveSession as an active record in the store so the engine's
// session-save and title-generation paths (which use sessionStore.activeSession)
// operate on the correct session from the first turn onward.
let initialRecord = Session(id: self.id, title: "New Session", messages: [])
try? appState.sessionStore?.save(initialRecord)
```

`SessionStore.save(_:)` sets `activeSessionID = session.id` internally, so after this call
`sessionStore.activeSession` will return the record for this LiveSession.

No other changes to this file.

---

## Edit 4: Merlin/Engine/ContextManager.swift

### Hard-truncate fallback when no tool-exchange groups exist

Find the section in `compact(force:)` starting at:

```swift
if groupsToRemove.isEmpty && force {
    let toolIndices = messages.indices.filter { messages[$0].role == .tool }
    if toolIndices.isEmpty {
        messages.append(Message(
            role: .system,
            content: .text("[context compacted]"),
            timestamp: Date()
        ))
    } else {
        let removeCount = max(1, toolIndices.count / 2)
        let indicesToRemove = Set(toolIndices.prefix(removeCount))
        let summary = Message(
            role: .system,
            content: .text("[context compacted — \(removeCount) standalone tool message(s) removed]"),
            timestamp: Date()
        )
        messages = messages.enumerated()
            .filter { !indicesToRemove.contains($0.offset) }
            .map { $0.element }
        messages.insert(summary, at: 0)
    }
}
```

Replace the entire `if groupsToRemove.isEmpty && force { ... }` block with:

```swift
if groupsToRemove.isEmpty && force {
    // No tool-exchange groups to remove. Hard-truncate to the most recent
    // `compactionKeepRecentTurns` messages so the context actually shrinks
    // even when it consists entirely of user/assistant text (no tool calls).
    // Without this, the old code just appended a sentinel string and left
    // the full context intact — causing HTTP 400s on the next LLM request.
    let kept = Array(messages.suffix(compactionKeepRecentTurns))
    let summary = Message(
        role: .system,
        content: .text("[context compacted — history truncated to last \(kept.count) messages]"),
        timestamp: Date()
    )
    messages = [summary] + kept
}
```

No other changes to this file.

---

## Edit 5: project.yml — version bump 1.8.0 → 1.8.1

```diff
-    MARKETING_VERSION: "1.8.0"
+    MARKETING_VERSION: "1.8.1"
```

`CURRENT_PROJECT_VERSION`: increment by 1 (8 → 9).

After editing `project.yml`:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin

# 193a tests pass
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGNING_ALLOWED=NO \
    -only-testing:MerlinTests/SessionBugFixTests 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20

# Full suite still green
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Zero warnings
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:' | head -20
```

Expected: all 4 `SessionBugFixTests` pass, full suite green, zero warnings.

---

## Commit, tag, push

```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/AppState.swift \
        Merlin/Views/WorkspaceView.swift \
        Merlin/Sessions/LiveSession.swift \
        Merlin/Engine/ContextManager.swift \
        project.yml \
        tasks/task-193a-session-bug-fixes-tests.md \
        tasks/task-193b-session-bug-fixes.md
git commit -m "Task 193b — Fix session dot, view isolation, auto-naming, compact context; v1.8.1"
git tag v1.8.1
git push origin main --tags
gh release create v1.8.1 \
    --repo j-zuilkowski/merlin \
    --title "v1.8.1 — Session bug fixes" \
    --notes "Four session fixes:
- Status dot clears when engine finishes (Combine subscriber ties toolActivityState to engine.isRunning)
- New session view resets correctly (.id(session.id) forces ContentView recreation)
- Sessions auto-name from first message (LiveSession registers itself in SessionStore on init)
- Compact Context actually reduces message count (hard-truncate fallback when no tool exchanges)" \
    --latest
```
