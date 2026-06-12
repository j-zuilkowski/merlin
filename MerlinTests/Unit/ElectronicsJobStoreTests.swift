import XCTest
@testable import Merlin

@MainActor
final class ElectronicsJobStoreTests: XCTestCase {
    func testJobStoreBuildsStateFromWorkspaceBusEvents() async throws {
        let runtime = try makeRuntime()
        let jobID = "job-1"

        await publishProgress(runtime, jobID: jobID, status: .inProgress)
        await publishArtifact(runtime, jobID: jobID, kind: .routingResult)
        await publishDiagnostic(runtime, jobID: jobID, reason: .unroutedNets)
        await publishApproval(runtime, jobID: jobID, kind: .highStakesSignoff)

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)

        XCTAssertEqual(store.jobs.map(\.id), [jobID])
        XCTAssertEqual(store.jobs[0].status, .blocked)
        XCTAssertEqual(store.jobs[0].artifacts.map(\.kind), [ElectronicsArtifactKind.routingResult.rawValue])
        XCTAssertEqual(store.jobs[0].diagnostics.first?.code, ElectronicsBlockedReason.unroutedNets.rawValue)
        XCTAssertEqual(store.jobs[0].approvalRequests.first?.kind, .highStakesSignoff)
    }

    func testStoresForSameWorkspaceSeeSameRecentJobState() async throws {
        let runtime = try makeRuntime()
        await publishProgress(runtime, jobID: "shared-job", status: .complete)

        let first = ElectronicsJobStore()
        let second = ElectronicsJobStore()
        await first.loadRecent(from: runtime.bus)
        await second.loadRecent(from: runtime.bus)

        XCTAssertEqual(first.jobs, second.jobs)
    }

    func testLeaderboardSeparatesRunningFromCompletedJobs() async throws {
        let runtime = try makeRuntime()
        await publishProgress(runtime, jobID: "complete-job", status: .complete, message: "Workflow complete")
        await publishProgress(runtime, jobID: "running-job", status: .inProgress, message: "Routing PCB")

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)

        XCTAssertEqual(store.leaderboardJobs.map(\.id), ["running-job", "complete-job"])
        XCTAssertEqual(store.runningJobs.map(\.id), ["running-job"])
        XCTAssertEqual(store.completedJobs.map(\.id), ["complete-job"])
        XCTAssertEqual(store.runningJobs.first?.latestProgressMessage, "Routing PCB")
        XCTAssertEqual(store.completedJobs.first?.latestProgressMessage, "Workflow complete")
    }

    func testJobStoreCapturesEndToEndHarnessProgress() async throws {
        let runtime = try makeRuntime()
        let result = ElectronicsEndToEndResult(
            status: .fabReady,
            isComplete: false,
            schematicStatus: .schematicVerified,
            pcbStatus: .pcbVerified,
            spiceStatus: .passed,
            fabricationStatus: .fabReady,
            missingEvidence: ["release_package", "release_approval"],
            diagnostics: [],
            certifiesSafety: false
        )
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "workflow.requirements_to_pcb"),
            origin: nil,
            kind: .progress,
            payload: try .encodeJSON(ElectronicsEndToEndJobProgress(
                jobID: "amp-low-voltage",
                result: result,
                message: "Harness reached FAB_READY"
            ))
        ))

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)

        XCTAssertEqual(store.jobs.first?.id, "amp-low-voltage")
        XCTAssertEqual(store.jobs.first?.endToEndResult?.status, .fabReady)
        XCTAssertEqual(store.jobs.first?.workflowStatusLabel, "FAB_READY")
        XCTAssertEqual(store.jobs.first?.missingEvidenceLabels, ["release_package", "release_approval"])
        XCTAssertFalse(store.jobs.first?.endToEndResult?.isComplete ?? true)
    }

    func testGUIProjectionsUseSingleDisplayStateForFabReadyJobs() async throws {
        let runtime = try makeRuntime()
        try await publishHarnessProgress(
            runtime,
            jobID: "fab-ready-job",
            result: e2eResult(status: .fabReady, fabricationStatus: .fabReady),
            message: "Fabrication evidence passed"
        )

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)

        XCTAssertEqual(store.jobs.first?.displayState.statusLabel, "FAB_READY")
        XCTAssertEqual(store.leaderboardRows.map(\.statusLabel), ["FAB_READY"])
        XCTAssertEqual(store.fabReadyRows.map(\.statusLabel), ["FAB_READY"])
        XCTAssertEqual(store.runningRows.map(\.jobID), [])
        XCTAssertEqual(store.completedRows.map(\.jobID), [])
    }

    func testGUIProjectionsSeparateRunningBlockedFabReadyAndCompleteStates() async throws {
        let runtime = try makeRuntime()
        await publishProgress(runtime, jobID: "running-job", status: .inProgress, message: "Routing PCB")
        await publishDiagnostic(runtime, jobID: "blocked-job", reason: .unroutedNets)
        try await publishHarnessProgress(
            runtime,
            jobID: "fab-ready-job",
            result: e2eResult(status: .fabReady, fabricationStatus: .fabReady),
            message: "Ready for release package"
        )
        try await publishHarnessProgress(
            runtime,
            jobID: "complete-job",
            result: e2eResult(status: .complete, fabricationStatus: .complete, isComplete: true),
            message: "Release complete"
        )

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)

        XCTAssertEqual(store.runningRows.map(\.jobID), ["running-job"])
        XCTAssertEqual(store.blockedRows.map(\.jobID), ["blocked-job"])
        XCTAssertEqual(store.fabReadyRows.map(\.jobID), ["fab-ready-job"])
        XCTAssertEqual(store.completedRows.map(\.jobID), ["complete-job"])
        XCTAssertEqual(
            store.leaderboardRows.map { "\($0.jobID):\($0.statusLabel)" },
            [
                "running-job:IN_PROGRESS",
                "blocked-job:BLOCKED",
                "fab-ready-job:FAB_READY",
                "complete-job:COMPLETE",
            ]
        )
    }

    func testBlockedComponentSelectionRevisionQuestionsProjectIntoDisplayState() async throws {
        let runtime = try makeRuntime()
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_revise_component_selection"),
            origin: nil,
            kind: .diagnostic,
            payload: .jsonString("""
            {
              "job_id": "ampdemo",
              "status": "BLOCKED_INPUT_QUALITY",
              "code": "COMPONENT_SELECTION_REVISION_BLOCKED",
              "message": "Component selection revision still has unresolved decisions.",
              "questions": [
                {
                  "id": "resolve-RPRE1B",
                  "prompt": "For RPRE1B, provide manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility.",
                  "affectedRefs": ["RPRE1B"]
                }
              ],
              "evidence_paths": [
                "/tmp/original-component_matrix.json",
                "/tmp/revised-component_matrix.json"
              ],
              "required_evidence_categories": [
                "manufacturer",
                "mpn",
                "datasheet",
                "footprint_pin_compatibility"
              ]
            }
            """)
        ))

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)

        let row = try XCTUnwrap(store.blockedRows.first)
        XCTAssertEqual(row.jobID, "ampdemo")
        XCTAssertEqual(row.statusLabel, "BLOCKED_INPUT_QUALITY")
        XCTAssertEqual(row.blockedQuestions, [
            "For RPRE1B, provide manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility."
        ])
        XCTAssertEqual(row.evidencePaths, [
            "/tmp/original-component_matrix.json",
            "/tmp/revised-component_matrix.json",
        ])
        XCTAssertEqual(row.requiredEvidenceCategories, [
            "manufacturer",
            "mpn",
            "datasheet",
            "footprint_pin_compatibility",
        ])
    }

    func testBlockedResolverQuestionsProjectActionableAnswerRequirements() async throws {
        let runtime = try makeRuntime()
        await publishBlockedResolverQuestion(runtime)

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)

        let row = try XCTUnwrap(store.blockedRows.first)
        let requirement = try XCTUnwrap(row.resolverAnswerRequirements.first)
        XCTAssertEqual(requirement.questionID, "resolve-QOUT1")
        XCTAssertEqual(requirement.refdes, "QOUT1")
        XCTAssertEqual(requirement.prompt, "For QOUT1, provide manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility.")
        XCTAssertEqual(requirement.requiredEvidenceCategories, [
            "manufacturer",
            "mpn",
            "package",
            "ratings",
            "datasheet",
            "footprint_pin_compatibility",
        ])
        XCTAssertEqual(requirement.evidencePaths, [
            "/tmp/original-component_matrix.json",
            "/tmp/revised-component_matrix.json",
            "/tmp/design_intent.json",
            "/tmp/circuit_ir.json",
        ])
    }

    func testResolverAnswerSubmissionWritesStructuredContinuationMessage() async throws {
        let runtime = try makeRuntime()
        await publishBlockedResolverQuestion(runtime)
        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)
        let injectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-electronics-resolver-answer-\(UUID().uuidString).txt")

        try store.writeResolverAnswerContinuation(
            jobID: "ampdemo",
            answers: [sampleResolverAnswer()],
            to: injectURL
        )

        let message = try String(contentsOf: injectURL, encoding: .utf8)
        XCTAssertTrue(message.hasPrefix("[CONTINUATION]"), message)
        XCTAssertTrue(message.contains("kicad_revise_component_selection"), message)
        XCTAssertTrue(message.contains(#""component_resolution_question_ids":["resolve-QOUT1"]"#), message)
        XCTAssertTrue(message.contains(#""component_resolution_answers""#), message)
        XCTAssertTrue(message.contains(#""refdes":"QOUT1""#), message)
        XCTAssertTrue(message.contains(#""mpn":"MJ15003G""#), message)
        XCTAssertTrue(message.contains(#""datasheet_url":"https://example.invalid/MJ15003G.pdf""#), message)
        XCTAssertTrue(message.contains(#""component_matrix_path":"/tmp/revised-component_matrix.json""#), message)
        XCTAssertTrue(message.contains(#""original_component_matrix_path":"/tmp/original-component_matrix.json""#), message)
        XCTAssertTrue(message.contains(#""design_intent_path":"/tmp/design_intent.json""#), message)
        XCTAssertTrue(message.contains(#""circuit_ir_path":"/tmp/circuit_ir.json""#), message)
    }

    private func makeRuntime() throws -> WorkspaceRuntime {
        try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp/electronics-job-store"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-electronics-jobs-\(UUID().uuidString)")
        )
    }

    private func publishProgress(
        _ runtime: WorkspaceRuntime,
        jobID: String,
        status: KiCadStatus,
        message: String = "Routing"
    ) async {
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "job.progress"),
            origin: nil,
            kind: .progress,
            payload: .jsonString(#"{"job_id":"\#(jobID)","status":"\#(status.rawValue)","message":"\#(message)"}"#)
        ))
    }

    private func publishArtifact(_ runtime: WorkspaceRuntime, jobID: String, kind: ElectronicsArtifactKind) async {
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "job.artifact"),
            origin: nil,
            kind: .artifactProduced,
            payload: try? .encodeJSON(WorkspaceArtifactRef(
                id: "artifact-\(jobID)",
                kind: kind.rawValue,
                url: URL(fileURLWithPath: "/tmp/\(jobID).ses"),
                displayName: "Route Result",
                metadata: ["job_id": jobID]
            ))
        ))
    }

    private func publishDiagnostic(_ runtime: WorkspaceRuntime, jobID: String, reason: ElectronicsBlockedReason) async {
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "job.diagnostic"),
            origin: nil,
            kind: .diagnostic,
            payload: .jsonString(#"{"job_id":"\#(jobID)","code":"\#(reason.rawValue)","message":"Route blocked"}"#)
        ))
    }

    private func publishApproval(_ runtime: WorkspaceRuntime, jobID: String, kind: ElectronicsApprovalKind) async {
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "job.approval"),
            origin: nil,
            kind: .approvalRequired,
            payload: .jsonString(#"{"job_id":"\#(jobID)","kind":"\#(kind.rawValue)","summary":"Review release"}"#)
        ))
    }

    private func publishBlockedResolverQuestion(_ runtime: WorkspaceRuntime) async {
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_revise_component_selection"),
            origin: nil,
            kind: .diagnostic,
            payload: .jsonString("""
            {
              "job_id": "ampdemo",
              "status": "BLOCKED_INPUT_QUALITY",
              "code": "COMPONENT_SELECTION_REVISION_BLOCKED",
              "message": "Component selection revision still has unresolved decisions.",
              "questions": [
                {
                  "id": "resolve-QOUT1",
                  "prompt": "For QOUT1, provide manufacturer, MPN, package, ratings, datasheet/provenance evidence, and footprint/pin compatibility.",
                  "affectedRefs": ["QOUT1"]
                }
              ],
              "required_evidence_categories": [
                "manufacturer",
                "mpn",
                "package",
                "ratings",
                "datasheet",
                "footprint_pin_compatibility"
              ],
              "handoff": {
                "design_intent_path": "/tmp/design_intent.json",
                "circuit_ir_path": "/tmp/circuit_ir.json",
                "original_component_matrix_path": "/tmp/original-component_matrix.json",
                "component_matrix_path": "/tmp/revised-component_matrix.json"
              }
            }
            """)
        ))
    }

    private func sampleResolverAnswer() -> ElectronicsComponentResolutionAnswer {
        ElectronicsComponentResolutionAnswer(
            refdes: "QOUT1",
            manufacturer: "onsemi",
            mpn: "MJ15003G",
            normalizedCategory: "power_transistor",
            package: "TO-3",
            ratings: ["voltage_v": "140", "current_a": "20", "power_w": "250"],
            datasheetURL: "https://example.invalid/MJ15003G.pdf",
            sourceURL: "https://provider.example/MJ15003G",
            availabilitySummary: "100 In Stock",
            lifecycleState: "Active",
            footprint: ElectronicsComponentResolutionFootprintAnswer(
                library: "Package_TO_SOT_THT",
                name: "TO-3",
                packageCompatibilityEvidence: "TO-3 package and pinout supplied by resolver answer",
                pinPadMap: ["B": "1", "C": "2"],
                sourceProviderID: "component_resolution_answer"
            )
        )
    }

    private func publishHarnessProgress(
        _ runtime: WorkspaceRuntime,
        jobID: String,
        result: ElectronicsEndToEndResult,
        message: String
    ) async throws {
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "workflow.requirements_to_pcb"),
            origin: nil,
            kind: .progress,
            payload: try .encodeJSON(ElectronicsEndToEndJobProgress(
                jobID: jobID,
                result: result,
                message: message
            ))
        ))
    }

    private func e2eResult(
        status: ElectronicsEndToEndStatus,
        fabricationStatus: FabricationReleaseStatus,
        isComplete: Bool = false
    ) -> ElectronicsEndToEndResult {
        ElectronicsEndToEndResult(
            status: status,
            isComplete: isComplete,
            schematicStatus: .schematicVerified,
            pcbStatus: .pcbVerified,
            spiceStatus: .passed,
            fabricationStatus: fabricationStatus,
            missingEvidence: status == .fabReady ? ["release_package", "release_approval"] : [],
            diagnostics: [],
            certifiesSafety: false
        )
    }
}
