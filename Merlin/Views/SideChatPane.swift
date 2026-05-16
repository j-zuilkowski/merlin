import SwiftUI

struct SideChatPane: View {
    @Binding var isVisible: Bool
    @StateObject private var appState: AppState
    @StateObject private var skillsRegistry: SkillsRegistry
    @StateObject private var sessionManager: SessionManager
    @StateObject private var chatViewModel: ChatViewModel

    init(isVisible: Binding<Bool>, projectPath: String) {
        _isVisible = isVisible
        let appState = AppState(projectPath: projectPath)
        _appState = StateObject(wrappedValue: appState)
        _skillsRegistry = StateObject(wrappedValue: SkillsRegistry(projectPath: projectPath))
        let ref = ProjectRef(path: projectPath, displayName: "Side Chat", lastOpenedAt: Date())
        _sessionManager = StateObject(wrappedValue: SessionManager(projectRef: ref))
        _chatViewModel = StateObject(wrappedValue: ChatViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isVisible {
                ChatView()
                    .environmentObject(appState)
                    .environmentObject(skillsRegistry)
                    .environmentObject(appState.registry)
                    .environmentObject(sessionManager)
                    .environmentObject(chatViewModel)
            } else {
                placeholder
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            appState.engine.skillsRegistry = skillsRegistry
            if sessionManager.liveSessions.isEmpty {
                await sessionManager.newSession()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Side Chat")
                .font(.headline)
            Spacer()
            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Close side chat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("Side chat is hidden")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
