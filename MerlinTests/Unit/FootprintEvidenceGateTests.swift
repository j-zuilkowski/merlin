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

    func testCircuitIRComponentsDriveFootprintAssignments() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(requiredPins: ["B", "C", "E"], root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
            circuitComponent(refdes: "CFILT1", role: "sweepable boost/cut capacitor", selectedSymbol: "Device:C", pins: ["1", "2"]),
        ], root: root)
        let matrixURL = try writeMatrix([
            decision(refdes: "RFILT1", candidate: validCandidate(mpn: "RC0603FR-0710KL", category: "resistor", footprint: passiveFootprint(name: "R_0603_1608Metric"))),
            decision(refdes: "CFILT1", candidate: validCandidate(mpn: "C0603C473K5RACTU", category: "capacitor", footprint: passiveFootprint(name: "C_0603_1608Metric"))),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)","circuit_ir_path":"\#(circuitIRURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "footprint_assignment" })
        let report = try JSONDecoder().decode(FootprintAssignmentReport.self, from: Data(contentsOf: artifact.url))
        XCTAssertEqual(Set(report.assignments.map(\.refdes)), ["RFILT1", "CFILT1"])
        XCTAssertEqual(report.assignments.first { $0.refdes == "RFILT1" }?.pinPadMap["1"], "1")
        XCTAssertEqual(report.assignments.first { $0.refdes == "CFILT1" }?.pinPadMap["2"], "2")
    }

    func testCircuitIRFootprintAssignmentBlocksWhenMatrixOmitsExpandedComponent() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(requiredPins: ["B", "C", "E"], root: root)
        let circuitIRURL = try writeCircuitIR([
            circuitComponent(refdes: "RFILT1", role: "sweepable boost/cut resistor", selectedSymbol: "Device:R", pins: ["1", "2"]),
            circuitComponent(refdes: "CFILT1", role: "sweepable boost/cut capacitor", selectedSymbol: "Device:C", pins: ["1", "2"]),
        ], root: root)
        let matrixURL = try writeMatrix([
            decision(refdes: "RFILT1", candidate: validCandidate(mpn: "RC0603FR-0710KL", category: "resistor", footprint: passiveFootprint(name: "R_0603_1608Metric"))),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","component_matrix_path":"\#(matrixURL.path)","circuit_ir_path":"\#(circuitIRURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        let warning = try XCTUnwrap(result.warnings.first { $0.code == "FOOTPRINT_SELECTION_REQUIRED" })
        XCTAssertTrue(warning.affectedRefs.contains("CFILT1"))
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
        try writeMatrix([decision(refdes: "QOUT1", candidate: candidate)], root: root)
    }

    private func writeMatrix(_ decisions: [PartSelectionDecision], root: URL) throws -> URL {
        let matrix = ComponentMatrix(
            designId: "amp-low-voltage",
            decisions: decisions,
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

    private func decision(refdes: String, candidate: ComponentCandidate) -> PartSelectionDecision {
        PartSelectionDecision(
            refdes: refdes,
            status: .selected,
            selectedCandidate: candidate,
            candidateSet: [candidate],
            rationale: "fixture selected",
            evidenceReferences: candidate.evidence,
            unresolvedDecisions: []
        )
    }

    private func validCandidate(footprints: [FootprintCandidate]) -> ComponentCandidate {
        validCandidate(mpn: "MJ15003G", category: "bipolar_power_transistor", footprints: footprints)
    }

    private func validCandidate(mpn: String, category: String, footprint: FootprintCandidate?) -> ComponentCandidate {
        validCandidate(mpn: mpn, category: category, footprints: footprint.map { [$0] } ?? [])
    }

    private func validCandidate(mpn: String, category: String, footprints: [FootprintCandidate]) -> ComponentCandidate {
        ComponentCandidate(
            mpn: mpn,
            manufacturer: "onsemi",
            normalizedCategory: category,
            value: nil,
            package: "TO-3",
            ratings: ["vceo_v": "140", "power_w": "250", "current_a": "20"],
            lifecycleState: "active",
            availabilitySummary: "fixture_available",
            datasheets: [
                DatasheetEvidence(
                    manufacturer: "onsemi",
                    mpn: mpn,
                    url: "https://example.invalid/\(mpn).pdf",
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
                    sourceURL: "https://example.invalid/\(mpn)",
                    localPath: nil,
                    retrievedAt: "2026-05-30T16:00:00Z",
                    cachePolicy: "fixture_no_cache",
                    sha256: nil,
                    extractedParameters: ["mpn": mpn, "package": "TO-3"],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: footprints
        )
    }

    private func passiveFootprint(name: String) -> FootprintCandidate {
        FootprintCandidate(
            library: "Resistor_SMD",
            name: name,
            packageCompatibilityEvidence: "fixture passive 0603 package match",
            pinPadMap: ["1": "1", "2": "2"],
            sourceProviderID: "fixture",
            sourcePath: "Resistor_SMD.pretty/\(name).kicad_mod",
            threeDModel: nil
        )
    }

    private func writeCircuitIR(_ components: [CircuitComponent], root: URL) throws -> URL {
        let circuitIR = CircuitIR(
            designId: "amp-low-voltage",
            boardId: "amp_low_voltage_audio",
            components: components,
            nets: [],
            constraints: [],
            verificationScenarios: []
        )
        let url = root.appendingPathComponent("circuit-ir.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(circuitIR).write(to: url)
        return url
    }

    private func circuitComponent(refdes: String, role: String, selectedSymbol: String, pins: [String]) -> CircuitComponent {
        CircuitComponent(
            refdes: refdes,
            role: role,
            selectedSymbol: selectedSymbol,
            selectedFootprint: nil,
            manufacturerPartNumber: nil,
            sourceEvidence: [SourceEvidence(kind: "design_intent_component", reference: "FILTER1")],
            pins: pins.map {
                CircuitPin(
                    componentRefdes: refdes,
                    pinNumber: $0,
                    canonicalName: $0,
                    electricalType: "passive",
                    symbolPin: $0,
                    footprintPad: nil
                )
            }
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
