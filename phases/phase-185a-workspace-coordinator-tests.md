# Phase 185a — WorkspaceCoordinatorTests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 184 complete: v1.5.0 shipped.

New surface introduced in phase 185b:
  - `WorkspaceCoordinator` — @MainActor ObservableObject; no-args init loads persisted
    projects from ~/.merlin/workspace.json; auto-sets showingProjectPicker=true when
    no projects are persisted (first launch)
  - `WorkspaceCoordinator.addProject(_ ref: ProjectRef) async` — creates SessionManager,
    persists to disk; no-op for duplicate path
  - `WorkspaceCoordinator.removeProject(_ ref: ProjectRef)` — removes manager, persists
  - `WorkspaceCoordinator.setActiveSession(_ session: LiveSession)` — sets globalactive
  - `WorkspaceCoordinator.activeProjectManager: SessionManager?` — manager that owns
    the currently active LiveSession
  - `WorkspaceCoordinator.showingProjectPicker: Bool` — drives picker sheet
  - `WorkspaceCoordinator.persistOpenProjects()` — writes [ProjectRef] to disk
  - `WorkspaceCoordinator.loadPersistedProjects(from url: URL) -> [ProjectRef]` — static,
    testable load helper (accepts URL so tests can point at a temp path)

TDD coverage:
  File 1 — WorkspaceCoordinatorTests: init first-launch, init persisted, addProject,
    duplicate prevention, removeProject, activeProjectManager, persistence round-trip

---

## Write to: MerlinTests/Unit/WorkspaceCoordinatorTests.swift

```swift
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
                      "No persisted projects → picker must be shown automatically")
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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `WorkspaceCoordinator` not found.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-185a-workspace-coordinator-tests.md \
        MerlinTests/Unit/WorkspaceCoordinatorTests.swift
git commit -m "Phase 185a — WorkspaceCoordinatorTests (failing)"
```
