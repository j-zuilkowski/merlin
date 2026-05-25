// SessionDotAndTitleFixTests.swift
// Task 194a — failing tests for session dot and auto-title bugs.
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
        let ref = ProjectRef(path: "/tmp/194a-new-\(UUID().uuidString)", displayName: "test")
        let mgr = SessionManager(projectRef: ref)
        let session = await mgr.newSession()
        XCTAssertEqual(session.appState.engine.sessionID, session.id)
    }

    /// SessionManager.restore() must also pin the engine's sessionID.
    /// FAILS TO COMPILE before 194b.
    func test_restore_sets_engine_sessionID() async {
        let ref = ProjectRef(path: "/tmp/194a-restore-\(UUID().uuidString)", displayName: "test")
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
