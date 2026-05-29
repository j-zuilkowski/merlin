import Foundation

struct NormalizedBOMValidation: Codable, Sendable, Equatable {
    var isValid: Bool
    var issues: [ElectronicsSchemaIssue]
}

struct NormalizedBOMValidator: Sendable {
    func validate(_ bom: NormalizedBOM) -> NormalizedBOMValidation {
        var issues: [ElectronicsSchemaIssue] = []
        let mappedLineIDs = Set(bom.vendorMappings.map(\.lineId))
        var seenRefdes: Set<String> = []

        for line in bom.lines {
            if line.mpn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ElectronicsSchemaIssue(
                    code: "BOM_MPN_REQUIRED",
                    message: "\(line.lineId) is missing a manufacturer part number."
                ))
            }
            if line.quantity <= 0 {
                issues.append(ElectronicsSchemaIssue(
                    code: "BOM_QUANTITY_REQUIRED",
                    message: "\(line.lineId) must have a positive quantity."
                ))
            }
            if line.referenceDesignators.isEmpty {
                issues.append(ElectronicsSchemaIssue(
                    code: "BOM_REFDES_REQUIRED",
                    message: "\(line.lineId) has no reference designators."
                ))
            }
            if !mappedLineIDs.contains(line.lineId) {
                issues.append(ElectronicsSchemaIssue(
                    code: "BOM_VENDOR_MAPPING_REQUIRED",
                    message: "\(line.lineId) has no vendor mapping."
                ))
            }

            for refdes in line.referenceDesignators {
                if seenRefdes.contains(refdes) {
                    issues.append(ElectronicsSchemaIssue(
                        code: "BOM_REFDES_DUPLICATE",
                        message: "\(refdes) appears in more than one BOM line."
                    ))
                }
                seenRefdes.insert(refdes)
            }
        }

        if bom.lines.isEmpty {
            issues.append(ElectronicsSchemaIssue(
                code: "BOM_LINE_REQUIRED",
                message: "Normalized BOM must contain at least one line."
            ))
        }

        return NormalizedBOMValidation(isValid: issues.isEmpty, issues: issues)
    }
}

enum VendorLifecycle: String, Codable, Sendable, Equatable {
    case active
    case obsolete
    case notRecommended = "not_recommended"
    case unknown
}

struct VendorAvailability: Codable, Sendable, Equatable {
    var lineId: String
    var mpn: String
    var vendorId: String
    var vendorPartNumber: String
    var lifecycle: VendorLifecycle
    var inStockQuantity: Int
}

struct VendorAvailabilityDiagnostics: Codable, Sendable, Equatable {
    var isOrderable: Bool
    var issues: [ElectronicsSchemaIssue]
}

struct VendorAvailabilityChecker: Sendable {
    func evaluate(
        bom: NormalizedBOM,
        availability: [VendorAvailability]
    ) -> VendorAvailabilityDiagnostics {
        var issues: [ElectronicsSchemaIssue] = []
        let availabilityByLine = Dictionary(grouping: availability, by: \.lineId)

        for line in bom.lines {
            guard let records = availabilityByLine[line.lineId], !records.isEmpty else {
                issues.append(ElectronicsSchemaIssue(
                    code: "BOM_VENDOR_AVAILABILITY_MISSING",
                    message: "\(line.lineId) has no vendor availability record."
                ))
                continue
            }

            if records.allSatisfy({ $0.inStockQuantity < line.quantity }) {
                issues.append(ElectronicsSchemaIssue(
                    code: "BOM_VENDOR_OUT_OF_STOCK",
                    message: "\(line.lineId) is not available in the required quantity."
                ))
            }

            for record in records {
                if record.mpn != line.mpn {
                    issues.append(ElectronicsSchemaIssue(
                        code: "BOM_VENDOR_MPN_MISMATCH",
                        message: "\(line.lineId) vendor record MPN \(record.mpn) does not match \(line.mpn)."
                    ))
                }
                if record.vendorPartNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(ElectronicsSchemaIssue(
                        code: "BOM_VENDOR_PART_NUMBER_REQUIRED",
                        message: "\(line.lineId) has an empty vendor part number."
                    ))
                }
                if record.lifecycle == .obsolete || record.lifecycle == .notRecommended {
                    issues.append(ElectronicsSchemaIssue(
                        code: "BOM_VENDOR_LIFECYCLE_BLOCKED",
                        message: "\(line.lineId) uses \(record.lifecycle.rawValue) part \(record.mpn)."
                    ))
                }
            }
        }

