import XCTest
@testable import Merlin

@MainActor
final class EscalationHandlerTests: XCTestCase {

    // MARK: - Helpers

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

    // MARK: - Tests

    func testIterationCapContinuesWithDecomposedSteps() async {
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
            reason: .iterationCap(loopCount: 24, lastObservation: "no new output"),
            context: []
        )

        switch decision {
        case .continueWith(let replacementSteps):
            XCTAssertEqual(replacementSteps.count, 1)
            XCTAssertEqual(replacementSteps[0].description, "Substep 1")
        case .routeToProvider(let providerID, let reason):
            XCTFail("Expected refinement to continue, got route to provider \(providerID): \(reason)")
        case .stop(let message):
            XCTFail("Expected refinement to continue, got stop: \(message)")
        }
    }

    func testIterationCapStopsWhenPlannerCannotDecompose() async {
        let planner = makePlanner(response: #"{"cannot_decompose":"step is atomic"}"#)
        let handler = EscalationHandler(planner: planner, maxRefinementsPerTurn: 2)

        let decision = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .iterationCap(loopCount: 24, lastObservation: "no new output"),
            context: []
        )

        switch decision {
        case .stop(let message):
            XCTAssertTrue(message.lowercased().contains("step is atomic"))
        case .routeToProvider(let providerID, let reason):
            XCTFail("Expected a stop decision, got route to provider \(providerID): \(reason)")
        case .continueWith(let replacementSteps):
            XCTFail("Expected a stop decision, got steps: \(replacementSteps)")
        }
    }

    func testRefinementBudgetStopsAfterConfiguredLimit() async {
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

        let first = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .iterationCap(loopCount: 24, lastObservation: "first pass"),
            context: []
        )
        let second = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .iterationCap(loopCount: 25, lastObservation: "second pass"),
            context: []
        )
        let third = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .iterationCap(loopCount: 26, lastObservation: "third pass"),
            context: []
        )

        switch first {
        case .continueWith:
            break
        case .routeToProvider(let providerID, let reason):
            XCTFail("First refinement should be allowed, got route to provider \(providerID): \(reason)")
        case .stop(let message):
            XCTFail("First refinement should be allowed, got stop: \(message)")
        }
        switch second {
        case .continueWith:
            break
        case .routeToProvider(let providerID, let reason):
            XCTFail("Second refinement should be allowed, got route to provider \(providerID): \(reason)")
        case .stop(let message):
            XCTFail("Second refinement should be allowed, got stop: \(message)")
        }
        switch third {
        case .stop(let message):
            XCTAssertTrue(message.lowercased().contains("budget"))
        case .routeToProvider(let providerID, let reason):
            XCTFail("Expected refinement budget exhaustion, got route to provider \(providerID): \(reason)")
        case .continueWith(let replacementSteps):
            XCTFail("Expected refinement budget exhaustion, got steps: \(replacementSteps)")
        }
    }
}
