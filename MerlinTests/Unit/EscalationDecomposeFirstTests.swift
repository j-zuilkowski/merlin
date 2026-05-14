import XCTest
@testable import Merlin

@MainActor
final class EscalationDecomposeFirstTests: XCTestCase {

    private func makePlanner(response: String) -> PlannerEngine {
        PlannerEngine(orchestrateProvider: MockPlannerProvider(response: response))
    }

    private func makeStep() -> PlanStep {
        PlanStep(
            description: "Finish the task",
            successCriteria: [.prose("the task is complete")],
            complexity: .standard,
            parallelSafe: false,
            tokenBudget: 12_000,
            requiresCritic: .optional,
            minContextRequired: 24_000
        )
    }

    func testDecomposedOverflowKeepsTheDecompositionPath() async {
        let planner = makePlanner(response: #"""
        [
          {
            "description": "Substep 1",
            "successCriteria": "done",
            "complexity": "routine",
            "parallelSafe": false,
            "tokenBudget": 6_000,
            "requiresCritic": "optional",
            "minContextRequired": 12_000
          }
        ]
        """#)
        let handler = EscalationHandler(planner: planner, maxRefinementsPerTurn: 2)

        let decision = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .preflightOverflow(estimated: 42_000, budget: 24_000),
            context: []
        )

        switch decision {
        case .continueWith(let replacementSteps):
            XCTAssertEqual(replacementSteps.count, 1)
            XCTAssertEqual(replacementSteps[0].description, "Substep 1")
        case .routeToProvider(let providerID, let reason):
            XCTFail("Expected decomposition, got route to provider \(providerID): \(reason)")
        case .stop(let message):
            XCTFail("Expected decomposition, got stop: \(message)")
        }
    }
}
