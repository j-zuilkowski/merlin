import AppKit
import XCTest
@testable import Merlin

@MainActor
final class WorkspaceCoordinatorTests: XCTestCase {

    private func makeRef(_ name: String) -> ProjectRef {
        ProjectRef(path: "/tmp/merlin-coord-\(name)-\(UUID().uuidString)",
                   displayName: name)
    }

    private func tempWorkspaceURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("workspace-\(UUID().uuidString).json")
    }

    // MARK: - First launch

    func test_init_no_persisted_sets_showingPicker_true() {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        XCTAssertTrue(coord.showingProjectPicker,
                      "No persisted projects -> picker must be shown automatically")
    }

    func test_init_no_persisted_has_no_project_managers() {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        XCTAssertTrue(coord.projectManagers.isEmpty)
    }

    // MARK: - Persistence load

    func test_init_loads_persisted_projects() throws {
        let url = tempWorkspaceURL()
        let refs = [makeRef("p1"), makeRef("p2")]
        let data = try JSONEncoder().encode(refs)
        try data.write(to: url)

        let coord = WorkspaceCoordinator(workspaceURL: url)
        XCTAssertEqual(coord.projectManagers.count, 2)
    }

    func test_init_with_persisted_does_not_show_picker() throws {
        let url = tempWorkspaceURL()
        let refs = [makeRef("p1")]
        try JSONEncoder().encode(refs).write(to: url)

        let coord = WorkspaceCoordinator(workspaceURL: url)
        XCTAssertFalse(coord.showingProjectPicker)
    }

    func test_loadPersistedProjects_returns_empty_for_missing_file() {
        let result = WorkspaceCoordinator.loadPersistedProjects(from: tempWorkspaceURL())
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - addProject

    func test_addProject_appends_manager() async {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        await coord.addProject(makeRef("p1"))
        XCTAssertEqual(coord.projectManagers.count, 1)
    }

    func test_addProject_noop_for_duplicate_path() async {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        let ref = makeRef("dup")
        await coord.addProject(ref)
        await coord.addProject(ProjectRef(path: ref.path, displayName: ref.displayName))
        XCTAssertEqual(coord.projectManagers.count, 1)
    }

    func test_addProject_sets_active_session() async {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        await coord.addProject(makeRef("p1"))
        XCTAssertNotNil(coord.activeSession)
    }

    func test_startSession_existingProjectCreatesLiveSessionAndActivatesIt() async throws {
        let url = tempWorkspaceURL()
        let ref = makeRef("restored")
        try JSONEncoder().encode([ref]).write(to: url)
        let coord = WorkspaceCoordinator(workspaceURL: url)

        XCTAssertNil(coord.activeSession)
        XCTAssertEqual(coord.projectManagers.count, 1)

        let session = await coord.startSession(for: ref)

        XCTAssertEqual(coord.projectManagers.count, 1)
        XCTAssertEqual(coord.activeSession?.id, session.id)
        XCTAssertEqual(coord.projectManagers.first?.liveSessions.count, 1)
        XCTAssertFalse(coord.showingProjectPicker)
    }

    func test_startSession_newProjectAddsProjectAndPersistsIt() async throws {
        let url = tempWorkspaceURL()
        let coord = WorkspaceCoordinator(workspaceURL: url)
        let ref = makeRef("fresh")

        let session = await coord.startSession(for: ref)

        XCTAssertEqual(coord.projectManagers.count, 1)
        XCTAssertEqual(coord.activeSession?.id, session.id)
        XCTAssertFalse(coord.showingProjectPicker)

        let data = try Data(contentsOf: url)
        let loaded = try JSONDecoder().decode([ProjectRef].self, from: data)
        XCTAssertEqual(loaded.map(\.path), [ref.path])
    }

    func test_startSessionWithExplicitDomainsDoesNotAppendProjectInferredDomain() async throws {
        let url = tempWorkspaceURL()
        let coord = WorkspaceCoordinator(workspaceURL: url)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-explicit-domain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("fixture.kicad_pro"))

        let session = await coord.startSession(
            for: ProjectRef(path: dir.path, displayName: dir.lastPathComponent),
            explicitDomainIDs: [SoftwareDomain.defaultID]
        )

        XCTAssertEqual(session.activeDomainIDs, [SoftwareDomain.defaultID])
    }

    func test_launchProjectRefAcceptsExplicitOpenProjectArgument() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ref = WorkspaceView.launchProjectRef(from: ["Merlin", "--open-project", dir.path])

        XCTAssertEqual(ref?.path, dir.path)
        XCTAssertEqual(ref?.displayName, dir.lastPathComponent)
    }

    func test_launchProjectRefAcceptsBareDirectoryArgument() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-bare-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ref = WorkspaceView.launchProjectRef(from: ["Merlin", dir.path])

        XCTAssertEqual(ref?.path, dir.path)
    }

    func test_openProjectArgumentAllowsFallbackWindowRecovery() {
        XCTAssertTrue(AppDelegate.shouldAllowFallbackWindowRecovery(
            arguments: ["Merlin", "--open-project", "/tmp/project"]
        ))
        XCTAssertTrue(AppDelegate.shouldAllowFallbackWindowRecovery(
            arguments: ["Merlin", "--open-test-project", "/tmp/project"]
        ))
        XCTAssertFalse(AppDelegate.shouldAllowFallbackWindowRecovery(
            arguments: ["Merlin"]
        ))
    }

    func test_fallbackWindowRecoveryRequiresUsableVisibleWorkspaceWindow() {
        let smallWindow = TestWorkspaceWindow(
            isVisible: true,
            isMiniaturized: false,
            canBecomeKey: true,
            styleMask: [.titled, .resizable],
            frame: NSRect(x: 0, y: 0, width: 500, height: 500)
        )

        XCTAssertFalse(WorkspaceWindowRecoveryManager.hasUsableWorkspaceWindow(
            in: [smallWindow]
        ))

        let workspaceWindow = TestWorkspaceWindow(
            isVisible: true,
            isMiniaturized: false,
            canBecomeKey: true,
            styleMask: [.titled, .resizable],
            frame: NSRect(x: 0, y: 0, width: 1200, height: 800)
        )

        XCTAssertTrue(WorkspaceWindowRecoveryManager.hasUsableWorkspaceWindow(
            in: [workspaceWindow]
        ))
    }

    func test_workspaceWindowRecoveryComputesUsableFallbackFrame() {
        let frame = WorkspaceWindowRecoveryManager.usableWorkspaceFrame(
            in: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame.width, 1200)
        XCTAssertEqual(frame.height, 800)
        XCTAssertEqual(frame.midX, 720)
        XCTAssertEqual(frame.midY, 450)
    }

    func test_launchActiveDomainIDAcceptsExplicitDomainArgument() {
        XCTAssertEqual(
            WorkspaceView.launchActiveDomainID(from: ["Merlin", "--active-domain", "electronics"]),
            "electronics"
        )
        XCTAssertNil(WorkspaceView.launchActiveDomainID(from: ["Merlin", "--active-domain", ""]))
        XCTAssertNil(WorkspaceView.launchActiveDomainID(from: ["Merlin"]))
    }

    func test_addProject_persists_to_disk() async throws {
        let url = tempWorkspaceURL()
        let coord = WorkspaceCoordinator(workspaceURL: url)
        await coord.addProject(makeRef("p1"))

        let data = try Data(contentsOf: url)
        let loaded = try JSONDecoder().decode([ProjectRef].self, from: data)
        XCTAssertEqual(loaded.count, 1)
    }

    // MARK: - removeProject

    func test_removeProject_reduces_count() async {
        let url = tempWorkspaceURL()
        let coord = WorkspaceCoordinator(workspaceURL: url)
        let ref = makeRef("p1")
        await coord.addProject(ref)
        coord.removeProject(ref)
        XCTAssertTrue(coord.projectManagers.isEmpty)
    }

    func test_removeProject_updates_persistence() async throws {
        let url = tempWorkspaceURL()
        let coord = WorkspaceCoordinator(workspaceURL: url)
        let ref1 = makeRef("p1")
        let ref2 = makeRef("p2")
        await coord.addProject(ref1)
        await coord.addProject(ref2)
        coord.removeProject(ref2)

        let data = try Data(contentsOf: url)
        let loaded = try JSONDecoder().decode([ProjectRef].self, from: data)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.path, ref1.path)
    }

    func test_removeProject_last_sets_active_nil() async {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        let ref = makeRef("only")
        await coord.addProject(ref)
        coord.removeProject(ref)
        XCTAssertNil(coord.activeSession)
    }

    func test_removeProject_active_session_updates_to_remaining() async {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        let ref1 = makeRef("p1")
        let ref2 = makeRef("p2")
        await coord.addProject(ref1)
        await coord.addProject(ref2)
        // Active session now belongs to p2
        coord.removeProject(ref2)
        // Active session must belong to p1 or be nil
        if let active = coord.activeSession {
            let inP1 = coord.projectManagers.first?.liveSessions.contains { $0.id == active.id } ?? false
            XCTAssertTrue(inP1)
        }
    }

    // MARK: - activeProjectManager

    func test_activeProjectManager_returns_manager_owning_active_session() async {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        let ref1 = makeRef("p1")
        let ref2 = makeRef("p2")
        await coord.addProject(ref1)
        await coord.addProject(ref2)
        // Active is p2's session after addProject
        let mgr = coord.activeProjectManager
        XCTAssertEqual(mgr?.projectRef.path, ref2.path)
    }

    func test_activeProjectManager_nil_when_no_active_session() {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        XCTAssertNil(coord.activeProjectManager)
    }

    // MARK: - setActiveSession

    func test_setActiveSession_updates_active() async {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        await coord.addProject(makeRef("p1"))
        await coord.addProject(makeRef("p2"))
        guard let p1Session = coord.projectManagers.first?.liveSessions.first else {
            XCTFail("p1 must have a live session"); return
        }
        coord.setActiveSession(p1Session)
        XCTAssertEqual(coord.activeSession?.id, p1Session.id)
    }

    // MARK: - showingProjectPicker

    func test_showingProjectPicker_toggles() {
        let coord = WorkspaceCoordinator(workspaceURL: tempWorkspaceURL())
        coord.showingProjectPicker = false
        XCTAssertFalse(coord.showingProjectPicker)
        coord.showingProjectPicker = true
        XCTAssertTrue(coord.showingProjectPicker)
    }
}

private struct TestWorkspaceWindow: WorkspaceWindowCandidate {
    let isVisible: Bool
    let isMiniaturized: Bool
    let canBecomeKey: Bool
    let styleMask: NSWindow.StyleMask
    let frame: NSRect
}
