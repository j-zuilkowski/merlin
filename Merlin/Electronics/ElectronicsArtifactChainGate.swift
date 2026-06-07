import Foundation

enum ElectronicsArtifactChainStage: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case requirementsInspection = "requirements_inspection"
    case designIntentApproval = "design_intent_approval"
    case boardDecomposition = "board_decomposition"
    case circuitIR = "circuit_ir"
    case componentSelectionRevision = "component_selection_revision"
    case footprintAssignment = "footprint_assignment"
    case schematicGeneration = "schematic_generation"
    case pcbGeneration = "pcb_generation"
    case ercRerun = "erc_rerun"
    case drcRerun = "drc_rerun"
    case spiceScenario = "spice_scenario"
    case spiceRun = "spice_run"
    case bomVendorPackage = "bom_vendor_package"
    case fabricationCAM = "fabrication_cam"
}

struct ElectronicsArtifactChainRecord: Codable, Sendable, Equatable {
    var stage: ElectronicsArtifactChainStage
    var artifactPaths: [String]
    var evidenceSummary: String
    var repairMutationRequired: Bool
    var mutationEvidencePath: String?
    var rerunEvidencePath: String?

    init(
        stage: ElectronicsArtifactChainStage,
        artifactPaths: [String],
        evidenceSummary: String,
        repairMutationRequired: Bool = false,
        mutationEvidencePath: String? = nil,
        rerunEvidencePath: String? = nil
    ) {
        self.stage = stage
        self.artifactPaths = artifactPaths
        self.evidenceSummary = evidenceSummary
        self.repairMutationRequired = repairMutationRequired
        self.mutationEvidencePath = mutationEvidencePath
        self.rerunEvidencePath = rerunEvidencePath
    }
}

struct ElectronicsArtifactChainGateResult: Sendable, Equatable {
    var isValid: Bool
    var missingStages: [ElectronicsArtifactChainStage]
    var diagnostics: [ElectronicsSchemaIssue]
}

struct ElectronicsArtifactChainGate: Sendable {
    func evaluate(records: [ElectronicsArtifactChainRecord]) -> ElectronicsArtifactChainGateResult {
        var latestByStage: [ElectronicsArtifactChainStage: ElectronicsArtifactChainRecord] = [:]
        for record in records {
            latestByStage[record.stage] = record
        }

        var missingStages: [ElectronicsArtifactChainStage] = []
        var diagnostics: [ElectronicsSchemaIssue] = []

        for stage in ElectronicsArtifactChainStage.allCases {
            guard let record = latestByStage[stage] else {
                missingStages.append(stage)
                diagnostics.append(issue(
                    "ARTIFACT_CHAIN_STAGE_MISSING",
                    "\(stage.rawValue) has no artifact-backed evidence record."
                ))
                continue
            }

            let concretePaths = record.artifactPaths
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if concretePaths.isEmpty || narrativeOnly(record.evidenceSummary) {
                diagnostics.append(issue(
                    "ARTIFACT_CHAIN_NARRATIVE_ONLY",
                    "\(stage.rawValue) must be backed by concrete artifact paths, not narrative claims."
                ))
            }

            if record.repairMutationRequired,
               record.mutationEvidencePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                diagnostics.append(issue(
                    "ARTIFACT_CHAIN_REPAIR_MUTATION_REQUIRED",
                    "\(stage.rawValue) repair advancement requires concrete mutation evidence."
                ))
            }

            if rerunStageRequiresEvidence(stage),
               record.rerunEvidencePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                diagnostics.append(issue(
                    "ARTIFACT_CHAIN_RERUN_EVIDENCE_REQUIRED",
                    "\(stage.rawValue) requires explicit rerun evidence before downstream advancement."
                ))
            }
        }

        return ElectronicsArtifactChainGateResult(
            isValid: missingStages.isEmpty && diagnostics.isEmpty,
            missingStages: missingStages,
            diagnostics: stableIssues(diagnostics)
        )
    }

    private func rerunStageRequiresEvidence(_ stage: ElectronicsArtifactChainStage) -> Bool {
        switch stage {
        case .ercRerun, .drcRerun, .spiceRun:
            return true
        default:
            return false
        }
    }

    private func narrativeOnly(_ summary: String) -> Bool {
        let lower = summary.lowercased()
        return lower.contains("narrative")
            || lower.contains("prose")
            || lower.contains("claimed")
            || lower.contains("declared")
    }

    private func issue(_ code: String, _ message: String) -> ElectronicsSchemaIssue {
        ElectronicsSchemaIssue(code: code, message: message)
    }

    private func stableIssues(_ issues: [ElectronicsSchemaIssue]) -> [ElectronicsSchemaIssue] {
        var seen = Set<String>()
        var result: [ElectronicsSchemaIssue] = []
        for issue in issues {
            let key = "\(issue.code):\(issue.message)"
            guard seen.insert(key).inserted else { continue }
            result.append(issue)
        }
        return result
    }
}
