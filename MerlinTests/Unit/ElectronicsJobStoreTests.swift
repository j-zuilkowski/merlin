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
}
