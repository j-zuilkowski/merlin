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

    // MARK: - Provider escalation (criticExhausted + refinement-exhausted)

    /// Builds a registry whose providers have the given usable-input budgets.
    private func makeRegistry(_ specs: [(id: String, usable: Int)]) -> ProviderRegistry {
        let configs = specs.map { spec in
            ProviderConfig(
                id: spec.id, displayName: spec.id, baseURL: "http://localhost",
                model: "m", isEnabled: true, isLocal: true,
                supportsThinking: false, supportsVision: false,
                kind: .openAICompatible,
                budget: ProviderBudget(maxInputTokens: spec.usable + 4_096,
                                       reservedOutputTokens: 4_096))
        }
        return ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-escal-\(UUID().uuidString).json"),
            initialProviders: configs)
    }

    private static let decomposableStep = #"""
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
    """#

    /// Critic exhaustion escalates straight to the strongest viable provider.
    func testCriticExhaustedRoutesToStrongerProvider() async {
        let handler = EscalationHandler(
            planner: makePlanner(response: "[]"),
            registry: makeRegistry([("local", 30_000), ("remote", 200_000)]),
            maxRefinementsPerTurn: 2,
            viableProviderIDs: ["local", "remote"]
        )
        let decision = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .criticExhausted(reason: "tests still red"),
            context: []
        )
        guard case .routeToProvider(let providerID, _) = decision else {
            return XCTFail("Expected routeToProvider, got \(decision)")
        }
        XCTAssertEqual(providerID, "remote",
                       "critic exhaustion must escalate to the strongest viable provider")
    }

    /// Escalation never routes to a provider absent from `viableProviderIDs`,
    /// even when it has the largest budget (the dead-`vllm` regression).
    func testEscalationSkipsNonViableProvider() async {
        let handler = EscalationHandler(
            planner: makePlanner(response: "[]"),
            // "vllm" has the biggest budget but is wired to no slot.
            registry: makeRegistry([("local", 30_000), ("remote", 120_000), ("vllm", 999_000)]),
            maxRefinementsPerTurn: 2,
            viableProviderIDs: ["local", "remote"]
        )
        let decision = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .criticExhausted(reason: "x"),
            context: []
        )
        guard case .routeToProvider(let providerID, _) = decision else {
            return XCTFail("Expected routeToProvider, got \(decision)")
        }
        XCTAssertEqual(providerID, "remote",
                       "escalation must skip the higher-budget but non-viable 'vllm'")
    }

    /// Once the refinement budget is spent, escalation routes to a stronger
    /// provider rather than dead-ending at `.stop`.
    func testRefinementExhaustedEscalatesToProvider() async {
        let handler = EscalationHandler(
            planner: makePlanner(response: Self.decomposableStep),
            registry: makeRegistry([("local", 30_000), ("remote", 200_000)]),
            maxRefinementsPerTurn: 2,
            viableProviderIDs: ["local", "remote"]
        )
        // Two refinements consume the budget…
        for i in 0..<2 {
            _ = await handler.escalateOrStop(
                currentStep: makeStep(),
                reason: .iterationCap(loopCount: 24 + i, lastObservation: "pass \(i)"),
                context: [])
        }
        // …the third escalates to a provider instead of stopping.
        let third = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .iterationCap(loopCount: 26, lastObservation: "exhausted"),
            context: []
        )
        guard case .routeToProvider(let providerID, _) = third else {
            return XCTFail("Expected provider escalation after refinement budget spent, got \(third)")
        }
        XCTAssertEqual(providerID, "remote")
    }
}
