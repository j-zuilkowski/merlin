# Task 185b — WorkspaceCoordinator Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 185a complete: WorkspaceCoordinatorTests committed (failing).

---

## Write to: Merlin/Sessions/WorkspaceCoordinator.swift

```swift
import Foundation
import SwiftUI

// WorkspaceCoordinator — owns all open project managers in one workspace window.
//
// Persists the list of open projects to ~/.merlin/workspace.json so the same
// set of projects is restored on next launch. Projects load without live sessions;
// users resume from the Prior Sessions list or create new ones via the header popover.
//
// On first launch (no persisted projects), showingProjectPicker is set true
// so the picker sheet appears automatically.
//
// See: Developer Manual § "Session & State Management → WorkspaceCoordinator"

@MainActor
final class WorkspaceCoordinator: ObservableObject {
    @Published private(set) var projectManagers: [SessionManager] = []
    @Published private(set) var activeSession: LiveSession?
    @Published var showingProjectPicker: Bool = false

    private let workspaceURL: URL

    // MARK: - Init

    /// Production init — uses the default ~/.merlin/workspace.json path.
    convenience init() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/workspace.json")
        self.init(workspaceURL: url)
    }

    /// Designated init — accepts a custom URL for testability.
    init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
        let persisted = WorkspaceCoordinator.loadPersistedProjects(from: workspaceURL)
        if persisted.isEmpty {
            showingProjectPicker = true
        } else {
            for ref in persisted {
                projectManagers.append(SessionManager(projectRef: ref))
            }
        }
    }

    // MARK: - Project management

    /// Adds a project to the workspace and creates its first live session.
    /// No-op if a manager for that path already exists.
    @discardableResult
    func addProject(_ ref: ProjectRef) async -> SessionManager? {
        guard !projectManagers.contains(where: { $0.projectRef.path == ref.path }) else {
            return nil
        }
        let mgr = SessionManager(projectRef: ref)
        projectManagers.append(mgr)
        let session = await mgr.newSession()
        activeSession = session
        persistOpenProjects()
        return mgr
    }

    /// Removes a project and all its live sessions.
    /// Updates activeSession to the last remaining session, or nil.
    func removeProject(_ ref: ProjectRef) {
        projectManagers.removeAll { $0.projectRef.path == ref.path }
        let remaining = projectManagers.flatMap { $0.liveSessions }
        if let current = activeSession,
           !remaining.contains(where: { $0.id == current.id }) {
            activeSession = remaining.last
        }
        persistOpenProjects()
    }

    /// The SessionManager that owns the currently active LiveSession.
    var activeProjectManager: SessionManager? {
        guard let active = activeSession else { return nil }
        return projectManagers.first { mgr in
            mgr.liveSessions.contains { $0.id == active.id }
        }
    }

    /// Makes a session the globally active one (called from sidebar tap).
    func setActiveSession(_ session: LiveSession) {
        activeSession = session
    }

    // MARK: - Persistence

    func persistOpenProjects() {
        let refs = projectManagers.map(\.projectRef)
        guard let data = try? JSONEncoder().encode(refs) else { return }
        let dir = workspaceURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        try? data.write(to: workspaceURL, options: .atomic)
    }

    static func loadPersistedProjects(from url: URL) -> [ProjectRef] {
        guard let data = try? Data(contentsOf: url),
              let refs = try? JSONDecoder().decode([ProjectRef].self, from: data)
        else { return [] }
        return refs
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
git add tasks/task-185b-workspace-coordinator.md \
        Merlin/Sessions/WorkspaceCoordinator.swift
git commit -m "Task 185b — WorkspaceCoordinator: multi-project state, persistence, activeProjectManager"
```
