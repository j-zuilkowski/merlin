import XCTest
@testable import Merlin

@MainActor
final class PreflightTelemetryTests: XCTestCase {

    func testRunLoopEmitsPreflightEstimateOncePerTurn() async throws {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "ok"), finishReason: "stop")
        ])
        let engine = makeEngine(provider: provider)

        for await _ in engine.send(userMessage: "hello") {}

        let events = recorder.events.filter { $0.event == "engine.preflight.estimate" }
        XCTAssertEqual(events.count, 1)
        XCTAssertGreaterThan(events[0].data["estimated_tokens"]?.intValue ?? 0, 0)
        XCTAssertEqual(events[0].data["provider_id"]?.stringValue, provider.id)
        XCTAssertEqual(events[0].data["slot"]?.stringValue, AgentSlot.execute.rawValue)
    }
}
