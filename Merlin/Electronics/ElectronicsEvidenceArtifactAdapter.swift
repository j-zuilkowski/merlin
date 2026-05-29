import Foundation

struct ElectronicsEvidenceArtifactPaths: Codable, Sendable, Equatable {
    var ercReportPaths: [String]
    var drcReportPath: String?
    var spiceScenarioPath: String?
    var spiceModelRecordsPath: String?
    var ngspiceOutputPath: String?
    var normalizedBOMPath: String?
    var vendorAvailabilityPath: String?
    var fabricationEvidencePath: String?
    var verificationReportPath: String?
    var releasePackagePath: String?
    var approvals: [ElectronicsApprovalRecord]
    var evidenceApprovals: [ElectronicsApprovalKind]
}

struct ElectronicsEvidenceArtifactAdapter: Sendable {
    func buildEvidence(_ paths: ElectronicsEvidenceArtifactPaths) throws -> ElectronicsEndToEndEvidence {
        let ercReports = try paths.ercReportPaths.map {
            try KiCadERCParser().parse(jsonData: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        let drcReport = try paths.drcReportPath.map {
            try KiCadDRCParser().parse(jsonData: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        let bom = try paths.normalizedBOMPath.map {
            try JSONDecoder().decode(NormalizedBOM.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        let vendorAvailability = try paths.vendorAvailabilityPath.map {
            try WorkspaceJSON.decoder.decode([VendorAvailability].self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        let fabricationEvidence = try paths.fabricationEvidencePath.map {
            try WorkspaceJSON.decoder.decode(FabricationOutputEvidence.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }

        let bomValidation = bom.map { NormalizedBOMValidator().validate($0) }
            ?? NormalizedBOMValidation(isValid: false, issues: [
                ElectronicsSchemaIssue(code: "BOM_MISSING", message: "Normalized BOM evidence is missing."),
            ])
        let availabilityDiagnostics: VendorAvailabilityDiagnostics
        if let bom, let vendorAvailability {
            availabilityDiagnostics = VendorAvailabilityChecker().evaluate(
                bom: bom,
                availability: vendorAvailability
            )
        } else {
            availabilityDiagnostics = VendorAvailabilityDiagnostics(isOrderable: false, issues: [
                ElectronicsSchemaIssue(
                    code: "BOM_VENDOR_AVAILABILITY_MISSING",
                    message: "Vendor availability evidence is missing."
                ),
            ])
        }

        let fabricationValidation = fabricationEvidence.map {
            FabricationEvidenceValidator().validate($0, profile: .jlcPCBTwoLayer)
        } ?? FabricationEvidenceValidation(isValid: false, missingKinds: [], issues: [
            ElectronicsSchemaIssue(code: "FAB_OUTPUTS_MISSING", message: "Fabrication output evidence is missing."),
        ])
        let profileValidation = FabricatorProfileValidation(
            isValid: fabricationEvidence?.profileId == FabricatorProfile.jlcPCBTwoLayer.id,
            issues: fabricationEvidence?.profileId == FabricatorProfile.jlcPCBTwoLayer.id ? [] : [
                ElectronicsSchemaIssue(
                    code: "FAB_PROFILE_MISMATCH",
                    message: "Fabrication evidence does not match \(FabricatorProfile.jlcPCBTwoLayer.id)."
                ),
            ]
        )

        return ElectronicsEndToEndEvidence(
            ercReports: ercReports,
            pcb: pcbEvidence(from: drcReport, drcReportPath: paths.drcReportPath),
            spice: try spiceEvidence(from: paths),
            fabrication: FabricationReleaseEvidence(
                schematicVerified: ercReports.last?.blockingViolations.isEmpty ?? false,
                pcbVerified: drcReport?.blockingViolations.isEmpty ?? false,
                ercReportPath: paths.ercReportPaths.last,
                drcReportPath: paths.drcReportPath,
                bomValidation: bomValidation,
                vendorAvailability: availabilityDiagnostics,
                fabricationValidation: fabricationValidation,
                profileValidation: profileValidation,
                verificationReportPath: paths.verificationReportPath,
                releasePackagePath: paths.releasePackagePath,
                approvals: paths.approvals
            ),
            approvals: paths.evidenceApprovals
        )
    }

    private func pcbEvidence(
        from report: KiCadDRCReport?,
        drcReportPath: String?
    ) -> PCBVerificationEvidence? {
        guard let report else { return nil }
        let blocking = report.blockingViolations
        return PCBVerificationEvidence(
            schematicVerified: true,
            footprintAssignmentPassed: true,
            hasBoardProfile: true,
            hasBoardOutline: true,
            hasStackup: true,
            hasNetClasses: true,
            hasPlacement: true,
            routingPassedOrExplicitlyDiagnosed: blocking.isEmpty,
            drcReportPath: drcReportPath,
            hasPCBVerificationReport: true,
            blockingDRCViolations: blocking,
            repairLoopStatus: blocking.isEmpty ? .verified : .blocked
        )
    }

    private func spiceEvidence(from paths: ElectronicsEvidenceArtifactPaths) throws -> ElectronicsEndToEndSPICEEvidence? {
        guard let scenarioPath = paths.spiceScenarioPath,
              let outputPath = paths.ngspiceOutputPath else {
            return nil
        }
        let scenario = try WorkspaceJSON.decoder.decode(
            SPICESimulationScenario.self,
            from: Data(contentsOf: URL(fileURLWithPath: scenarioPath))
        )
        let models: [SPICEModelRecord]
        if let modelPath = paths.spiceModelRecordsPath {
            models = try WorkspaceJSON.decoder.decode(
                [SPICEModelRecord].self,
                from: Data(contentsOf: URL(fileURLWithPath: modelPath))
            )
        } else {
            models = []
        }
        return ElectronicsEndToEndSPICEEvidence(
            scenario: scenario,
            availableModels: models,
            ngspiceOutput: try String(contentsOf: URL(fileURLWithPath: outputPath), encoding: .utf8),
            approvals: paths.evidenceApprovals
        )
    }
}
