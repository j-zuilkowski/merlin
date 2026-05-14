import XCTest
@testable import Merlin

final class PlannerStepTelemetryTests: XCTestCase {

    func testPlannerEmitsOneTelemetryEventPerStep() async throws {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

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

        let events = await recorder.events.filter { $0.event == "planner.step.executing" }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].data["step_index"]?.intValue, 0)
        XCTAssertEqual(events[1].data["step_index"]?.intValue, 1)
        XCTAssertEqual(events[0].data["total_steps"]?.intValue, 2)
        XCTAssertEqual(events[1].data["total_steps"]?.intValue, 2)
    }
}
