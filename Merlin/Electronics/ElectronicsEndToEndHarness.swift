import Foundation

enum ElectronicsEndToEndStatus: String, Codable, Sendable, Equatable {
    case blocked = "BLOCKED"
    case schematicVerified = "SCHEMATIC_VERIFIED"
    case pcbVerified = "PCB_VERIFIED"
    case fabReady = "FAB_READY"
    case complete = "COMPLETE"
}

enum ElectronicsEndToEndSPICEStatus: String, Codable, Sendable, Equatable {
    case notRequired = "NOT_REQUIRED"
    case missing = "MISSING"
    case blocked = "BLOCKED"
    case passed = "PASSED"
}

struct ElectronicsEndToEndSPICEEvidence: Codable, Sendable, Equatable {
    var scenario: SPICESimulationScenario
    var availableModels: [SPICEModelRecord]
    var ngspiceOutput: String
    var approvals: [ElectronicsApprovalKind]
    var modelRecordsProvided: Bool?
    var circuitDeckProvided: Bool?
}

struct ElectronicsEndToEndEvidence: Codable, Sendable, Equatable {
    var ercReports: [KiCadERCReport]
    var pcb: PCBVerificationEvidence?
    var spice: ElectronicsEndToEndSPICEEvidence?
    var fabrication: FabricationReleaseEvidence
    var approvals: [ElectronicsApprovalKind]

    static let none = ElectronicsEndToEndEvidence(
        ercReports: [],
        pcb: nil,
        spice: nil,
        fabrication: FabricationReleaseEvidence(
            schematicVerified: false,
            pcbVerified: false,
            ercReportPath: nil,
            drcReportPath: nil,
            bomValidation: NormalizedBOMValidation(isValid: false, issues: [
                ElectronicsSchemaIssue(code: "BOM_MISSING", message: "Normalized BOM evidence is missing."),
            ]),
            vendorAvailability: VendorAvailabilityDiagnostics(isOrderable: false, issues: [
                ElectronicsSchemaIssue(code: "BOM_VENDOR_AVAILABILITY_MISSING", message: "Vendor availability evidence is missing."),
            ]),
            fabricationValidation: FabricationEvidenceValidation(isValid: false, missingKinds: [], issues: [
                ElectronicsSchemaIssue(code: "FAB_OUTPUTS_MISSING", message: "Fabrication output evidence is missing."),
            ]),
            profileValidation: FabricatorProfileValidation(isValid: false, issues: [
                ElectronicsSchemaIssue(code: "FAB_PROFILE_MISSING", message: "Fabricator profile evidence is missing."),
            ]),
            verificationReportPath: nil,
            releasePackagePath: nil,
            approvals: []
        ),
        approvals: []
    )

    static let ampLowVoltageVerified = ElectronicsEndToEndEvidence(
        ercReports: [KiCadERCReport(violations: [])],
        pcb: .complete,
        spice: ElectronicsEndToEndSPICEEvidence(
            scenario: SPICESimulationScenario(
                scenarioId: "amp-low-voltage-output-stage",
                designId: "amp_low_voltage_audio",
                circuitPath: "/tmp/amp-low-voltage/output-stage.cir",
                analyses: ["tran", "ac"],
                requiredModelRefs: ["MJ15003G"],
                measurementEnvelopes: [
                    SPICEMeasurementEnvelope(name: "output_power_w", min: 24.0, max: 28.0),
                    SPICEMeasurementEnvelope(name: "thd_percent", min: nil, max: 1.0),
                ]
            ),
            availableModels: [
                SPICEModelRecord(modelRef: "MJ15003G", legallyUsable: true, isGeneric: false),
            ],
            ngspiceOutput: """
            output_power_w = 25.1
            thd_percent = 0.72
            """,
            approvals: [],
            modelRecordsProvided: nil,
            circuitDeckProvided: nil
        ),
        fabrication: .fabReadyFixture,
        approvals: [.highStakesSignoff]
    )

    static let mainsPowerCADVerified = ElectronicsEndToEndEvidence(
        ercReports: [KiCadERCReport(violations: [])],
        pcb: .complete,
        spice: nil,
        fabrication: .fabReadyFixture,
        approvals: [.highStakesSignoff]
    )
}

struct ElectronicsEndToEndInput: Sendable {
    var designIntent: DesignIntent?
    var circuitIR: CircuitIR?
    var outputDirectory: URL
    var evidence: ElectronicsEndToEndEvidence
    var approvals: [ElectronicsApprovalKind]?

    init(
        designIntent: DesignIntent?,
        circuitIR: CircuitIR?,
        outputDirectory: URL,
        evidence: ElectronicsEndToEndEvidence,
        approvals: [ElectronicsApprovalKind]? = nil
    ) {
        self.designIntent = designIntent
        self.circuitIR = circuitIR
        self.outputDirectory = outputDirectory
        self.evidence = evidence
        self.approvals = approvals
    }
}

