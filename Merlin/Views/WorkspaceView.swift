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
                        .environmentObject(sessionManager)
                        .environmentObject(session.appState)
                        .environmentObject(session.appState.registry)
                        .frame(minWidth: 500)

                    DiffPane(
                        buffer: StagingBufferWrapper(buffer: session.stagingBuffer),
                        onCommit: { /* commit flow in phase 36 */ }
                    )
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
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
            if sessionManager.liveSessions.isEmpty {
                await sessionManager.newSession()
            }
        }
        .navigationTitle(projectRef.displayName)
    }
}
