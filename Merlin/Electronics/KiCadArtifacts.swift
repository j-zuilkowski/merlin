import Foundation

struct DesignIntent: Codable, Sendable, Equatable {
    var designId: String
    var title: String
    var origin: DesignIntentOrigin
    var approval: DesignApproval
    var requirements: [Requirement]
    var assumptions: [Assumption]
    var components: [ComponentIntent]
    var nets: [NetIntent]
    var unresolvedDecisions: [UnresolvedDecision]
    var boards: [BoardIntent]
    var safetyProfile: SafetyProfile
    var verificationPlan: VerificationPlan

    init(
        designId: String,
        title: String,
        origin: DesignIntentOrigin = .userAuthored,
        approval: DesignApproval? = nil,
        requirements: [Requirement],
        assumptions: [Assumption],
        components: [ComponentIntent] = [],
        nets: [NetIntent] = [],
        unresolvedDecisions: [UnresolvedDecision] = [],
        boards: [BoardIntent] = [],
        safetyProfile: SafetyProfile,
        verificationPlan: VerificationPlan = VerificationPlan()
    ) {
        self.designId = designId
        self.title = title
        self.origin = origin
        self.approval = approval ?? DesignApproval(status: .draft)
        self.requirements = requirements
        self.assumptions = assumptions
        self.components = components
        self.nets = nets
        self.unresolvedDecisions = unresolvedDecisions
        self.boards = boards
        self.safetyProfile = safetyProfile
        self.verificationPlan = verificationPlan
    }

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case title
        case origin
        case approval
        case requirements
        case assumptions
        case components
        case nets
        case unresolvedDecisions = "unresolved_decisions"
        case boards
        case safetyProfile = "safety_profile"
        case verificationPlan = "verification_plan"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        designId = try container.decode(String.self, forKey: .designId)
        title = try container.decode(String.self, forKey: .title)
        origin = try container.decodeIfPresent(DesignIntentOrigin.self, forKey: .origin) ?? .userAuthored
        approval = try container.decodeIfPresent(DesignApproval.self, forKey: .approval) ?? DesignApproval(status: .draft)
        requirements = try container.decodeIfPresent([Requirement].self, forKey: .requirements) ?? []
        assumptions = try container.decodeIfPresent([Assumption].self, forKey: .assumptions) ?? []
        components = try container.decodeIfPresent([ComponentIntent].self, forKey: .components) ?? []
        nets = try container.decodeIfPresent([NetIntent].self, forKey: .nets) ?? []
        unresolvedDecisions = try container.decodeIfPresent([UnresolvedDecision].self, forKey: .unresolvedDecisions) ?? []
        boards = try container.decodeIfPresent([BoardIntent].self, forKey: .boards) ?? []
        safetyProfile = try container.decode(SafetyProfile.self, forKey: .safetyProfile)
        verificationPlan = try container.decodeIfPresent(VerificationPlan.self, forKey: .verificationPlan) ?? VerificationPlan()
    }
}

enum DesignIntentOrigin: String, Codable, Sendable, Equatable {
    case naturalLanguage = "natural_language"
    case schematicIngest = "schematic_ingest"
    case userAuthored = "user_authored"
}

enum DesignApprovalStatus: String, Codable, Sendable, Equatable {
    case draft
    case approved
    case rejected
}

struct DesignApproval: Codable, Sendable, Equatable {
    var status: DesignApprovalStatus
    var approvedBy: String?
    var approvedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
    }
}

struct Requirement: Codable, Sendable, Equatable {
    var id: String
    var text: String
    var priority: String
}

struct Assumption: Codable, Sendable, Equatable {
    var id: String
    var text: String
    var rationale: String
}

struct UnresolvedDecision: Codable, Sendable, Equatable {
    var id: String
    var question: String
    var blocking: Bool
}

struct BoardIntent: Codable, Sendable, Equatable {
    var id: String
    var title: String
    var safetyDomain: String
    var verificationPlan: VerificationPlan?
    var interBoardConnectors: [InterBoardConnectorIntent]

