import Foundation
import XCTest
@testable import Merlin

@MainActor
final class IterationCapEscalationTests: XCTestCase {

    func testNearCeilingWithNoProgressEmitsEscalationTelemetry() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("iteration-cap-escalation-\(UUID().uuidString).jsonl")
            .path
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

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

        await TelemetryEmitter.shared.flushForTesting()
        let escalationEvents: [[String: Any]]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
           let content = String(data: data, encoding: .utf8) {
            escalationEvents = content
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }
                .filter { $0["event"] as? String == "engine.escalation.start" }
        } else {
            escalationEvents = []
        }
        XCTAssertFalse(
            escalationEvents.isEmpty,
            "Expected escalation telemetry when the loop approaches the ceiling without progress"
        )
    }
}
