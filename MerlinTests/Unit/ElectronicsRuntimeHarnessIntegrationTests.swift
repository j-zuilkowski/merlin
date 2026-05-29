import XCTest
@testable import Merlin

@MainActor
final class ElectronicsRuntimeHarnessIntegrationTests: XCTestCase {
    func testRequirementsWorkflowReturnsFabReadyHarnessResultFromStructuredEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let payload = try harnessPayload(evidence: .ampLowVoltageVerified)
        XCTAssertNoThrow(try WorkspaceMessagePayload.jsonString(payload).decodeJSON(ElectronicsEndToEndWorkflowRequest.self))
        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .fabReady)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.missingEvidence.contains("release_package"))
        XCTAssertTrue(result.missingEvidence.contains("release_approval"))
    }

    func testRequirementsWorkflowBlocksWhenHarnessMissingRequiredSPICEEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        var evidence = ElectronicsEndToEndEvidence.ampLowVoltageVerified
        evidence.spice = nil

        let payload = try harnessPayload(evidence: evidence)
        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.missingEvidence.contains("spice_measurements"))
        XCTAssertFalse(result.isComplete)
    }

    func testRequirementsWorkflowReturnsCompleteOnlyWithReleasePackageAndApproval() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        var evidence = ElectronicsEndToEndEvidence.ampLowVoltageVerified
        evidence.fabrication.releasePackagePath = "/tmp/amp-low-voltage/release.zip"
        evidence.fabrication.approvals.append(ElectronicsApprovalRecord(
            kind: .release,
            approvedBy: "test",
            summary: "Release package approved"
        ))

        let payload = try harnessPayload(evidence: evidence)
        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .ok)
        let result = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsEndToEndResult.self))
        XCTAssertEqual(result.status, .complete)
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.missingEvidence.isEmpty)
    }

    private func harnessPayload(evidence: ElectronicsEndToEndEvidence) throws -> String {
        let outputDirectory = temporaryDirectory("runtime-harness")
        let evidenceData = try WorkspaceJSON.encoder.encode(evidence)
        let evidenceObject = try JSONSerialization.jsonObject(with: evidenceData)
        let object: [String: Any] = [
            "job_id": "amp-low-voltage-runtime",
            "design_intent_path": repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/design_intent.json").path,
            "circuit_ir_path": repoURL("plugins/electronics/fixtures/amp_low_voltage_audio/circuit_ir.json").path,
            "output_directory": outputDirectory.path,
            "evidence": evidenceObject,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
