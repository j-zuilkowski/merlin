import Foundation

struct CompletionGateInputs: Codable, Sendable, Equatable {
    var unroutedNets: Int
    var ercViolations: Int
    var drcViolations: Int
    var parityPassed: Bool
    var fabValidationPassed: Bool
    var requiredSimulationPassed: Bool
}

struct KiCadCompletionGateEvaluator: Sendable {
    func evaluate(_ inputs: CompletionGateInputs) -> KiCadStatus {
        let allPass = inputs.unroutedNets == 0
            && inputs.ercViolations == 0
            && inputs.drcViolations == 0
            && inputs.parityPassed
            && inputs.fabValidationPassed
            && inputs.requiredSimulationPassed

        return allPass ? .complete : .blocked
    }
}

struct SPICEModelCachePolicy: Sendable {
    func evaluateModelAvailability(required: Bool,
                                   manufacturerModelAvailable: Bool,
                                   legallyObtainable: Bool,
                                   genericSubstituteAvailable: Bool) -> SPICEModelDecision {
        guard required else {
            return SPICEModelDecision(
                severity: .pass,
                status: nil,
                code: "SPICE_MODEL_NOT_REQUIRED",
                message: "Simulation model is not required.",
                requiresUserApproval: false
            )
        }

        if manufacturerModelAvailable && legallyObtainable {
            return SPICEModelDecision(
                severity: .pass,
                status: nil,
                code: "SPICE_MODEL_AVAILABLE",
                message: "Required SPICE model is available.",
                requiresUserApproval: false
            )
        }

        if genericSubstituteAvailable {
            return SPICEModelDecision(
                severity: .warning,
                status: nil,
                code: "SPICE_MODEL_GENERIC_SUBSTITUTE_SUGGESTED",
                message: "Required model unavailable; generic substitute can be used with review.",
                requiresUserApproval: true
            )
        }

        return SPICEModelDecision(
            severity: .blocked,
            status: .blockedSimulation,
            code: "SPICE_MODEL_UNAVAILABLE",
            message: "No required or substitute SPICE model is available.",
            requiresUserApproval: false
        )
    }
}

struct VisualQAEvaluation: Codable, Sendable, Equatable {
    var status: KiCadStatus
    var releaseAllowed: Bool
    var findings: [String]
}

struct VisualQAEvaluator: Sendable {
    let requiredChecks: [VisualQACheck] = [
        .silkscreenOverlap,
        .refdesLegibility,
        .polarityAndPin1Markings,
        .connectorOrientation,
        .testPointAccessibility,
        .layerViewSanity,
    ]

    func evaluate(findings: [String], electricalGatesPassed: Bool) -> VisualQAEvaluation {
        guard electricalGatesPassed else {
            return VisualQAEvaluation(status: .blocked, releaseAllowed: false, findings: findings)
        }

        if findings.isEmpty {
            return VisualQAEvaluation(status: .complete, releaseAllowed: true, findings: [])
        }

        return VisualQAEvaluation(status: .blocked, releaseAllowed: false, findings: findings)
    }
}

struct ThreeDModelSourcingPolicy: Sendable {
    enum Source: String, Codable, Sendable, Equatable {
        case kicadModel = "kicad_model"
        case vendorModel = "vendor_model"
        case generatedEnvelope = "generated_envelope"
        case userRequired = "user_required"
        case omittedWithReport = "omitted_with_report"
    }

    func selectSource(kicadModelAvailable: Bool,
                      vendorModelAvailable: Bool,
                      userRequiresModel: Bool) -> Source {
        if kicadModelAvailable {
            return .kicadModel
        }
        if vendorModelAvailable {
            return .vendorModel
        }
        if userRequiresModel {
            return .generatedEnvelope
        }
        return .omittedWithReport
    }
}

struct FabricationProfilePolicy: Codable, Sendable, Equatable {
    var profileId: String
    var requiredOutputKinds: [String]

    static let `default` = FabricationProfilePolicy(
        profileId: "default_fabrication_profile",
        requiredOutputKinds: ["gerbers", "drills", "drill_map", "bom", "pnp", "drawings", "verification_report"]
    )
}

struct FabPackageValidation: Codable, Sendable, Equatable {
    var isValid: Bool
    var missingKinds: [String]
}

struct FabPackageValidator: Sendable {
    func validate(outputKinds: [String], requiredKinds: [String]) -> FabPackageValidation {
        let outputSet = Set(outputKinds)
        let requiredSet = Set(requiredKinds)
        let missing = requiredSet.subtracting(outputSet).sorted()
        return FabPackageValidation(isValid: missing.isEmpty, missingKinds: missing)
    }
}
