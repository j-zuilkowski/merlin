import XCTest
@testable import Merlin

/// Task 296a — failing tests for subagent-sidebar wiring.
@MainActor
final class SubagentSidebarWiringTests: XCTestCase {

    func testSubagentStartedAddsSidebarEntry() {
        let model = ChatViewModel()
        let sidebar = SubagentSidebarViewModel(parentSessionID: UUID())
        model.subagentSidebar = sidebar
        let id = UUID()
        model.applyEngineEvent(.subagentStarted(id: id, agentName: "explorer"))
        XCTAssertEqual(sidebar.workerEntries.count, 1)
        XCTAssertEqual(sidebar.workerEntries.first?.agentName, "explorer")
        XCTAssertEqual(sidebar.workerEntries.first?.id, id)
        XCTAssertEqual(sidebar.selectedEntryID, id)
    }

    func testSubagentCompletedMarksSidebarEntryCompleted() {
        let model = ChatViewModel()
        let sidebar = SubagentSidebarViewModel(parentSessionID: UUID())
        model.subagentSidebar = sidebar
        let id = UUID()
        model.applyEngineEvent(.subagentStarted(id: id, agentName: "explorer"))
        model.applyEngineEvent(.subagentUpdate(id: id, event: .completed(summary: "done")))
        XCTAssertEqual(sidebar.workerEntries.first?.status, .completed)
    }

    func testWorkerReadyAttachesWorktreeAndStagingBufferToSidebarEntry() {
        let model = ChatViewModel()
        let sidebar = SubagentSidebarViewModel(parentSessionID: UUID())
        model.subagentSidebar = sidebar
        let id = UUID()
        let worktreePath = URL(fileURLWithPath: "/tmp/worker")
        let buffer = StagingBuffer()

        model.applyEngineEvent(.subagentStarted(id: id, agentName: "worker"))
        model.applyEngineEvent(.subagentUpdate(
            id: id,
            event: .workerReady(worktreePath: worktreePath, stagingBuffer: buffer)
        ))

        XCTAssertEqual(sidebar.workerEntries.first?.worktreePath, worktreePath)
        XCTAssertTrue(sidebar.workerEntries.first?.stagingBuffer === buffer)
        XCTAssertEqual(sidebar.selectedEntryID, id)
    }

    func testWorkerCompletionKeepsWorkerDiffSelected() {
        let model = ChatViewModel()
        let sidebar = SubagentSidebarViewModel(parentSessionID: UUID())
        model.subagentSidebar = sidebar
        let id = UUID()
        let buffer = StagingBuffer()

        model.applyEngineEvent(.subagentStarted(id: id, agentName: "worker"))
        model.applyEngineEvent(.subagentUpdate(
            id: id,
            event: .workerReady(worktreePath: URL(fileURLWithPath: "/tmp/worker"), stagingBuffer: buffer)
        ))
        model.applyEngineEvent(.subagentUpdate(id: id, event: .completed(summary: "done")))

        XCTAssertEqual(sidebar.workerEntries.first?.status, .completed)
        XCTAssertTrue(sidebar.workerEntries.first?.stagingBuffer === buffer)
        XCTAssertEqual(sidebar.selectedEntryID, id)
    }
}
