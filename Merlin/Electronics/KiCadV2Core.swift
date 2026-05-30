import Foundation

enum KiCadStatus: String, Codable, Sendable, CaseIterable {
    case complete = "COMPLETE"
    case blocked = "BLOCKED"
    case blockedInputQuality = "BLOCKED_INPUT_QUALITY"
    case blockedVersion = "BLOCKED_VERSION"
    case blockedSimulation = "BLOCKED_SIMULATION"
    case blockedTooling = "BLOCKED_TOOLING"
    case blockedLibrary = "BLOCKED_LIBRARY"
    case blockedEngineeringDecision = "BLOCKED_ENGINEERING_DECISION"
    case inProgress = "IN_PROGRESS"
}

struct ArtifactRef: Codable, Sendable, Equatable {
    var path: String
    var kind: String
}

struct KiCadViolation: Codable, Sendable, Equatable {
    var gate: String
    var severity: String
    var message: String
    var affectedRefs: [String]
}

struct ClarificationQuestion: Codable, Sendable, Equatable {
    var id: String
    var prompt: String
    var affectedRefs: [String]
}

struct KiCadWarning: Codable, Sendable, Equatable {
    var code: String
    var message: String
    var affectedRefs: [String]
    var suggestedAction: String?
}

struct KiCadWorkflowHandoff: Codable, Sendable, Equatable {
    var designIntentPath: String?
    var circuitIRPath: String?
    var componentMatrixPath: String?
    var footprintAssignmentPath: String?
    var projectPath: String?
    var ercReportPath: String?
    var drcReportPath: String?
    var spiceMeasurementsPath: String?

    init(designIntentPath: String? = nil,
         circuitIRPath: String? = nil,
         componentMatrixPath: String? = nil,
         footprintAssignmentPath: String? = nil,
         projectPath: String? = nil,
         ercReportPath: String? = nil,
         drcReportPath: String? = nil,
         spiceMeasurementsPath: String? = nil) {
        self.designIntentPath = designIntentPath
        self.circuitIRPath = circuitIRPath
        self.componentMatrixPath = componentMatrixPath
        self.footprintAssignmentPath = footprintAssignmentPath
        self.projectPath = projectPath
        self.ercReportPath = ercReportPath
        self.drcReportPath = drcReportPath
        self.spiceMeasurementsPath = spiceMeasurementsPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        designIntentPath = Self.string(in: container, for: ["designIntentPath", "design_intent_path"])
        circuitIRPath = Self.string(in: container, for: ["circuitIRPath", "circuitIrPath", "circuit_ir_path"])
        componentMatrixPath = Self.string(in: container, for: ["componentMatrixPath", "component_matrix_path"])
        footprintAssignmentPath = Self.string(in: container, for: ["footprintAssignmentPath", "footprint_assignment_path"])
        projectPath = Self.string(in: container, for: ["projectPath", "project_path"])
        ercReportPath = Self.string(in: container, for: ["ercReportPath", "erc_report_path"])
        drcReportPath = Self.string(in: container, for: ["drcReportPath", "drc_report_path"])
        spiceMeasurementsPath = Self.string(in: container, for: ["spiceMeasurementsPath", "spice_measurements_path"])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleCodingKey.self)
        try container.encodeIfPresent(designIntentPath, forKey: FlexibleCodingKey("designIntentPath"))
        try container.encodeIfPresent(circuitIRPath, forKey: FlexibleCodingKey("circuitIRPath"))
        try container.encodeIfPresent(componentMatrixPath, forKey: FlexibleCodingKey("componentMatrixPath"))
        try container.encodeIfPresent(footprintAssignmentPath, forKey: FlexibleCodingKey("footprintAssignmentPath"))
        try container.encodeIfPresent(projectPath, forKey: FlexibleCodingKey("projectPath"))
        try container.encodeIfPresent(ercReportPath, forKey: FlexibleCodingKey("ercReportPath"))
        try container.encodeIfPresent(drcReportPath, forKey: FlexibleCodingKey("drcReportPath"))
        try container.encodeIfPresent(spiceMeasurementsPath, forKey: FlexibleCodingKey("spiceMeasurementsPath"))
    }

    private struct FlexibleCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }
    }

    private static func string(
        in container: KeyedDecodingContainer<FlexibleCodingKey>,
        for keys: [String]
    ) -> String? {
        keys.compactMap {
            try? container.decodeIfPresent(String.self, forKey: FlexibleCodingKey($0))
        }.first ?? nil
    }
}

