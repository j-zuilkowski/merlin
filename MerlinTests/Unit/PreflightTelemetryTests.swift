import XCTest
@testable import Merlin

@MainActor
final class PreflightTelemetryTests: XCTestCase {

    func testRunLoopEmitsPreflightEstimateOncePerTurn() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("preflight-telemetry-\(UUID().uuidString).jsonl")
            .path
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "ok"), finishReason: "stop")
        ])
        let engine = makeEngine(provider: provider)

        for await _ in engine.send(userMessage: "hello") {}

        await TelemetryEmitter.shared.flushForTesting()
        let events = readTelemetryEvents(fromFile: tempPath)
            .filter { $0["event"] as? String == "engine.preflight.estimate" }
        XCTAssertEqual(events.count, 1)
        let data = events[0]["data"] as? [String: Any]
        XCTAssertGreaterThan(data?["estimated_tokens"] as? Int ?? 0, 0)
        XCTAssertEqual(data?["provider_id"] as? String, provider.id)
        XCTAssertEqual(data?["slot"] as? String, AgentSlot.execute.rawValue)
    }
}
