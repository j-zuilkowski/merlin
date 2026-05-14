import Foundation

struct DesignIntent: Codable, Sendable, Equatable {
    var designId: String
    var title: String
    var requirements: [Requirement]
    var assumptions: [Assumption]
    var components: [ComponentIntent]
    var nets: [NetIntent]
    var safetyProfile: SafetyProfile

    enum CodingKeys: String, CodingKey {
        case designId = "design_id"
        case title
        case requirements
        case assumptions
        case components
        case nets
        case safetyProfile = "safety_profile"
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
