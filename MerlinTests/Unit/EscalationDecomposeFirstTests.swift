import XCTest
@testable import Merlin

@MainActor
final class EscalationDecomposeFirstTests: XCTestCase {

    private func makePlanner(response: String) -> PlannerEngine {
        PlannerEngine(orchestrateProvider: MockPlannerProvider(response: response))
    }

    private func makeRegistry() -> ProviderRegistry {
        ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-escalation-decompose-\(UUID().uuidString).json"),
            initialProviders: [
                ProviderConfig(
                    id: "fallback",
                    displayName: "Fallback",
                    baseURL: "http://localhost",
                    model: "fallback",
                    isEnabled: true,
                    isLocal: true,
                    supportsThinking: false,
                    supportsVision: false,
                    kind: .openAICompatible,
                    budget: ProviderBudget(maxInputTokens: 48_000, reservedOutputTokens: 4_096)
                )
            ]
        )
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
        let handler = EscalationHandler(planner: planner, registry: makeRegistry(), maxRefinementsPerTurn: 2)

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
