import XCTest
@testable import Merlin

/// Tests for the scroll-lock bridge: JS → Swift message → autoScroll state changes.
///
/// ConversationWebView.Coordinator handles the WKScriptMessageHandler callbacks.
/// We test the Coordinator directly without a live WKWebView.
@MainActor
final class ScrollLockTests: XCTestCase {

    // MARK: - Coordinator message handling

    func test_scrollLock_true_message_sets_locked() {
        var didCallLockChange = false
        var receivedLocked: Bool? = nil

        let coordinator = ConversationWebView.Coordinator(
            onToggleThinking: { _ in },
            onToggleTool:     { _ in },
            onScrollLockChange: { locked in
                didCallLockChange = true
                receivedLocked = locked
            }
        )

        // Simulate the JS bridge posting { type: "scrollLock", locked: "true" }
        coordinator.simulateBridgeMessage(["type": "scrollLock", "locked": "true"])

        XCTAssertTrue(didCallLockChange, "onScrollLockChange must be called for scrollLock messages")
        XCTAssertEqual(receivedLocked, true)
    }

    func test_scrollLock_false_message_resumes() {
        var receivedLocked: Bool? = nil

        let coordinator = ConversationWebView.Coordinator(
            onToggleThinking: { _ in },
            onToggleTool:     { _ in },
            onScrollLockChange: { receivedLocked = $0 }
        )

        coordinator.simulateBridgeMessage(["type": "scrollLock", "locked": "false"])
        XCTAssertEqual(receivedLocked, false)
    }

    func test_unknown_message_type_does_not_crash() {
        let coordinator = ConversationWebView.Coordinator(
            onToggleThinking: { _ in },
            onToggleTool:     { _ in },
            onScrollLockChange: { _ in }
        )
        // Must not crash or assert.
        coordinator.simulateBridgeMessage(["type": "unknownEvent", "data": "foo"])
        XCTAssertTrue(true)
    }

    func test_scrollLock_message_without_locked_key_is_ignored() {
        var callCount = 0
        let coordinator = ConversationWebView.Coordinator(
            onToggleThinking: { _ in },
            onToggleTool:     { _ in },
            onScrollLockChange: { _ in callCount += 1 }
        )
        coordinator.simulateBridgeMessage(["type": "scrollLock"])  // missing "locked"
        XCTAssertEqual(callCount, 0, "malformed scrollLock message must be ignored")
    }

    // MARK: - State round-trip

    func test_coordinator_init_accepts_onScrollLockChange() {
        // Verify the new init parameter compiles and is stored.
        var called = false
        let coordinator = ConversationWebView.Coordinator(
            onToggleThinking: { _ in },
            onToggleTool:     { _ in },
            onScrollLockChange: { _ in called = true }
        )
        coordinator.simulateBridgeMessage(["type": "scrollLock", "locked": "true"])
        XCTAssertTrue(called)
    }
}

// MARK: - Test helper extension

extension ConversationWebView.Coordinator {
    /// Directly invokes the bridge message handler with a synthetic body dictionary,
    /// bypassing the live WKWebView. Used in unit tests only.
    func simulateBridgeMessage(_ body: [String: String]) {
        // Route through the same dispatch path as the real WKScriptMessageHandler.
        // This calls the internal handler that processes the body dict.
        handleBridgeBody(body)
    }
}
