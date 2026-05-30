import XCTest
@testable import Merlin

@MainActor
final class FootprintEvidenceGateTests: XCTestCase {
    func testAssignFootprintsBlocksWhenComponentMatrixIsMissing() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(requiredPins: ["B", "C"], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(root.appendingPathComponent("missing.json").path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == ElectronicsBlockedReason.missingArtifact.rawValue })
    }

    func testAssignFootprintsBlocksWhenSelectedComponentHasNoFootprintCandidate() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(requiredPins: ["B", "C"], root: root)
        let matrixURL = try writeMatrix(candidate: validCandidate(footprints: []), root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "FOOTPRINT_CANDIDATE_REQUIRED" })
        XCTAssertTrue(result.warnings.flatMap(\.affectedRefs).contains("QOUT1"))
    }

    func testPinPadMismatchBlocksWithRefdesAndCandidateFootprint() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(requiredPins: ["B", "C", "E"], root: root)
        let matrixURL = try writeMatrix(candidate: validCandidate(footprints: [
            FootprintCandidate(
                library: "Package_TO_SOT_THT",
                name: "TO-3P-3_Vertical",
                packageCompatibilityEvidence: "fixture package match",
                pinPadMap: ["B": "1", "C": "2"],
                sourceProviderID: "fixture",
                sourcePath: "Package_TO_SOT_THT.pretty/TO-3P-3_Vertical.kicad_mod",
                threeDModel: nil
            ),
        ]), root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        let warning = try XCTUnwrap(result.warnings.first { $0.code == "FOOTPRINT_PIN_PAD_MISMATCH" })
        XCTAssertTrue(warning.affectedRefs.contains("QOUT1"))
        XCTAssertTrue(warning.affectedRefs.contains("Package_TO_SOT_THT:TO-3P-3_Vertical"))
    }

    func testFixtureProviderFootprintEvidenceProducesAssignmentArtifact() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(requiredPins: ["B", "C", "E"], root: root)
        let matrixURL = try writeMatrix(candidate: validCandidate(footprints: [validFootprint()]), root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "footprint_assignment" })
        let report = try JSONDecoder().decode(FootprintAssignmentReport.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(report.assignments.map(\.refdes), ["QOUT1"])
        XCTAssertEqual(report.assignments.first?.footprint, "Package_TO_SOT_THT:TO-3P-3_Vertical")
        XCTAssertEqual(report.assignments.first?.pinPadMap["E"], "3")
    }

    func testAssignmentArtifactPreservesFootprintSourceProvenance() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(requiredPins: ["B", "C", "E"], root: root)
        let matrixURL = try writeMatrix(candidate: validCandidate(footprints: [validFootprint()]), root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "footprint_assignment" })
        let report = try JSONDecoder().decode(FootprintAssignmentReport.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(report.assignments.first?.sourceProviderID, "fixture")
        XCTAssertEqual(report.assignments.first?.sourcePath, "Package_TO_SOT_THT.pretty/TO-3P-3_Vertical.kicad_mod")
        XCTAssertEqual(report.assignments.first?.packageCompatibilityEvidence, "fixture package match")
    }

    private func send(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_assign_footprints"),
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

    private func writeIntent(requiredPins: [String], root: URL) throws -> URL {
        let intent = DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: .naturalLanguage,
            approval: DesignApproval(status: .approved, approvedBy: "test", approvedAt: "2026-05-30T16:00:00Z"),
            requirements: [
                Requirement(id: "req-1", text: "Evidence-gated footprint assignment", priority: "must"),
            ],
            assumptions: [],
            components: [
                ComponentIntent(
                    refdes: "QOUT1",
                    role: "single-ended Class-A output transistor",
                    constraints: ["required_pins": requiredPins.joined(separator: ",")]
                ),
            ],
            nets: [],
            unresolvedDecisions: [],
            boards: [
                BoardIntent(id: "amp_low_voltage_audio", title: "Low Voltage Audio Board", safetyDomain: "isolated_secondary"),
            ],
            safetyProfile: SafetyProfile(isolationRequired: true, creepageMm: 0, notes: []),
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true)
        )
        let url = root.appendingPathComponent("intent.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(intent).write(to: url)
        return url
    }

    private func writeMatrix(candidate: ComponentCandidate, root: URL) throws -> URL {
        let matrix = ComponentMatrix(
            designId: "amp-low-voltage",
            decisions: [
                PartSelectionDecision(
                    refdes: "QOUT1",
                    status: .selected,
                    selectedCandidate: candidate,
                    candidateSet: [candidate],
                    rationale: "fixture selected",
                    evidenceReferences: candidate.evidence,
                    unresolvedDecisions: []
                ),
            ],
            warnings: [],
            providers: ["fixture"],
            cacheMetadata: [:]
        )
        let url = root.appendingPathComponent("component-matrix.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(matrix).write(to: url)
        return url
    }

    private func validCandidate(footprints: [FootprintCandidate]) -> ComponentCandidate {
        ComponentCandidate(
            mpn: "MJ15003G",
            manufacturer: "onsemi",
            normalizedCategory: "bipolar_power_transistor",
            value: nil,
            package: "TO-3",
            ratings: ["vceo_v": "140", "power_w": "250", "current_a": "20"],
            lifecycleState: "active",
            availabilitySummary: "fixture_available",
            datasheets: [
                DatasheetEvidence(
                    manufacturer: "onsemi",
                    mpn: "MJ15003G",
                    url: "https://example.invalid/MJ15003G-D.PDF",
                    localPath: nil,
                    sha256: nil,
                    providerID: "fixture",
                    retrievedAt: "2026-05-30T16:00:00Z",
                    license: "fixture",
                    citations: []
                ),
            ],
            evidence: [
                ComponentEvidence(
                    providerID: "fixture",
                    sourceURL: "https://example.invalid/MJ15003G",
                    localPath: nil,
                    retrievedAt: "2026-05-30T16:00:00Z",
                    cachePolicy: "fixture_no_cache",
                    sha256: nil,
                    extractedParameters: ["mpn": "MJ15003G", "package": "TO-3"],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: footprints
        )
    }

    private func validFootprint() -> FootprintCandidate {
        FootprintCandidate(
            library: "Package_TO_SOT_THT",
            name: "TO-3P-3_Vertical",
            packageCompatibilityEvidence: "fixture package match",
            pinPadMap: ["B": "1", "C": "2", "E": "3"],
            sourceProviderID: "fixture",
            sourcePath: "Package_TO_SOT_THT.pretty/TO-3P-3_Vertical.kicad_mod",
            threeDModel: nil
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-footprint-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
