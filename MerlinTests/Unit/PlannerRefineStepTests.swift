import XCTest
@testable import Merlin

final class PlannerRefineStepTests: XCTestCase {

    private func makePlanner(response: String) -> PlannerEngine {
        PlannerEngine(orchestrateProvider: MockPlannerProvider(response: response))
    }

    private func makeLargeStep() -> PlanStep {
        PlanStep(
            description: "Implement the whole feature in one shot",
            successCriteria: [.prose("feature works")],
            complexity: .highStakes,
            parallelSafe: false,
            tokenBudget: 50_000,
            requiresCritic: .optional,
            minContextRequired: 32_000
        )
    }

    func testBudgetRefinementProducesSmallerSubsteps() async {
        let planner = makePlanner(response: #"""
        {
          "steps": [
            { "description": "Split the data model", "successCriteria": ["done"], "complexity": "standard", "tokenBudget": 20000, "minContextRequired": 16000 },
            { "description": "Wire the UI", "successCriteria": ["done"], "complexity": "standard", "tokenBudget": 18000, "minContextRequired": 12000 }
          ]
        }
        """#)

        let outcome = await planner.refineStep(
            makeLargeStep(),
            reason: .budget(estimated: 50_000, budget: 32_000),
            context: []
        )

        switch outcome {
        case .decomposed(let substeps):
            XCTAssertGreaterThanOrEqual(substeps.count, 2)
            XCTAssertTrue(substeps.allSatisfy { $0.tokenBudget < 50_000 })
        case .cannotDecompose(let reason):
            XCTFail("Expected decomposition, got cannotDecompose: \(reason)")
        }
    }

    func testIterationCapProducesTighterScopeSubsteps() async {
        let planner = makePlanner(response: #"""
        {
          "steps": [
            { "description": "Narrow the scope", "successCriteria": ["done"], "complexity": "routine", "tokenBudget": 12000, "minContextRequired": 8000 }
          ]
        }
        """#)

        let outcome = await planner.refineStep(
            makeLargeStep(),
            reason: .iterationCap(loopCount: 9, lastObservation: "still thrashing"),
            context: []
        )

        switch outcome {
        case .decomposed(let substeps):
            XCTAssertFalse(substeps.isEmpty)
            XCTAssertTrue(substeps.contains { $0.description.lowercased().contains("scope") })
        case .cannotDecompose(let reason):
            XCTFail("Expected decomposition, got cannotDecompose: \(reason)")
        }
    }

    func testAtomicStepReturnsCannotDecompose() async {
        let planner = makePlanner(response: #"{ "steps": [] }"#)

        let outcome = await planner.refineStep(
            PlanStep(
                description: "Here is one 180k-token file",
                successCriteria: [.prose("file handled")],
                complexity: .highStakes,
                parallelSafe: false,
                tokenBudget: 180_000,
                requiresCritic: .required,
                minContextRequired: 180_000
            ),
            reason: .budget(estimated: 180_000, budget: 32_000),
            context: []
        )

        switch outcome {
        case .cannotDecompose(let reason):
            XCTAssertFalse(reason.isEmpty)
        case .decomposed:
            XCTFail("Expected cannotDecompose for atomic input")
        }
    }
}
