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
        let activeManager = coordinator.activeProjectManager
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ContentView()
                    .id(session.id)
                    .environmentObject(session.skillsRegistry)
                    .environmentObject(session.appState)
                    .environmentObject(session.appState.registry)
                    .focusedObject(coordinator)
                    .focusedObject(activeManager)
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
