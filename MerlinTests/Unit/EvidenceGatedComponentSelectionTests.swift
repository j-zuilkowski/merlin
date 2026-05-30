import XCTest
@testable import Merlin

@MainActor
final class EvidenceGatedComponentSelectionTests: XCTestCase {
    func testRoleOnlyComponentIntentRequiresVendorResolutionWhenNoProviderConfigured() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "QOUT1", role: "single-ended Class-A output transistor"), root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.map(\.status), [.requiresVendorResolution])
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
    }

    func testFixtureProviderEvidenceCanSelectComponent() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "QOUT1", role: "single-ended Class-A output transistor"), root: root)
        let catalogURL = try writeCandidates([validCandidate(mpn: "MJ15003G")], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.map(\.status), [.selected])
        XCTAssertEqual(matrix.decisions.first?.selectedCandidate?.mpn, "MJ15003G")
        XCTAssertEqual(matrix.providers, ["fixture"])
    }

    func testMultipleValidCandidatesAreAmbiguous() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "BR1", role: "bridge rectifier"), root: root)
        let catalogURL = try writeCandidates([
            validCandidate(mpn: "GBU806", category: "bridge_rectifier"),
            validCandidate(mpn: "GBU808", category: "bridge_rectifier"),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .ok)
        let matrix = try decodeMatrix(from: response)
        XCTAssertEqual(matrix.decisions.map(\.status), [.ambiguous])
        XCTAssertEqual(matrix.decisions.first?.candidateSet.count, 2)
        XCTAssertNil(matrix.decisions.first?.selectedCandidate)
    }

    func testIncompleteProviderCandidateBlocksSelection() async throws {
        let root = try temporaryDirectory()
        let runtime = try WorkspaceRuntime(rootURL: root)
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let intentURL = try writeIntent(component(refdes: "QOUT1", role: "single-ended Class-A output transistor"), root: root)
        let catalogURL = try writeCandidates([
            ComponentCandidate(
                mpn: "UNKNOWN",
                manufacturer: "",
                normalizedCategory: "power_transistor",
                value: nil,
                package: "",
                ratings: [:],
                lifecycleState: "",
                availabilitySummary: "",
                datasheets: [],
                evidence: [],
                footprintCandidates: []
            ),
        ], root: root)

        let response = await send(
            runtime,
            payload: #"{"design_id":"amp-low-voltage","design_intent_path":"\#(intentURL.path)","catalog_candidates_path":"\#(catalogURL.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        let result = try XCTUnwrap(response.payload?.decodeJSON(KiCadToolResult.self))
        XCTAssertTrue(result.warnings.contains { $0.code == "COMPONENT_SELECTION_BLOCKED" })
        let matrixArtifact = try XCTUnwrap(response.artifacts.first { $0.kind == "component_matrix" })
        let matrix = try JSONDecoder().decode(ComponentMatrix.self, from: Data(contentsOf: matrixArtifact.url))
        XCTAssertEqual(matrix.decisions.map(\.status), [.blocked])
    }

    private func decodeMatrix(from response: WorkspaceMessageResponse) throws -> ComponentMatrix {
        let artifact = try XCTUnwrap(response.artifacts.first { $0.kind == "component_matrix" })
        return try JSONDecoder().decode(ComponentMatrix.self, from: Data(contentsOf: artifact.url))
    }

    private func component(refdes: String, role: String) -> ComponentIntent {
        ComponentIntent(refdes: refdes, role: role, constraints: ["implementation": "discrete"])
    }

    private func writeIntent(_ component: ComponentIntent, root: URL) throws -> URL {
        let intent = DesignIntent(
            designId: "amp-low-voltage",
            title: "Amp Low Voltage Audio Board",
            origin: .naturalLanguage,
            approval: DesignApproval(status: .approved, approvedBy: "test", approvedAt: "2026-05-30T15:00:00Z"),
            requirements: [
                Requirement(id: "req-1", text: "Evidence-gated component selection", priority: "must"),
            ],
            assumptions: [],
            components: [component],
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

    private func writeCandidates(_ candidates: [ComponentCandidate], root: URL) throws -> URL {
        let url = root.appendingPathComponent("catalog-candidates.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(candidates).write(to: url)
        return url
    }

    private func validCandidate(mpn: String, category: String = "power_transistor") -> ComponentCandidate {
        ComponentCandidate(
            mpn: mpn,
            manufacturer: "onsemi",
            normalizedCategory: category,
            value: nil,
            package: "TO-3",
            ratings: ["voltage_v": "140", "current_a": "20", "power_w": "250"],
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
                    retrievedAt: "2026-05-30T15:00:00Z",
                    license: "fixture",
                    citations: []
                ),
            ],
            evidence: [
                ComponentEvidence(
                    providerID: "fixture",
                    sourceURL: "https://example.invalid/\(mpn)",
                    localPath: nil,
                    retrievedAt: "2026-05-30T15:00:00Z",
                    cachePolicy: "fixture_no_cache",
                    sha256: nil,
                    extractedParameters: ["mpn": mpn, "package": "TO-3"],
                    confidence: 1.0,
                    warnings: []
                ),
            ],
            footprintCandidates: [
                FootprintCandidate(
                    library: "Package_TO_SOT_THT",
                    name: "TO-3",
                    packageCompatibilityEvidence: "fixture package match",
                    pinPadMap: ["B": "1", "C": "2"],
                    sourceProviderID: "fixture",
                    sourcePath: "Package_TO_SOT_THT.pretty/TO-3.kicad_mod",
                    threeDModel: nil
                ),
            ]
        )
    }

    private func send(_ runtime: WorkspaceRuntime, payload: String) async -> WorkspaceMessageResponse {
        await runtime.bus.send(WorkspaceMessageRequest(
            id: UUID(),
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_select_components"),
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
            .appendingPathComponent("merlin-evidence-selection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
