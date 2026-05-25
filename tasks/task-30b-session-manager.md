# Phase 30b — SessionManager Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 30a complete: failing SessionManagerTests in place.

Implement `LiveSession`, `SessionManager`, `SessionSidebar`, and replace the placeholder
`WorkspaceView` with the real layout (sidebar + chat pane). Settings are wired back in.

`LiveSession` wraps one `AppState` per session. `SessionManager` owns `[LiveSession]`.
`WorkspaceView` creates a `SessionManager` as `@StateObject` and injects the active
session's `AppState` into existing views unchanged.

---

## Write to: Merlin/Sessions/LiveSession.swift

```swift
import Foundation
import SwiftUI

@MainActor
final class LiveSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let appState: AppState
    var permissionMode: PermissionMode = .ask   // expanded in phase 31b
    let createdAt: Date

    init(projectRef: ProjectRef) {
        self.id = UUID()
        self.title = "New Session"
        self.createdAt = Date()
        self.appState = AppState(projectPath: projectRef.path)
    }
}
```

---

## Write to: Merlin/Sessions/SessionManager.swift

```swift
import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    let projectRef: ProjectRef
    @Published private(set) var liveSessions: [LiveSession] = []
    @Published private(set) var activeSessionID: UUID?

    var activeSession: LiveSession? {
        liveSessions.first { $0.id == activeSessionID }
    }

    init(projectRef: ProjectRef) {
        self.projectRef = projectRef
    }

    @discardableResult
    func newSession(mode: PermissionMode = .ask) async -> LiveSession {
        let session = LiveSession(projectRef: projectRef)
        session.permissionMode = mode
        liveSessions.append(session)
        activeSessionID = session.id
        return session
    }

    func switchSession(to id: UUID) {
        guard liveSessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
    }

    func closeSession(_ id: UUID) async {
        liveSessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = liveSessions.last?.id
        }
    }
}
```

---

## Modify: Merlin/App/AppState.swift

Add a `projectPath` parameter to `AppState.init` so each live session can be rooted
to its project directory. Add after the class declaration opening:

```swift
let projectPath: String

init(projectPath: String = "") {
    self.projectPath = projectPath
    // ... rest of existing init unchanged
}
```

All existing call sites that call `AppState()` continue to compile because the
parameter has a default value.

---

## Write to: Merlin/Views/WorkspaceView.swift (replace placeholder)

```swift
import SwiftUI

struct WorkspaceView: View {
    let projectRef: ProjectRef
    @EnvironmentObject private var recents: RecentProjectsStore
    @StateObject private var sessionManager: SessionManager

    init(projectRef: ProjectRef) {
        self.projectRef = projectRef
        _sessionManager = StateObject(wrappedValue: SessionManager(projectRef: projectRef))
    }

    var body: some View {
        Group {
            if let session = sessionManager.activeSession {
                HSplitView {
                    SessionSidebar()
                        .environmentObject(sessionManager)
                        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

                    ContentView()
                        .environmentObject(session.appState)
                        .environmentObject(session.appState.registry)
                }
            } else {
                VStack(spacing: 16) {
                    Text("No sessions open")
                        .foregroundStyle(.secondary)
                    Button("New Session") {
                        Task { await sessionManager.newSession() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Open one session automatically when the window opens
            if sessionManager.liveSessions.isEmpty {
                await sessionManager.newSession()
            }
        }
        .navigationTitle(projectRef.displayName)
    }
}
```

---

## Write to: Merlin/Views/SessionSidebar.swift

```swift
import SwiftUI

struct SessionSidebar: View {
    @EnvironmentObject private var mgr: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            // Project header
            HStack(spacing: 8) {
                Circle()
                    .fill(.purple)
                    .frame(width: 8, height: 8)
                Text(mgr.projectRef.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Session list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ForEach(mgr.liveSessions) { session in
                        SessionRowView(session: session,
                                       isActive: session.id == mgr.activeSessionID)
                            .onTapGesture { mgr.switchSession(to: session.id) }
                            .contextMenu {
                                Button("Close Session", role: .destructive) {
                                    Task { await mgr.closeSession(session.id) }
                                }
                            }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }

            Divider()

            // Footer
            Button {
                Task { await mgr.newSession() }
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .background(.windowBackground)
    }
}

private struct SessionRowView: View {
    @ObservedObject var session: LiveSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    PermissionModeBadge(mode: session.permissionMode)
                    if session.appState.toolActivityState != .idle {
                        Circle()
                            .fill(.purple)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// Placeholder badge — replaced with real implementation in phase 31b
private struct PermissionModeBadge: View {
    let mode: PermissionMode
    var body: some View {
        Text(mode.label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(mode.color.opacity(0.15))
            .foregroundStyle(mode.color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
```

---

## Modify: Merlin/App/MerlinApp.swift

Wire `Settings` scene to `ProviderSettingsView`. In the `Settings` scene body, replace
the placeholder `Text("Settings")` with:

```swift
Settings {
    ProviderSettingsView()
        .environmentObject(ProviderRegistry())
}
```

Note: `ProviderSettingsView` needs a `ProviderRegistry` environment object. For the
Settings window (which is outside any workspace window) create a standalone registry.

---

## Modify: project.yml

Add to Merlin target sources:
- `Merlin/Sessions/LiveSession.swift`
- `Merlin/Sessions/SessionManager.swift`
- `Merlin/Views/SessionSidebar.swift`

Then regenerate:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `SessionManagerTests` → 8 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Sessions/LiveSession.swift \
        Merlin/Sessions/SessionManager.swift \
        Merlin/App/AppState.swift \
        Merlin/Views/WorkspaceView.swift \
        Merlin/Views/SessionSidebar.swift \
        Merlin/App/MerlinApp.swift \
        project.yml
git commit -m "Phase 30b — SessionManager + LiveSession + WorkspaceView + SessionSidebar"
```
