import XCTest
@testable import Merlin

@MainActor
final class ElectronicsWorkflowCompletionTests: XCTestCase {
    func testCompleteEvidenceProducesFinalReportForBothWorkflows() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let payload = try workflowPayload(jobID: "job-complete", highStakes: false)
        for capability in ["workflow.schematic_to_pcb", "workflow.requirements_to_pcb"] {
            let response = await sendElectronics(runtime, capability: capability, payload: payload)
            XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.ok, capability)
            let report = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsFinalReport.self))
            XCTAssertEqual(report.status, .complete)
            XCTAssertFalse(report.artifacts.isEmpty)
        }
    }

    func testIncompleteEvidenceBlocksWorkflow() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let payload = #"{"job_id":"incomplete","evidence":{"artifacts":[],"gates":{},"approvals":[],"high_stakes":false}}"#

        let response = await sendElectronics(runtime, capability: "workflow.schematic_to_pcb", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.missingArtifact.rawValue)
    }

    func testHighStakesWorkflowBlocksWithoutSignoff() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let payload = try workflowPayload(jobID: "job-high", highStakes: true, approvals: [])

        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == ElectronicsBlockedReason.failedGate.rawValue })
    }

    func testOrderSubmissionRequiresExplicitApproval() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let response = await sendElectronics(runtime, capability: "kicad_submit_vendor_order", payload: #"{"job_id":"order-1"}"#, scope: .userApprovedIrreversible)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, "APPROVAL_REQUIRED")
    }
}
