import XCTest
@testable import Merlin

final class FinalElectronicsDocumentationSweepTests: XCTestCase {
    func testFinalDocsDescribeEvidenceGatedCompletion() throws {
        let docs = try [
            "spec.md",
            "FEATURES.md",
            "Merlin/Docs/UserGuide.md",
            "Merlin/Docs/DeveloperManual.md",
        ].map { try repoText($0) }.joined(separator: "\n")

        XCTAssertTrue(docs.localizedCaseInsensitiveContains("evidence-gated"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("placeholder"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("LocalFreeRoutingBackend"))
        XCTAssertFalse(docs.contains("target server is `merlin-kicad-mcp`"))
    }

    func testCurrentDocsNameActiveElectronicsRuntimePlugin() throws {
        let activeDocPaths = [
            "README.md",
            "Requirements.md",
            "Merlin/Docs/UserGuide.md",
            "Merlin/Docs/DeveloperManual.md",
            "merlin-eval/README.md",
            "merlin-eval/scenarios/S6-electronics.md",
            "merlin-eval/BLOCKED.md",
            "merlin-eval/PROVING-RUN-STATE.md",
        ]
        let docs = try activeDocPaths.map { try repoText($0) }.joined(separator: "\n")

        XCTAssertTrue(docs.contains("plugins/electronics"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("evidence-gated"))

        for stalePhrase in [
            "built on `merlin-kicad-mcp`",
            "merlin/plugins/merlin-kicad-mcp",
            "Register the merlin-kicad-mcp server",
            "merlin-kicad-mcp server registered",
            "KiCad 10.0.3, merlin-kicad-mcp",
            "merlin-kicad-mcp + FreeRouting",
        ] {
            XCTAssertFalse(docs.contains(stalePhrase), stalePhrase)
        }
    }
}

@MainActor
func testRuntime() throws -> WorkspaceRuntime {
    try WorkspaceRuntime(
        rootURL: temporaryDirectory("workspace"),
        merlinHomeURL: temporaryDirectory("home").appendingPathComponent(".merlin")
    )
}

@MainActor
func sendElectronics(
    _ runtime: WorkspaceRuntime,
    capability: String,
    payload: String,
    scope: WorkspacePermissionScope = .externalSideEffect
) async -> WorkspaceMessageResponse {
    await runtime.bus.send(WorkspaceMessageRequest(
        id: UUID(),
        address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: capability),
        origin: .parentSession(
            workspaceID: runtime.workspaceID,
            sessionID: nil,
            activeDomainIDs: [ElectronicsDomain.defaultID],
            permissionScope: scope
        ),
        payload: .jsonString(payload),
        cancellationGroup: nil
    ))
}

func workflowPayload(
    jobID: String,
    highStakes: Bool,
    approvals: [ElectronicsApprovalRecord] = []
) throws -> String {
    let artifacts = try completionFixtureArtifacts(jobID: jobID)
    let evidence = ElectronicsCompletionEvidence(
        artifacts: artifacts,
        gates: ElectronicsGateResult.allPassingRequired,
        approvals: approvals,
        highStakes: highStakes
    )
    let request = ElectronicsWorkflowRequest(jobID: jobID, evidence: evidence)
    let data = try WorkspaceJSON.encoder.encode(request)
    return String(data: data, encoding: .utf8) ?? "{}"
}

func completionFixtureArtifacts(jobID: String) throws -> [ElectronicsCompletionArtifact] {
    let directory = temporaryDirectory("electronics-completion-\(jobID)")
    let paths: [(ElectronicsArtifactKind, String, String)] = [
        (.kicadProject, "project.kicad_pro", #"{"meta":{"version":1}}"#),
        (.schematic, "project.kicad_sch", "(kicad_sch (version 20250114) (generator Merlin))\n"),
        (.board, "project.kicad_pcb", "(kicad_pcb (version 20250114) (generator Merlin))\n"),
        (.routingInterchange, "project.dsn", "dsn route interchange\n"),
        (.routingResult, "project.ses", "ses route result unrouted_nets=0\n"),
        (.bom, "bom.csv", "RefDes,Value,MPN,DigiKey,Mouser,Quantity\nR1,10k,RC0603FR-0710KL,311-10.0KHRCT-ND,603-RC0603FR-0710KL,1\n"),
        (.pickAndPlace, "centroid.csv", "Designator,Mid X,Mid Y,Layer,Rotation\nR1,1,1,F.Cu,0\n"),
        (.spiceMeasurements, "spice-run.log", "frequency = 1000\n"),
        (.verificationReport, "verification.json", #"{"status":"COMPLETE"}"#),
        (.approvalRecord, "approvals.json", #"{"approved":true}"#),
    ]

    var artifacts: [ElectronicsCompletionArtifact] = []
    for (kind, name, body) in paths {
        let url = directory.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        artifacts.append(ElectronicsCompletionArtifact(kind: kind, path: url.path))
    }

    let fabURL = directory.appendingPathComponent("fab.zip")
    try Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]).write(to: fabURL)
    artifacts.append(ElectronicsCompletionArtifact(kind: .fabricationPackage, path: fabURL.path))

    return artifacts
}

func temporaryDirectory(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("merlin-\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func repoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(relative)
}

func repoText(_ relative: String) throws -> String {
    try String(contentsOf: repoURL(relative), encoding: .utf8)
}

actor RecordingElectronicsRouteBackend: ElectronicsRoutePassRunning {
    private(set) var callCount = 0
    let result: KiCadToolResult

    init(result: KiCadToolResult) {
        self.result = result
    }

    func route(
        _ request: LocalFreeRoutingRequest,
        bus: WorkspaceMessageBus,
        origin: WorkspaceMessageOrigin
    ) async -> KiCadToolResult {
        callCount += 1
        if result.status == .complete {
            await bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: UUID(),
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_route_pass"),
                origin: origin,
                kind: .artifactProduced,
                payload: try? .encodeJSON(WorkspaceArtifactRef(
                    id: "\(request.jobID)-routing",
                    kind: ElectronicsArtifactKind.routingResult.rawValue,
                    url: request.sesURL,
                    displayName: "Routing Result",
                    metadata: ["job_id": request.jobID]
                ))
            ))
        }
        return result
    }

    func recordedCallCount() -> Int {
        callCount
    }
}
