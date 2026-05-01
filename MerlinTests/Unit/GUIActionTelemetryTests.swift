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
