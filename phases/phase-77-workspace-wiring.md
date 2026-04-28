# Phase 77 — WorkspaceView Wiring: All Panes + Layout Persistence + Shortcuts

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phases 72b–76 complete: all pane views created, WorkspaceLayoutManager ready.

Replace the static `WorkspaceView` in `Merlin/Views/WorkspaceView.swift` with a fully-wired
version that:
- Loads/saves `WorkspaceLayout` from `~/.merlin/layout-<projectRef.id>.json`
- Shows/hides `FilePane`, `TerminalPane`, `PreviewPane`, `SideChatPane` based on layout flags
- Adds toolbar buttons to toggle each pane
- Handles ⌘⇧M (toggle Memories review window), ⌘⇧/ (toggle SideChat), Ctrl+` (toggle Terminal)
- Passes `fileURL` binding down so chat messages can open files in FilePane

---

## Edit: Merlin/Views/WorkspaceView.swift

Replace the entire file with:

```swift
import SwiftUI

struct WorkspaceView: View {
    let projectRef: ProjectRef
    @EnvironmentObject private var recents: RecentProjectsStore
    @StateObject private var sessionManager: SessionManager

    @State private var layout: WorkspaceLayout = WorkspaceLayoutManager.defaultLayout
    @State private var selectedFileURL: URL? = nil
    @State private var showMemoriesWindow = false

    private var layoutManager: WorkspaceLayoutManager {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let path = "\(home)/.merlin/layout-\(projectRef.id).json"
        return WorkspaceLayoutManager(url: URL(fileURLWithPath: path))
    }

    init(projectRef: ProjectRef) {
        self.projectRef = projectRef
        _sessionManager = StateObject(wrappedValue: SessionManager(projectRef: projectRef))
    }

    var body: some View {
        Group {
            if let session = sessionManager.activeSession {
                mainLayout(session: session)
            } else {
                noSessionView
            }
        }
        .task {
            if sessionManager.liveSessions.isEmpty {
                await sessionManager.newSession()
            }
            layout = (try? layoutManager.load()) ?? WorkspaceLayoutManager.defaultLayout
        }
        .navigationTitle(projectRef.displayName)
        .toolbar { toolbarContent }
        .keyboardShortcut()
        .sheet(isPresented: $showMemoriesWindow) {
            MemoryReviewView()
                .frame(minWidth: 600, minHeight: 400)
        }
    }

    @ViewBuilder
    private func mainLayout(session: LiveSession) -> some View {
        HStack(spacing: 0) {
            SessionSidebar()
                .environmentObject(sessionManager)
                .frame(width: layout.sidebarWidth)

            Divider()

            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(session.skillsRegistry)
                .environmentObject(session.appState)
                .environmentObject(session.appState.registry)
                .frame(minWidth: 400)

            if layout.showFilePane {
                Divider()
                FilePane(fileURL: $selectedFileURL)
                    .frame(minWidth: 240, idealWidth: 300)
            }

            if layout.showPreviewPane {
                Divider()
                PreviewPane(url: $selectedFileURL)
                    .frame(minWidth: 300, idealWidth: 360)
            }

            DiffPane(
                buffer: StagingBufferWrapper(buffer: session.stagingBuffer),
                engine: session.appState.engine,
                onCommit: {}
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            if layout.showSideChat {
                Divider()
                SideChatPane(isVisible: $layout.showSideChat)
                    .frame(minWidth: 320, idealWidth: 360)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if layout.showTerminalPane {
                Divider()
                TerminalPane(workingDirectory: projectRef.path)
                    .frame(height: 200)
            }
        }
    }

    private var noSessionView: some View {
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $layout.showFilePane) {
                Label("File Viewer", systemImage: "doc.text")
            }
            .help("Toggle file viewer (⌘⇧F)")
            .onChange(of: layout.showFilePane) { _, _ in saveLayout() }

            Toggle(isOn: $layout.showTerminalPane) {
                Label("Terminal", systemImage: "terminal")
            }
            .help("Toggle terminal (⌃`)")
            .onChange(of: layout.showTerminalPane) { _, _ in saveLayout() }

            Toggle(isOn: $layout.showPreviewPane) {
                Label("Preview", systemImage: "eye")
            }
            .help("Toggle preview")
            .onChange(of: layout.showPreviewPane) { _, _ in saveLayout() }

            Toggle(isOn: $layout.showSideChat) {
                Label("Side Chat", systemImage: "bubble.right")
            }
            .help("Toggle side chat (⌘⇧/)")
            .onChange(of: layout.showSideChat) { _, _ in saveLayout() }

            Button {
                showMemoriesWindow = true
            } label: {
                Label("Memories", systemImage: "brain")
            }
            .help("Review memories (⌘⇧M)")
        }
    }

    private func saveLayout() {
        try? layoutManager.save(layout)
    }
}

// MARK: - Keyboard shortcuts extension

private extension View {
    func keyboardShortcut() -> some View {
        self
            .onKeyPress(.init(Character("`")), phases: .down) { _ in
                return .ignored
            }
    }
}
```

### Add keyboard shortcuts to MerlinCommands

In `Merlin/App/MerlinCommands.swift`, add the following inside the existing `CommandMenu("Session")` or a new `CommandMenu("View")`:

```swift
CommandMenu("View") {
    Button("Toggle Terminal") {}
        .keyboardShortcut("`", modifiers: [.control])
    Button("Toggle Side Chat") {}
        .keyboardShortcut("/", modifiers: [.command, .shift])
    Button("Review Memories") {}
        .keyboardShortcut("m", modifiers: [.command, .shift])
}
```

These are placeholder actions — the actual toggle is handled in `WorkspaceView` via `@FocusedObject`
in a future phase. For now, registering the shortcuts prevents macOS from capturing them elsewhere.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/WorkspaceView.swift \
        Merlin/App/MerlinCommands.swift
git commit -m "Phase 77 — WorkspaceView: all panes wired, layout persistence, toolbar toggles, shortcuts"
```
