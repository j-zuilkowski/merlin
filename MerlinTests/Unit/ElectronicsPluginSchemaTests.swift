import XCTest
@testable import Merlin

final class ElectronicsPluginSchemaTests: XCTestCase {
    func testElectronicsPluginOwnsCatalogProviderSettingsSchema() {
        let schema = ElectronicsRuntimePlugin.settingsSchema

        XCTAssertEqual(schema.namespace, "plugin.electronics")
        XCTAssertTrue(schema.fields.contains {
            $0.key == "catalog_provider_mouser_enabled" && $0.defaultValue == .boolean(true)
        })
        XCTAssertTrue(schema.fields.contains {
            $0.key == "catalog_provider_digikey_enabled" && $0.defaultValue == .boolean(true)
        })
        XCTAssertTrue(schema.fields.contains {
            $0.key == "catalog_provider_nexar_enabled" && $0.defaultValue == .boolean(false)
        })
        XCTAssertTrue(schema.fields.contains {
            $0.key == "catalog_provider_trustedparts_enabled" && $0.defaultValue == .boolean(false)
        })
        XCTAssertTrue(schema.fields.contains {
            $0.key == "catalog_provider_onsemi_enabled" && $0.defaultValue == .boolean(false)
        })
        XCTAssertTrue(schema.fields.contains {
            $0.key == "catalog_provider_vendor_feed_enabled" && $0.defaultValue == .boolean(true)
        })
        let datasheetPathField = schema.fields.first { $0.key == "datasheet_cache_directory" }
        XCTAssertEqual(datasheetPathField?.kind, .path)
        XCTAssertEqual(datasheetPathField?.defaultValue, .string(ElectronicsRuntimePlugin.defaultDatasheetCacheDirectory.path))
        let datasheetTTLField = schema.fields.first { $0.key == "datasheet_cache_revalidate_after_seconds" }
        XCTAssertEqual(datasheetTTLField?.kind, .integer)
        XCTAssertEqual(datasheetTTLField?.defaultValue, .integer(604_800))
    }

    func testDesignIntentAndCircuitIRRoundTrip() throws {
        XCTAssertRoundTrips(validApprovedIntent())
        XCTAssertRoundTrips(validCircuitIR())
    }

