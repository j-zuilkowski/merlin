import XCTest
@testable import Merlin

final class SubagentBusOriginTests: XCTestCase {
    func testOriginFactoryBuildsParentExplorerDefaultAndWorkerOrigins() {
        let workspaceID = "workspace"
        let sessionID = UUID()
        let subagentID = UUID()

        let parent = WorkspaceMessageOrigin.parentSession(
            workspaceID: workspaceID,
            sessionID: sessionID,
            activeDomainIDs: ["software"]
        )
        XCTAssertEqual(parent.permissionScope, .workspaceWrite)
        XCTAssertNil(parent.subagentID)

        let explorer = WorkspaceMessageOrigin.subagent(
            workspaceID: workspaceID,
            sessionID: sessionID,
            subagentID: subagentID,
            role: .explorer,
            depth: 1,
            worktreeID: nil,
            activeDomainIDs: ["software"]
        )
        XCTAssertEqual(explorer.permissionScope, .readOnly)
        XCTAssertEqual(explorer.subagentID, subagentID)

        let worker = WorkspaceMessageOrigin.subagent(
            workspaceID: workspaceID,
            sessionID: sessionID,
            subagentID: subagentID,
            role: .worker,
            depth: 1,
            worktreeID: "tree",
            activeDomainIDs: ["software"]
        )
        XCTAssertEqual(worker.permissionScope, .worktreeWrite)
        XCTAssertEqual(worker.worktreeID, "tree")
    }
}
