import SwiftUI

struct WorkspaceView: View {
    let projectRef: ProjectRef
    @EnvironmentObject private var recents: RecentProjectsStore
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var sessionManager: SessionManager

    @State private var layout: WorkspaceLayout = WorkspaceLayoutManager.defaultLayout
    @State private var selectedFileURL: URL? = nil
    @State private var showMemoriesWindow = false
    @State private var didLoadLayout = false

    private var layoutManager: WorkspaceLayoutManager {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let layoutURL = home.appendingPathComponent(".merlin/layout-\(projectRef.id).json")
        return WorkspaceLayoutManager(url: layoutURL)
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
            didLoadLayout = true
            recents.touch(projectRef)
        }
        .navigationTitle(projectRef.displayName)
        .toolbar { toolbarContent }
        .onChange(of: layout.showFilePane) { _, _ in saveLayoutIfLoaded() }
        .onChange(of: layout.showTerminalPane) { _, _ in saveLayoutIfLoaded() }
        .onChange(of: layout.showPreviewPane) { _, _ in saveLayoutIfLoaded() }
        .onChange(of: layout.showSideChat) { _, _ in saveLayoutIfLoaded() }
        .preferredColorScheme(settings.appearance.theme.colorScheme)
        .font(settings.appearance.fontName.isEmpty
            ? .system(size: settings.appearance.fontSize)
            : .custom(settings.appearance.fontName, size: settings.appearance.fontSize))
        .sheet(isPresented: $showMemoriesWindow) {
            MemoryReviewView()
                .frame(minWidth: 600, minHeight: 400)
        }
    }

    @ViewBuilder
    private func mainLayout(session: LiveSession) -> some View {
        VStack(spacing: 0) {
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
                    .focusedObject(sessionManager)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.isFileURL else {
                            return .systemAction
                        }
                        selectedFileURL = url
                        return .handled
                    })
                    .frame(minWidth: 400, maxWidth: .infinity)

                Divider()

                DiffPane(
                    buffer: StagingBufferWrapper(buffer: session.stagingBuffer),
                    engine: session.appState.engine,
                    onCommit: {}
                )
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

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
                        .frame(width: layout.chatWidth)
                }
            }

            if layout.showTerminalPane {
                Divider()
                TerminalPane(workingDirectory: projectRef.path)
                    .frame(height: 220)
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
            Button {
                layout.showFilePane.toggle()
                saveLayoutIfLoaded()
            } label: {
                Label("File Viewer", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .tint(layout.showFilePane ? .accentColor : .secondary)
            .help("Toggle file viewer")

            Button {
                layout.showTerminalPane.toggle()
                saveLayoutIfLoaded()
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            .tint(layout.showTerminalPane ? .accentColor : .secondary)
            .help("Toggle terminal")

            Button {
                layout.showPreviewPane.toggle()
                saveLayoutIfLoaded()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .tint(layout.showPreviewPane ? .accentColor : .secondary)
            .help("Toggle preview")

            Button {
                layout.showSideChat.toggle()
                saveLayoutIfLoaded()
            } label: {
                Label("Side Chat", systemImage: "bubble.right")
            }
            .buttonStyle(.bordered)
            .tint(layout.showSideChat ? .accentColor : .secondary)
            .help("Toggle side chat")

            Button {
                showMemoriesWindow = true
            } label: {
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
