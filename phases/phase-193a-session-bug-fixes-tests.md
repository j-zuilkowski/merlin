# Phase 193a — Session Bug Fix Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 192b complete: KAGEngine.scheduleExtraction wired into AgenticEngine; v1.8.0.

Four UI/session bugs found after v1.8.0 shipped:
  1. Status dot stays active after engine run completes — `toolActivityState` not reset by engine
  2. New session shows old session's view — missing `.id(session.id)` forces view reuse
  3. Sessions never auto-name — new LiveSessions not registered in SessionStore so engine saves to wrong record
  4. Compact Context → 400 — force-compact with no tool exchanges leaves context unchanged

New surface introduced in phase 193b:
  - `AppState`: Combine subscriber resets `toolActivityState = .idle` when `engine.isRunning` → false
  - `WorkspaceView.sessionContent`: `.id(session.id)` on `ContentView()`
  - `LiveSession.init`: calls `appState.sessionStore?.save(Session(id: self.id, title: "New Session", messages: []))` immediately
  - `ContextManager.compact(force:)`: hard-truncate fallback when no tool-exchange groups exist

TDD coverage:
  File 1 — `MerlinTests/Unit/SessionBugFixTests.swift`:
    - `test_toolActivityState_resets_to_idle_when_isRunning_becomes_false`
    - `test_liveSession_registers_in_sessionStore_on_init`
    - `test_liveSession_id_matches_store_active_session_id`
    - `test_compact_force_truncates_non_tool_messages`

---

## Write to: MerlinTests/Unit/SessionBugFixTests.swift

```swift
import XCTest
@testable import Merlin

// Tests for the four session bugs fixed in Phase 193b.
// All tests are @MainActor because AppState, LiveSession, and ContextManager
// are @MainActor types.

@MainActor
final class SessionBugFixTests: XCTestCase {

    // MARK: - Bug 1: toolActivityState resets when engine finishes

    /// When `engine.isRunning` flips to false, `AppState.toolActivityState`
    /// must reset to `.idle` automatically — regardless of whether ChatView
    /// is still alive to close its send loop.
    func test_toolActivityState_resets_to_idle_when_isRunning_becomes_false() async throws {
        let appState = AppState()

        // Simulate the state that exists while a run is active.
        appState.toolActivityState = .streaming
        appState.engine.isRunning = true

        // Engine finishes — flip isRunning to false.
        appState.engine.isRunning = false

        // Allow Combine subscriber to propagate on RunLoop.main.
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            appState.toolActivityState, .idle,
            "toolActivityState must reset to .idle when engine.isRunning becomes false"
        )
    }

    // MARK: - Bug 2 & 3: LiveSession registers itself in SessionStore

    /// A newly created LiveSession must immediately add a Session record to
    /// the shared SessionStore so the engine can find the right session via
    /// `sessionStore.activeSession` (used by `applyTitleUpdateIfNeeded` and saving).
    func test_liveSession_registers_in_sessionStore_on_init() async {
        let storeDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-193a-\(UUID().uuidString)", isDirectory: true)
        let store = SessionStore(storeDirectory: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let ref = ProjectRef(path: "/tmp/merlin-193a-\(UUID().uuidString)",
                             displayName: "test")
        let live = LiveSession(projectRef: ref, sessionStore: store)

        // Allow any async init tasks to settle.
        await Task.yield()

        XCTAssertFalse(
            store.sessions.isEmpty,
            "LiveSession.init must register a Session record in the provided SessionStore"
        )
    }

    /// The Session record's id must match the LiveSession's own id so that
    /// `sessionStore.activeSession` returns the record for this specific LiveSession.
    func test_liveSession_id_matches_store_active_session_id() async {
        let storeDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-193a-\(UUID().uuidString)", isDirectory: true)
        let store = SessionStore(storeDirectory: storeDir)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let ref = ProjectRef(path: "/tmp/merlin-193a-\(UUID().uuidString)",
                             displayName: "test")
        let live = LiveSession(projectRef: ref, sessionStore: store)

        await Task.yield()

        XCTAssertEqual(
            store.activeSessionID, live.id,
            "SessionStore.activeSessionID must equal LiveSession.id after init"
        )
    }

    // MARK: - Bug 4: Compact context actually removes messages

    /// When force-compacting a context that has no tool-exchange groups
    /// (only user + assistant messages), `compact(force: true)` must
    /// reduce the message count — not just append a sentinel string.
    func test_compact_force_truncates_non_tool_messages() {
        let ctx = ContextManager()

        // Seed 40 user + assistant message pairs (no tool calls).
        for i in 0..<40 {
            ctx.append(Message(role: .user,
                               content: .text("User message \(i) " + String(repeating: "x", count: 500)),
                               timestamp: Date()))
            ctx.append(Message(role: .assistant,
                               content: .text("Assistant response \(i) " + String(repeating: "y", count: 500)),
                               timestamp: Date()))
        }

        let countBefore = ctx.messages.count
        XCTAssertGreaterThan(countBefore, 20, "Precondition: context must have >20 messages")

        ctx.forceCompaction()

        XCTAssertLessThan(
            ctx.messages.count, countBefore,
            "forceCompaction() must reduce message count when context has no tool-exchange groups"
        )
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — `test_toolActivityState_resets_to_idle_when_isRunning_becomes_false`
fails (no Combine subscriber exists yet), `test_liveSession_registers_in_sessionStore_on_init`
fails (LiveSession doesn't save to store on init), `test_compact_force_truncates_non_tool_messages`
fails (compact just appends a sentinel).

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SessionBugFixTests.swift \
        phases/phase-193a-session-bug-fixes-tests.md
git commit -m "Phase 193a — SessionBugFixTests (failing)"
```