struct KiCadToolResult: Codable, Sendable, Equatable {
    var status: KiCadStatus
    var artifacts: [ArtifactRef]
    var violations: [KiCadViolation]
    var warnings: [KiCadWarning]
    var metrics: [String: Double]
    var questions: [ClarificationQuestion]
    var nextActions: [String]
    var handoff: KiCadWorkflowHandoff?

    init(status: KiCadStatus,
         artifacts: [ArtifactRef] = [],
         violations: [KiCadViolation] = [],
         warnings: [KiCadWarning] = [],
         metrics: [String: Double] = [:],
         questions: [ClarificationQuestion] = [],
         nextActions: [String] = [],
         handoff: KiCadWorkflowHandoff? = nil) {
        self.status = status
        self.artifacts = artifacts
        self.violations = violations
        self.warnings = warnings
        self.metrics = metrics
        self.questions = questions
        self.nextActions = nextActions
        self.handoff = handoff
    }
}

struct StackupLayer: Codable, Sendable, Equatable {
    var name: String
    var kind: String
}

struct ImpedanceRule: Codable, Sendable, Equatable {
    var netClass: String
    var targetOhms: Double
    var tolerancePercent: Double
}

struct DifferentialPairRule: Codable, Sendable, Equatable {
    var id: String
    var intraPairSkewMaxMm: Double
    var pairToPairSkewMaxMm: Double!
    var differentialImpedanceOhms: Double

    static let ethernet100BaseTX = DifferentialPairRule(
        id: "ethernet_100base_tx",
        intraPairSkewMaxMm: 10.0,
        pairToPairSkewMaxMm: nil,
        differentialImpedanceOhms: 100.0
    )

    static let ethernet1000BaseT = DifferentialPairRule(
        id: "ethernet_1000base_t",
        intraPairSkewMaxMm: 5.0,
        pairToPairSkewMaxMm: 25.0,
        differentialImpedanceOhms: 100.0
    )
}

struct BoardProfile: Codable, Sendable, Equatable {
    var id: String
    var fabricator: String
    var layerCount: Int
    var stackup: [StackupLayer]
    var copperWeightOz: Double
    var minTraceMm: Double
    var minClearanceMm: Double
    var minViaDrillMm: Double
    var minViaPadMm: Double
    var copperToEdgeMm: Double
    var impedanceRequirements: [ImpedanceRule]
    var differentialPairRules: [DifferentialPairRule]

    static let jlcpcb2LayerDefault = BoardProfile(
        id: "jlcpcb_2layer_default",
        fabricator: "JLCPCB",
        layerCount: 2,
        stackup: [
            StackupLayer(name: "F.Cu", kind: "copper"),
            StackupLayer(name: "B.Cu", kind: "copper"),
        ],
        copperWeightOz: 1.0,
        minTraceMm: 0.1524,
        minClearanceMm: 0.1524,
        minViaDrillMm: 0.30,
        minViaPadMm: 0.60,
        copperToEdgeMm: 0.25,
        impedanceRequirements: [],
        differentialPairRules: [
            .ethernet100BaseTX,
            .ethernet1000BaseT,
        ]
    )
}

struct SPICEModelAvailability: Codable, Sendable, Equatable {
    var required: Bool
    var manufacturerModelAvailable: Bool
    var legallyObtainable: Bool
    var genericSubstituteAvailable: Bool
    var profileAllowsGenericEquivalence: Bool
    var userApprovedGenericDowngrade: Bool
}

enum SPICEModelDecisionSeverity: String, Codable, Sendable {
    case pass = "PASS"
    case warning = "WARNING"
    case blocked = "BLOCKED"
}

struct SPICEModelDecision: Codable, Sendable, Equatable {
    var severity: SPICEModelDecisionSeverity
    var status: KiCadStatus?
    var code: String
    var message: String
    var requiresUserApproval: Bool
}

struct KiCadSimulationPolicy: Codable, Sendable, Equatable {
    static let `default` = KiCadSimulationPolicy()

