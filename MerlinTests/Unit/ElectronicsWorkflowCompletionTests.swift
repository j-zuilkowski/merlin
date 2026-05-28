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

    func testRequirementsWorkflowCanSynthesizeCompleteEvidenceFromPromptContract() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let output = temporaryDirectory("requirements-to-pcb")
        let payload = #"{"job_id":"s6","requirements":"555 astable LED blinker","output_directory":"\#(output.path)","high_stakes":false}"#

        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.ok)
        let report = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsFinalReport.self))
        XCTAssertEqual(report.status, .complete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("merlin-board.kicad_pro").path))
        XCTAssertTrue(report.artifacts.contains { $0.kind == .routingResult })
        let spice = try XCTUnwrap(report.artifacts.first { $0.kind == .spiceMeasurements })
        let spiceOutput = try String(contentsOfFile: spice.path, encoding: .utf8)
        XCTAssertTrue(spiceOutput.contains("frequency"), spiceOutput)
        XCTAssertEqual(report.gates.first { $0.gate == .simulation }?.status, .pass)
        XCTAssertTrue(report.gates.allSatisfy { $0.status == .pass })
    }

    func testRunSpiceRejectsSummaryLogsBeforeInvokingNgspice() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let output = temporaryDirectory("spice-invalid-input")
        let project = output.appendingPathComponent("project.kicad_pro")
        let summary = output.appendingPathComponent("spice.log")
        try "{}".write(to: project, atomically: true, encoding: .utf8)
        try "555 astable transient simulation\noscillation=pass\n".write(to: summary, atomically: true, encoding: .utf8)

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_spice",
            payload: #"{"project_path":"\#(project.path)","scenario_path":"\#(summary.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.invalidInputQuality.rawValue)
    }

    func testSynthesizedRequirementsProjectSupportsKiCadERC() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let output = temporaryDirectory("requirements-to-pcb-erc")
        let project = output.appendingPathComponent("merlin-board.kicad_pro").path
        let payload = #"{"job_id":"s6-erc","requirements":"555 astable LED blinker","output_directory":"\#(output.path)","high_stakes":false}"#

        let workflow = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)
        XCTAssertEqual(workflow.status, WorkspaceMessageResponseStatus.ok)

        let erc = await sendElectronics(
            runtime,
            capability: "kicad_run_erc",
            payload: #"{"project_path":"\#(project)"}"#
        )
        XCTAssertEqual(erc.status, WorkspaceMessageResponseStatus.ok, erc.diagnostics.map(\.message).joined(separator: "\n"))
        XCTAssertFalse(erc.artifacts.isEmpty)
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