        return VendorAvailabilityDiagnostics(isOrderable: issues.isEmpty, issues: issues)
    }
}

enum FabricationOutputKind: String, Codable, Sendable, Equatable, CaseIterable {
    case gerberArchive = "gerber_archive"
    case excellonDrill = "excellon_drill"
    case normalizedBOM = "normalized_bom"
    case pickAndPlace = "pick_and_place"
    case fabricationReport = "fabrication_report"
    case assemblyDrawing = "assembly_drawing"
}

struct FabricationOutput: Codable, Sendable, Equatable {
    var kind: FabricationOutputKind
    var path: String
}

struct FabricationOutputEvidence: Codable, Sendable, Equatable {
    var profileId: String
    var outputs: [FabricationOutput]
    var camReportPath: String?
}

struct FabricatorProfile: Codable, Sendable, Equatable {
    var id: String
    var maxLayerCount: Int
    var minTraceMm: Double
    var minClearanceMm: Double
    var requiredOutputKinds: [FabricationOutputKind]

    static let jlcPCBTwoLayer = FabricatorProfile(
        id: "jlcpcb_2_layer",
        maxLayerCount: 2,
        minTraceMm: 0.127,
        minClearanceMm: 0.127,
        requiredOutputKinds: [.gerberArchive, .excellonDrill, .normalizedBOM, .pickAndPlace, .fabricationReport]
    )
}

struct FabricationEvidenceValidation: Codable, Sendable, Equatable {
    var isValid: Bool
    var missingKinds: [FabricationOutputKind]
    var issues: [ElectronicsSchemaIssue]
}

struct FabricationEvidenceValidator: Sendable {
    func validate(
        _ evidence: FabricationOutputEvidence,
        profile: FabricatorProfile
    ) -> FabricationEvidenceValidation {
        let present = Set(evidence.outputs.filter { !$0.path.isEmpty }.map(\.kind))
        var missing = profile.requiredOutputKinds.filter { !present.contains($0) }
        if evidence.camReportPath?.isEmpty ?? true, !missing.contains(.fabricationReport) {
            missing.append(.fabricationReport)
        }

        var issues = missing.map {
            ElectronicsSchemaIssue(
                code: "FAB_OUTPUT_REQUIRED",
                message: "Missing required fabrication output: \($0.rawValue)."
            )
        }
        if evidence.profileId != profile.id {
            issues.append(ElectronicsSchemaIssue(
                code: "FAB_PROFILE_MISMATCH",
                message: "Evidence profile \(evidence.profileId) does not match \(profile.id)."
            ))
        }

        return FabricationEvidenceValidation(
            isValid: missing.isEmpty && issues.isEmpty,
            missingKinds: missing,
            issues: issues
        )
    }
}

struct FabricatorProfileValidation: Codable, Sendable, Equatable {
    var isValid: Bool
    var issues: [ElectronicsSchemaIssue]
}

struct FabricatorProfileValidator: Sendable {
    func validate(
        _ candidate: PCBBoardCandidate,
        profile: FabricatorProfile
    ) -> FabricatorProfileValidation {
        var issues: [ElectronicsSchemaIssue] = []

        if candidate.boardProfile.layerCount > profile.maxLayerCount {
            issues.append(ElectronicsSchemaIssue(
                code: "FAB_PROFILE_LAYER_COUNT_UNSUPPORTED",
                message: "\(profile.id) supports up to \(profile.maxLayerCount) layers."
            ))
        }
        if candidate.boardProfile.minTraceMm < profile.minTraceMm {
            issues.append(ElectronicsSchemaIssue(
                code: "FAB_PROFILE_TRACE_UNSUPPORTED",
                message: "\(profile.id) minimum trace is \(profile.minTraceMm) mm."
            ))
        }
        if candidate.boardProfile.minClearanceMm < profile.minClearanceMm {
            issues.append(ElectronicsSchemaIssue(
                code: "FAB_PROFILE_CLEARANCE_UNSUPPORTED",
                message: "\(profile.id) minimum clearance is \(profile.minClearanceMm) mm."
            ))
        }

        return FabricatorProfileValidation(isValid: issues.isEmpty, issues: issues)
    }
}

enum IrreversibleElectronicsAction: String, Codable, Sendable, Equatable {
    case vendorOrder = "vendor_order"
    case fabricationOrder = "fabrication_order"
}

