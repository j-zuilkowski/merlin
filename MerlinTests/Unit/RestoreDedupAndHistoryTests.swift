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
