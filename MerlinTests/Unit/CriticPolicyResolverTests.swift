import XCTest
@testable import Merlin

final class CriticPolicyResolverTests: XCTestCase {

    private func makeSkill(_ critic: CriticMode? = nil) -> SkillFrontmatter {
        var skill = SkillFrontmatter(name: "review", description: "Review the change")
        skill.critic = critic
        return skill
    }

    private func makeStep(
        requiresCritic: CriticMode? = .optional,
        criteria: [StepCriterion] = [.prose("done")]
    ) -> PlanStep {
        PlanStep(
            description: "Ship the feature",
            successCriteria: criteria,
            complexity: .standard,
            parallelSafe: false,
            tokenBudget: 12_000,
            requiresCritic: requiresCritic ?? .optional,
            minContextRequired: 24_000
        )
    }

    func testSkillSkipOverridesEverything() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(.skip),
            step: makeStep(requiresCritic: .required),
            heuristic: (writtenFiles: true, substantial: true, complexity: .highStakes),
            classifierOverride: true
        )

        XCTAssertEqual(decision, .skip)
    }

    func testSkillRequiredOverridesStepSkip() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(.required),
            step: makeStep(requiresCritic: .skip),
            heuristic: (writtenFiles: false, substantial: false, complexity: .routine),
            classifierOverride: false
        )

        XCTAssertEqual(decision, .run)
    }

    func testStepSkipOverridesDeterministicAndHeuristicSignals() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(nil),
            step: makeStep(requiresCritic: .skip, criteria: [.buildSucceeds]),
            heuristic: (writtenFiles: true, substantial: true, complexity: .highStakes),
            classifierOverride: true
        )

        XCTAssertEqual(decision, .skip)
    }

    func testStepRequiredOverridesDeterministicSignals() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(nil),
            step: makeStep(requiresCritic: .required, criteria: [.buildSucceeds]),
            heuristic: (writtenFiles: false, substantial: false, complexity: .routine),
            classifierOverride: false
        )

        XCTAssertEqual(decision, .run)
    }

    func testDeterministicOnlyWhenOnlyMechanicalCriteriaRemain() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(nil),
            step: makeStep(
                requiresCritic: .optional,
                criteria: [.buildSucceeds, .fileExists(path: "/tmp/example")]
            ),
            heuristic: (writtenFiles: false, substantial: false, complexity: .routine),
            classifierOverride: false
        )

        XCTAssertEqual(decision, .deterministicOnly)
    }

    func testHeuristicRunsWhenNoHigherPrecedenceSignalExists() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(nil),
            step: makeStep(requiresCritic: .optional, criteria: [.prose("done")]),
            heuristic: (writtenFiles: false, substantial: true, complexity: .routine),
            classifierOverride: false
        )

        XCTAssertEqual(decision, .run)
    }

    func testClassifierOverrideRunsUnlessSkillExplicitlySkips() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(nil),
            step: nil,
            heuristic: (writtenFiles: false, substantial: false, complexity: .routine),
            classifierOverride: true
        )

        XCTAssertEqual(decision, .run)
    }

    func testClassifierOverrideCannotOverrideSkillSkip() {
        let decision = CriticPolicyResolver.resolve(
            skill: makeSkill(.skip),
            step: nil,
            heuristic: (writtenFiles: true, substantial: true, complexity: .highStakes),
            classifierOverride: true
        )

        XCTAssertEqual(decision, .skip)
    }
}
