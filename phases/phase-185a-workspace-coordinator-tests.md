# Phase 185a — WorkspaceCoordinatorTests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 184 complete: v1.5.0 shipped — Session.archived, SessionStore scoped path,
SessionManager.restore, SessionSidebar prior/archived sections.

New surface introduced in phase 185b:
  - `WorkspaceCoordinator` — new @MainActor ObservableObject that owns the list of open
    project managers and the globally active LiveSession across all of them
  - `WorkspaceCoordinator.init(initialRef: ProjectRef)` — starts with one SessionManager
  - `WorkspaceCoordinator.addProject(_ ref: ProjectRef) async` — appends a new SessionManager;
    no-op if a manager for that path already exists; sets activeSession to first session
  - `WorkspaceCoordinator.removeProject(_ ref: ProjectRef)` — removes the manager; updates
    activeSession to the last remaining session or nil
  - `WorkspaceCoordinator.setActiveSession(_ session: LiveSession)` — called on sidebar tap
  - `WorkspaceCoordinator.showingProjectPicker: Bool` — drives picker sheet presentation

TDD coverage:
  File 1 — WorkspaceCoordinatorTests: init, addProject, duplicate prevention,
    removeProject, setActiveSession, activeSession continuity on remove

---

## Write to: MerlinTests/Unit/WorkspaceCoordinatorTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class WorkspaceCoordinatorTests: XCTestCase {

    private func makeRef(_ suffix: String) -> ProjectRef {
        ProjectRef(path: "/tmp/merlin-coord-\(suffix)-\(UUID().uuidString)",
                   displayName: suffix)
    }

    // MARK: - init

    func test_init_creates_one_project_manager() {
        let coord = WorkspaceCoordinator(initialRef: makeRef("p1"))
        XCTAssertEqual(coord.projectManagers.count, 1)
    }

    func test_init_showingProjectPicker_is_false() {
        let coord = WorkspaceCoordinator(initialRef: makeRef("p1"))
        XCTAssertFalse(coord.showingProjectPicker)
    }

    // MARK: - addProject

    func test_addProject_appends_new_manager() async {
        let coord = WorkspaceCoordinator(initialRef: makeRef("p1"))
        await coord.addProject(makeRef("p2"))
        XCTAssertEqual(coord.projectManagers.count, 2)
    }

    func test_addProject_is_noop_for_duplicate_path() async {
        let ref = makeRef("dup")
        let coord = WorkspaceCoordinator(initialRef: ref)
        await coord.addProject(ProjectRef(path: ref.path, displayName: ref.displayName))
        XCTAssertEqual(coord.projectManagers.count, 1)
    }

    func test_addProject_sets_active_session() async {
        let coord = WorkspaceCoordinator(initialRef: makeRef("p1"))
        await coord.addProject(makeRef("p2"))
        XCTAssertNotNil(coord.activeSession)
    }

    func test_addProject_active_session_belongs_to_new_project() async {
        let ref1 = makeRef("p1")
        let ref2 = makeRef("p2")
        let coord = WorkspaceCoordinator(initialRef: ref1)
        await coord.addProject(ref2)
        let newMgr = coord.projectManagers.last
        let activeInNew = newMgr?.liveSessions.contains {
            $0.id == coord.activeSession?.id
        } ?? false
        XCTAssertTrue(activeInNew, "Active session must belong to the newly added project")
    }

    // MARK: - removeProject

    func test_removeProject_reduces_manager_count() async {
        let ref1 = makeRef("p1")
        let ref2 = makeRef("p2")
        let coord = WorkspaceCoordinator(initialRef: ref1)
        await coord.addProject(ref2)
        coord.removeProject(ref2)
        XCTAssertEqual(coord.projectManagers.count, 1)
    }

    func test_removeProject_nonexistent_is_noop() {
        let coord = WorkspaceCoordinator(initialRef: makeRef("p1"))
        coord.removeProject(makeRef("ghost"))
        XCTAssertEqual(coord.projectManagers.count, 1)
    }

    func test_removeProject_active_project_clears_or_updates_active_session() async {
        let ref1 = makeRef("p1")
        let ref2 = makeRef("p2")
        let coord = WorkspaceCoordinator(initialRef: ref1)
        await coord.addProject(ref2)
        // Make the second project's session active
        if let session = coord.projectManagers.last?.activeSession {
            coord.setActiveSession(session)
        }
        coord.removeProject(ref2)
        // Active session must now belong to a remaining project (or be nil if no sessions)
        if let active = coord.activeSession {
            let remainingIDs = Set(coord.projectManagers.flatMap { $0.liveSessions }.map(\.id))
            XCTAssertTrue(remainingIDs.contains(active.id),
                          "Active session must belong to a still-open project")
        }
        // At minimum, no crash and manager count is correct
        XCTAssertEqual(coord.projectManagers.count, 1)
    }

    func test_removeProject_last_project_sets_active_nil() {
        let ref = makeRef("only")
        let coord = WorkspaceCoordinator(initialRef: ref)
        coord.removeProject(ref)
        XCTAssertNil(coord.activeSession)
        XCTAssertTrue(coord.projectManagers.isEmpty)
    }

    // MARK: - setActiveSession

    func test_setActiveSession_updates_activeSession() async {
        let ref1 = makeRef("p1")
        let ref2 = makeRef("p2")
        let coord = WorkspaceCoordinator(initialRef: ref1)
        await coord.addProject(ref2)

        // Pick a session from the first project
        guard let firstSession = coord.projectManagers.first?.liveSessions.first else {
            XCTFail("Expected at least one live session in first project")
            return
        }
        coord.setActiveSession(firstSession)
        XCTAssertEqual(coord.activeSession?.id, firstSession.id)
    }

    // MARK: - showingProjectPicker

    func test_showingProjectPicker_toggles() {
        let coord = WorkspaceCoordinator(initialRef: makeRef("p1"))
        coord.showingProjectPicker = true
        XCTAssertTrue(coord.showingProjectPicker)
        coord.showingProjectPicker = false
        XCTAssertFalse(coord.showingProjectPicker)
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
