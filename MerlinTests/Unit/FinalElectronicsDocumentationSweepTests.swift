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
    let evidence = ElectronicsCompletionEvidence(
        artifacts: ElectronicsCompletionArtifact.requiredFixtureArtifacts,
        gates: ElectronicsGateResult.allPassingRequired,
        approvals: approvals,
        highStakes: highStakes
    )
    let request = ElectronicsWorkflowRequest(jobID: jobID, evidence: evidence)
    let data = try WorkspaceJSON.encoder.encode(request)
    return String(data: data, encoding: .utf8) ?? "{}"
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