    init(
        id: String,
        title: String,
        safetyDomain: String,
        verificationPlan: VerificationPlan? = nil,
        interBoardConnectors: [InterBoardConnectorIntent] = []
    ) {
        self.id = id
        self.title = title
        self.safetyDomain = safetyDomain
        self.verificationPlan = verificationPlan
        self.interBoardConnectors = interBoardConnectors
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case safetyDomain = "safety_domain"
        case verificationPlan = "verification_plan"
        case interBoardConnectors = "inter_board_connectors"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        safetyDomain = try container.decode(String.self, forKey: .safetyDomain)
        verificationPlan = try container.decodeIfPresent(VerificationPlan.self, forKey: .verificationPlan)
        interBoardConnectors = try container.decodeIfPresent([InterBoardConnectorIntent].self, forKey: .interBoardConnectors) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(safetyDomain, forKey: .safetyDomain)
        try container.encodeIfPresent(verificationPlan, forKey: .verificationPlan)
        if !interBoardConnectors.isEmpty {
            try container.encode(interBoardConnectors, forKey: .interBoardConnectors)
        }
    }
}

struct InterBoardConnectorIntent: Codable, Sendable, Equatable {
    var id: String
    var targetBoardId: String
    var signalRole: String

    enum CodingKeys: String, CodingKey {
        case id
        case targetBoardId = "target_board_id"
        case signalRole = "signal_role"
    }
}

struct VerificationPlan: Codable, Sendable, Equatable {
    var ercRequired: Bool
    var drcRequired: Bool
    var spiceRequired: Bool

    init(ercRequired: Bool = true, drcRequired: Bool = false, spiceRequired: Bool = false) {
        self.ercRequired = ercRequired
        self.drcRequired = drcRequired
        self.spiceRequired = spiceRequired
    }

    enum CodingKeys: String, CodingKey {
        case ercRequired = "erc_required"
        case drcRequired = "drc_required"
        case spiceRequired = "spice_required"
    }
}

struct ComponentIntent: Codable, Sendable, Equatable {
    var refdes: String
    var role: String
    var constraints: [String: String]
}

struct NetIntent: Codable, Sendable, Equatable {
    var name: String
    var role: String
    var source: String
    var destination: String
}

struct SafetyProfile: Codable, Sendable, Equatable {
    var isolationRequired: Bool
    var creepageMm: Double
    var notes: [String]

    enum CodingKeys: String, CodingKey {
        case isolationRequired = "isolation_required"
        case creepageMm = "creepage_mm"
        case notes
    }
}

struct ExtractionReport: Codable, Sendable, Equatable {
    var designId: String
    var sourceType: String
    var extractedComponents: [ExtractedComponent]
    var extractedNets: [ExtractedNet]
    var confidence: ExtractionConfidence
    var sourceRegions: [SourceRegion]
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case sourceType = "source_type"
        case extractedComponents = "extracted_components"
        case extractedNets = "extracted_nets"
        case confidence
        case sourceRegions = "source_regions"
        case warnings
    }
}

struct ExtractedComponent: Codable, Sendable, Equatable {
    var refdes: String
    var value: String
    var footprintHint: String

    enum CodingKeys: String, CodingKey {
        case refdes
        case value
        case footprintHint = "footprint_hint"
    }
}

struct ExtractedNet: Codable, Sendable, Equatable {
    var name: String
    var endpoints: [String]
}

struct SourceRegion: Codable, Sendable, Equatable {
    var page: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct ExtractionConfidence: Codable, Sendable, Equatable {
    var overall: Double
    var criticalFields: Double

    enum CodingKeys: String, CodingKey {
        case overall
        case criticalFields = "critical_fields"
    }
}

struct NormalizedBOM: Codable, Sendable, Equatable {
    var designId: String
    var lines: [BOMLine]
    var vendorMappings: [VendorBOMMapping]
    var substitutions: [SubstitutionCandidate]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case lines
        case vendorMappings = "vendor_mappings"
        case substitutions
    }
}

struct BOMLine: Codable, Sendable, Equatable {
    var lineId: String
    var mpn: String
    var quantity: Int
    var referenceDesignators: [String]

    enum CodingKeys: String, CodingKey {
        case lineId = "line_id"
        case mpn
        case quantity
        case referenceDesignators = "reference_designators"
    }
}

struct VendorBOMMapping: Codable, Sendable, Equatable {
    var vendorId: String
    var lineId: String
    var vendorPartNumber: String

    enum CodingKeys: String, CodingKey {
        case vendorId = "vendor_id"
        case lineId = "line_id"
        case vendorPartNumber = "vendor_part_number"
    }
}

struct SubstitutionCandidate: Codable, Sendable, Equatable {
    var lineId: String
    var candidateMPN: String
    var reason: String

    enum CodingKeys: String, CodingKey {
        case lineId = "line_id"
        case candidateMPN = "candidate_mpn"
        case reason
    }
}

struct NetClassPlan: Codable, Sendable, Equatable {
    var designId: String
    var classes: [String: [String: Double]]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case classes
    }
}

