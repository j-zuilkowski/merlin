# Phase 196a — Restore Dedup & History Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 195b complete: ChatViewModel owned by LiveSession (v1.8.3).

Two bugs remain:

**Bug A — Clicking a prior session creates duplicate live sessions**
Root cause: `SessionManager.restore()` always creates a new `LiveSession` with a fresh
UUID. `SessionSidebar` filters the Prior Sessions list by `liveIDs = Set(mgr.liveSessions.map(\.id))`.
Restored live sessions have new UUIDs — the original record's UUID is never in `liveIDs` —
so the same prior session keeps appearing in the list and can be restored multiple times.

Fix: Add `var originalSessionID: UUID?` to `LiveSession`. Set it to `session.id` in
`SessionManager.restore()`. `SessionSidebar` checks `mgr.liveSessions.first(where: { $0.originalSessionID == session.id })` before calling restore — if a live session for that record already exists, just switch to it.

**Bug B — Restored sessions show no message history**
Root cause: `restore()` injects `session.messages` into `engine.contextManager`, but
`chatViewModel.items` (what `ChatView` renders) is an independent view-layer list populated
only from live streaming events. A freshly created `ChatViewModel` always starts empty.

Fix: Add `func load(from messages: [Message])` to `ChatViewModel` that converts stored
`Message` records to `ChatEntry` display items. Call it from `LiveSession.init` when
`initialMessages` is non-empty, so the view is populated immediately on restore.

New surface in phase 196b:
  - `LiveSession.originalSessionID: UUID?`
  - `SessionManager.restore()` sets `live.originalSessionID = session.id`
  - `ChatViewModel.load(from: [Message])` — converts stored messages to display entries
  - `MessageContent` extension `var plainText: String` for content extraction
  - `LiveSession.init` calls `chatViewModel.load(from: initialMessages)` when non-empty
  - `SessionSidebar` PriorSessionRow tap checks for existing live session before restoring

TDD coverage:
  File — RestoreDedupAndHistoryTests.swift: 4 tests

---

## Write to: MerlinTests/Unit/RestoreDedupAndHistoryTests.swift

```swift
// RestoreDedupAndHistoryTests.swift
// Phase 196a — failing tests for prior-session restore deduplication and history display.
import XCTest
@testable import Merlin

@MainActor
final class RestoreDedupAndHistoryTests: XCTestCase {

    // MARK: - Bug A: duplicate restore

    /// LiveSession must carry the UUID of the store record it was restored from
    /// so the sidebar can detect it's already live.
    /// FAILS TO COMPILE before 196b — `originalSessionID` does not exist on LiveSession.
    func test_liveSession_has_originalSessionID_property() {
        let ref = ProjectRef(path: "/tmp/196a-orig-\(UUID().uuidString)", displayName: "t")
        let session = LiveSession(projectRef: ref)
        // Freshly-created sessions have no original (they were never restored).
        XCTAssertNil(session.originalSessionID)
    }

    /// SessionManager.restore() must set originalSessionID to the source record's id.
    /// FAILS TO COMPILE before 196b.
    func test_restore_sets_originalSessionID() async throws {
        let ref = ProjectRef(path: "/tmp/196a-restore-\(UUID().uuidString)", displayName: "t")
        let mgr = SessionManager(projectRef: ref)
        let stored = Session(id: UUID(), title: "Work", messages: [])
        try mgr.sessionStore.save(stored)

        let live = await mgr.restore(session: stored)
        XCTAssertEqual(live.originalSessionID, stored.id,
            "originalSessionID must equal the source Session's id")
    }

    // MARK: - Bug B: history not shown

    /// ChatViewModel.load(from:) must exist and populate items from stored messages.
    /// FAILS TO COMPILE before 196b — `load(from:)` does not exist on ChatViewModel.
    func test_chatViewModel_load_populates_user_message() {
        let vm = ChatViewModel()
        let messages = [
            Message(role: .user,
                    content: .text("show project directory"),
                    timestamp: Date())
        ]
        vm.load(from: messages)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.role, .user)
        XCTAssertEqual(vm.items.first?.text, "show project directory")
    }

    /// When LiveSession is restored with initial messages, chatViewModel.items must
    /// be populated so the history is visible immediately.
    /// FAILS TO COMPILE / FAILS AT RUNTIME before 196b.
    func test_restored_liveSession_chatViewModel_has_items() {
        let ref = ProjectRef(path: "/tmp/196a-items-\(UUID().uuidString)", displayName: "t")
        let messages = [
            Message(role: .user,
                    content: .text("list files"),
                    timestamp: Date()),
            Message(role: .assistant,
                    content: .text("Here are the files: ..."),
                    timestamp: Date())
        ]
        let session = LiveSession(projectRef: ref, initialMessages: messages)
        XCTAssertEqual(session.chatViewModel.items.count, 2,
            "chatViewModel must be pre-populated from initialMessages on restore")
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -15
```
Expected: **BUILD FAILED** — `originalSessionID` and `load(from:)` do not exist.

## Commit
```bash
git add MerlinTests/Unit/RestoreDedupAndHistoryTests.swift
git commit -m "Phase 196a — RestoreDedupAndHistoryTests (failing)"
```
