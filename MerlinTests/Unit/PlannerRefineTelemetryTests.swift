import XCTest
@testable import Merlin

@MainActor
final class PlannerRefineTelemetryTests: XCTestCase {

    private func makePlanner(response: String) -> PlannerEngine {
        PlannerEngine(orchestrateProvider: MockPlannerProvider(response: response))
    }

    private func makeStep() -> PlanStep {
        PlanStep(
            description: "Break the work down",
            successCriteria: [.prose("done")],
            complexity: .standard,
            parallelSafe: false,
            tokenBudget: 24_000,
            requiresCritic: .optional,
            minContextRequired: 16_000
        )
    }

    func testRefineStepEmitsExactlyOneTerminalTelemetryEvent() async {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

        let planner = makePlanner(response: #"""
        {
          "steps": [
            { "description": "Step 1", "successCriteria": ["ok"], "complexity": "routine", "tokenBudget": 8000, "minContextRequired": 4000 }
          ]
        }
        """#)

        _ = await planner.refineStep(
            makeStep(),
            reason: .budget(estimated: 24_000, budget: 12_000),
            context: []
        )

        let terminalEvents = recorder.events.filter {
            $0.event == "planner.refine.success" || $0.event == "planner.refine.cannot_decompose"
        }
        XCTAssertEqual(terminalEvents.count, 1)
        if let event = terminalEvents.first, event.event == "planner.refine.success" {
            XCTAssertNotNil(event.data["substep_count"])
        }
    }
}