struct PlacementPlan: Codable, Sendable, Equatable {
    var designId: String
    var hints: [String: String]
    var keepouts: [String]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case hints
        case keepouts
    }
}

struct SimulationScenario: Codable, Sendable, Equatable {
    var scenarioId: String
    var designId: String
    var analyses: [String]
    var requiredModelRefs: [String]

    enum CodingKeys: String, CodingKey {
        case scenarioId = "scenario_id"
        case designId = "design_id"
        case analyses
        case requiredModelRefs = "required_model_refs"
    }
}

struct FabPackage: Codable, Sendable, Equatable {
    var designId: String
    var gerberArchivePath: String
    var drillFilePath: String
    var bomPath: String
    var pickAndPlacePath: String
    var vendorOrders: [VendorOrderSummary]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case gerberArchivePath = "gerber_archive_path"
        case drillFilePath = "drill_file_path"
        case bomPath = "bom_path"
        case pickAndPlacePath = "pick_and_place_path"
        case vendorOrders = "vendor_orders"
    }
}

struct VerificationReport: Codable, Sendable, Equatable {
    var designId: String
    var releaseStatus: String
    var warnings: [String]
    var assumptions: [String]
    var approvals: [ApprovalRecord]
    var gates: [VerificationGateResult]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case releaseStatus = "release_status"
        case warnings
        case assumptions
        case approvals
        case gates
    }
}

struct ApprovalRecord: Codable, Sendable, Equatable {
    var approver: String
    var decision: String
    var timestampISO8601: String
    var note: String

    enum CodingKeys: String, CodingKey {
        case approver
        case decision
        case timestampISO8601 = "timestamp_iso8601"
        case note
    }
}

struct VerificationGateResult: Codable, Sendable, Equatable {
    var gate: String
    var passed: Bool
    var details: String
}

struct VendorOrderSummary: Codable, Sendable, Equatable {
    var vendorId: String
    var orderReference: String
    var paymentAlias: String
    var totalEstimate: Double

    enum CodingKeys: String, CodingKey {
        case vendorId = "vendor_id"
        case orderReference = "order_reference"
        case paymentAlias = "payment_alias"
        case totalEstimate = "total_estimate"
    }
}

struct CircuitIR: Codable, Sendable, Equatable {
    var designId: String
    var boardId: String
    var components: [CircuitComponent]
    var nets: [CircuitNet]
    var constraints: [CircuitConstraint]
    var verificationScenarios: [VerificationScenario]

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case boardId = "board_id"
        case components
        case nets
        case constraints
        case verificationScenarios = "verification_scenarios"
    }
}

struct CircuitComponent: Codable, Sendable, Equatable {
    var refdes: String
    var role: String
    var selectedSymbol: String
    var selectedFootprint: String?
    var manufacturerPartNumber: String?
    var sourceEvidence: [SourceEvidence]
    var pins: [CircuitPin]
    var constraints: [String: String]

    init(
        refdes: String,
        role: String,
        selectedSymbol: String,
        selectedFootprint: String?,
        manufacturerPartNumber: String?,
        sourceEvidence: [SourceEvidence],
        pins: [CircuitPin],
        constraints: [String: String] = [:]
    ) {
        self.refdes = refdes
        self.role = role
        self.selectedSymbol = selectedSymbol
        self.selectedFootprint = selectedFootprint
        self.manufacturerPartNumber = manufacturerPartNumber
        self.sourceEvidence = sourceEvidence
        self.pins = pins
        self.constraints = constraints
    }

    enum CodingKeys: String, CodingKey {
        case refdes
        case role
        case selectedSymbol = "selected_symbol"
        case selectedFootprint = "selected_footprint"
        case manufacturerPartNumber = "manufacturer_part_number"
        case sourceEvidence = "source_evidence"
        case pins
        case constraints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refdes = try container.decode(String.self, forKey: .refdes)
        role = try container.decode(String.self, forKey: .role)
        selectedSymbol = try container.decode(String.self, forKey: .selectedSymbol)
        selectedFootprint = try container.decodeIfPresent(String.self, forKey: .selectedFootprint)
        manufacturerPartNumber = try container.decodeIfPresent(String.self, forKey: .manufacturerPartNumber)
        sourceEvidence = try container.decodeIfPresent([SourceEvidence].self, forKey: .sourceEvidence) ?? []
        pins = try container.decodeIfPresent([CircuitPin].self, forKey: .pins) ?? []
        constraints = try container.decodeIfPresent([String: String].self, forKey: .constraints) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(refdes, forKey: .refdes)
        try container.encode(role, forKey: .role)
        try container.encode(selectedSymbol, forKey: .selectedSymbol)
        try container.encodeIfPresent(selectedFootprint, forKey: .selectedFootprint)
        try container.encodeIfPresent(manufacturerPartNumber, forKey: .manufacturerPartNumber)
        try container.encode(sourceEvidence, forKey: .sourceEvidence)
        try container.encode(pins, forKey: .pins)
        if !constraints.isEmpty {
            try container.encode(constraints, forKey: .constraints)
        }
    }
}

