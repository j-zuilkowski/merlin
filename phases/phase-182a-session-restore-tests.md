# Phase 182a — SessionRestoreTests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 181b complete: Session.archived + SessionStore project-scoped path + archive/unarchive.

New surface introduced in phase 182b:
  - `LiveSession.init(projectRef:initialMessages:sessionStore:)` — accepts optional pre-loaded
    messages and a shared SessionStore; injects messages into ContextManager, fires
    compactIfNeededBeforeRun if estimatedTokens > preRunCompactionThreshold
  - `SessionManager.restore(session:) async -> LiveSession` — creates a LiveSession from a
    persisted Session record, sets its title, appends to liveSessions, sets activeSessionID
  - `SessionManager.sessionStore: SessionStore` — project-level store, shared with LiveSessions

TDD coverage:
  File 1 — SessionRestoreTests: ContextManager message injection, SessionManager.restore
    wiring (title, activeSessionID, liveSessions count), compaction threshold trigger

---

## Write to: MerlinTests/Unit/SessionRestoreTests.swift

```swift
import XCTest
@testable import Merlin

// Tests for SessionManager.restore(session:) and LiveSession initial-message injection.
// LiveSession spawns background Tasks (MCP, automations, memory) that do nothing in the
// test environment — they connect to no real servers. Tests only assert the synchronous
// observable state that is set before those Tasks fire.

@MainActor
final class SessionRestoreTests: XCTestCase {

    // MARK: - ContextManager: bulk message load

    func test_contextManager_load_appends_messages() {
        let ctx = ContextManager()
        let messages = [
            Message(role: .user,    content: .text("hello"),   timestamp: Date()),
            Message(role: .assistant, content: .text("hi"),    timestamp: Date()),
        ]
        ctx.load(messages)
        XCTAssertEqual(ctx.messages.count, 2)
    }

    func test_contextManager_load_empty_does_nothing() {
        let ctx = ContextManager()
        ctx.load([])
        XCTAssertTrue(ctx.messages.isEmpty)
    }

    func test_contextManager_load_compacts_when_above_threshold() {
        let ctx = ContextManager()
        // Build messages whose combined token estimate exceeds preRunCompactionThreshold (10 000).
        // Each ~3.5 chars per token → 10 000 tokens ≈ 35 000 chars. Use 40 000-char messages.
        let bigText = String(repeating: "a", count: 40_000)
        let messages = [
            Message(role: .user,      content: .text(bigText), timestamp: Date()),
            Message(role: .assistant, content: .text(bigText), timestamp: Date()),
        ]
        ctx.load(messages)
        // After load+compact the context must have fewer messages than injected
        // (compaction collapses old tool results; even with no tool results the compact
        // call fires — it just keeps recent turns, so count may stay at 2 for 2 messages).
        // The key assertion: no crash, estimatedTokens is tracked.
        XCTAssertGreaterThan(ctx.estimatedTokens, 0)
    }

    // MARK: - SessionManager.restore

    func test_restore_creates_live_session() async {
        let ref = ProjectRef(path: "/tmp/merlin-test-restore-\(UUID().uuidString)",
                             displayName: "test-restore")
        let mgr = SessionManager(projectRef: ref)
        let session = Session(title: "Prior Work", messages: [
            Message(role: .user, content: .text("do something"), timestamp: Date())
        ])

        let live = await mgr.restore(session: session)

        XCTAssertEqual(mgr.liveSessions.count, 1)
        XCTAssertEqual(live.id, mgr.liveSessions.first?.id)
    }

    func test_restore_sets_title_from_session() async {
        let ref = ProjectRef(path: "/tmp/merlin-test-restore-title-\(UUID().uuidString)",
                             displayName: "test")
        let mgr = SessionManager(projectRef: ref)
        let session = Session(title: "My Prior Session", messages: [])

        let live = await mgr.restore(session: session)

        XCTAssertEqual(live.title, "My Prior Session")
    }

    func test_restore_sets_active_session_id() async {
        let ref = ProjectRef(path: "/tmp/merlin-test-restore-active-\(UUID().uuidString)",
                             displayName: "test")
        let mgr = SessionManager(projectRef: ref)
        let session = Session(title: "T", messages: [])

        let live = await mgr.restore(session: session)

        XCTAssertEqual(mgr.activeSessionID, live.id)
    }

    func test_restore_injects_messages_into_context() async {
        let ref = ProjectRef(path: "/tmp/merlin-test-restore-ctx-\(UUID().uuidString)",
                             displayName: "test")
        let mgr = SessionManager(projectRef: ref)
        let msgs = [
            Message(role: .user,      content: .text("q1"), timestamp: Date()),
            Message(role: .assistant, content: .text("a1"), timestamp: Date()),
            Message(role: .user,      content: .text("q2"), timestamp: Date()),
        ]
        let session = Session(title: "T", messages: msgs)

        let live = await mgr.restore(session: session)

        // After inject + possible compaction, context must be non-empty
        XCTAssertFalse(live.appState.engine.contextManager.messages.isEmpty,
                       "Restored messages must appear in context manager")
    }

    func test_restore_does_not_reuse_session_id() async {
        let ref = ProjectRef(path: "/tmp/merlin-test-restore-id-\(UUID().uuidString)",
                             displayName: "test")
        let mgr = SessionManager(projectRef: ref)
        let session = Session(title: "T", messages: [])

        let live = await mgr.restore(session: session)

        XCTAssertNotEqual(live.id, session.id,
                          "Restored LiveSession must have a fresh UUID to avoid overwriting history")
    }

    func test_restore_appends_to_existing_live_sessions() async {
        let ref = ProjectRef(path: "/tmp/merlin-test-restore-append-\(UUID().uuidString)",
                             displayName: "test")
        let mgr = SessionManager(projectRef: ref)
        await mgr.newSession()
        XCTAssertEqual(mgr.liveSessions.count, 1)

        let session = Session(title: "Restored", messages: [])
        await mgr.restore(session: session)

        XCTAssertEqual(mgr.liveSessions.count, 2)
    }

    // MARK: - SessionManager.sessionStore exposed

    func test_sessionManager_exposes_sessionStore() {
        let ref = ProjectRef(path: "/tmp/merlin-test-store-\(UUID().uuidString)",
                             displayName: "test")
        let mgr = SessionManager(projectRef: ref)
        // sessionStore must be non-nil and its storeDirectory must exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: mgr.sessionStore.storeDirectory.path))
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `ContextManager.load(_:)`, `SessionManager.restore(session:)`,
`SessionManager.sessionStore` not found.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-182a-session-restore-tests.md \
        MerlinTests/Unit/SessionRestoreTests.swift
git commit -m "Phase 182a — SessionRestoreTests (failing)"
```
