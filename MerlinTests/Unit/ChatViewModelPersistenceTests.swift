// ChatViewModelPersistenceTests.swift
// Task 195a — failing tests for ChatViewModel persistence across session switches.
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