    func testNaturalLanguageDesignIntentDefaultsToDraftApproval() {
        let intent = DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: .naturalLanguage,
            requirements: [],
            assumptions: [],
            unresolvedDecisions: [],
            boards: [],
            safetyProfile: SafetyProfile(isolationRequired: false, creepageMm: 0.0, notes: []),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: false, spiceRequired: true)
        )

        XCTAssertEqual(intent.approval.status, .draft)
    }

    func testValidatorBlocksUnapprovedIntentAndUnresolvedDecisions() {
        var intent = validApprovedIntent()
        intent.approval = DesignApproval(status: .draft)
        intent.unresolvedDecisions = [
            UnresolvedDecision(id: "ud-1", question: "Select output transistor", blocking: true),
        ]

        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: intent,
            circuitIR: validCircuitIR()
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "DESIGN_INTENT_NOT_APPROVED"))
        XCTAssertTrue(result.contains(code: "UNRESOLVED_DECISION"))
    }

    func testValidatorBlocksComponentWithoutEvidence() {
        var ir = validCircuitIR()
        ir.components[0].sourceEvidence = []

        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: validApprovedIntent(),
            circuitIR: ir
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "COMPONENT_EVIDENCE_MISSING"))
    }

    func testValidatorBlocksInvalidPinReferencesAndNetEndpoints() {
        var ir = validCircuitIR()
        ir.components[0].pins[0].componentRefdes = "U404"
        ir.nets[0].endpoints.append(CircuitNetEndpoint(componentRefdes: "Q404", pinNumber: "99"))

        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: validApprovedIntent(),
            circuitIR: ir
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "INVALID_PIN_REFERENCE"))
        XCTAssertTrue(result.contains(code: "INVALID_NET_ENDPOINT"))
    }

    func testValidatorBlocksMissingSafetyDomain() {
        var ir = validCircuitIR()
        ir.nets[0].safetyDomain = ""

        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: validApprovedIntent(),
            circuitIR: ir
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "SAFETY_DOMAIN_MISSING"))
    }

    func testInvalidCircuitIRBlocksBeforeKiCadMutation() {
        var ir = validCircuitIR()
        ir.components.removeAll()

        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: validApprovedIntent(),
            circuitIR: ir
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.blocksKiCadMutation)
    }

    func testGenericMultiboardDecompositionBlocksMergedMainsAndLowVoltageDomains() {
        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: mixedDomainMergedBoardIntent(),
            circuitIR: mixedDomainCircuitIR(boardId: "single_board")
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "MULTIBOARD_DECOMPOSITION_REQUIRED"))
        XCTAssertTrue(result.contains(code: "INTERBOARD_CONNECTOR_REQUIRED"))
        XCTAssertTrue(result.contains(code: "BOARD_VERIFICATION_PLAN_REQUIRED"))
    }

    func testGenericMultiboardDecompositionPassesSeparatedDomainEvidence() {
        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: separatedDomainIntent(),
            circuitIR: mixedDomainCircuitIR(boardId: "low_voltage_control")
        )

        XCTAssertTrue(result.isValid, result.issues.map(\.message).joined(separator: "\n"))
    }

    func testCircuitIRBoardIDMustReferenceDesignIntentBoard() {
        let result = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: separatedDomainIntent(),
            circuitIR: mixedDomainCircuitIR(boardId: "unknown_board")
        )

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.contains(code: "CIRCUIT_IR_BOARD_UNKNOWN"))
    }

    private func validApprovedIntent() -> DesignIntent {
        DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: .userAuthored,
            approval: DesignApproval(
                status: .approved,
                approvedBy: "jon",
                approvedAt: "2026-05-29T13:00:00Z"
            ),
            requirements: [
                Requirement(id: "req-1", text: "Low-voltage audio board for 25W Class-A guitar amplifier", priority: "must"),
            ],
            assumptions: [],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(id: "amp_low_voltage_audio", title: "Low Voltage Audio Board", safetyDomain: "isolated_secondary"),
            ],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 6.4, notes: ["Mains power supply is a separate board"]),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: false, spiceRequired: true)
        )
    }

    private func validCircuitIR() -> CircuitIR {
        CircuitIR(
            designId: "amp-low-voltage",
            boardId: "amp_low_voltage_audio",
            components: [
                CircuitComponent(
                    refdes: "Q1",
                    role: "Class-A output transistor",
                    selectedSymbol: "Device:Q_NPN_BCE",
                    selectedFootprint: "Package_TO_SOT_THT:TO-3P-3_Vertical",
                    manufacturerPartNumber: "MJ15003G",
                    sourceEvidence: [
                        SourceEvidence(kind: "datasheet", reference: "onsemi MJ15003G datasheet"),
                    ],
                    pins: [
                        CircuitPin(componentRefdes: "Q1", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "B", footprintPad: "1"),
                        CircuitPin(componentRefdes: "Q1", pinNumber: "2", canonicalName: "C", electricalType: "power", symbolPin: "C", footprintPad: "2"),
                    ]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "DRV_OUT",
                    role: "driver output",
                    endpoints: [
                        CircuitNetEndpoint(componentRefdes: "Q1", pinNumber: "1"),
                    ],
                    netClass: "audio_signal",
                    safetyDomain: "isolated_secondary"
                ),
            ],
            constraints: [
                CircuitConstraint(kind: "thermal", target: "Q1", value: "external heatsink required"),
            ],
            verificationScenarios: [
                VerificationScenario(id: "erc-basic", kind: "erc", expectation: "No blocking ERC errors"),
            ]
        )
    }

    private func mixedDomainMergedBoardIntent() -> DesignIntent {
        DesignIntent(
            designId: "generic_mixed_power_controller",
            title: "Generic mixed mains and low-voltage controller",
            origin: .naturalLanguage,
            approval: DesignApproval(status: .approved, approvedBy: "test", approvedAt: "2026-06-06T00:00:00Z"),
            requirements: [
                Requirement(id: "req-1", text: "Design a board with mains input, transformer primary, isolated low-voltage controller, and signal output.", priority: "must"),
            ],
            assumptions: [],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(id: "single_board", title: "Merged power and control board", safetyDomain: "mains_and_low_voltage"),
            ],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 6.4, notes: ["Mains input and isolated low-voltage control are both required."]),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: false)
        )
    }

    private func separatedDomainIntent() -> DesignIntent {
        DesignIntent(
            designId: "generic_mixed_power_controller",
            title: "Generic mixed mains and low-voltage controller",
            origin: .naturalLanguage,
            approval: DesignApproval(status: .approved, approvedBy: "test", approvedAt: "2026-06-06T00:00:00Z"),
            requirements: [
                Requirement(id: "req-1", text: "Design a mains transformer supply and isolated low-voltage controller as separate safety domains.", priority: "must"),
            ],
            assumptions: [
                Assumption(id: "assume-1", text: "Hazardous mains and isolated low-voltage circuitry are separate board domains.", rationale: "Isolation boundary and review requirements differ."),
            ],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(
                    id: "mains_power",
                    title: "Mains transformer board",
                    safetyDomain: "mains_primary",
                    verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: false),
                    interBoardConnectors: [
                        InterBoardConnectorIntent(id: "JSEC", targetBoardId: "low_voltage_control", signalRole: "isolated secondary handoff"),
                    ]
                ),
                BoardIntent(
                    id: "low_voltage_control",
                    title: "Low voltage control board",
                    safetyDomain: "isolated_secondary",
                    verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true),
                    interBoardConnectors: [
                        InterBoardConnectorIntent(id: "JPRI", targetBoardId: "mains_power", signalRole: "isolated secondary handoff"),
                    ]
                ),
            ],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 6.4, notes: ["Mains and isolated secondary domains are separated."]),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true)
        )
    }

    private func mixedDomainCircuitIR(boardId: String) -> CircuitIR {
        var ir = validCircuitIR()
        ir.designId = "generic_mixed_power_controller"
        ir.boardId = boardId
        ir.nets[0].safetyDomain = "isolated_secondary"
        return ir
    }

    private func XCTAssertRoundTrips<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(T.self, from: data)
            XCTAssertEqual(decoded, value, file: file, line: line)
        } catch {
            XCTFail("Round-trip failed: \(error)", file: file, line: line)
        }
    }
}
