import Foundation

protocol VendorBOMAdapter: Sendable {
    var vendorName: String { get }
    func exportNativeBOM(from normalizedBOMPath: String, quantity: Int) -> VendorOrderPreparation
}

struct DefaultVendorBOMAdapter: VendorBOMAdapter {
    var vendorName: String

    func exportNativeBOM(from normalizedBOMPath: String, quantity: Int) -> VendorOrderPreparation {
        VendorOrderPreparation.prepare(
            vendorName: vendorName,
            normalizedBOMPath: normalizedBOMPath,
            quantity: quantity
        )
    }
}

struct VendorCatalog: Sendable {
    var vendors: [VendorSource]
    private var adapters: [String: DefaultVendorBOMAdapter]

    static let `default`: VendorCatalog = {
        let vendors: [VendorSource] = [
            VendorSource(canonicalName: "Digi-Key", aliases: ["Digikey", "DigiKey"]),
            VendorSource(canonicalName: "Mouser", aliases: []),
            VendorSource(canonicalName: "Arrow", aliases: []),
            VendorSource(canonicalName: "Newark", aliases: []),
            VendorSource(canonicalName: "Farnell", aliases: []),
            VendorSource(canonicalName: "element14", aliases: ["Element14"]),
            VendorSource(canonicalName: "LCSC", aliases: []),
            VendorSource(canonicalName: "Parts Express", aliases: []),
        ]
        var map: [String: DefaultVendorBOMAdapter] = [:]
        for vendor in vendors {
            map[vendor.canonicalName] = DefaultVendorBOMAdapter(vendorName: vendor.canonicalName)
        }
        return VendorCatalog(vendors: vendors, adapters: map)
    }()

    func adapter(for vendorName: String) -> (any VendorBOMAdapter)? {
        adapters[vendorName]
    }
}

enum PricingLookupMode: String, Codable, Sendable, Equatable {
    case advisory
}

struct PricingAvailabilityResult: Codable, Sendable, Equatable {
    var mode: PricingLookupMode
    var substitutionsApproved: Bool
    var advisoryNotes: [String]
}

struct PurchaseLimitDecision: Codable, Sendable, Equatable {
    var allowed: Bool
    var totalUSD: Double
    var limitUSD: Double
}

struct VendorOrderPolicy: Sendable {
    static let `default` = VendorOrderPolicy()

    func lookupPricingAndAvailability(vendorName: String,
                                      lineItems: [String]) -> PricingAvailabilityResult {
        PricingAvailabilityResult(
            mode: .advisory,
            substitutionsApproved: false,
            advisoryNotes: ["Advisory lookup only for \(vendorName).", "No substitutions approved automatically."]
        )
    }

    func enforcePurchaseLimit(totalUSD: Double, limitUSD: Double) -> PurchaseLimitDecision {
        PurchaseLimitDecision(
            allowed: totalUSD <= limitUSD,
            totalUSD: totalUSD,
            limitUSD: limitUSD
        )
    }
}

struct VendorOrderPreparation: Codable, Sendable, Equatable {
    var vendorName: String
    var normalizedBOMPath: String
    var quantity: Int
    var orderPayloadPath: String?
    var submitted: Bool

    static func prepare(vendorName: String,
                        normalizedBOMPath: String,
                        quantity: Int) -> VendorOrderPreparation {
        VendorOrderPreparation(
            vendorName: vendorName,
            normalizedBOMPath: normalizedBOMPath,
            quantity: quantity,
            orderPayloadPath: "/tmp/order-payload-\(vendorName.lowercased().replacingOccurrences(of: " ", with: "-"))-\(quantity).json",
            submitted: false
        )
    }
}

struct VendorOrderSubmissionPolicy: Sendable {
    static let `default` = VendorOrderSubmissionPolicy()

    func canSubmit(preparation: VendorOrderPreparation,
                   approvalKinds: [ElectronicsApprovalKind]) -> Bool {
        !preparation.submitted && approvalKinds.contains(.orderSubmission)
    }
}

enum ElectronicsApprovalKind: String, Codable, Sendable, CaseIterable {
    case clarification = "clarification"
    case highStakesSignoff = "high_stakes_signoff"
    case release = "release"
    case profileChange = "profile_change"
    case substitution = "substitution"
    case orderSubmission = "order_submission"
    case fabricationSubmission = "fabrication_submission"
    case libraryGeneration = "library_generation"
}

struct ElectronicsApprovalRequest: Codable, Sendable, Equatable {
    var requestId: String
    var kind: ElectronicsApprovalKind
    var rationale: String
    var designId: String
}

struct ElectronicsApprovalEvaluation: Codable, Sendable, Equatable {
    var approved: Bool
    var reason: String
}

struct ElectronicsApprovalEvaluator: Sendable {
    func evaluate(request: ElectronicsApprovalRequest,
                  grantedKinds: [ElectronicsApprovalKind]) -> ElectronicsApprovalEvaluation {
        let approved = grantedKinds.contains(request.kind)
        return ElectronicsApprovalEvaluation(
            approved: approved,
            reason: approved ? "Approval granted" : "Approval kind missing"
        )
    }
}
