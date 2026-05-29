import XCTest
@testable import Merlin

@MainActor
final class DesignIntentApprovalFlowTests: XCTestCase {
    func testRequirementsDraftDesignIntentWithoutCreatingKiCadFiles() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let response = await send(
            runtime,
            capability: "kicad_build_intent_model",
            payload: #"{"design_id":"amp-low-voltage","requirements":"25W Class-A guitar amplifier low-voltage audio board"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "design_intent" })
        let intent = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(intent.origin, .naturalLanguage)
        XCTAssertEqual(intent.approval.status, .draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("amp-low-voltage.kicad_sch").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("amp-low-voltage.kicad_pcb").path))
    }

    func testUnapprovedNaturalLanguageIntentBlocksCompile() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(approval: DesignApproval(status: .draft), origin: .naturalLanguage), root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await send(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == "DESIGN_INTENT_NOT_APPROVED" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("amp-low-voltage.kicad_sch").path))
    }

    func testApprovedIntentCanProceedToCompileBoundary() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(approval: DesignApproval(
            status: .approved,
            approvedBy: "jon",
            approvedAt: "2026-05-29T13:30:00Z"
        )), root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await send(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(response.artifacts.contains { $0.kind == ElectronicsArtifactKind.kicadProject.rawValue })
    }

    func testRejectedIntentBlocksCompileWithDiagnostic() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(validIntent(approval: DesignApproval(status: .rejected)), root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await send(
            runtime,
            capability: "kicad_compile_project",
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == "DESIGN_INTENT_REJECTED" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("amp-low-voltage.kicad_pro").path))
    }

    private func validIntent(
        approval: DesignApproval,
        origin: DesignIntentOrigin = .userAuthored
    ) -> DesignIntent {
        DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: origin,
            approval: approval,
            requirements: [
                Requirement(id: "req-1", text: "Low-voltage audio board for 25W Class-A guitar amplifier", priority: "must"),
            ],
            assumptions: [],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(id: "amp_low_voltage_audio", title: "Low Voltage Audio Board", safetyDomain: "isolated_secondary"),
            ],
            safetyProfile: SafetyProfile(isolationRequired: false, creepageMm: 0.0, notes: []),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: false, spiceRequired: true)
        )
    }

    private func writeIntent(_ intent: DesignIntent, root: URL) throws -> URL {
        let url = root.appendingPathComponent("\(intent.designId)-intent.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(intent).write(to: url)
        return url
    }

    private func send(
        _ runtime: WorkspaceRuntime,
        capability: String,
        payload: String
    ) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: capability),
            origin: WorkspaceMessageOrigin.parentSession(
                workspaceID: runtime.workspaceID,
                sessionID: nil,
                activeDomainIDs: [ElectronicsDomain.defaultID],
                permissionScope: .externalSideEffect
            ),
            payload: .jsonString(payload),
            cancellationGroup: nil
        ))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-design-intent-approval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
