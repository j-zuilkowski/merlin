import XCTest
@testable import Merlin

final class AccessibilityIDTests: XCTestCase {

    // MARK: - Catalog completeness

    /// All identifiers that must exist for osascript / E2E test automation.
    private let required: [String] = [
        AccessibilityID.chatInput,
        AccessibilityID.chatSendButton,
        AccessibilityID.chatCancelButton,
        AccessibilityID.sessionList,
        AccessibilityID.newSessionButton,
        AccessibilityID.providerHUD,
        AccessibilityID.settingsButton,
        AccessibilityID.providerSelector,
    ]

    func testAllRequiredIDsAreNonEmpty() {
        for id in required {
            XCTAssertFalse(id.isEmpty, "Accessibility ID must not be empty")
        }
    }

    func testAllRequiredIDsAreUnique() {
        let set = Set(required)
        XCTAssertEqual(set.count, required.count, "Accessibility IDs must be unique — duplicates found")
    }

    func testAllRequiredIDsUseLowercaseDashFormat() {
        let pattern = try! NSRegularExpression(pattern: "^[a-z][a-z0-9-]*$")
        for id in required {
            let range = NSRange(id.startIndex..., in: id)
            let match = pattern.firstMatch(in: id, range: range)
            XCTAssertNotNil(match, "ID '\(id)' must be lowercase-dash format (e.g. 'chat-input')")
        }
    }

    func testChatInputIDValue() {
        XCTAssertEqual(AccessibilityID.chatInput, "chat-input")
    }

    func testChatSendButtonIDValue() {
        XCTAssertEqual(AccessibilityID.chatSendButton, "chat-send-button")
    }

    func testSessionListIDValue() {
        XCTAssertEqual(AccessibilityID.sessionList, "session-list")
    }
}
