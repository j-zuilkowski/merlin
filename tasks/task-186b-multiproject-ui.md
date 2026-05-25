# Phase 186b — Multi-Project UI Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 185b complete: WorkspaceCoordinator with persistence and activeProjectManager.

No 186a test phase — all new surface is SwiftUI view composition.
Correctness verified by build success + manual E2E steps below.

This phase enforces a single workspace window (removes WindowGroup(for: ProjectRef.self)),
fixes SideChatPane to use the active project's path, fixes TerminalPane to follow the
active project, and wires all views through WorkspaceCoordinator.

---

## Edit: Merlin/App/MerlinApp.swift

Remove the picker WindowGroup and the per-project WindowGroup. Replace with a single
workspace WindowGroup. Full replacement:

```swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // Bring the workspace window to front if the user clicks the Dock icon
        // while the app is already running with no visible windows.
        if !flag {
            NSApp.windows.first { $0.identifier?.rawValue == "workspace" }?
                .makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@main
struct MerlinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recents = RecentProjectsStore()
    @StateObject private var scheduler = SchedulerEngine()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup("Merlin", id: "workspace") {
            WorkspaceView()
                .environmentObject(recents)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands { MerlinCommands() }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsWindowView()
                .environmentObject(scheduler)
        }
        .windowResizability(.contentMinSize)
    }
}
```

---

## Edit: Merlin/Views/ProjectPickerView.swift

