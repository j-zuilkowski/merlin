import XCTest
@testable import Merlin

@MainActor
final class IterationCapEscalationTests: XCTestCase {

    func testNearCeilingWithNoProgressEmitsEscalationTelemetry() async throws {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

        let provider = MockProvider(responses: [
            .toolCall(id: "t1", name: "noop", args: "{}"),
            .toolCall(id: "t2", name: "noop", args: "{}"),
            .toolCall(id: "t3", name: "noop", args: "{}"),
            .toolCall(id: "t4", name: "noop", args: "{}"),
            .text("done"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("noop") { _ in "ok" }
        engine.maxIterationsOverride = 6
        engine.nearCeilingThreshold = 3

        for await _ in engine.send(userMessage: "keep going until the ceiling") {}

        let escalationEvents = recorder.events.filter { $0.event == "engine.escalation.start" }
        XCTAssertFalse(
            escalationEvents.isEmpty,
            "Expected escalation telemetry when the loop approaches the ceiling without progress"
        )
    }
}
