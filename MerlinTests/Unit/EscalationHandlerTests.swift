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

    /// A capability escalation routes to the engine-designated preferred provider
    /// (the reason slot), NOT the highest-budget one — a local model loaded at a
    /// large context must not out-rank the designated stronger remote model.
    func testCriticExhaustedPrefersDesignatedProviderOverBudget() async {
        let handler = EscalationHandler(
            planner: makePlanner(response: "[]"),
            // "local" has the BIGGEST budget; "remote" is the designated provider.
            registry: makeRegistry([("local", 200_000), ("remote", 60_000)]),
            maxRefinementsPerTurn: 2,
            viableProviderIDs: ["local", "remote"],
            preferredEscalationProviderID: "remote"
        )
        let decision = await handler.escalateOrStop(
            currentStep: makeStep(),
            reason: .criticExhausted(reason: "still red"),
            context: []
        )
        guard case .routeToProvider(let providerID, _) = decision else {
            return XCTFail("Expected routeToProvider, got \(decision)")
        }
        XCTAssertEqual(providerID, "remote",
                       "must escalate to the designated provider, not the largest-budget one")
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

    /// After the designated provider has been tried, a further capability
    /// escalation stops rather than downgrading to a weaker provider.
    func testCapabilityEscalationDoesNotDowngradeAfterDesignatedProviderTried() async {
        let handler = EscalationHandler(
            planner: makePlanner(response: "[]"),
            registry: makeRegistry([("local", 200_000), ("remote", 60_000)]),
            maxRefinementsPerTurn: 4,
            viableProviderIDs: ["local", "remote"],
            preferredEscalationProviderID: "remote"
        )
        let first = await handler.escalateOrStop(
            currentStep: makeStep(), reason: .criticExhausted(reason: "x"), context: [])
        guard case .routeToProvider("remote", _) = first else {
            return XCTFail("first escalation should route to the designated provider, got \(first)")
        }
        let second = await handler.escalateOrStop(
            currentStep: makeStep(), reason: .criticExhausted(reason: "x again"), context: [])
        guard case .stop = second else {
            return XCTFail("second escalation must stop, not downgrade — got \(second)")
        }
    }

    // MARK: - Escalation handoff context

    /// The handoff context is a clean task framing — the original task plus an
    /// instruction to ignore the prior conversation — not the stalled model's
    /// flailing history.
    func testEscalationHandoffMessagesAreACleanTaskFraming() {
        let messages = AgenticEngine.escalationHandoffMessages(task: "Fix the failing tests")
        XCTAssertEqual(messages.count, 2, "handoff = original task + handoff instruction")
        XCTAssertEqual(messages[0].content.plainText, "Fix the failing tests",
                       "first message must be the original task, verbatim")
        let handoff = messages[1].content.plainText.lowercased()
        XCTAssertTrue(handoff.contains("escalation handoff"))
        XCTAssertTrue(handoff.contains("not rely on any prior conversation"),
                      "the escalated model must be told to ignore the stalled history")
        XCTAssertTrue(handoff.contains("assess"),
                      "the escalated model must be told to assess the project state itself")
    }
}
