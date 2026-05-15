import Foundation
import XCTest
@testable import Merlin

final class PlannerStepTelemetryTests: XCTestCase {

    func testPlannerEmitsOneTelemetryEventPerStep() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("planner-step-telemetry-\(UUID().uuidString).jsonl")
            .path
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let engine = PlannerEngine(
            executeProvider: MockProvider(chunks: []),
            orchestrateProvider: MockProvider(responses: [
                .text("""
                {
                  "steps": [
                    { "description": "step one", "successCriteria": "done", "complexity": "routine" },
                    { "description": "step two", "successCriteria": "done", "complexity": "standard" }
                  ]
                }
                """)
            ]),
            maxPlanRetries: 1
        )

        _ = await engine.decompose(task: "split work", context: [])

        await TelemetryEmitter.shared.flushForTesting()
        let events: [[String: Any]]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
           let content = String(data: data, encoding: .utf8) {
            events = content
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }
                .filter { $0["event"] as? String == "planner.step.executing" }
        } else {
            events = []
        }
        XCTAssertEqual(events.count, 2)
        let firstData = events[0]["data"] as? [String: Any]
        let secondData = events[1]["data"] as? [String: Any]
        XCTAssertEqual(firstData?["step_index"] as? Int, 0)
        XCTAssertEqual(secondData?["step_index"] as? Int, 1)
        XCTAssertEqual(firstData?["total_steps"] as? Int, 2)
        XCTAssertEqual(secondData?["total_steps"] as? Int, 2)
    }
}
