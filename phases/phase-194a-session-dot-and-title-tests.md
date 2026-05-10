# Phase 194a — Session Dot & Title Fix Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 193b complete: session dot, view isolation, auto-naming, and compact-context fixes
shipped in v1.8.1.

Two bugs survive:

**Bug A — Activity dot never clears for non-active sessions**
Root cause: `LiveSessionRow` uses `@ObservedObject var session: LiveSession`.
`LiveSession.appState` is a plain `let` constant — not `@Published`. SwiftUI's
`@ObservedObject` only fires redraws when a direct `@Published` property of the
observed object changes. Changes to `appState.toolActivityState` are invisible to
`LiveSessionRow`, so the dot never clears even though the Combine subscriber in
`AppState` correctly sets `toolActivityState = .idle`.

**Bug B — Sessions never get auto-named**
Root cause: `SessionStore.save(_:)` unconditionally writes
`activeSessionID = session.id` on every save (line 87). All sessions in a project
share one `SessionStore`. When Session 2 is created its `LiveSession.init` calls
`save(initialRecord2)` → `activeSessionID` is clobbered to session 2's ID. When
Session 1's engine finishes its turn it reads `sessionStore.activeSession` →
gets session 2's record → writes session 1's messages into session 2 and calls
`onTitleUpdate` with a title that belongs to session 1. Neither session ends up
with the right title.

New surface introduced in phase 194b:
  - `AgenticEngine.sessionID: UUID?` — set by `SessionManager`; used for direct
    session-record lookup instead of `sessionStore.activeSession`
  - `SessionManager.newSession()` sets `session.appState.engine.sessionID = session.id`
  - `SessionManager.restore(session:)` sets `live.appState.engine.sessionID = live.id`
  - `SessionStore.save(_:)` no longer writes `activeSessionID = session.id`
  - `LiveSessionRow` gains `@ObservedObject var appState: AppState` with a custom
    `init(session:isActive:)` that extracts `session.appState`

TDD coverage:
  File — SessionDotAndTitleFixTests.swift: 4 tests targeting both bugs

---

## Write to: MerlinTests/Unit/SessionDotAndTitleFixTests.swift

```swift
// SessionDotAndTitleFixTests.swift
// Phase 194a — failing tests for session dot and auto-title bugs.
//
// Bug A: LiveSessionRow reads session.appState.toolActivityState but only
//   observes `session` (not `appState`), so dot never updates.
// Bug B: SessionStore.save(_:) clobbers activeSessionID on every write,
//   so multi-session title saves target the wrong record.
import XCTest
@testable import Merlin

@MainActor
final class SessionDotAndTitleFixTests: XCTestCase {

    // MARK: - Bug B tests (model-level, fail to compile until 194b)

    /// AgenticEngine must expose a `sessionID` property so it can look up its
    /// own store record directly rather than via `sessionStore.activeSession`.
    /// FAILS TO COMPILE before 194b — `sessionID` does not exist on AgenticEngine.
    func test_agenticEngine_has_sessionID_property() {
        let engine = AgenticEngine()
        // sessionID starts nil; SessionManager sets it after creation.
        XCTAssertNil(engine.sessionID)
    }

    /// SessionManager.newSession() must pin the engine's sessionID to the
    /// LiveSession's id so the engine always saves to its own record.
    /// FAILS TO COMPILE before 194b — `engine.sessionID` does not exist.
    func test_newSession_sets_engine_sessionID() async {
        let ref = ProjectRef(path: "/tmp/194a-new-\(UUID().uuidString)")
        let mgr = SessionManager(projectRef: ref)
        let session = await mgr.newSession()
        XCTAssertEqual(session.appState.engine.sessionID, session.id)
    }

    /// SessionManager.restore() must also pin the engine's sessionID.
    /// FAILS TO COMPILE before 194b.
    func test_restore_sets_engine_sessionID() async {
        let ref = ProjectRef(path: "/tmp/194a-restore-\(UUID().uuidString)")
        let mgr = SessionManager(projectRef: ref)

        let stored = Session(id: UUID(), title: "Old Work", messages: [
            Message(role: .user,
                    content: .text("Implement login"),
                    timestamp: Date())
        ])
        try? mgr.sessionStore.save(stored)

        let live = await mgr.restore(session: stored)
        // The restored LiveSession gets a fresh UUID; engine.sessionID must match it.
        XCTAssertEqual(live.appState.engine.sessionID, live.id)
    }

    /// SessionStore.save(_:) must NOT update activeSessionID.
    /// FAILS at runtime before 194b — save() currently writes activeSessionID = session.id.
    func test_sessionStore_save_does_not_clobber_activeSessionID() throws {
        let dir = URL(fileURLWithPath: "/tmp/194a-store-\(UUID().uuidString)")
        let store = SessionStore(storeDirectory: dir)

        let s1 = Session(id: UUID(), title: "S1", messages: [])
        let s2 = Session(id: UUID(), title: "S2", messages: [])

        try store.save(s1)
        store.activeSessionID = s1.id   // pin explicitly after first save

        try store.save(s2)              // must NOT move activeSessionID to s2

        XCTAssertEqual(store.activeSessionID, s1.id,
            "save(_:) must not overwrite activeSessionID — only UI session switches may do that")
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
Expected: **BUILD FAILED** with errors referencing `sessionID` (no member on `AgenticEngine`).
The `test_sessionStore_save_does_not_clobber_activeSessionID` test would also fail at
runtime once the compile errors are resolved.

## Commit
```bash
git add MerlinTests/Unit/SessionDotAndTitleFixTests.swift
git commit -m "Phase 194a — SessionDotAndTitleFixTests (failing)"
```
