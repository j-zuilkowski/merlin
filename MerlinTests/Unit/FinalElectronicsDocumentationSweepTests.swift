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

    func testReleaseDocsRequireKiCadScreenshotsAfterGreenBattery() throws {
        let docs = try [
            "spec.md",
            "Merlin/Docs/UserGuide.md",
            "Merlin/Docs/DeveloperManual.md",
        ].map { try repoText($0) }.joined(separator: "\n")

        XCTAssertTrue(docs.contains("after the full battery is green"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("open the generated KiCad schematic"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("open the generated KiCad PCB"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("capture release screenshots"))
    }

    func testReadmeReflectsCurrentReleaseGateAndKiCadScreenshots() throws {
        let readme = try repoText("README.md")
        let screenshotPaths = [
            "docs/assets/screenshots/v2.4.0/merlin-workspace.png",
            "docs/assets/screenshots/v2.4.0/merlin-settings-providers.png",
            "docs/assets/screenshots/v2.4.0/merlin-settings-provider-slots.png",
            "docs/assets/screenshots/v2.4.0/kicad-schematic-editor.png",
            "docs/assets/screenshots/v2.4.0/kicad-pcb-editor.png",
            "docs/assets/screenshots/v2.4.0/kicad-3d-viewer.png",
            "docs/assets/screenshots/v2.4.0/kicad-routed-composite.png",
        ]

        XCTAssertTrue(readme.contains("Version 2.4.0"))
        XCTAssertTrue(readme.localizedCaseInsensitiveContains("full green E2E"))
        XCTAssertTrue(readme.localizedCaseInsensitiveContains("after the full battery is green"))
        XCTAssertTrue(readme.localizedCaseInsensitiveContains("open the generated KiCad schematic"))
        XCTAssertTrue(readme.localizedCaseInsensitiveContains("open the generated KiCad PCB"))
        for screenshotPath in screenshotPaths {
            XCTAssertTrue(readme.contains(screenshotPath), screenshotPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL(screenshotPath).path), screenshotPath)
        }

        let electronicsSection = try XCTUnwrap(readme.range(of: "**Electronics / KiCad Domain**"))
        let multiDomainSection = try XCTUnwrap(readme.range(of: "**Multi-Domain Sessions**"))
        for screenshotPath in screenshotPaths.filter({ $0.contains("/kicad-") }) {
            let pathRange = try XCTUnwrap(readme.range(of: screenshotPath), screenshotPath)
            XCTAssertGreaterThanOrEqual(pathRange.lowerBound, electronicsSection.lowerBound, screenshotPath)
            XCTAssertLessThan(pathRange.lowerBound, multiDomainSection.lowerBound, screenshotPath)
        }
    }

    func testDocsDefineGitHubScreenshotDestinations() throws {
        let docs = try [
            "README.md",
            "spec.md",
        ].map { try repoText($0) }.joined(separator: "\n")

        XCTAssertTrue(docs.contains("docs/assets/screenshots/v2.4.0/"))
        XCTAssertTrue(docs.contains("docs/e2e/<date>-v2.4.0-release/screenshots/"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("GitHub Release"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("release assets"))
    }

    func testReleaseRunLedgerIsResumableAndBlocksScreenshotsUntilGreen() throws {
        let ledger = try repoText("docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md")

        XCTAssertTrue(ledger.contains("Full Green E2E Battery"))
        XCTAssertTrue(ledger.contains("| 1 | Core test target"))
        XCTAssertTrue(ledger.contains("| 9 | Electronics/KiCad"))
        XCTAssertTrue(ledger.contains("| 10 | KiCad release screenshots"))
        XCTAssertTrue(ledger.contains("| 11 | GitHub and README feature screenshots | passed |"))
        XCTAssertTrue(ledger.contains("blocked"))
        XCTAssertTrue(ledger.localizedCaseInsensitiveContains("after the full battery is green"))
        XCTAssertTrue(ledger.contains("docs/e2e/2026-06-08-v2.4.0-release/logs/"))
        XCTAssertTrue(ledger.contains("docs/e2e/2026-06-08-v2.4.0-release/logs/11-readme-screenshots.log"))
    }

    func testReleaseEvidenceReportSummarizesPassedGatesAndBoundaries() throws {
        let report = try repoText("docs/e2e/2026-06-08-v2.4.0-release/REPORT.md")
        let ledger = try repoText("docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md")

        XCTAssertTrue(report.contains("Overall status: **passed through gate #14**"), report)
        XCTAssertTrue(report.contains("Gates #1-#14 are passed"), report)
        XCTAssertTrue(report.contains("docs/e2e/2026-06-08-v2.4.0-release/logs/01-MerlinTests.log"), report)
        XCTAssertTrue(report.contains("docs/e2e/2026-06-08-v2.4.0-release/logs/08-capability-runner.log"), report)
        XCTAssertTrue(report.contains("docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log"), report)
        XCTAssertTrue(report.contains("docs/e2e/2026-06-08-v2.4.0-release/screenshots/kicad/README.md"), report)
        XCTAssertTrue(report.contains("docs/assets/screenshots/v2.4.0/"), report)
        XCTAssertTrue(report.contains("0 DRC violations, 0 unconnected items, and 0 schematic parity issues"), report)
        XCTAssertTrue(report.contains("59 schematic parity warnings"), report)
        XCTAssertTrue(report.localizedCaseInsensitiveContains("not a fabrication-ready claim"), report)
        XCTAssertTrue(report.contains("No Merlin app processes remain"), report)
        XCTAssertTrue(report.contains("No 8081 or 8083 listeners"), report)
        XCTAssertTrue(ledger.contains("| 12 | Release evidence report | passed |"), ledger)
        XCTAssertTrue(ledger.contains("docs/e2e/2026-06-08-v2.4.0-release/REPORT.md"), ledger)
    }

    func testFinalSafetyGateRecordsCleanVersionEvidenceAndProcessState() throws {
        let safety = try repoText("docs/e2e/2026-06-08-v2.4.0-release/logs/13-final-safety.log")
        let ledger = try repoText("docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md")

        XCTAssertTrue(safety.contains("Initial git status: clean"), safety)
        XCTAssertTrue(safety.contains("MARKETING_VERSION: \"2.4.0\""), safety)
        XCTAssertTrue(safety.contains("CURRENT_PROJECT_VERSION: 26"), safety)
        XCTAssertTrue(safety.contains("Release evidence present: yes"), safety)
        XCTAssertTrue(safety.contains("README screenshot assets present: 7"), safety)
        XCTAssertTrue(safety.contains("No Merlin app processes remain"), safety)
        XCTAssertTrue(safety.contains("No KiCad app processes remain"), safety)
        XCTAssertTrue(safety.contains("No release helper services remain on 8081 or 8083"), safety)
        XCTAssertTrue(safety.contains("Local tag v2.4.0 absent"), safety)
        XCTAssertTrue(safety.contains("Remote tag v2.4.0 absent"), safety)
        XCTAssertTrue(ledger.contains("| 13 | Final safety check: clean status, version 2.4.0, evidence present, no orphan services/helpers | passed |"), ledger)
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

    func testElectronicsFinishChecklistMatchesFinalEvidenceContract() throws {
        let handoff = try repoText("tasks/HANDOFF.md")
        XCTAssertTrue(handoff.contains("Latest completed task is Task 517"), handoff)
        XCTAssertTrue(handoff.contains("[x] **F5: Completion contract and status cleanup."), handoff)
        XCTAssertTrue(handoff.contains("Electronics domain status: finished as evidence-gated workflow infrastructure"), handoff)
        XCTAssertTrue(handoff.contains("current GUI proof stops at `COMPONENT_SELECTION_REVISION_BLOCKED`"), handoff)
        XCTAssertTrue(handoff.contains("Task 492 added"), handoff)
        XCTAssertTrue(handoff.contains("Task 503 passed release gate #8"), handoff)
        XCTAssertTrue(handoff.contains("Task 504 passed release gate #9"), handoff)
        XCTAssertTrue(handoff.contains("Task 512 supersedes that evidence"), handoff)
        XCTAssertTrue(handoff.contains("72 track segments, 18 nets, and 0"), handoff)
        XCTAssertTrue(handoff.contains("Task 506 passed release gate #11"), handoff)
        XCTAssertTrue(handoff.contains("Task 507 passed release gate #12"), handoff)
        XCTAssertTrue(handoff.contains("Task 508 passed release gate #13"), handoff)
        XCTAssertTrue(handoff.contains("Task 513 reran gate #13"), handoff)
        XCTAssertTrue(handoff.contains("Task 514 completed release gate #14"), handoff)
        XCTAssertTrue(handoff.contains("Task 515 performed a focused documentation sweep"), handoff)
        XCTAssertTrue(handoff.contains("Task 516 moves the README KiCad screenshots"), handoff)
        XCTAssertTrue(handoff.contains("Task 517 repairs the PR #3 GitHub CI failure"), handoff)

        let pluginSpec = try repoText("plugins/electronics/spec.md")
        XCTAssertTrue(pluginSpec.contains("Current Completion Contract"), pluginSpec)
        XCTAssertTrue(pluginSpec.contains("FAB_READY"), pluginSpec)
        XCTAssertTrue(pluginSpec.contains("COMPONENT_SELECTION_REVISION_BLOCKED"), pluginSpec)
        XCTAssertTrue(pluginSpec.contains("requirements -> DesignIntent -> Circuit IR -> component selection/revision"), pluginSpec)

        for stalePhrase in [
            "Out Of Scope For First Milestone",
            "Full PCB completion and fabrication release",
            "Full autonomous natural-language-to-fabrication workflow",
            "First milestone targets `amp_low_voltage_audio` schematic verification only.",
            "The power-supply board is a second milestone.",
            "Minimum First Implementation Tasks",
        ] {
            XCTAssertFalse(pluginSpec.contains(stalePhrase), stalePhrase)
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
