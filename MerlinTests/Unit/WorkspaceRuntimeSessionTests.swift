import XCTest
@testable import Merlin

@MainActor
final class WorkspaceRuntimeSessionTests: XCTestCase {
    func testSessionManagerOwnsWorkspaceRuntime() throws {
        let project = ProjectRef(path: "/tmp/merlin-session-runtime", displayName: "Runtime")
        let manager = SessionManager(projectRef: project)

        XCTAssertEqual(manager.workspaceRuntime.rootURL.path, URL(fileURLWithPath: project.path).standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testMultipleSessionsForSameProjectShareRuntime() async throws {
        let project = ProjectRef(path: "/tmp/merlin-shared-runtime", displayName: "Shared")
        let manager = SessionManager(projectRef: project)
        let first = await manager.newSession(mode: .autoAccept)
        let second = await manager.newSession(mode: .autoAccept)

        XCTAssertTrue(first.workspaceRuntime === second.workspaceRuntime)
        XCTAssertTrue(first.appState.workspaceRuntime === manager.workspaceRuntime)
        XCTAssertTrue(second.appState.workspaceRuntime === manager.workspaceRuntime)
    }

    func testWorkspaceCoordinatorReusesRuntimeForRestoredProject() async throws {
        let workspaceFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-workspace-\(UUID().uuidString).json")
        let coordinator = WorkspaceCoordinator(workspaceURL: workspaceFile)
        let ref = ProjectRef(path: "/tmp/merlin-coordinator-runtime", displayName: "Coordinator")

        let manager = await coordinator.addProject(ref)
        let session = manager?.activeSession

        XCTAssertNotNil(manager?.workspaceRuntime)
        XCTAssertTrue(session?.workspaceRuntime === manager?.workspaceRuntime)
    }
}