Add `onSelect: ((ProjectRef) -> Void)?` parameter for sheet mode.
Full replacement:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectPickerView: View {
    @EnvironmentObject private var recents: RecentProjectsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// When provided the picker runs as a sheet: selecting a project calls this
    /// closure and dismisses instead of opening a new window.
    var onSelect: ((ProjectRef) -> Void)? = nil

    @State private var selected: ProjectRef?
    @State private var isShowingFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merlin")
                        .font(.title2.bold())
                    Text(onSelect == nil
                         ? "Open a project to start a session"
                         : "Choose a project to add to this workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            if recents.projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No recent projects")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent Projects")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        ForEach(recents.projects) { ref in
                            ProjectRowView(ref: ref, isSelected: selected?.path == ref.path)
                                .onTapGesture { selected = ref }
                                .onTapGesture(count: 2) { open(ref) }
                                .contextMenu {
                                    Button("Remove from Recents") {
                                        if selected?.path == ref.path { selected = nil }
                                        recents.remove(ref)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            Divider()

            HStack {
                Button("Clear Recents") { recents.clear() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if onSelect != nil {
                    Button("Cancel") { dismiss() }
                }
                Button("Open Folder…") { isShowingFilePicker = true }
                Button(onSelect == nil ? "Open" : "Add to Workspace") {
                    if let s = selected { open(s) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 380)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                open(.make(url: url))
            }
        }
    }

    private func open(_ ref: ProjectRef) {
        recents.touch(ref)
        if let onSelect {
            onSelect(ref)
            dismiss()
        } else {
            NSApp.keyWindow?.close()
            openWindow(value: ref)
        }
    }
}

private struct ProjectRowView: View {
    let ref: ProjectRef
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.displayName)
                    .font(.body.weight(.medium))
                Text(ref.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ref.lastOpenedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
```

---

## Edit: Merlin/Views/WorkspaceView.swift

Remove `projectRef` parameter. Drive layout from `WorkspaceCoordinator`.
Sidebar always visible. Terminal and SideChatPane follow active project.
Full replacement:

```swift
import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var recents: RecentProjectsStore
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var coordinator = WorkspaceCoordinator()

    @State private var layout: WorkspaceLayout = WorkspaceLayoutManager.defaultLayout
    @State private var selectedFileURL: URL? = nil
    @State private var showMemoriesWindow = false
    @State private var didLoadLayout = false

    private var layoutManager: WorkspaceLayoutManager {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".merlin/layout-workspace.json")
        return WorkspaceLayoutManager(url: url)
    }

    var body: some View {
        HStack(spacing: 0) {
            SessionSidebar()
                .environmentObject(coordinator)
                .frame(width: layout.sidebarWidth)

            Divider()

            if let session = coordinator.activeSession {
                sessionContent(session: session)
            } else {
                placeholderContent
            }
        }
        .task {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let configURL = home.appendingPathComponent(".merlin/config.toml")
            try? await AppSettings.shared.load(from: configURL)
            AppSettings.shared.startWatching(url: configURL)
            layout = (try? layoutManager.load()) ?? WorkspaceLayoutManager.defaultLayout
            didLoadLayout = true
        }
        .navigationTitle(
            coordinator.activeSession?.title
            ?? coordinator.activeProjectManager?.projectRef.displayName
            ?? "Merlin"
        )
        .toolbar { toolbarContent }
        .onChange(of: layout.showDiffPane)     { _, _ in saveLayoutIfLoaded() }
        .onChange(of: layout.showFilePane)     { _, _ in saveLayoutIfLoaded() }
        .onChange(of: layout.showTerminalPane) { _, _ in saveLayoutIfLoaded() }
        .onChange(of: layout.showPreviewPane)  { _, _ in saveLayoutIfLoaded() }
        .onChange(of: layout.showSideChat)     { _, _ in saveLayoutIfLoaded() }
        .preferredColorScheme(settings.appearance.theme.colorScheme)
        .sheet(isPresented: $coordinator.showingProjectPicker) {
            ProjectPickerView(onSelect: { ref in
                Task { await coordinator.addProject(ref) }
            })
            .environmentObject(recents)
        }
        .sheet(isPresented: $showMemoriesWindow) {
            MemoryReviewView()
                .environment(\.merlinAppState, coordinator.activeSession?.appState)
                .frame(minWidth: 600, minHeight: 400)
        }
    }

    @ViewBuilder
    private func sessionContent(session: LiveSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ContentView()
                    .environmentObject(session.skillsRegistry)
                    .environmentObject(session.appState)
                    .environmentObject(session.appState.registry)
                    .focusedObject(coordinator)
                    .focusedObject(session.appState)
                    .focusedObject(session.appState.registry)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.isFileURL else { return .systemAction }
                        selectedFileURL = url
                        return .handled
                    })
                    .frame(minWidth: 400, maxWidth: .infinity)

                if layout.showDiffPane {
                    Divider()
                    DiffPane(
                        buffer: StagingBufferWrapper(buffer: session.stagingBuffer),
                        engine: session.appState.engine,
                        onCommit: {}
                    )
                    .frame(width: 260)
                }

                if layout.showFilePane {
                    Divider()
                    FilePane(fileURL: $selectedFileURL)
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
                }

                if layout.showPreviewPane {
                    Divider()
                    PreviewPane(url: $selectedFileURL)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                }

                if layout.showSideChat {
                    Divider()
                    SideChatPane(
                        isVisible: $layout.showSideChat,
                        projectPath: coordinator.activeProjectManager?.projectRef.path ?? ""
                    )
                    .frame(minWidth: 260, idealWidth: layout.chatWidth, maxWidth: 400)
                }
            }

            if layout.showTerminalPane {
                Divider()
                TerminalPane(
                    workingDirectory: coordinator.activeProjectManager?.projectRef.path ?? ""
                )
                .frame(height: 220)
            }
        }
        .focusedObject(session.appState)
        .focusedObject(session.appState.registry)
    }

    private var placeholderContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(coordinator.projectManagers.isEmpty
                 ? "Add a project to get started"
                 : "Select a session from the sidebar")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { layout.showDiffPane.toggle() } label: {
                Label("Staged Changes", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.bordered)
            .tint(layout.showDiffPane ? .accentColor : .secondary)
            .help("Toggle staged changes")

            Button { layout.showFilePane.toggle() } label: {
                Label("File Viewer", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .tint(layout.showFilePane ? .accentColor : .secondary)
            .help("Toggle file viewer")

            Button { layout.showTerminalPane.toggle() } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            .tint(layout.showTerminalPane ? .accentColor : .secondary)
            .help("Toggle terminal")

            Button { layout.showPreviewPane.toggle() } label: {
                Label("Preview", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .tint(layout.showPreviewPane ? .accentColor : .secondary)
            .help("Toggle preview")

            Button { layout.showSideChat.toggle() } label: {
                Label("Side Chat", systemImage: "bubble.right")
            }
            .buttonStyle(.bordered)
            .tint(layout.showSideChat ? .accentColor : .secondary)
            .help("Toggle side chat")

            Button { showMemoriesWindow = true } label: {
                Label("Memories", systemImage: "brain")
            }
            .buttonStyle(.bordered)
            .help("Review memories")
        }
    }

    private func saveLayoutIfLoaded() {
        guard didLoadLayout else { return }
        try? layoutManager.save(layout)
    }
}
```

---

## Edit: Merlin/Views/SideChatPane.swift

Accept `projectPath` so the side chat uses the active project's path.

**Find:**
```swift
    @StateObject private var appState = AppState(projectPath: "")
    @StateObject private var skillsRegistry = SkillsRegistry(projectPath: "")
    @StateObject private var sessionManager: SessionManager

    init(isVisible: Binding<Bool>) {
        _isVisible = isVisible
        let ref = ProjectRef(path: "", displayName: "Side Chat", lastOpenedAt: Date())
        _sessionManager = StateObject(wrappedValue: SessionManager(projectRef: ref))
    }
```

**Replace with:**
```swift
    @StateObject private var appState: AppState
    @StateObject private var skillsRegistry: SkillsRegistry
    @StateObject private var sessionManager: SessionManager

    init(isVisible: Binding<Bool>, projectPath: String) {
        _isVisible = isVisible
        let appState = AppState(projectPath: projectPath)
        _appState = StateObject(wrappedValue: appState)
        _skillsRegistry = StateObject(wrappedValue: SkillsRegistry(projectPath: projectPath))
        let ref = ProjectRef(path: projectPath, displayName: "Side Chat", lastOpenedAt: Date())
        _sessionManager = StateObject(wrappedValue: SessionManager(projectRef: ref))
    }
```

---

## Edit: Merlin/Views/SessionSidebar.swift

Full replacement — multi-project layout. One `ProjectSection` per manager.
Project header is a tappable label that opens a popover.
Bottom button → "New Project Workspace":

```swift
import SwiftUI

struct SessionSidebar: View {
    @EnvironmentObject private var coordinator: WorkspaceCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(coordinator.projectManagers, id: \.projectRef.path) { mgr in
                        ProjectSection(mgr: mgr, coordinator: coordinator)
                        Divider()
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.sessionList)

            Divider()

            Button {
                TelemetryEmitter.shared.emitGUIAction("tap",
                    identifier: AccessibilityID.newSessionButton)
                coordinator.showingProjectPicker = true
            } label: {
                Label("New Project Workspace", systemImage: "plus.square.on.square")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.newSessionButton)
            .padding(8)
        }
        .background(.windowBackground)
    }
}