struct ElectronicsEndToEndWorkflowRequest: Codable, Sendable, Equatable {
    var jobId: String
    var designIntentPath: String
    var circuitIrPath: String
    var outputDirectory: String
    var evidence: ElectronicsEndToEndEvidence?
    var evidenceArtifacts: ElectronicsEvidenceArtifactPaths?
    var approvals: [ElectronicsApprovalKind]?
}

struct ElectronicsEndToEndResult: Codable, Sendable, Equatable {
    var status: ElectronicsEndToEndStatus
    var isComplete: Bool
    var schematicStatus: SchematicVerificationStatus?
    var pcbStatus: PCBVerificationStatus?
    var spiceStatus: ElectronicsEndToEndSPICEStatus
    var fabricationStatus: FabricationReleaseStatus
    var missingEvidence: [String]
    var diagnostics: [ElectronicsSchemaIssue]
    var certifiesSafety: Bool
}

struct ElectronicsEndToEndHarness: Sendable {
    func run(_ input: ElectronicsEndToEndInput) throws -> ElectronicsEndToEndResult {
        var missing: [String] = []
        var diagnostics: [ElectronicsSchemaIssue] = []
        let grantedApprovals = input.approvals ?? input.evidence.approvals

        guard let intent = input.designIntent else {
            return blocked(
                missing: ["design_intent", "circuit_ir", "SCHEMATIC_VERIFIED"],
                diagnostics: diagnostics
            )
        }

        let safety = HighStakesSafetyPolicy().evaluate(intent: intent, grantedApprovals: grantedApprovals)
        diagnostics.append(contentsOf: safety.issues)
        if safety.requiredApprovals.contains(.highStakesSignoff),
           !grantedApprovals.contains(.highStakesSignoff) {
            missing.append("high_stakes_signoff")
        }

        guard let circuitIR = input.circuitIR else {
            missing.append("circuit_ir")
            missing.append("SCHEMATIC_VERIFIED")
            return blocked(missing: missing, diagnostics: diagnostics, certifiesSafety: safety.certifiesSafety)
        }

        let schema = ElectronicsSchemaValidator.validateReadyForKiCadMutation(
            designIntent: intent,
            circuitIR: circuitIR
        )
        diagnostics.append(contentsOf: schema.issues)

        let resolver = resolver(for: circuitIR)
        let resolutions = circuitIR.components.map { resolver.resolve(component: $0, pcbBound: true) }
        for resolution in resolutions where !resolution.isResolved {
            diagnostics.append(contentsOf: resolution.issues.map {
                ElectronicsSchemaIssue(code: $0.code, message: $0.message)
            })
        }

        let schematicResult = try schematicVerification(
            schemaPassed: schema.isValid,
            circuitIR: circuitIR,
            outputDirectory: input.outputDirectory,
            ercReports: input.evidence.ercReports,
            resolverEvidence: resolutions
        )
        diagnostics.append(contentsOf: schematicResult.diagnostics)
        if schematicResult.status != .schematicVerified {
            missing.append("SCHEMATIC_VERIFIED")
            missing.append(contentsOf: schematicResult.missingEvidence.map(\.rawValue))
        }

        let pcbResult = pcbVerification(
            schematicVerified: schematicResult.status == .schematicVerified,
            evidence: input.evidence.pcb
        )
        diagnostics.append(contentsOf: pcbResult.diagnostics)
        if pcbResult.status != .pcbVerified {
            missing.append("PCB_VERIFIED")
            missing.append(contentsOf: pcbResult.missingEvidence.map(\.rawValue))
        }

        let spice = try spiceVerification(intent: intent, evidence: input.evidence.spice)
        diagnostics.append(contentsOf: spice.diagnostics)
        missing.append(contentsOf: spice.missingEvidence)

        let upstreamVerified = schematicResult.status == .schematicVerified
            && pcbResult.status == .pcbVerified
            && spice.statusIsPassing
            && safety.issues.isEmpty
            && schema.isValid
            && resolutions.allSatisfy(\.isResolved)

        let fabrication = upstreamVerified
            ? FabricationReleaseGate().evaluate(input.evidence.fabrication)
            : FabricationReleaseEvaluation(
                status: .blocked,
                canPackageRelease: false,
                isComplete: false,
                missingEvidence: ["upstream_verification"],
                diagnostics: []
            )
        diagnostics.append(contentsOf: fabrication.diagnostics)
        missing.append(contentsOf: fabrication.missingEvidence)

        let normalizedMissing = stableUnique(missing)
        let releaseOnlyMissing = fabrication.status == .fabReady
            && diagnostics.isEmpty
            && normalizedMissing.allSatisfy { $0 == "release_package" || $0 == "release_approval" }

        if (!normalizedMissing.isEmpty && !releaseOnlyMissing) || !diagnostics.isEmpty {
            return ElectronicsEndToEndResult(
                status: .blocked,
                isComplete: false,
                schematicStatus: schematicResult.status,
                pcbStatus: pcbResult.status,
                spiceStatus: spice.status,
                fabricationStatus: fabrication.status,
                missingEvidence: normalizedMissing,
                diagnostics: stableIssues(diagnostics),
                certifiesSafety: safety.certifiesSafety
            )
        }

        let status: ElectronicsEndToEndStatus
        if fabrication.isComplete {
            status = .complete
        } else if fabrication.status == .fabReady {
            status = .fabReady
        } else if pcbResult.status == .pcbVerified {
            status = .pcbVerified
        } else {
            status = .schematicVerified
        }

        return ElectronicsEndToEndResult(
            status: status,
            isComplete: status == .complete,
            schematicStatus: schematicResult.status,
            pcbStatus: pcbResult.status,
            spiceStatus: spice.status,
            fabricationStatus: fabrication.status,
            missingEvidence: normalizedMissing,
            diagnostics: stableIssues(diagnostics),
            certifiesSafety: safety.certifiesSafety
        )
    }

