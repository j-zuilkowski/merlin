import Foundation
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
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("planner-refine-telemetry-\(UUID().uuidString).jsonl")
            .path
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

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

        await TelemetryEmitter.shared.flushForTesting()
        let terminalEvents: [[String: Any]]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
           let content = String(data: data, encoding: .utf8) {
            terminalEvents = content
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }
                .filter {
                    let event = $0["event"] as? String
                    return event == "planner.refine.success" || event == "planner.refine.cannot_decompose"
                }
        } else {
            terminalEvents = []
        }
        XCTAssertEqual(terminalEvents.count, 1)
        if let event = terminalEvents.first,
           let name = event["event"] as? String,
           name == "planner.refine.success" {
            let data = event["data"] as? [String: Any]
            XCTAssertNotNil(data?["substep_count"])
        }
    }
}
