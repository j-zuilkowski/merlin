import XCTest
@testable import Merlin

@MainActor
final class HookTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-hook-telemetry-\(UUID().uuidString).jsonl"
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

    func testPreToolHookEmitsEvent() async throws {
        // Empty hooks — should still emit allow event
        let engine = HookEngine(hooks: [])
        _ = await engine.runPreToolUse(toolName: "read_file", input: ["path": "/tmp/test.txt"])

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "hook.pre_tool" }
        XCTAssertFalse(events.isEmpty, "hook.pre_tool not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["tool_name"] as? String, "read_file")
        XCTAssertNotNil(d?["decision"])
        XCTAssertNotNil(d?["duration_ms"])
    }

    func testPostToolHookEmitsEvent() async throws {
        let engine = HookEngine(hooks: [])
        _ = await engine.runPostToolUse(toolName: "shell", result: "exit 0")

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "hook.post_tool" }
        XCTAssertFalse(events.isEmpty, "hook.post_tool not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["tool_name"] as? String, "shell")
        XCTAssertNotNil(d?["had_note"])
    }

    func testPromptSubmitHookEmitsEvent() async throws {
        let engine = HookEngine(hooks: [])
        _ = await engine.runUserPromptSubmit(prompt: "hello world")

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "hook.prompt_submit" }
        XCTAssertFalse(events.isEmpty, "hook.prompt_submit not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["modified"])
        XCTAssertNotNil(d?["duration_ms"])
    }
}
