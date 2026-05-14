import XCTest
@testable import Merlin

@MainActor
final class CleanStopOutcomeTests: XCTestCase {

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

    private func extractCleanStop(from events: [AgentEvent]) -> (reason: String, summary: String)? {
        for event in events {
            if case .cleanStop(let reason, let summary) = event {
                return (reason, summary)
            }
        }
        return nil
    }

    func testStopDecisionUsesStructuredCannotContinueMessage() async {
        let planner = makePlanner(response: #"{"cannot_decompose":"step is atomic"}"#)
        let handler = EscalationHandler(planner: planner, maxRefinementsPerTurn: 1)

        let decision = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .iterationCap(loopCount: 12, lastObservation: "no progress"),
            context: []
        )

        switch decision {
        case .stop(let message):
            XCTAssertTrue(message.contains("Cannot continue"))
            XCTAssertTrue(message.contains("Suggested"))
            XCTAssertTrue(message.contains("Progress so far"))
        case .routeToProvider(let providerID, let reason):
            XCTFail("Expected stop decision, got route to provider \(providerID): \(reason)")
        case .continueWith(let replacementSteps):
            XCTFail("Expected stop decision, got steps: \(replacementSteps)")
        }
    }
}