struct SourceEvidence: Codable, Sendable, Equatable {
    var kind: String
    var reference: String
}

struct CircuitPin: Codable, Sendable, Equatable, Hashable {
    var componentRefdes: String
    var pinNumber: String
    var canonicalName: String
    var electricalType: String
    var symbolPin: String
    var footprintPad: String?

    enum CodingKeys: String, CodingKey {
        case componentRefdes = "component_refdes"
        case pinNumber = "pin_number"
        case canonicalName = "canonical_name"
        case electricalType = "electrical_type"
        case symbolPin = "symbol_pin"
        case footprintPad = "footprint_pad"
    }
}

struct CircuitNet: Codable, Sendable, Equatable {
    var name: String
    var role: String
    var endpoints: [CircuitNetEndpoint]
    var netClass: String
    var safetyDomain: String

    enum CodingKeys: String, CodingKey {
        case name
        case role
        case endpoints
        case netClass = "net_class"
        case safetyDomain = "safety_domain"
    }
}

struct CircuitNetEndpoint: Codable, Sendable, Equatable, Hashable {
    var componentRefdes: String
    var pinNumber: String

    enum CodingKeys: String, CodingKey {
        case componentRefdes = "component_refdes"
        case pinNumber = "pin_number"
    }
}

struct CircuitConstraint: Codable, Sendable, Equatable {
    var kind: String
    var target: String
    var value: String
}

struct VerificationScenario: Codable, Sendable, Equatable {
    var id: String
    var kind: String
    var expectation: String
}

struct ElectronicsSchemaIssue: Codable, Sendable, Equatable {
    var code: String
    var message: String
}

struct ElectronicsSchemaValidationResult: Codable, Sendable, Equatable {
    var issues: [ElectronicsSchemaIssue]

    var isValid: Bool {
        issues.isEmpty
    }

    var blocksKiCadMutation: Bool {
        !isValid
    }

    func contains(code: String) -> Bool {
        issues.contains { $0.code == code }
    }
}

enum ElectronicsSchemaValidator {
    static func validateReadyForKiCadMutation(
        designIntent: DesignIntent,
        circuitIR: CircuitIR
    ) -> ElectronicsSchemaValidationResult {
        var issues: [ElectronicsSchemaIssue] = []

        if designIntent.approval.status != .approved {
            issues.append(ElectronicsSchemaIssue(
                code: "DESIGN_INTENT_NOT_APPROVED",
                message: "DesignIntent must be approved before KiCad mutation."
            ))
        }

        for decision in designIntent.unresolvedDecisions where decision.blocking {
            issues.append(ElectronicsSchemaIssue(
                code: "UNRESOLVED_DECISION",
                message: "Blocking design decision remains unresolved: \(decision.id)."
            ))
        }

        if designIntent.safetyProfile.isolationRequired,
           designIntent.boards.contains(where: { $0.safetyDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(ElectronicsSchemaIssue(
                code: "SAFETY_DOMAIN_MISSING",
                message: "Every board must declare a safety domain when isolation is required."
            ))
        }

        if !designIntent.boards.isEmpty {
            let boardIDs = Set(designIntent.boards.map(\.id))
            if !boardIDs.contains(circuitIR.boardId) {
                issues.append(ElectronicsSchemaIssue(
                    code: "CIRCUIT_IR_BOARD_UNKNOWN",
                    message: "Circuit IR board_id \(circuitIR.boardId) does not match a board declared by DesignIntent."
                ))
            }
        }

        issues.append(contentsOf: validateMultiBoardDecomposition(designIntent))

        if circuitIR.components.isEmpty {
            issues.append(ElectronicsSchemaIssue(
                code: "COMPONENTS_MISSING",
                message: "Circuit IR must include evidence-backed components before KiCad mutation."
            ))
        }

        var validPins = Set<CircuitNetEndpoint>()
        for component in circuitIR.components {
            if component.sourceEvidence.isEmpty {
                issues.append(ElectronicsSchemaIssue(
                    code: "COMPONENT_EVIDENCE_MISSING",
                    message: "\(component.refdes) has no source evidence."
                ))
            }
            for pin in component.pins {
                if pin.componentRefdes != component.refdes || pin.pinNumber.isEmpty {
                    issues.append(ElectronicsSchemaIssue(
                        code: "INVALID_PIN_REFERENCE",
                        message: "\(component.refdes) has an invalid pin reference."
                    ))
                } else {
                    validPins.insert(CircuitNetEndpoint(componentRefdes: pin.componentRefdes, pinNumber: pin.pinNumber))
                }
            }
        }

        for net in circuitIR.nets {
            if net.safetyDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ElectronicsSchemaIssue(
                    code: "SAFETY_DOMAIN_MISSING",
                    message: "\(net.name) has no safety domain."
                ))
            }
            for endpoint in net.endpoints where !validPins.contains(endpoint) {
                issues.append(ElectronicsSchemaIssue(
                    code: "INVALID_NET_ENDPOINT",
                    message: "\(net.name) endpoint \(endpoint.componentRefdes).\(endpoint.pinNumber) does not map to a known circuit pin."
                ))
            }
        }

