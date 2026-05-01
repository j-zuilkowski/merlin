# Phase diag-07a — Accessibility Identifier Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-06b complete: infrastructure telemetry instrumented.

New surface introduced in phase diag-07b:
  - All primary interactive controls in `ChatView`, `SessionSidebar`, `ContentView`, `ProviderHUD`,
    and `SettingsView` gain stable `.accessibilityIdentifier(_:)` modifiers.
  - A complete accessibility identifier manifest is defined in `AccessibilityID.swift` as an enum
    of string constants so test code and `osascript` automation use the same identifiers.
  - `TelemetryEmitter.emitGUIAction(_:identifier:)` emits `gui.action` events when accessibility-
    tracked controls are activated (button taps, field focus).

Identifier catalog (all must be present in the running app):
  - `"chat-input"`          — the main message input field
  - `"chat-send-button"`    — the send / submit button
  - `"chat-cancel-button"`  — the cancel/stop-generation button
  - `"session-list"`        — the session sidebar list
  - `"new-session-button"`  — button to create a new session
  - `"provider-hud"`        — the provider status HUD
  - `"settings-button"`     — toolbar settings gear
  - `"provider-selector"`   — provider picker in settings or HUD

TDD coverage:
  File 1 — AccessibilityIDTests: verify the AccessibilityID constant enum compiles and all expected IDs are present
  File 2 — GUIActionTelemetryTests: verify `emitGUIAction` writes a `gui.action` event with identifier and action fields

---

## Write to: MerlinTests/Unit/AccessibilityIDTests.swift

```swift
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
```

---

## Write to: MerlinTests/Unit/GUIActionTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class GUIActionTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-gui-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testEmitGUIActionWritesEvent() async throws {
        TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.chatSendButton)
        await TelemetryEmitter.shared.flushForTesting()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "gui.action" }
        XCTAssertFalse(events.isEmpty, "gui.action not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["identifier"] as? String, AccessibilityID.chatSendButton)
        XCTAssertEqual(d?["action"] as? String, "tap")
    }

    func testEmitGUIActionForMultipleControls() async throws {
        TelemetryEmitter.shared.emitGUIAction("tap",   identifier: AccessibilityID.newSessionButton)
        TelemetryEmitter.shared.emitGUIAction("focus", identifier: AccessibilityID.chatInput)
        await TelemetryEmitter.shared.flushForTesting()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "gui.action" }
        XCTAssertEqual(events.count, 2)

        let ids = events.compactMap { ($0["data"] as? [String: Any])?["identifier"] as? String }
        XCTAssertTrue(ids.contains(AccessibilityID.newSessionButton))
        XCTAssertTrue(ids.contains(AccessibilityID.chatInput))
    }

    func testGUIActionEventContainsTimestamp() async throws {
        TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.settingsButton)
        await TelemetryEmitter.shared.flushForTesting()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "gui.action" }
        XCTAssertFalse(events.isEmpty)
        XCTAssertNotNil(events[0]["ts"], "Timestamp must be present on gui.action events")
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
Expected: BUILD FAILED — `AccessibilityID` enum not found; `TelemetryEmitter.emitGUIAction(_:identifier:)` not defined.

## Commit
```bash
git add MerlinTests/Unit/AccessibilityIDTests.swift \
        MerlinTests/Unit/GUIActionTelemetryTests.swift
git commit -m "Phase diag-07a — Accessibility identifier tests (failing)"
```
