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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case safetyDomain = "safety_domain"
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

    enum CodingKeys: String, CodingKey {
        case refdes
        case role
        case selectedSymbol = "selected_symbol"
        case selectedFootprint = "selected_footprint"
        case manufacturerPartNumber = "manufacturer_part_number"
        case sourceEvidence = "source_evidence"
        case pins
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
}