struct IrreversibleElectronicsActionDecision: Codable, Sendable, Equatable {
    var approved: Bool
    var requiredApproval: ElectronicsApprovalKind
    var reason: String
}

struct IrreversibleElectronicsActionPolicy: Sendable {
    func canSubmit(
        _ action: IrreversibleElectronicsAction,
        approvals: [ElectronicsApprovalKind]
    ) -> IrreversibleElectronicsActionDecision {
        let required: ElectronicsApprovalKind = action == .vendorOrder ? .orderSubmission : .fabricationSubmission
        let approved = approvals.contains(required)
        return IrreversibleElectronicsActionDecision(
            approved: approved,
            requiredApproval: required,
            reason: approved ? "Approval granted." : "\(required.rawValue) approval is required."
        )
    }
}

enum FabricationReleaseStatus: String, Codable, Sendable, Equatable {
    case blocked = "BLOCKED"
    case fabReady = "FAB_READY"
    case complete = "COMPLETE"
}

struct FabricationReleaseEvidence: Codable, Sendable, Equatable {
    var schematicVerified: Bool
    var pcbVerified: Bool
    var ercReportPath: String?
    var drcReportPath: String?
    var bomValidation: NormalizedBOMValidation
    var vendorAvailability: VendorAvailabilityDiagnostics
    var fabricationValidation: FabricationEvidenceValidation
    var profileValidation: FabricatorProfileValidation
    var verificationReportPath: String?
    var releasePackagePath: String?
    var approvals: [ElectronicsApprovalRecord]

    static let fabReadyFixture = FabricationReleaseEvidence(
        schematicVerified: true,
        pcbVerified: true,
        ercReportPath: "/tmp/amp/erc.json",
        drcReportPath: "/tmp/amp/drc.json",
        bomValidation: NormalizedBOMValidation(isValid: true, issues: []),
        vendorAvailability: VendorAvailabilityDiagnostics(isOrderable: true, issues: []),
        fabricationValidation: FabricationEvidenceValidation(isValid: true, missingKinds: [], issues: []),
        profileValidation: FabricatorProfileValidation(isValid: true, issues: []),
        verificationReportPath: "/tmp/amp/verification.json",
        releasePackagePath: nil,
        approvals: []
    )
}

struct FabricationReleaseEvaluation: Codable, Sendable, Equatable {
    var status: FabricationReleaseStatus
    var canPackageRelease: Bool
    var isComplete: Bool
    var missingEvidence: [String]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct FabricationReleaseGate: Sendable {
    func evaluate(_ evidence: FabricationReleaseEvidence) -> FabricationReleaseEvaluation {
        var missing: [String] = []
        var diagnostics: [ElectronicsSchemaIssue] = []

        if !evidence.schematicVerified { missing.append("SCHEMATIC_VERIFIED") }
        if !evidence.pcbVerified { missing.append("PCB_VERIFIED") }
        if evidence.ercReportPath?.isEmpty ?? true { missing.append("erc_report") }
        if evidence.drcReportPath?.isEmpty ?? true { missing.append("drc_report") }
        if !evidence.bomValidation.isValid { diagnostics.append(contentsOf: evidence.bomValidation.issues) }
        if !evidence.vendorAvailability.isOrderable { diagnostics.append(contentsOf: evidence.vendorAvailability.issues) }
        if !evidence.fabricationValidation.isValid { diagnostics.append(contentsOf: evidence.fabricationValidation.issues) }
        if !evidence.profileValidation.isValid { diagnostics.append(contentsOf: evidence.profileValidation.issues) }
        if evidence.verificationReportPath?.isEmpty ?? true { missing.append("verification_report") }

        let ready = missing.isEmpty && diagnostics.isEmpty
        guard ready else {
            return FabricationReleaseEvaluation(
                status: .blocked,
                canPackageRelease: false,
                isComplete: false,
                missingEvidence: missing,
                diagnostics: diagnostics
            )
        }

        let hasReleasePackage = !(evidence.releasePackagePath?.isEmpty ?? true)
        let releaseApproved = evidence.approvals.contains { $0.kind == .release }
        let complete = hasReleasePackage && releaseApproved

        return FabricationReleaseEvaluation(
            status: complete ? .complete : .fabReady,
            canPackageRelease: true,
            isComplete: complete,
            missingEvidence: complete ? [] : ["release_package", "release_approval"].filter { key in
                if key == "release_package" { return !hasReleasePackage }
                return !releaseApproved
            },
            diagnostics: []
        )
    }
}
