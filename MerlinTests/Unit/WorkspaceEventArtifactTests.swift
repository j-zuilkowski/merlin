import XCTest
@testable import Merlin

@MainActor
final class WorkspaceEventArtifactTests: XCTestCase {
    func testArtifactMetadataPersistsAndEventHistoryIsRecentOnly() async throws {
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-artifact-tests-\(UUID().uuidString)"),
            eventCapacity: 100
        )
        let artifact = WorkspaceArtifactRef(
            id: "artifact-1",
            kind: "report",
            url: runtime.stateRootURL.appendingPathComponent("report.txt"),
            displayName: "Report",
            metadata: ["source": "test"]
        )

        try runtime.artifactStore.save(artifact)
        let loaded = try runtime.artifactStore.loadAll()
        XCTAssertEqual(loaded, [artifact])

        for index in 0..<150 {
            await runtime.bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: nil,
                address: WorkspaceMessageAddress(namespace: "workflow.demo", capability: "progress"),
                origin: nil,
                kind: index == 149 ? .artifactProduced : .progress,
                payload: .jsonString(#"{"index":\#(index)}"#)
            ))
        }

        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "workflow."))
        XCTAssertEqual(events.count, 100)
        XCTAssertEqual(events.last?.kind, .artifactProduced)
    }
}
