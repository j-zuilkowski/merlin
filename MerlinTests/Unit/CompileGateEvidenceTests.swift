import XCTest
@testable import Merlin

@MainActor
final class CompileGateEvidenceTests: XCTestCase {
    func testNaturalLanguageDesignCannotCompileFromDesignIntentAlone() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(approval: .approved, root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await compile(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "CIRCUIT_IR_REQUIRED" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("amp-low-voltage.kicad_sch").path))
    }

    func testCompileRequiresApprovedDesignIntent() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(approval: .draft, root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await compile(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == "DESIGN_INTENT_NOT_APPROVED" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("amp-low-voltage.kicad_sch").path))
    }

    func testCompileRequiresCircuitIR() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(approval: .approved, root: root)
        let matrixURL = try writeMatrix(root: root)
        let footprintsURL = try writeFootprintAssignments(root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await compile(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)","footprint_assignment_path":"\#(footprintsURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "CIRCUIT_IR_REQUIRED" })
    }

    func testCompileRequiresComponentMatrix() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(approval: .approved, root: root)
        let circuitIRURL = try writeCircuitIR(root: root)
        let footprintsURL = try writeFootprintAssignments(root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await compile(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","footprint_assignment_path":"\#(footprintsURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "COMPONENT_MATRIX_REQUIRED" })
    }

    func testCompileRequiresFootprintAssignmentForPCBBoundComponents() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(approval: .approved, root: root)
        let circuitIRURL = try writeCircuitIR(root: root)
        let matrixURL = try writeMatrix(root: root)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await compile(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","circuit_ir_path":"\#(circuitIRURL.path)","component_matrix_path":"\#(matrixURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "FOOTPRINT_ASSIGNMENT_REQUIRED" })
    }

    func testDraftPreviewArtifactCannotSatisfyVerifiedCompileStatus() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(approval: .approved, root: root)
        let previewURL = root.appendingPathComponent("preview.kicad_sch")
        try "(kicad_sch (version 20250114) (generator preview))\n".write(to: previewURL, atomically: true, encoding: .utf8)
        let output = root.appendingPathComponent("out", isDirectory: true)

        let response = await compile(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","draft_preview_path":"\#(previewURL.path)","output_directory":"\#(output.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertNotEqual(result.status, .complete)
        XCTAssertTrue(result.warnings.contains { $0.code == "CIRCUIT_IR_REQUIRED" })
    }

    private func compile(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_compile_project"),
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

    private func writeIntent(approval: DesignApprovalStatus, root: URL) throws -> URL {
        let intent = DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: .naturalLanguage,
            approval: DesignApproval(status: approval, approvedBy: approval == .approved ? "test" : nil, approvedAt: approval == .approved ? "2026-05-30T16:30:00Z" : nil),
            requirements: [
                Requirement(id: "req-1", text: "Evidence-gated compile", priority: "must"),
            ],
            assumptions: [],
            components: [
                ComponentIntent(refdes: "QOUT1", role: "Class-A output transistor", constraints: ["required_pins": "B,C,E"]),
            ],
            nets: [
                NetIntent(name: "SPK_OUT", role: "speaker output", source: "QOUT1", destination: "JSPK"),
            ],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(id: "amp_low_voltage_audio", title: "Low Voltage Audio Board", safetyDomain: "isolated_secondary"),
            ],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 0, notes: []),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true)
        )
        let url = root.appendingPathComponent("intent.json")
        try electronicsEncoder().encode(intent).write(to: url)
        return url
    }

    private func writeCircuitIR(root: URL) throws -> URL {
        let ir = CircuitIR(
            designId: "amp-low-voltage",
            boardId: "amp_low_voltage_audio",
            components: [
                CircuitComponent(
                    refdes: "QOUT1",
                    role: "Class-A output transistor",
                    selectedSymbol: "Device:Q_NPN_BCE",
                    selectedFootprint: "Package_TO_SOT_THT:TO-3P-3_Vertical",
                    manufacturerPartNumber: "MJ15003G",
                    sourceEvidence: [SourceEvidence(kind: "component_matrix", reference: "QOUT1")],
                    pins: [
                        CircuitPin(componentRefdes: "QOUT1", pinNumber: "1", canonicalName: "B", electricalType: "input", symbolPin: "B", footprintPad: "1"),
                        CircuitPin(componentRefdes: "QOUT1", pinNumber: "2", canonicalName: "C", electricalType: "power", symbolPin: "C", footprintPad: "2"),
                        CircuitPin(componentRefdes: "QOUT1", pinNumber: "3", canonicalName: "E", electricalType: "passive", symbolPin: "E", footprintPad: "3"),
                    ]
                ),
            ],
            nets: [
                CircuitNet(
                    name: "SPK_OUT",
                    role: "speaker output",
                    endpoints: [CircuitNetEndpoint(componentRefdes: "QOUT1", pinNumber: "2")],
                    netClass: "power",
                    safetyDomain: "isolated_secondary"
                ),
            ],
            constraints: [],
            verificationScenarios: [VerificationScenario(id: "erc", kind: "erc", expectation: "no blocking ERC errors")]
        )
        let url = root.appendingPathComponent("circuit-ir.json")
        try electronicsEncoder().encode(ir).write(to: url)
        return url
    }

    private func writeMatrix(root: URL) throws -> URL {
        let candidate = ComponentCandidate(
            mpn: "MJ15003G",
            manufacturer: "onsemi",
            normalizedCategory: "bipolar_power_transistor",
            value: nil,
            package: "TO-3",
            ratings: ["vceo_v": "140", "power_w": "250"],
            lifecycleState: "active",
            availabilitySummary: "fixture_available",
            datasheets: [
                DatasheetEvidence(manufacturer: "onsemi", mpn: "MJ15003G", url: "https://example.invalid/MJ15003G.pdf", localPath: nil, sha256: nil, providerID: "fixture", retrievedAt: "2026-05-30T16:30:00Z", license: "fixture", citations: []),
            ],
            evidence: [
                ComponentEvidence(providerID: "fixture", sourceURL: nil, localPath: nil, retrievedAt: "2026-05-30T16:30:00Z", cachePolicy: "fixture_no_cache", sha256: nil, extractedParameters: ["mpn": "MJ15003G"], confidence: 1, warnings: []),
            ],
            footprintCandidates: [
                FootprintCandidate(library: "Package_TO_SOT_THT", name: "TO-3P-3_Vertical", packageCompatibilityEvidence: "fixture package match", pinPadMap: ["B": "1", "C": "2", "E": "3"], sourceProviderID: "fixture", sourcePath: "Package_TO_SOT_THT.pretty/TO-3P-3_Vertical.kicad_mod", threeDModel: nil),
            ]
        )
        let matrix = ComponentMatrix(
            designId: "amp-low-voltage",
            decisions: [
                PartSelectionDecision(refdes: "QOUT1", status: .selected, selectedCandidate: candidate, candidateSet: [candidate], rationale: "fixture selected", evidenceReferences: candidate.evidence, unresolvedDecisions: []),
            ],
            warnings: [],
            providers: ["fixture"],
            cacheMetadata: [:]
        )
        let url = root.appendingPathComponent("component-matrix.json")
        try electronicsEncoder().encode(matrix).write(to: url)
        return url
    }

    private func writeFootprintAssignments(root: URL) throws -> URL {
        let report = FootprintAssignmentReport(
            assignments: [
                FootprintAssignment(
                    refdes: "QOUT1",
                    footprint: "Package_TO_SOT_THT:TO-3P-3_Vertical",
                    source: .exactMPN,
                    pinPadMap: ["B": "1", "C": "2", "E": "3"],
                    sourceProviderID: "fixture",
                    sourcePath: "Package_TO_SOT_THT.pretty/TO-3P-3_Vertical.kicad_mod",
                    packageCompatibilityEvidence: "fixture package match"
                ),
            ],
            unknownFootprints: 0
        )
        let url = root.appendingPathComponent("footprints.json")
        try electronicsEncoder().encode(report).write(to: url)
        return url
    }

    private func electronicsEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-compile-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