// MARK: - Project section

private struct ProjectSection: View {
    @ObservedObject var mgr: SessionManager
    let coordinator: WorkspaceCoordinator

    @State private var showHeaderPopover = false
    @State private var showArchived = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable project header
            Button {
                showHeaderPopover = true
            } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHeaderPopover, arrowEdge: .trailing) {
                ProjectHeaderPopover(mgr: mgr, coordinator: coordinator,
                                     isPresented: $showHeaderPopover)
            }

            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("Sessions")

                ForEach(mgr.liveSessions) { session in
                    LiveSessionRow(session: session,
                                   isActive: session.id == coordinator.activeSession?.id)
                        .onTapGesture { coordinator.setActiveSession(session) }
                        .contextMenu {
                            Button("Close Session", role: .destructive) {
                                Task { await mgr.closeSession(session.id) }
                            }
                        }
                }

                // Prior sessions (disk records not currently live)
                let liveIDs = Set(mgr.liveSessions.map(\.id))
                let prior = mgr.sessionStore.activeSessions.filter { !liveIDs.contains($0.id) }

                if !prior.isEmpty {
                    SectionLabel("Prior Sessions").padding(.top, 6)

                    ForEach(prior) { session in
                        PriorSessionRow(session: session)
                            .onTapGesture {
                                Task {
                                    let live = await mgr.restore(session: session)
                                    coordinator.setActiveSession(live)
                                }
                            }
                            .contextMenu {
                                Button("Resume") {
                                    Task {
                                        let live = await mgr.restore(session: session)
                                        coordinator.setActiveSession(live)
                                    }
                                }
                                Divider()
                                Button("Archive") {
                                    try? mgr.sessionStore.archive(session.id)
                                }
                                Button("Delete", role: .destructive) {
                                    try? mgr.sessionStore.delete(session.id)
                                }
                            }
                    }
                }

                // Archived sessions (collapsible)
                let archived = mgr.sessionStore.archivedSessions
                if !archived.isEmpty {
                    Button {
                        showArchived.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Show archived")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)

                    if showArchived {
                        ForEach(archived) { session in
                            PriorSessionRow(session: session, dimmed: true)
                                .contextMenu {
                                    Button("Recall") {
                                        try? mgr.sessionStore.unarchive(session.id)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        try? mgr.sessionStore.delete(session.id)
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Project header popover

private struct ProjectHeaderPopover: View {
    let mgr: SessionManager
    let coordinator: WorkspaceCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                isPresented = false
                Task {
                    let session = await mgr.newSession()
                    coordinator.setActiveSession(session)
                }
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) {
                isPresented = false
                coordinator.removeProject(mgr.projectRef)
            } label: {
                Label("Close Project", systemImage: "xmark")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .frame(minWidth: 180)
    }
}

// MARK: - Row views

private struct LiveSessionRow: View {
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

private struct PriorSessionRow: View {
    let session: Session
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(session.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(dimmed ? .tertiary : .secondary)
                .lineLimit(1)
            Spacer()
            Text(RelativeTimestampFormatter.string(from: session.updatedAt))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
        .contentShape(Rectangle())
    }
}

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

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

## Edit: Merlin/App/MerlinCommands.swift

Replace `sessionManager` references with `coordinator`. Full find/replace:

**Find:** `@FocusedObject var sessionManager: SessionManager?`
**Replace:** `@FocusedObject var coordinator: WorkspaceCoordinator?`

**Find:**
```swift
        CommandGroup(replacing: .newItem) {
            Button("New Project Workspace") {
                coordinator?.showingProjectPicker = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(coordinator == nil)
        }
```
(Already correct from the previous fix — verify it reads this way, otherwise apply it.)

**Find every remaining** `sessionManager?.activeSession` → replace with `coordinator?.activeSession`

**Find:** `guard let session = sessionManager?.activeSession else { return }`
**Replace:** `guard let session = coordinator?.activeSession else { return }`

**Find (Compact Context disabled check):**
```swift
            .disabled(sessionManager?.activeSession == nil)
```
**Replace all occurrences** with:
```swift
            .disabled(coordinator?.activeSession == nil)
```

**Find (Pop Out Session):**
```swift
                guard let activeSession = sessionManager?.activeSession else { return }
```
**Replace:**
```swift
                guard let activeSession = coordinator?.activeSession else { return }
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, zero errors, zero warnings.

## Manual E2E verification
```bash
pkill -x Merlin 2>/dev/null; sleep 1
open ~/Documents/localProject/merlin/build/Debug/Merlin.app
```
1. First launch (or delete ~/.merlin/workspace.json first) → project picker sheet appears automatically.
2. Select a project → it appears in the sidebar with its sessions.
3. Click the project name label → popover shows "New Session" and "Close Project".
4. "New Session" → new live session added; becomes active in content area.
5. Click "+ New Project Workspace" → picker sheet with "Add to Workspace" button.
6. Add a second project → second project section appears below first.
7. Click sessions in each project — content area switches; terminal follows active project.
8. Open Side Chat — it uses the active project's path (check constitution.md is loaded from active project).
9. Quit and relaunch → both projects reopen with their prior sessions listed.
10. Cmd+N → project picker sheet (not a new window).
11. Close Project via popover → section disappears; active switches to remaining project.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-186b-multiproject-ui.md \
        Merlin/App/MerlinApp.swift \
        Merlin/Views/ProjectPickerView.swift \
        Merlin/Views/WorkspaceView.swift \
        Merlin/Views/SideChatPane.swift \
        Merlin/Views/SessionSidebar.swift \
        Merlin/App/MerlinCommands.swift
git commit -m "Phase 186b — Single-window multi-project: coordinator-driven UI, picker sheet, persistence"
```

---

## Fixes (addendum — committed separately as `2fddbac`)

**Bug:** `ChatView` declared `@EnvironmentObject private var sessionManager: SessionManager`.
After the v1.6 refactor `SessionManager` is no longer injected as an `@EnvironmentObject`
(replaced by `WorkspaceCoordinator`). This caused a hard `EnvironmentObject.error()` trap
the moment `currentMode` was evaluated — crashing on launch as soon as any session became active.

**Root cause in production:** The crash first appeared in the v1.6.0 release build.
The fix was committed in the same session and released as v1.6.1 (build 6).

### Edit: Merlin/Views/ChatView.swift

**Find:**
```swift
    @EnvironmentObject private var sessionManager: SessionManager
```
**Replace with:**
```swift
    @FocusedObject private var sessionManager: SessionManager?
```

**Find:**
```swift
            if let session = sessionManager.activeSession {
```
**Replace with:**
```swift
            if let session = sessionManager?.activeSession {
```

**Find:**
```swift
    private var currentMode: PermissionMode {
        sessionManager.activeSession?.permissionMode ?? .ask
    }
```
**Replace with:**
```swift
    private var currentMode: PermissionMode {
        sessionManager?.activeSession?.permissionMode ?? appState.engine.permissionMode
    }
```

### Edit: Merlin/Views/WorkspaceView.swift

Inside `sessionContent(session:)`, expose the active `SessionManager` as a focused object
so `ChatView`'s `@FocusedObject` resolves correctly.

**Find** (inside `sessionContent`):
```swift
    @ViewBuilder
    private func sessionContent(session: LiveSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ContentView()
                    .environmentObject(session.skillsRegistry)
                    .environmentObject(session.appState)
                    .environmentObject(session.appState.registry)
                    .focusedObject(coordinator)
                    .focusedObject(session.appState)
```
**Replace with:**
```swift
    @ViewBuilder
    private func sessionContent(session: LiveSession) -> some View {
        let activeManager = coordinator.activeProjectManager
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ContentView()
                    .environmentObject(session.skillsRegistry)
                    .environmentObject(session.appState)
                    .environmentObject(session.appState.registry)
                    .focusedObject(coordinator)
                    .focusedObject(activeManager)
                    .focusedObject(session.appState)
```

### Addendum commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/ChatView.swift Merlin/Views/WorkspaceView.swift
git commit -m "Phase 186b addendum — ChatView @FocusedObject, WorkspaceView activeManager focusedObject"
```
