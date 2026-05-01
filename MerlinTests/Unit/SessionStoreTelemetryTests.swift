import XCTest
@testable import Merlin

@MainActor
final class SessionStoreTelemetryTests: XCTestCase {

    private var tempTelemetryPath: String!
    private var tempStoreDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempTelemetryPath = "/tmp/merlin-session-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempTelemetryPath)
        tempStoreDir = URL(fileURLWithPath: "/tmp/merlin-session-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempStoreDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempTelemetryPath)
        try? FileManager.default.removeItem(at: tempStoreDir)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempTelemetryPath),
              let content = try? String(contentsOfFile: tempTelemetryPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testSessionSaveEventEmitted() async throws {
        let store = SessionStore(storeDirectory: tempStoreDir)
        var session = Session(title: "Test Session", messages: [])
        session.messages = [
            Message(role: .user, content: .text("hello"), timestamp: Date()),
            Message(role: .assistant, content: .text("hi"), timestamp: Date())
        ]

        try? store.save(session)

        let captured = try await capturedEvents()
        let saves = captured.filter { $0["event"] as? String == "session.save" }
        XCTAssertFalse(saves.isEmpty, "session.save not emitted")
        let d = saves[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["session_id"])
        XCTAssertEqual(d?["message_count"] as? Int, 2)
    }

    func testSessionSaveIncludesDuration() async throws {
        let store = SessionStore(storeDirectory: tempStoreDir)
        let session = Session(title: "T", messages: [])

        try? store.save(session)

        let captured = try await capturedEvents()
        let saves = captured.filter { $0["event"] as? String == "session.save" }
        XCTAssertFalse(saves.isEmpty)
        let ms = saves[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }
}
