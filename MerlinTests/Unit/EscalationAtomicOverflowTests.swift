import XCTest
@testable import Merlin

@MainActor
final class EscalationAtomicOverflowTests: XCTestCase {

    private func makePlanner(response: String) -> PlannerEngine {
        PlannerEngine(orchestrateProvider: MockPlannerProvider(response: response))
    }

    private func makeRegistry(providers: [ProviderConfig]) -> ProviderRegistry {
        ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-escalation-atomic-\(UUID().uuidString).json"),
            initialProviders: providers
        )
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
        let registry = makeRegistry(providers: [
            ProviderConfig(
                id: "small-model",
                displayName: "Small Model",
                baseURL: "http://localhost",
                model: "small",
                isEnabled: true,
                isLocal: true,
                supportsThinking: false,
                supportsVision: false,
                kind: .openAICompatible,
                budget: ProviderBudget(maxInputTokens: 28_000, reservedOutputTokens: 4_096)
            ),
            ProviderConfig(
                id: "big-model",
                displayName: "Big Model",
                baseURL: "http://localhost",
                model: "big",
                isEnabled: true,
                isLocal: true,
                supportsThinking: false,
                supportsVision: false,
                kind: .openAICompatible,
                budget: ProviderBudget(maxInputTokens: 128_000, reservedOutputTokens: 8_192)
            )
        ])
        let handler = EscalationHandler(planner: planner, registry: registry, maxRefinementsPerTurn: 2)

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
        let registry = makeRegistry(providers: [
            ProviderConfig(
                id: "small-model",
                displayName: "Small Model",
                baseURL: "http://localhost",
                model: "small",
                isEnabled: true,
                isLocal: true,
                supportsThinking: false,
                supportsVision: false,
                kind: .openAICompatible,
                budget: ProviderBudget(maxInputTokens: 28_000, reservedOutputTokens: 4_096)
            )
        ])
        let handler = EscalationHandler(planner: planner, registry: registry, maxRefinementsPerTurn: 2)

        let decision = await handler.escalateOrStop(
            currentStep: makeAtomicStep(),
            reason: .preflightOverflow(estimated: 96_000, budget: 24_000),
            context: []
        )

        switch decision {
        case .stop(let message):
            XCTAssertEqual(
                message,
                "step requires 64000 tokens; no configured provider supports that budget"
            )
        case .continueWith(let replacementSteps):
            XCTFail("Expected stop, got steps: \(replacementSteps)")
        case .routeToProvider(let providerID, let reason):
            XCTFail("Expected stop, got route to provider \(providerID): \(reason)")
        }
    }
}
