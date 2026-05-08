import XCTest
@testable import Merlin

// Tests for AgenticEngine.onTitleUpdate and LiveSession title auto-labeling.
// Uses MockProvider so no network calls are made.

@MainActor
final class SessionTitleTests: XCTestCase {

    // MARK: - AgenticEngine.onTitleUpdate

    func test_onTitleUpdate_fires_after_first_save_when_title_is_new_session() async throws {
        let store = makeStore()
        defer { cleanup(store) }

        // Create a session with default title
        let session = store.create()
        XCTAssertEqual(session.title, "New Session")

        let engine = EngineFactory.make(sessionStore: store)
        var receivedTitle: String?
        engine.onTitleUpdate = { receivedTitle = $0 }

        // Simulate a save with a user message present
        let userMessage = Message(role: .user, content: .text("Fix the parser bug"),
                                  timestamp: Date())
        var updated = session
        updated.messages = [userMessage]
        updated.updatedAt = Date()
        engine.applyTitleUpdateIfNeeded(to: &updated)
        try store.save(updated)

        XCTAssertNotNil(receivedTitle)
        XCTAssertEqual(receivedTitle, "Fix the parser bug")
    }

    func test_onTitleUpdate_does_not_fire_when_title_already_set() throws {
        let store = makeStore()
        defer { cleanup(store) }

        var session = store.create()
        session.title = "Custom Title"
        try store.save(session)

        let engine = EngineFactory.make(sessionStore: store)
        var fired = false
        engine.onTitleUpdate = { _ in fired = true }

        var updated = session
        updated.messages = [Message(role: .user, content: .text("hello"), timestamp: Date())]
        engine.applyTitleUpdateIfNeeded(to: &updated)

        XCTAssertFalse(fired, "onTitleUpdate must not fire when title was already customised")
    }

    func test_onTitleUpdate_does_not_fire_when_no_user_messages() throws {
        let store = makeStore()
        defer { cleanup(store) }

        let session = store.create()
        let engine = EngineFactory.make(sessionStore: store)
        var fired = false
        engine.onTitleUpdate = { _ in fired = true }

        var updated = session
        updated.messages = []
        engine.applyTitleUpdateIfNeeded(to: &updated)

        XCTAssertFalse(fired)
    }

    func test_generated_title_truncates_to_50_chars() throws {
        let store = makeStore()
        defer { cleanup(store) }

        let session = store.create()
        let engine = EngineFactory.make(sessionStore: store)
        var receivedTitle: String?
        engine.onTitleUpdate = { receivedTitle = $0 }

        let longText = String(repeating: "a", count: 100)
        var updated = session
        updated.messages = [Message(role: .user, content: .text(longText), timestamp: Date())]
        engine.applyTitleUpdateIfNeeded(to: &updated)

        XCTAssertEqual(receivedTitle?.count, 50)
    }

    func test_generated_title_matches_session_generateTitle() throws {
        let store = makeStore()
        defer { cleanup(store) }

        let session = store.create()
        let engine = EngineFactory.make(sessionStore: store)
        var receivedTitle: String?
        engine.onTitleUpdate = { receivedTitle = $0 }

        let msg = Message(role: .user, content: .text("Refactor the auth layer"),
                          timestamp: Date())
        var updated = session
        updated.messages = [msg]
        engine.applyTitleUpdateIfNeeded(to: &updated)

        let expected = Session.generateTitle(from: [msg])
        XCTAssertEqual(receivedTitle, expected)
    }

    // MARK: - LiveSession title wiring

    func test_liveSession_title_updates_via_onTitleUpdate_callback() async {
        let ref = ProjectRef(path: "/tmp/merlin-title-\(UUID().uuidString)",
                             displayName: "test")
        let live = LiveSession(projectRef: ref)
        XCTAssertEqual(live.title, "New Session")

        // Fire the callback directly to verify wiring
        live.appState.engine.onTitleUpdate?("Refactored Auth Layer")

        // Allow MainActor tasks to settle
        await Task.yield()

        XCTAssertEqual(live.title, "Refactored Auth Layer",
                       "LiveSession.title must update when engine.onTitleUpdate fires")
    }

    // MARK: - Helpers

    private func makeStore() -> SessionStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-title-store-\(UUID().uuidString)", isDirectory: true)
        return SessionStore(storeDirectory: dir)
    }

    private func cleanup(_ store: SessionStore) {
        try? FileManager.default.removeItem(at: store.storeDirectory)
    }
}
