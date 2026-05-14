import XCTest
@testable import Merlin

final class VerificationFabPolicyTests: XCTestCase {

    func test_completionGate_requiresAllElectricalAndFabricationConditions() {
        let evaluator = KiCadCompletionGateEvaluator()

        let failed = evaluator.evaluate(
            CompletionGateInputs(
                unroutedNets: 1,
                ercViolations: 0,
                drcViolations: 0,
                parityPassed: true,
                fabValidationPassed: true,
                requiredSimulationPassed: true
            )
        )
        XCTAssertEqual(failed, .blocked)

        let passed = evaluator.evaluate(
            CompletionGateInputs(
                unroutedNets: 0,
                ercViolations: 0,
                drcViolations: 0,
                parityPassed: true,
                fabValidationPassed: true,
                requiredSimulationPassed: true
            )
        )
        XCTAssertEqual(passed, .complete)
    }

    func test_spicePolicy_warnsWhenRequiredModelLegallyUnavailableButGenericExists() {
        let policy = SPICEModelCachePolicy()
        let decision = policy.evaluateModelAvailability(
            required: true,
            manufacturerModelAvailable: false,
            legallyObtainable: false,
            genericSubstituteAvailable: true
        )

        XCTAssertEqual(decision.severity, .warning)
        XCTAssertEqual(decision.status, nil)
    }

    func test_spicePolicy_blocksWhenRequiredModelAndNoSubstitute() {
        let policy = SPICEModelCachePolicy()
        let decision = policy.evaluateModelAvailability(
            required: true,
            manufacturerModelAvailable: false,
            legallyObtainable: false,
            genericSubstituteAvailable: false
        )

        XCTAssertEqual(decision.severity, .blocked)
        XCTAssertEqual(decision.status, .blockedSimulation)
    }

    func test_visualQA_containsRequiredScopeChecks() {
        let evaluator = VisualQAEvaluator()
        let checks = Set(evaluator.requiredChecks.map(\.rawValue))

        XCTAssertTrue(checks.contains("silkscreen_overlap"))
        XCTAssertTrue(checks.contains("refdes_legibility"))
        XCTAssertTrue(checks.contains("polarity_and_pin1_markings"))
        XCTAssertTrue(checks.contains("connector_orientation"))
        XCTAssertTrue(checks.contains("test_point_accessibility"))
        XCTAssertTrue(checks.contains("layer_view_sanity"))
    }

    func test_visualQACannotOverrideFailedElectricalGates() {
        let evaluator = VisualQAEvaluator()
        let result = evaluator.evaluate(
            findings: [],
            electricalGatesPassed: false
        )

        XCTAssertFalse(result.releaseAllowed)
        XCTAssertEqual(result.status, .blocked)
    }

    func test_stepPolicy_selectsDefinedSourcePriorityPaths() {
        let policy = ThreeDModelSourcingPolicy()

        XCTAssertEqual(policy.selectSource(kicadModelAvailable: true, vendorModelAvailable: true, userRequiresModel: false), .kicadModel)
        XCTAssertEqual(policy.selectSource(kicadModelAvailable: false, vendorModelAvailable: true, userRequiresModel: false), .vendorModel)
        XCTAssertEqual(policy.selectSource(kicadModelAvailable: false, vendorModelAvailable: false, userRequiresModel: true), .generatedEnvelope)
        XCTAssertEqual(policy.selectSource(kicadModelAvailable: false, vendorModelAvailable: false, userRequiresModel: false), .omittedWithReport)
    }

    func test_fabPackageValidator_requiresCoreOutputs() {
        let policy = FabricationProfilePolicy.default
        let validator = FabPackageValidator()

        let outputs = [
            "gerbers", "drills", "drill_map", "bom", "pnp", "drawings", "verification_report",
        ]
        let valid = validator.validate(outputKinds: outputs, requiredKinds: policy.requiredOutputKinds)
        XCTAssertTrue(valid.isValid)

        let invalid = validator.validate(outputKinds: ["gerbers", "drills"], requiredKinds: policy.requiredOutputKinds)
        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(invalid.missingKinds.contains("verification_report"))
    }
}
