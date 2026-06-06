import XCTest
@testable import Merlin

final class SPICEOptimizationTests: XCTestCase {
    func testSPICEScenarioRequiresCircuitPathAnalysesAndMeasurementEnvelopes() {
        let scenario = SPICESimulationScenario(
            scenarioId: "amp-output-stage-ac",
            designId: "amp-low-voltage",
            circuitPath: "",
            analyses: [],
            requiredModelRefs: ["MJ15003G.lib"],
            measurementEnvelopes: []
        )

        let result = SPICEScenarioValidator().validate(scenario)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.code == "SPICE_CIRCUIT_PATH_REQUIRED" })
        XCTAssertTrue(result.issues.contains { $0.code == "SPICE_ANALYSIS_REQUIRED" })
        XCTAssertTrue(result.issues.contains { $0.code == "SPICE_MEASUREMENT_ENVELOPE_REQUIRED" })
    }

    func testModelResolverBlocksRequiredUnapprovedGenericSubstitute() {
        let result = SPICEModelResolver().resolve(
            requiredModels: ["MJ15003G"],
            availableModels: [SPICEModelRecord(modelRef: "GENERIC_NPN_POWER", legallyUsable: true, isGeneric: true)],
            approvals: []
        )

        XCTAssertFalse(result.canSimulate)
        XCTAssertTrue(result.issues.contains { $0.code == "SPICE_MODEL_GENERIC_APPROVAL_REQUIRED" })
    }

    func testNgspiceMeasurementParserReadsScalarMeasurements() throws {
        let report = try NgspiceMeasurementParser().parse("""
        gain_db = 24.8
        output_power_w = 25.6
        vout_rms = 3.49091e+00 from=  1.00000e-02 to=  2.00000e-02
        thd_percent = 0.72
        """)

        XCTAssertEqual(report.measurements["gain_db"] ?? .nan, 24.8, accuracy: 0.001)
        XCTAssertEqual(report.measurements["output_power_w"] ?? .nan, 25.6, accuracy: 0.001)
        XCTAssertEqual(report.measurements["vout_rms"] ?? .nan, 3.49091, accuracy: 0.00001)
        XCTAssertEqual(report.measurements["thd_percent"] ?? .nan, 0.72, accuracy: 0.001)
    }

    func testMeasurementEnvelopeBlocksOutOfRangeResults() {
        let report = SPICEMeasurementReport(measurements: ["output_power_w": 18.0, "thd_percent": 0.8])
        let envelopes = [
            SPICEMeasurementEnvelope(name: "output_power_w", min: 24.0, max: 28.0),
            SPICEMeasurementEnvelope(name: "thd_percent", min: nil, max: 1.0),
        ]

        let result = SPICEMeasurementEnvelopeEvaluator().evaluate(report: report, envelopes: envelopes)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failures.first?.measurement, "output_power_w")
    }

    func testSimulationRepairPlannerOnlyReturnsSupportedParameterActions() {
        let plan = SPICESimulationRepairPlanner().plan(
            failures: [SPICEMeasurementFailure(measurement: "output_power_w", actual: 18.0, expected: "24.0...28.0")],
            topology: .singleEndedClassA
        )

        XCTAssertEqual(plan.patches.first?.repairClass, .parameterAdjustment)
        XCTAssertEqual(plan.patches.first?.parameterName, "bias_current")
        XCTAssertFalse(plan.requiresTopologyChange)
    }

    func testFixedTopologyOptimizerIsBoundedAndRejectsTopologyChanges() {
        let optimizer = FixedTopologySPICEOptimizer(maxIterations: 3)
        let result = optimizer.optimize(
            topology: .singleEndedClassA,
            parameters: [SPICEParameter(name: "bias_current", value: 1.2, min: 1.0, max: 2.5)],
            proposals: [
                SPICEOptimizationProposal(parameterName: "bias_current", value: 1.5, changesTopology: false),
                SPICEOptimizationProposal(parameterName: "output_transformer", value: 1.0, changesTopology: true),
                SPICEOptimizationProposal(parameterName: "bias_current", value: 2.0, changesTopology: false),
                SPICEOptimizationProposal(parameterName: "bias_current", value: 2.2, changesTopology: false),
            ]
        )

        XCTAssertEqual(result.applied.count, 3)
        XCTAssertTrue(result.rejected.contains { $0.code == "SPICE_TOPOLOGY_CHANGE_UNSUPPORTED" })
        XCTAssertTrue(result.rejected.contains { $0.code == "SPICE_OPTIMIZATION_ITERATION_LIMIT" })
        XCTAssertEqual(result.finalParameters["bias_current"] ?? .nan, 2.2, accuracy: 0.001)
    }
}
