# Phase 195a — ChatViewModel Persistence Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 194b complete: session dot and auto-title fixes shipped in v1.8.2.

**Bug — Session messages disappear on session switch**

Root cause: `ChatViewModel` is declared as `@StateObject private var model = ChatViewModel()`
inside `ChatView`. The `.id(session.id)` fix (phase 193b) correctly forces SwiftUI to tear
down and recreate `ContentView` on every session switch. This also destroys the `ChatViewModel`,
clearing all `items`. The engine's `contextManager.messages` retains the conversation, but
`ChatView` never reads from it on reappear — it only populates `items` by consuming live
streaming events. Switching back to a completed session creates a fresh empty `ChatViewModel`
and shows a blank chat.

Fix (phase 195b):
- `LiveSession` owns `chatViewModel: ChatViewModel` — persists for the session's lifetime
- `WorkspaceView.sessionContent(session:)` injects it as `.environmentObject(session.chatViewModel)`
- `ChatView` changes `@StateObject private var model = ChatViewModel()` →
  `@EnvironmentObject private var model: ChatViewModel`
- `ChatViewModel` is `public` within the module — no structural changes needed

New surface introduced in phase 195b:
  - `LiveSession.chatViewModel: ChatViewModel` — session-scoped, not view-scoped

TDD coverage:
  File — ChatViewModelPersistenceTests.swift: 3 tests

---

## Write to: MerlinTests/Unit/ChatViewModelPersistenceTests.swift

```swift
// ChatViewModelPersistenceTests.swift
// Phase 195a — failing tests for ChatViewModel persistence across session switches.
//
// Before 195b: ChatViewModel is a @StateObject inside ChatView — destroyed on every
//   .id(session.id) teardown, clearing all chat items.
// After 195b: LiveSession owns chatViewModel; ChatView receives it via @EnvironmentObject.
import XCTest
@testable import Merlin

@MainActor
final class ChatViewModelPersistenceTests: XCTestCase {

    /// LiveSession must own a ChatViewModel so it survives view teardowns.
    /// FAILS TO COMPILE before 195b — `chatViewModel` does not exist on LiveSession.
    func test_liveSession_owns_chatViewModel() {
        let ref = ProjectRef(path: "/tmp/195a-own-\(UUID().uuidString)", displayName: "test")
        let session = LiveSession(projectRef: ref)
        XCTAssertNotNil(session.chatViewModel)
    }

    /// The ChatViewModel instance is the same object across two accesses — it is
    /// not recreated on each access.
    /// FAILS TO COMPILE before 195b.
    func test_liveSession_chatViewModel_is_stable_identity() {
        let ref = ProjectRef(path: "/tmp/195a-stable-\(UUID().uuidString)", displayName: "test")
        let session = LiveSession(projectRef: ref)
        let first = session.chatViewModel
        let second = session.chatViewModel
        XCTAssertTrue(first === second, "chatViewModel must be the same instance on repeated access")
    }

    /// Items appended to the ChatViewModel survive beyond the scope of a single
    /// view presentation — the model is owned by the session, not the view.
    /// FAILS TO COMPILE before 195b.
    func test_chatViewModel_items_survive_simulated_view_teardown() {
        let ref = ProjectRef(path: "/tmp/195a-items-\(UUID().uuidString)", displayName: "test")
        let session = LiveSession(projectRef: ref)

        // Simulate the view appending a user message during a turn.
        let entry = ChatEntry(role: .user, text: "show project directory")
        session.chatViewModel.items.append(entry)

        // Simulate the view being torn down and recreated (session switch and back).
        // Since chatViewModel lives on LiveSession, items must still be present.
        XCTAssertEqual(session.chatViewModel.items.count, 1)
        XCTAssertEqual(session.chatViewModel.items.first?.text, "show project directory")
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: **BUILD FAILED** — `chatViewModel` does not exist on `LiveSession`.

## Commit
```bash
git add MerlinTests/Unit/ChatViewModelPersistenceTests.swift
git commit -m "Phase 195a — ChatViewModelPersistenceTests (failing)"
```