        return ElectronicsSchemaValidationResult(issues: issues)
    }

    private static func validateMultiBoardDecomposition(_ intent: DesignIntent) -> [ElectronicsSchemaIssue] {
        guard requiresHazardousLowVoltageDecomposition(intent) else { return [] }

        let boardIDs = Set(intent.boards.map(\.id))
        let connectors = intent.boards.flatMap(\.interBoardConnectors)
        var issues: [ElectronicsSchemaIssue] = []

        if intent.boards.count < 2 || intent.boards.contains(where: { isMergedHazardousLowVoltageDomain($0.safetyDomain) }) {
            issues.append(ElectronicsSchemaIssue(
                code: "MULTIBOARD_DECOMPOSITION_REQUIRED",
                message: "DesignIntent mixes hazardous and isolated low-voltage domains without separate board intent evidence."
            ))
        }

        if intent.boards.contains(where: { $0.verificationPlan == nil }) {
            issues.append(ElectronicsSchemaIssue(
                code: "BOARD_VERIFICATION_PLAN_REQUIRED",
                message: "Each board in a mixed-domain design must declare its own ERC/DRC/SPICE verification plan."
            ))
        }

        let hasCrossBoardConnector = intent.boards.contains { board in
            board.interBoardConnectors.contains { connector in
                connector.targetBoardId != board.id && boardIDs.contains(connector.targetBoardId)
            }
        }
        if !hasCrossBoardConnector {
            issues.append(ElectronicsSchemaIssue(
                code: "INTERBOARD_CONNECTOR_REQUIRED",
                message: "Mixed-domain decomposition must declare connector evidence across the isolated board boundary."
            ))
        }

        for connector in connectors where !boardIDs.contains(connector.targetBoardId) {
            issues.append(ElectronicsSchemaIssue(
                code: "INTERBOARD_CONNECTOR_TARGET_UNKNOWN",
                message: "Inter-board connector \(connector.id) targets unknown board \(connector.targetBoardId)."
            ))
        }

        return issues
    }

    private static func requiresHazardousLowVoltageDecomposition(_ intent: DesignIntent) -> Bool {
        guard intent.safetyProfile.isolationRequired else { return false }
        let evidenceText = (
            intent.requirements.map(\.text)
            + intent.assumptions.map(\.text)
            + intent.components.map(\.role)
            + intent.nets.flatMap { [$0.role, $0.source, $0.destination] }
            + intent.boards.flatMap { [$0.title, $0.safetyDomain] }
        )
        .joined(separator: " ")
        .lowercased()

        return containsHazardousPowerTerm(evidenceText)
            && containsIsolatedLowVoltageTerm(evidenceText)
    }

    private static func isMergedHazardousLowVoltageDomain(_ domain: String) -> Bool {
        let lowered = domain.lowercased()
        return containsHazardousPowerTerm(lowered)
            && containsIsolatedLowVoltageTerm(lowered)
    }

    private static func containsHazardousPowerTerm(_ text: String) -> Bool {
        text.contains("mains")
            || text.contains("line voltage")
            || text.contains("hazardous")
            || text.contains("transformer primary")
            || text.contains("primary side")
            || text.contains("mains_primary")
            || text.contains("protective earth")
    }

    private static func containsIsolatedLowVoltageTerm(_ text: String) -> Bool {
        text.contains("low-voltage")
            || text.contains("low voltage")
            || text.contains("isolated")
            || text.contains("secondary")
            || text.contains("control")
    }
}
