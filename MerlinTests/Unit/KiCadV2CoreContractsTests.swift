import XCTest
@testable import Merlin

@MainActor
final class KiCadV2CoreContractsTests: XCTestCase {

    override func tearDown() {
        ToolRegistry.shared.reset()
        super.tearDown()
    }

    func test_statusWireValues_matchArchitectureContract() {
        XCTAssertEqual(KiCadStatus.complete.rawValue, "COMPLETE")
        XCTAssertEqual(KiCadStatus.blocked.rawValue, "BLOCKED")
        XCTAssertEqual(KiCadStatus.blockedInputQuality.rawValue, "BLOCKED_INPUT_QUALITY")
        XCTAssertEqual(KiCadStatus.blockedVersion.rawValue, "BLOCKED_VERSION")
        XCTAssertEqual(KiCadStatus.blockedSimulation.rawValue, "BLOCKED_SIMULATION")
        XCTAssertEqual(KiCadStatus.blockedTooling.rawValue, "BLOCKED_TOOLING")
        XCTAssertEqual(KiCadStatus.blockedLibrary.rawValue, "BLOCKED_LIBRARY")
        XCTAssertEqual(KiCadStatus.blockedEngineeringDecision.rawValue, "BLOCKED_ENGINEERING_DECISION")
        XCTAssertEqual(KiCadStatus.inProgress.rawValue, "IN_PROGRESS")
    }

    func test_jlcpcb2LayerDefault_isFirstMVPProfile() {
        let profile = BoardProfile.jlcpcb2LayerDefault

        XCTAssertEqual(profile.id, "jlcpcb_2layer_default")
        XCTAssertEqual(profile.fabricator, "JLCPCB")
        XCTAssertEqual(profile.layerCount, 2)
        XCTAssertEqual(profile.minTraceMm, 0.1524, accuracy: 0.0001)
        XCTAssertEqual(profile.minClearanceMm, 0.1524, accuracy: 0.0001)
        XCTAssertEqual(profile.minViaDrillMm, 0.30, accuracy: 0.0001)
        XCTAssertEqual(profile.minViaPadMm, 0.60, accuracy: 0.0001)
        XCTAssertEqual(profile.copperToEdgeMm, 0.25, accuracy: 0.0001)
    }

    func test_ethernetDifferentialPairDefaults_areQuantified() {
        let fast = DifferentialPairRule.ethernet100BaseTX
        XCTAssertEqual(fast.id, "ethernet_100base_tx")
        XCTAssertEqual(fast.intraPairSkewMaxMm, 10.0, accuracy: 0.001)
        XCTAssertNil(fast.pairToPairSkewMaxMm)
        XCTAssertEqual(fast.differentialImpedanceOhms, 100.0, accuracy: 0.001)

        let gigabit = DifferentialPairRule.ethernet1000BaseT
        XCTAssertEqual(gigabit.id, "ethernet_1000base_t")
        XCTAssertEqual(gigabit.intraPairSkewMaxMm, 5.0, accuracy: 0.001)
        XCTAssertEqual(gigabit.pairToPairSkewMaxMm, 25.0, accuracy: 0.001)
        XCTAssertEqual(gigabit.differentialImpedanceOhms, 100.0, accuracy: 0.001)
    }

    func test_spicePolicy_warnsForLegallyUnobtainableRequiredModel_whenGenericSubstituteAvailable() {
        let policy = KiCadSimulationPolicy.default
        let decision = policy.evaluateModelAvailability(
            SPICEModelAvailability(
                required: true,
                manufacturerModelAvailable: false,
                legallyObtainable: false,
                genericSubstituteAvailable: true,
                profileAllowsGenericEquivalence: false,
                userApprovedGenericDowngrade: false
            )
        )

        XCTAssertEqual(decision.severity, .warning)
        XCTAssertEqual(decision.code, "SPICE_MODEL_GENERIC_SUBSTITUTE_SUGGESTED")
        XCTAssertTrue(decision.requiresUserApproval)
        XCTAssertTrue(decision.message.contains("generic"))
    }

    func test_spicePolicy_blocksRequiredModelOnlyWhenNoLegalOrGenericModelExists() {
        let policy = KiCadSimulationPolicy.default
        let decision = policy.evaluateModelAvailability(
            SPICEModelAvailability(
                required: true,
                manufacturerModelAvailable: false,
                legallyObtainable: false,
                genericSubstituteAvailable: false,
                profileAllowsGenericEquivalence: false,
                userApprovedGenericDowngrade: false
            )
        )

        XCTAssertEqual(decision.severity, .blocked)
        XCTAssertEqual(decision.status, .blockedSimulation)
    }

    func test_handDrawnSketch_isConceptualUnlessItMeetsAuthoritativeThresholds() {
        let decision = HandDrawnSchematicPolicy.classify(
            SchematicInputAssessment(
                kind: .handDrawn,
                dpi: 300,
                overallConfidence: 0.80,
                criticalFieldConfidence: 0.70,
                ambiguousNets: 4,
                unknownComponents: 2
            )
        )

        XCTAssertEqual(decision.disposition, .conceptualOnly)
        XCTAssertEqual(decision.status, .blockedInputQuality)
        XCTAssertFalse(decision.mayProceedToPCBSynthesis)
        XCTAssertTrue(decision.message.contains("conceptual"))
    }

    func test_visualQAProfile_containsPositiveScopeChecks() {
        let checks = Set(VisualQAProfile.default.requiredChecks.map(\.rawValue))

        XCTAssertTrue(checks.contains("silkscreen_overlap"))
        XCTAssertTrue(checks.contains("refdes_legibility"))
        XCTAssertTrue(checks.contains("polarity_and_pin1_markings"))
        XCTAssertTrue(checks.contains("connector_orientation"))
        XCTAssertTrue(checks.contains("front_panel_label_consistency"))
        XCTAssertTrue(checks.contains("test_point_accessibility"))
        XCTAssertTrue(checks.contains("keepout_and_enclosure_visibility"))
        XCTAssertTrue(checks.contains("component_orientation_anomalies"))
        XCTAssertTrue(checks.contains("layer_view_sanity"))
    }

    func test_kicadToolDefinitions_includeRequiredCoreToolNames() {
        let names = Set(KiCadToolDefinitions.all.map { $0.function.name })

        for requiredName in KiCadToolDefinitions.requiredToolNames {
            XCTAssertTrue(names.contains(requiredName), "Missing KiCad tool definition: \(requiredName)")
        }
    }

    func test_kicadIngestSchematicSchema_requiresSourceArtifactTypeAndProfile() throws {
        let tool = try XCTUnwrap(KiCadToolDefinitions.all.first { $0.function.name == "kicad_ingest_schematic" })
        let required = Set(tool.function.parameters.required ?? [])

        XCTAssertEqual(tool.type, "function")
        XCTAssertTrue(required.contains("source_artifact_path"))
        XCTAssertTrue(required.contains("source_type"))
        XCTAssertTrue(required.contains("extraction_profile"))
        XCTAssertNotNil(tool.function.parameters.properties?["source_artifact_path"])
        XCTAssertNotNil(tool.function.parameters.properties?["source_type"])
        XCTAssertNotNil(tool.function.parameters.properties?["extraction_profile"])
    }

    func test_registerBuiltins_registersKiCadTools() {
        ToolRegistry.shared.registerBuiltins()

        for requiredName in KiCadToolDefinitions.requiredToolNames {
            XCTAssertTrue(ToolRegistry.shared.contains(named: requiredName), "ToolRegistry missing: \(requiredName)")
        }
    }
}
