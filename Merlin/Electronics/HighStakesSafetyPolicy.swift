import Foundation

struct HighStakesSafetyEvaluation: Codable, Sendable, Equatable {
    var status: KiCadStatus
    var requiredApprovals: [ElectronicsApprovalKind]
    var certifiesSafety: Bool
    var issues: [ElectronicsSchemaIssue]
}

struct SafetyCertificationClaimDecision: Codable, Sendable, Equatable {
    var allowed: Bool
    var issue: ElectronicsSchemaIssue
}

struct CADSafetyReviewEvaluation: Codable, Sendable, Equatable {
    var cadArtifactsMayBePrepared: Bool
    var certifiesSafety: Bool
    var disclaimers: [String]
    var issues: [ElectronicsSchemaIssue]
}

struct HighStakesSafetyPolicy: Sendable {
    func evaluate(
        intent: DesignIntent,
        grantedApprovals: [ElectronicsApprovalKind]
    ) -> HighStakesSafetyEvaluation {
        guard isHighStakes(intent) else {
            return HighStakesSafetyEvaluation(
                status: .complete,
                requiredApprovals: [],
                certifiesSafety: false,
                issues: []
            )
        }

        var issues: [ElectronicsSchemaIssue] = []
        if !grantedApprovals.contains(.highStakesSignoff) {
            issues.append(ElectronicsSchemaIssue(
                code: "HIGH_STAKES_REVIEW_REQUIRED",
                message: "\(intent.designId) requires qualified high-stakes safety review."
            ))
        }
        for decision in intent.unresolvedDecisions where decision.blocking {
            issues.append(ElectronicsSchemaIssue(
                code: "HIGH_STAKES_DECISION_UNRESOLVED",
                message: "Blocking safety decision remains unresolved: \(decision.id)."
            ))
        }

        return HighStakesSafetyEvaluation(
            status: issues.isEmpty ? .complete : .blocked,
            requiredApprovals: [.highStakesSignoff],
            certifiesSafety: false,
            issues: issues
        )
    }

    func evaluateCertificationClaim(_ text: String) -> SafetyCertificationClaimDecision {
        let lowered = text.lowercased()
        let blocked = lowered.contains("safe to build")
            || lowered.contains("safe to use")
            || lowered.contains("certified safe")
            || lowered.contains("safety certified")

        return SafetyCertificationClaimDecision(
            allowed: !blocked,
            issue: ElectronicsSchemaIssue(
                code: blocked ? "SAFETY_CERTIFICATION_CLAIM_BLOCKED" : "NO_SAFETY_CERTIFICATION_CLAIM",
                message: blocked
                    ? "Merlin may not certify high-stakes electronics safe to build or use."
                    : "No blocked safety certification claim detected."
            )
        )
    }

    func evaluateCADVerification(
        intent: DesignIntent,
        schematicVerified: Bool,
        pcbVerified: Bool,
        fabReady: Bool,
        grantedApprovals: [ElectronicsApprovalKind]
    ) -> CADSafetyReviewEvaluation {
        let safety = evaluate(intent: intent, grantedApprovals: grantedApprovals)
        let cadReady = schematicVerified && pcbVerified && fabReady
        let disclaimer = "CAD verification does not certify build, use, regulatory, thermal, grounding, creepage, or clearance safety."

        return CADSafetyReviewEvaluation(
            cadArtifactsMayBePrepared: cadReady,
            certifiesSafety: false,
            disclaimers: [disclaimer],
            issues: safety.issues
        )
    }

    private func isHighStakes(_ intent: DesignIntent) -> Bool {
        if intent.safetyProfile.isolationRequired { return true }
        let safetyText = (intent.safetyProfile.notes + intent.boards.map(\.safetyDomain)).joined(separator: " ").lowercased()
        return safetyText.contains("mains")
            || safetyText.contains("hazardous")
            || safetyText.contains("protective earth")
            || safetyText.contains("qualified safety review")
    }
}
