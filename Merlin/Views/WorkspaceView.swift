import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var recents: RecentProjectsStore
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var coordinator = WorkspaceCoordinator()
    @StateObject private var settingsSessionContext = SettingsSessionContext.shared

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
        workspaceLifecycleView
    }

    private var workspaceLifecycleView: some View {
        workspacePresentationView
            .task {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let configURL = home.appendingPathComponent(".merlin/config.toml")
                try? await AppSettings.shared.load(from: configURL)
                AppSettings.shared.startWatching(url: configURL)
                layout = (try? layoutManager.load()) ?? WorkspaceLayoutManager.defaultLayout
                didLoadLayout = true

                // UI-test hook: open a throwaway project so a session is active and the
                // chat/tool-log surfaces actually render (without a session WorkspaceView
                // only shows placeholderContent). Used by MerlinUITests.
                if ProcessInfo.processInfo.arguments.contains("--open-test-project"),
                   coordinator.activeSession == nil {
                    let dir = NSTemporaryDirectory()
                        + "merlin-uitest-project-\(UUID().uuidString)"
                    try? FileManager.default.createDirectory(
                        atPath: dir, withIntermediateDirectories: true)
                    _ = await coordinator.addProject(
                        ProjectRef(path: dir, displayName: "UITest", lastOpenedAt: Date()))
                }
            }
        .onAppear {
            settingsSessionContext.bind(to: coordinator.activeSession)
        }
        .onChange(of: coordinator.activeSession?.id) { _, _ in
            settingsSessionContext.bind(to: coordinator.activeSession)
        }
        .onDisappear {
            settingsSessionContext.clearIfMatching(coordinator.activeSession?.appState)
        }
    }

    private var workspacePresentationView: some View {
        workspaceSheetView
            .preferredColorScheme(settings.appearance.theme.colorScheme)
    }

    private var workspaceSheetView: some View {
        workspaceEventView
            .sheet(isPresented: $coordinator.showingProjectPicker) {
                projectPickerSheet
            }
            .sheet(isPresented: $showMemoriesWindow) {
                memoryReviewSheet
            }
    }

    private var workspaceEventView: some View {
        workspaceNavigationView
            .onChange(of: layout.showDiffPane)     { _, _ in saveLayoutIfLoaded() }
            .onChange(of: layout.showFilePane)     { _, _ in saveLayoutIfLoaded() }
            .onChange(of: layout.showTerminalPane) { _, _ in saveLayoutIfLoaded() }
            .onChange(of: layout.showPreviewPane)  { _, _ in saveLayoutIfLoaded() }
            .onChange(of: layout.showSideChat)     { _, _ in saveLayoutIfLoaded() }
            .onChange(of: layout.showCAGPane)      { _, _ in saveLayoutIfLoaded() }
            .onReceive(NotificationCenter.default.publisher(for: .merlinToggleTerminal)) { _ in
                layout.showTerminalPane.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .merlinToggleSideChat)) { _ in
                layout.showSideChat.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .merlinReviewMemories)) { _ in
                showMemoriesWindow = true
            }
    }

    private var workspaceNavigationView: some View {
        workspaceRoot
            .navigationTitle(
                coordinator.activeSession?.title
                ?? coordinator.activeProjectManager?.projectRef.displayName
                ?? "Merlin"
            )
            .toolbar { toolbarContent }
    }

    private var workspaceRoot: some View {
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
    }

    private var projectPickerSheet: some View {
        ProjectPickerView(onSelect: { ref in
            Task { await coordinator.addProject(ref) }
        })
        .environmentObject(recents)
    }

    private var memoryReviewSheet: some View {
        MemoryReviewView()
            .environment(\.merlinAppState, coordinator.activeSession?.appState)
            .frame(minWidth: 600, minHeight: 400)
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
                    .environmentObject(session.chatViewModel)
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

                if layout.showCAGPane {
                    Divider()
                    CAGMetricsPane(
                        providers: session.appState.registry.providers,
                        isVisible: $layout.showCAGPane
                    )
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)
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
                .foregroundStyle(.accessibleSecondary)
            Text(coordinator.projectManagers.isEmpty
                 ? "Add a project to get started"
                 : "Select a session from the sidebar")
                .foregroundStyle(.accessibleSecondary)
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
            .tint(layout.showDiffPane ? .accentColor : .accessibleSecondary)
            .help("Toggle staged changes")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleDiffButton)

            Button { layout.showFilePane.toggle() } label: {
                Label("File Viewer", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .tint(layout.showFilePane ? .accentColor : .accessibleSecondary)
            .help("Toggle file viewer")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleFileButton)

            Button { layout.showTerminalPane.toggle() } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            .tint(layout.showTerminalPane ? .accentColor : .accessibleSecondary)
            .help("Toggle terminal")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleTerminalButton)

            Button { layout.showPreviewPane.toggle() } label: {
                Label("Preview", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .tint(layout.showPreviewPane ? .accentColor : .accessibleSecondary)
            .help("Toggle preview")
            .accessibilityIdentifier(AccessibilityID.workspaceTogglePreviewButton)

            Button { layout.showCAGPane.toggle() } label: {
                Label("CAG Metrics", systemImage: "bolt.horizontal.circle")
            }
            .buttonStyle(.bordered)
            .tint(layout.showCAGPane ? .accentColor : .accessibleSecondary)
            .help("Toggle CAG metrics")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleCAGMetricsButton)

            Button { layout.showSideChat.toggle() } label: {
                Label("Side Chat", systemImage: "bubble.right")
            }
            .buttonStyle(.bordered)
            .tint(layout.showSideChat ? .accentColor : .accessibleSecondary)
            .help("Toggle side chat")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleSideChatButton)

            Button { showMemoriesWindow = true } label: {
                Label("Memories", systemImage: "brain")
            }
            .buttonStyle(.bordered)
            .help("Review memories")
            .accessibilityIdentifier(AccessibilityID.workspaceToggleMemoriesButton)
        }
    }

    private func saveLayoutIfLoaded() {
        guard didLoadLayout else { return }
        try? layoutManager.save(layout)
    }
}