    func evaluateModelAvailability(_ availability: SPICEModelAvailability) -> SPICEModelDecision {
        guard availability.required else {
            return SPICEModelDecision(
                severity: .pass,
                status: nil,
                code: "SPICE_MODEL_NOT_REQUIRED",
                message: "SPICE model is not required by the selected profile.",
                requiresUserApproval: false
            )
        }

        if availability.manufacturerModelAvailable && availability.legallyObtainable {
            return SPICEModelDecision(
                severity: .pass,
                status: nil,
                code: "SPICE_MODEL_AVAILABLE",
                message: "Required manufacturer SPICE model is available.",
                requiresUserApproval: false
            )
        }

        if availability.genericSubstituteAvailable {
            let genericAccepted = availability.profileAllowsGenericEquivalence || availability.userApprovedGenericDowngrade
            return SPICEModelDecision(
                severity: .warning,
                status: nil,
                code: "SPICE_MODEL_GENERIC_SUBSTITUTE_SUGGESTED",
                message: "Required manufacturer SPICE model is unavailable or legally unobtainable; use an approved generic substitute if acceptable for this profile.",
                requiresUserApproval: !genericAccepted
            )
        }

        return SPICEModelDecision(
            severity: .blocked,
            status: .blockedSimulation,
            code: "SPICE_MODEL_UNAVAILABLE",
            message: "No legal manufacturer SPICE model or acceptable generic substitute is available for a required simulation scenario.",
            requiresUserApproval: false
        )
    }
}

enum SchematicInputKind: String, Codable, Sendable {
    case nativeKiCad = "native_kicad"
    case vectorPDF = "vector_pdf"
    case rasterImage = "raster_image"
    case handDrawn = "hand_drawn"
}

struct SchematicInputAssessment: Codable, Sendable, Equatable {
    var kind: SchematicInputKind
    var dpi: Int
    var overallConfidence: Double
    var criticalFieldConfidence: Double
    var ambiguousNets: Int
    var unknownComponents: Int
}

enum SchematicInputDisposition: String, Codable, Sendable {
    case authoritative = "authoritative"
    case conceptualOnly = "conceptual_only"
}

struct SchematicInputDecision: Codable, Sendable, Equatable {
    var disposition: SchematicInputDisposition
    var status: KiCadStatus?
    var mayProceedToPCBSynthesis: Bool
    var message: String
}

enum HandDrawnSchematicPolicy {
    static func classify(_ assessment: SchematicInputAssessment) -> SchematicInputDecision {
        let meetsThresholds = assessment.dpi >= 300
            && assessment.overallConfidence >= 0.985
            && assessment.criticalFieldConfidence >= 0.995
            && assessment.ambiguousNets == 0
            && assessment.unknownComponents == 0

        if assessment.kind == .handDrawn && !meetsThresholds {
            return SchematicInputDecision(
                disposition: .conceptualOnly,
                status: .blockedInputQuality,
                mayProceedToPCBSynthesis: false,
                message: "Hand-drawn schematics are conceptual input unless they meet authoritative extraction thresholds."
            )
        }

        return SchematicInputDecision(
            disposition: .authoritative,
            status: nil,
            mayProceedToPCBSynthesis: true,
            message: "Input meets authoritative schematic extraction thresholds."
        )
    }
}

enum VisualQACheck: String, Codable, Sendable, CaseIterable {
    case silkscreenOverlap = "silkscreen_overlap"
    case refdesLegibility = "refdes_legibility"
    case polarityAndPin1Markings = "polarity_and_pin1_markings"
    case connectorOrientation = "connector_orientation"
    case frontPanelLabelConsistency = "front_panel_label_consistency"
    case testPointAccessibility = "test_point_accessibility"
    case keepoutAndEnclosureVisibility = "keepout_and_enclosure_visibility"
    case componentOrientationAnomalies = "component_orientation_anomalies"
    case layerViewSanity = "layer_view_sanity"
}

struct VisualQAProfile: Codable, Sendable, Equatable {
    var id: String
    var requiredChecks: [VisualQACheck]
    var canOverrideElectricalGates: Bool

    static let `default` = VisualQAProfile(
        id: "default_visual_qa",
        requiredChecks: VisualQACheck.allCases,
        canOverrideElectricalGates: false
    )
}
