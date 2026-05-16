import XCTest
@testable import Merlin

/// Phase 296a — failing tests for subagent-sidebar wiring.
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
}