    private func schematicVerification(
        schemaPassed: Bool,
        circuitIR: CircuitIR,
        outputDirectory: URL,
        ercReports: [KiCadERCReport],
        resolverEvidence: [KiCadLibraryPinResolution]
    ) throws -> SchematicVerificationResult {
        guard schemaPassed else {
            return SchematicVerificationGate().evaluate(.missingEvidence)
        }

        let materialized = try CircuitIRKiCadSchematicMaterializer().materialize(
            circuitIR: circuitIR,
            outputDirectory: outputDirectory
        )
        let schematicText = try String(contentsOf: materialized.schematicURL, encoding: .utf8)
        let schematic = try KiCadSchematicParser().parse(schematicText)
        let parity = CircuitIRSchematicParityChecker().check(circuitIR: circuitIR, schematic: schematic)
        guard parity.isValid else {
            return SchematicVerificationResult(
                status: .blocked,
                report: SchematicVerificationReport(
                    status: .blocked,
                    statusCode: SchematicVerificationStatus.blocked.rawValue,
                    missingEvidence: [],
                    blockingERCViolations: [],
                    diagnostics: parity.issues
                ),
                missingEvidence: [],
                diagnostics: parity.issues
            )
        }

        let realism = SchematicRealismValidator().validate(circuitIR: circuitIR, schematic: schematic)
        guard realism.isValid else {
            return SchematicVerificationResult(
                status: .blocked,
                report: SchematicVerificationReport(
                    status: .blocked,
                    statusCode: SchematicVerificationStatus.blocked.rawValue,
                    missingEvidence: [],
                    blockingERCViolations: [],
                    diagnostics: realism.issues
                ),
                missingEvidence: [],
                diagnostics: realism.issues
            )
        }

        let ercLoop = ERCRepairLoop().run(
            initialSchematic: schematic,
            circuitIR: circuitIR,
            ercReports: ercReports,
            resolverEvidence: resolverEvidence
        )

        var result = SchematicVerificationGate().evaluate(SchematicVerificationEvidence(
            approvedDesignIntent: true,
            circuitIRValidationPassed: true,
            kicadProjectPath: materialized.projectURL.path,
            kicadSchematicPath: materialized.schematicURL.path,
            ercReportPath: ercReports.isEmpty ? nil : outputDirectory.appendingPathComponent("erc-report.json").path,
            hasSchematicVerificationReport: true,
            blockingERCViolations: (ercReports.last ?? KiCadERCReport(violations: [])).schematicVerificationBlockingViolations,
            repairLoopStatus: ercLoop.status
        ))
        result.diagnostics.append(contentsOf: ercLoop.diagnostics)
        result.report.diagnostics.append(contentsOf: ercLoop.diagnostics)
        return result
    }

    private func pcbVerification(
        schematicVerified: Bool,
        evidence: PCBVerificationEvidence?
    ) -> PCBVerificationResult {
        guard var evidence else {
            return PCBVerificationGate().evaluate(.missingEvidence)
        }
        evidence.schematicVerified = schematicVerified
        return PCBVerificationGate().evaluate(evidence)
    }

