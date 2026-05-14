import XCTest
@testable import Merlin

@MainActor
final class EscalationAtomicOverflowTests: XCTestCase {

    private func makePlanner(response: String) -> PlannerEngine {
        PlannerEngine(orchestrateProvider: MockPlannerProvider(response: response))
    }

    private func makeAtomicStep() -> PlanStep {
        PlanStep(
            description: "Publish the bundle",
            successCriteria: [.prose("the bundle ships")],
            complexity: .highStakes,
            parallelSafe: false,
            tokenBudget: 16_000,
            requiresCritic: .required,
            minContextRequired: 64_000
        )
    }

    func testAtomicOverflowRoutesToProviderWhenOneFits() async {
        let planner = makePlanner(response: #"{"cannot_decompose":"step is atomic"}"#)
        let handler = EscalationHandler(planner: planner, maxRefinementsPerTurn: 2)

        let decision = await handler.escalateOrStop(
            currentStep: makeAtomicStep(),
            reason: .preflightOverflow(estimated: 96_000, budget: 24_000),
            context: []
        )

        switch decision {
        case .routeToProvider(let providerID, let reason):
            XCTAssertEqual(providerID, "big-model")
            XCTAssertTrue(reason.contains("atomic"))
        case .continueWith(let replacementSteps):
            XCTFail("Expected routing, got steps: \(replacementSteps)")
        case .stop(let message):
            XCTFail("Expected routing, got stop: \(message)")
        }
    }

    func testAtomicOverflowStopsWhenNoProviderFits() async {
        let planner = makePlanner(response: #"{"cannot_decompose":"step is atomic"}"#)
        let handler = EscalationHandler(planner: planner, maxRefinementsPerTurn: 2)

        let decision = await handler.escalateOrStop(
            currentStep: makeAtomicStep(),
            reason: .preflightOverflow(estimated: 96_000, budget: 24_000),
            context: []
        )

        switch decision {
        case .stop(let message):
            XCTAssertTrue(message.lowercased().contains("atomic"))
        case .continueWith(let replacementSteps):
            XCTFail("Expected stop, got steps: \(replacementSteps)")
        case .routeToProvider(let providerID, let reason):
            XCTFail("Expected stop, got route to provider \(providerID): \(reason)")
        }
    }
}
