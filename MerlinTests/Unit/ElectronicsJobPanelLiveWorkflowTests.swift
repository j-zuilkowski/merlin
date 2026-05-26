import XCTest
@testable import Merlin

@MainActor
final class ElectronicsJobPanelLiveWorkflowTests: XCTestCase {
    func testJobStoreCapturesFinalReportEvents() async throws {
        let runtime = try testRuntime()
        let store = ElectronicsJobStore()
        let report = ElectronicsFinalReport(
            jobID: "job-report",
            evaluation: ElectronicsCompletionEvaluator().evaluate(ElectronicsCompletionEvidence(
                artifacts: ElectronicsCompletionArtifact.requiredFixtureArtifacts,
                gates: ElectronicsGateResult.allPassingRequired,
                approvals: [],
                highStakes: false
            ))
        )

        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "workflow.schematic_to_pcb"),
            origin: nil,
            kind: .artifactProduced,
            payload: try .encodeJSON(report)
        ))
        await store.loadRecent(from: runtime.bus)

        XCTAssertEqual(store.jobs.first?.reports.first?.jobID, "job-report")
    }
}

