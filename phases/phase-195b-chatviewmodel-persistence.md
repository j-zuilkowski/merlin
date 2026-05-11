# Phase 195b — ChatViewModel Persistence Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 195a complete: failing tests in place.

Three targeted edits. No new types. No API changes.

---

## Edit 1: Merlin/Sessions/LiveSession.swift

Add `chatViewModel` as a stored property. `ChatViewModel` is defined in `ChatView.swift`
and is accessible across the module (not `private`).

After the `let skillsRegistry: SkillsRegistry` line, add:

```swift
    let chatViewModel = ChatViewModel()
```

Full property block context for placement:

```swift
    let id: UUID
    @Published var title: String
    let appState: AppState
    let skillsRegistry: SkillsRegistry
    let chatViewModel = ChatViewModel()          // ← add this line
    private let mcpBridge = MCPBridge()
```

---

## Edit 2: Merlin/Views/WorkspaceView.swift

Inject `session.chatViewModel` into the environment alongside the other session objects.

In `sessionContent(session:)`, find:
```swift
                ContentView()
                    .id(session.id)
                    .environmentObject(session.skillsRegistry)
                    .environmentObject(session.appState)
```

Replace with:
```swift
                ContentView()
                    .id(session.id)
                    .environmentObject(session.skillsRegistry)
                    .environmentObject(session.appState)
                    .environmentObject(session.chatViewModel)
```

---

## Edit 3: Merlin/Views/ChatView.swift

Change `model` from a view-owned `@StateObject` to an environment-provided `@EnvironmentObject`.

Find (near the top of `struct ChatView: View`):
```swift
    @StateObject private var model = ChatViewModel()
```

Replace with:
```swift
    @EnvironmentObject private var model: ChatViewModel
```

No other changes to `ChatView` — all existing `model.` call sites remain valid.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test-without-building \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    -only-testing:MerlinTests/ChatViewModelPersistenceTests 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: all 3 phase-195a tests pass.

Then full build + zero warnings:
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: **TEST BUILD SUCCEEDED**, zero warnings.

## Commit

```bash
git add Merlin/Sessions/LiveSession.swift \
        Merlin/Views/WorkspaceView.swift \
        Merlin/Views/ChatView.swift
git commit -m "Phase 195b — Own ChatViewModel on LiveSession so messages survive session switches"
```
