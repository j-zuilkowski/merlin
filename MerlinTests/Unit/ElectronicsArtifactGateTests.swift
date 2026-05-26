import XCTest
@testable import Merlin

final class ElectronicsArtifactGateTests: XCTestCase {
    func testMissingRequiredArtifactsBlockCompletion() {
        let evaluation = ElectronicsCompletionEvaluator().evaluate(ElectronicsCompletionEvidence(
            artifacts: [
                .init(kind: .kicadProject, path: "project.kicad_pro"),
                .init(kind: .routingResult, path: "board.ses"),
            ],
            gates: ElectronicsGateResult.allPassingRequired,
            approvals: [],
            highStakes: false
        ))

        XCTAssertEqual(evaluation.status, .blocked)
        XCTAssertTrue(evaluation.blockedReasons.contains(.missingArtifact))
        XCTAssertTrue(evaluation.missingArtifactKinds.contains(.fabricationPackage))
        XCTAssertTrue(evaluation.missingArtifactKinds.contains(.bom))
        XCTAssertTrue(evaluation.missingArtifactKinds.contains(.verificationReport))
    }

    func testFailedGateBlocksCompletion() {
        var gates = ElectronicsGateResult.allPassingRequired
        gates[.drc] = ElectronicsGateResult(gate: .drc, status: .fail, details: "2 clearance errors")

        let evaluation = ElectronicsCompletionEvaluator().evaluate(ElectronicsCompletionEvidence(
            artifacts: ElectronicsCompletionArtifact.requiredFixtureArtifacts,
            gates: gates,
            approvals: [],
            highStakes: false
        ))

        XCTAssertEqual(evaluation.status, .blocked)
        XCTAssertTrue(evaluation.blockedReasons.contains(.failedGate))
        XCTAssertEqual(evaluation.failedGates.map(\.gate), [.drc])
    }

    func testHighStakesRequiresExplicitSignoffApproval() {
        let withoutApproval = ElectronicsCompletionEvaluator().evaluate(ElectronicsCompletionEvidence(
            artifacts: ElectronicsCompletionArtifact.requiredFixtureArtifacts,
            gates: ElectronicsGateResult.allPassingRequired,
            approvals: [],
            highStakes: true
        ))

        XCTAssertEqual(withoutApproval.status, .blocked)
        XCTAssertTrue(withoutApproval.failedGates.contains { $0.gate == .highStakesSignoff })

        let withApproval = ElectronicsCompletionEvaluator().evaluate(ElectronicsCompletionEvidence(
            artifacts: ElectronicsCompletionArtifact.requiredFixtureArtifacts,
            gates: ElectronicsGateResult.allPassingRequired,
            approvals: [ElectronicsApprovalRecord(kind: .highStakesSignoff, approvedBy: "user", summary: "Approved for release")],
            highStakes: true
        ))

        XCTAssertEqual(withApproval.status, .complete)
    }

    func testFinalReportSummarizesArtifactsGatesAndApprovals() {
        let report = ElectronicsFinalReport(
            jobID: "job-1",
            evaluation: ElectronicsCompletionEvaluator().evaluate(ElectronicsCompletionEvidence(
                artifacts: ElectronicsCompletionArtifact.requiredFixtureArtifacts,
                gates: ElectronicsGateResult.allPassingRequired,
                approvals: [ElectronicsApprovalRecord(kind: .release, approvedBy: "user", summary: "Release approved")],
                highStakes: false
            ))
        )

        XCTAssertEqual(report.status, .complete)
        XCTAssertFalse(report.artifacts.isEmpty)
        XCTAssertFalse(report.gates.isEmpty)
        XCTAssertEqual(report.approvals.first?.kind, .release)
    }
}
