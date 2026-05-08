# Phase 186b — Multi-Project UI Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 185b complete: WorkspaceCoordinator in place.

No 186a test phase: all new surface in this phase is SwiftUI view composition.
Correctness is verified by build success + manual E2E steps below.

---

## Edit: Merlin/Views/ProjectPickerView.swift

Add optional `onSelect` parameter. When provided the picker runs in sheet mode —
selecting a project calls `onSelect` and dismisses instead of opening a new window.

Full replacement:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectPickerView: View {
    @EnvironmentObject private var recents: RecentProjectsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    /// When set the picker runs in sheet mode: selecting a project calls this
    /// closure instead of opening a new window.
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

## Edit: Merlin/Views/SessionSidebar.swift

Full replacement — multi-project layout: one section per project manager,
project header popover, "+ New Project Workspace" bottom button:

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
            // Project header — tappable to open popover
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
                                     dismiss: { showHeaderPopover = false })
            }

            VStack(alignment: .leading, spacing: 2) {
                // Live sessions
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

                // Prior sessions (on disk, not currently live)
                let liveIDs = Set(mgr.liveSessions.map(\.id))
                let prior = mgr.sessionStore.activeSessions.filter { !liveIDs.contains($0.id) }

                if !prior.isEmpty {
                    SectionLabel("Prior Sessions")
                        .padding(.top, 6)

                    ForEach(prior) { session in
                        PriorSessionRow(session: session)
                            .onTapGesture { Task { await mgr.restore(session: session) } }
                            .contextMenu {
                                Button("Resume") { Task { await mgr.restore(session: session) } }
                                Divider()
                                Button("Archive") { try? mgr.sessionStore.archive(session.id) }
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
                                    Button("Recall") { try? mgr.sessionStore.unarchive(session.id) }
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
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                dismiss()
                Task {
                    let session = await mgr.newSession()
                    coordinator.setActiveSession(session)
                }
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())

            Divider()

            Button(role: .destructive) {
                dismiss()
                coordinator.removeProject(mgr.projectRef)
            } label: {
                Label("Close Project", systemImage: "xmark")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
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

## Edit: Merlin/Views/WorkspaceView.swift

Replace single `SessionManager` with `WorkspaceCoordinator`. Full replacement:

```swift
import SwiftUI

struct WorkspaceView: View {
    let initialRef: ProjectRef
    @EnvironmentObject private var recents: RecentProjectsStore
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var coordinator: WorkspaceCoordinator

    @State private var layout: WorkspaceLayout = WorkspaceLayoutManager.defaultLayout
    @State private var selectedFileURL: URL? = nil
    @State private var showMemoriesWindow = false
    @State private var didLoadLayout = false

    private var layoutManager: WorkspaceLayoutManager {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let layoutURL = home.appendingPathComponent(".merlin/layout-\(initialRef.id).json")
        return WorkspaceLayoutManager(url: layoutURL)
    }

    init(projectRef: ProjectRef) {
        self.initialRef = projectRef
        _coordinator = StateObject(wrappedValue: WorkspaceCoordinator(initialRef: projectRef))
    }

    var body: some View {
        Group {
            if let session = coordinator.activeSession {
                mainLayout(session: session)
                    .focusedObject(session.appState)
                    .focusedObject(session.appState.registry)
            } else {
                noSessionView
            }
        }
        .task {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let configURL = home.appendingPathComponent(".merlin/config.toml")
            try? await AppSettings.shared.load(from: configURL)
            AppSettings.shared.startWatching(url: configURL)

            layout = (try? layoutManager.load()) ?? WorkspaceLayoutManager.defaultLayout
            didLoadLayout = true
            recents.touch(initialRef)
        }
        .navigationTitle(coordinator.activeSession?.title ?? initialRef.displayName)
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
    private func mainLayout(session: LiveSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SessionSidebar()
                    .environmentObject(coordinator)
                    .frame(width: layout.sidebarWidth)

                Divider()

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
                    SideChatPane(isVisible: $layout.showSideChat)
                        .frame(minWidth: 260, idealWidth: layout.chatWidth, maxWidth: 400)
                }
            }

            if layout.showTerminalPane {
                Divider()
                TerminalPane(workingDirectory: initialRef.path)
                    .frame(height: 220)
            }
        }
    }

    private var noSessionView: some View {
        VStack(spacing: 16) {
            Text("No projects open")
                .foregroundStyle(.secondary)
            Button("Add Project") { coordinator.showingProjectPicker = true }
                .buttonStyle(.borderedProminent)
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

## Edit: Merlin/App/MerlinCommands.swift

Replace `@FocusedObject var sessionManager` with `@FocusedObject var coordinator`.
Update "New Session" command to show the project picker instead.

**Find:**
```swift
    @FocusedObject var sessionManager: SessionManager?
```
**Replace with:**
```swift
    @FocusedObject var coordinator: WorkspaceCoordinator?
```

**Find:**
```swift
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                Task { await sessionManager?.newSession() }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(sessionManager == nil)
        }
```
**Replace with:**
```swift
        CommandGroup(replacing: .newItem) {
            Button("New Project Workspace") {
                coordinator?.showingProjectPicker = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(coordinator == nil)
        }
```

**Find (in Session menu):**
```swift
            .disabled(sessionManager?.activeSession == nil)
```
**Replace with:**
```swift
            .disabled(coordinator?.activeSession == nil)
```

**Find (in Window menu):**
```swift
            Button("Pop Out Session") {
                guard let activeSession = sessionManager?.activeSession else { return }
```
**Replace with:**
```swift
            Button("Pop Out Session") {
                guard let activeSession = coordinator?.activeSession else { return }
```

**Find:**
```swift
            .disabled(sessionManager?.activeSession == nil)
```
**Replace with (second occurrence — Window menu):**
```swift
            .disabled(coordinator?.activeSession == nil)
```

**Find:**
```swift
    private func copyConversation() {
        guard let session = sessionManager?.activeSession else { return }
```
**Replace with:**
```swift
    private func copyConversation() {
        guard let session = coordinator?.activeSession else { return }
```

**Find:**
```swift
            .disabled(sessionManager?.activeSession == nil)
```
**Replace with (third occurrence — Edit menu Copy Conversation):**
```swift
            .disabled(coordinator?.activeSession == nil)
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
1. Open any project — sidebar shows one project section with "Sessions" and a "New Project Workspace" button at the bottom.
2. Click the project name label (e.g., "xcalibre-server") → popover shows "New Session" and "Close Project".
3. Click "New Session" in popover → new session appears under the project's Sessions section.
4. Click "New Project Workspace" at bottom → project picker sheet appears with subtitle "Choose a project to add to this workspace".
5. Select a different project → new project section appears in sidebar below the first, with its own header and initial session.
6. Click sessions in each project → content area switches between them.
7. Cmd+N → project picker sheet opens.
8. Click project label → "Close Project" → that project's section disappears.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-186b-multiproject-ui.md \
        Merlin/Views/ProjectPickerView.swift \
        Merlin/Views/SessionSidebar.swift \
        Merlin/Views/WorkspaceView.swift \
        Merlin/App/MerlinCommands.swift
git commit -m "Phase 186b — Multi-project sidebar: project sections, header popover, picker sheet"
```