    private func spiceVerification(
        intent: DesignIntent,
        evidence: ElectronicsEndToEndSPICEEvidence?
    ) throws -> SPICEHarnessEvaluation {
        guard intent.verificationPlan.spiceRequired else {
            return SPICEHarnessEvaluation(status: .notRequired, missingEvidence: [], diagnostics: [])
        }

        guard let evidence else {
            return SPICEHarnessEvaluation(
                status: .missing,
                missingEvidence: ["spice_measurements"],
                diagnostics: []
            )
        }

        var diagnostics: [ElectronicsSchemaIssue] = []
        let scenario = SPICEScenarioValidator().validate(evidence.scenario)
        diagnostics.append(contentsOf: scenario.issues)

        if evidence.circuitDeckProvided == true,
           !evidence.scenario.circuitPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let circuitURL = URL(fileURLWithPath: evidence.scenario.circuitPath)
            if FileManager.default.fileExists(atPath: circuitURL.path) {
                let deckText = try String(contentsOf: circuitURL, encoding: .utf8)
                let deck = SPICECircuitDeckValidator().validate(deckText: deckText, scenario: evidence.scenario)
                diagnostics.append(contentsOf: deck.issues)
            } else {
                diagnostics.append(ElectronicsSchemaIssue(
                    code: "SPICE_CIRCUIT_DECK_REQUIRED",
                    message: "\(evidence.scenario.scenarioId) references missing circuit deck \(evidence.scenario.circuitPath)."
                ))
            }
        }

        if evidence.modelRecordsProvided == false,
           !evidence.scenario.requiredModelRefs.isEmpty {
            diagnostics.append(ElectronicsSchemaIssue(
                code: "SPICE_MODEL_RECORDS_REQUIRED",
                message: "\(evidence.scenario.scenarioId) requires local SPICE model records for \(evidence.scenario.requiredModelRefs.joined(separator: ", "))."
            ))
        } else {
            let models = SPICEModelResolver().resolve(
                requiredModels: evidence.scenario.requiredModelRefs,
                availableModels: evidence.availableModels,
                approvals: evidence.approvals
            )
            diagnostics.append(contentsOf: models.issues)
        }

        let report = try NgspiceMeasurementParser().parse(evidence.ngspiceOutput)
        if report.measurements.isEmpty,
           !evidence.scenario.measurementEnvelopes.isEmpty {
            diagnostics.append(ElectronicsSchemaIssue(
                code: "SPICE_MEASUREMENT_PARSE_FAILED",
                message: "\(evidence.scenario.scenarioId) ngspice output did not contain scalar measurements for declared envelopes."
            ))
        } else {
            let measurements = SPICEMeasurementEnvelopeEvaluator().evaluate(
                report: report,
                envelopes: evidence.scenario.measurementEnvelopes
            )
            diagnostics.append(contentsOf: measurements.failures.map {
                ElectronicsSchemaIssue(
                    code: "SPICE_MEASUREMENT_OUT_OF_RANGE",
                    message: "\($0.measurement) was \($0.actual), expected \($0.expected)."
                )
            })
        }

        return SPICEHarnessEvaluation(
            status: diagnostics.isEmpty ? .passed : .blocked,
            missingEvidence: diagnostics.isEmpty ? [] : ["spice_measurements"],
            diagnostics: diagnostics
        )
    }

    private func resolver(for circuitIR: CircuitIR) -> KiCadLibraryPinResolver {
        KiCadLibraryPinResolver(
            symbols: circuitIR.components.map { component in
                KiCadSymbolDefinition(
                    name: component.selectedSymbol,
                    pins: component.pins.map {
                        KiCadSymbolPin(
                            number: $0.pinNumber,
                            name: $0.symbolPin,
                            electricalType: $0.electricalType
                        )
                    }
                )
            },
            footprints: circuitIR.components.compactMap { component in
                guard let footprint = component.selectedFootprint else { return nil }
                return KiCadFootprintDefinition(
                    name: footprint,
                    pads: component.pins.compactMap { pin in
                        guard let pad = pin.footprintPad else { return nil }
                        return KiCadFootprintPad(number: pad, name: nil)
                    }
                )
            }
        )
    }

    private func blocked(
        missing: [String],
        diagnostics: [ElectronicsSchemaIssue],
        certifiesSafety: Bool = false
    ) -> ElectronicsEndToEndResult {
        ElectronicsEndToEndResult(
            status: .blocked,
            isComplete: false,
            schematicStatus: nil,
            pcbStatus: nil,
            spiceStatus: .missing,
            fabricationStatus: .blocked,
            missingEvidence: stableUnique(missing),
            diagnostics: stableIssues(diagnostics),
            certifiesSafety: certifiesSafety
        )
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func stableIssues(_ issues: [ElectronicsSchemaIssue]) -> [ElectronicsSchemaIssue] {
        var seen = Set<String>()
        var result: [ElectronicsSchemaIssue] = []
        for issue in issues {
            let key = "\(issue.code):\(issue.message)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(issue)
        }
        return result
    }
}

private struct SPICEHarnessEvaluation: Sendable, Equatable {
    var status: ElectronicsEndToEndSPICEStatus
    var missingEvidence: [String]
    var diagnostics: [ElectronicsSchemaIssue]

    var statusIsPassing: Bool {
        status == .passed || status == .notRequired
    }
}
