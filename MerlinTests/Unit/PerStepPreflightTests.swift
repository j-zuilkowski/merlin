import XCTest
@testable import Merlin

@MainActor
final class PerStepPreflightTests: XCTestCase {

    private func makeTestEngine() -> AgenticEngine {
        makeEngine(provider: MockProvider(chunks: []))
    }

    private func makeStep(description: String, tokenBudget: Int) -> PlanStep {
        PlanStep(
            description: description,
            successCriteria: [.prose("done")],
            complexity: .standard,
            parallelSafe: false,
            tokenBudget: tokenBudget,
            requiresCritic: .optional,
            minContextRequired: tokenBudget * 2
        )
    }

    func testPerStepPreflightRunsBeforeTheFirstProviderCall() async {
        let engine = makeTestEngine()
        let provider = MockProvider(chunks: [])
        let request = CompletionRequest(model: provider.id, messages: [])
        let step = makeStep(description: "Step 2", tokenBudget: 96_000)

        _ = await engine.preflightPlanStep(
            step: step,
            request: request,
            provider: provider
        )
    }
}
