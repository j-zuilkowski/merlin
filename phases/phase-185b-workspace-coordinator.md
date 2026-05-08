# Phase 185b — WorkspaceCoordinator Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 185a complete: WorkspaceCoordinatorTests committed (failing).

---

## Write to: Merlin/Sessions/WorkspaceCoordinator.swift

```swift
import Foundation
import SwiftUI

// WorkspaceCoordinator — owns all open project managers within one workspace window.
//
// Replaces the single SessionManager in WorkspaceView. Tracks the globally active
// LiveSession across all open projects so the content area always knows what to show.
//
// See: Developer Manual § "Session & State Management → WorkspaceCoordinator"

@MainActor
final class WorkspaceCoordinator: ObservableObject {
    @Published private(set) var projectManagers: [SessionManager] = []
    @Published private(set) var activeSession: LiveSession?
    @Published var showingProjectPicker: Bool = false

    init(initialRef: ProjectRef) {
        let mgr = SessionManager(projectRef: initialRef)
        projectManagers.append(mgr)
        Task {
            let session = await mgr.newSession()
            activeSession = session
        }
    }

    /// Adds a new project to the workspace. No-op if a manager for that path already exists.
    /// Creates an initial session for the new project and makes it active.
    @discardableResult
    func addProject(_ ref: ProjectRef) async -> SessionManager? {
        guard !projectManagers.contains(where: { $0.projectRef.path == ref.path }) else {
            return nil
        }
        let mgr = SessionManager(projectRef: ref)
        projectManagers.append(mgr)
        let session = await mgr.newSession()
        activeSession = session
        return mgr
    }

    /// Removes a project and all its live sessions from the workspace.
    /// If the active session belonged to the removed project, switches to the
    /// last session of the remaining projects, or nil if none remain.
    func removeProject(_ ref: ProjectRef) {
        projectManagers.removeAll { $0.projectRef.path == ref.path }
        let remaining = projectManagers.flatMap { $0.liveSessions }
        if let current = activeSession, !remaining.contains(where: { $0.id == current.id }) {
            activeSession = remaining.last
        }
    }

    /// Sets the globally active session. Called when the user taps a session row
    /// in any project section of the sidebar.
    func setActiveSession(_ session: LiveSession) {
        activeSession = session
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'WorkspaceCoordinator.*passed|WorkspaceCoordinator.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; all WorkspaceCoordinatorTests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-185b-workspace-coordinator.md \
        Merlin/Sessions/WorkspaceCoordinator.swift
git commit -m "Phase 185b — WorkspaceCoordinator multi-project state manager"
```
