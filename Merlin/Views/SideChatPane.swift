import SwiftUI

struct SideChatPane: View {
    @Binding var isVisible: Bool
    @StateObject private var appState = AppState(projectPath: "")
    @StateObject private var skillsRegistry = SkillsRegistry(projectPath: "")
    @StateObject private var sessionManager: SessionManager

    init(isVisible: Binding<Bool>) {
        _isVisible = isVisible
        let ref = ProjectRef(path: "", displayName: "Side Chat", lastOpenedAt: Date())
        _sessionManager = StateObject(wrappedValue: SessionManager(projectRef: ref))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isVisible {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(skillsRegistry)
                    .environmentObject(appState.registry)
                    .environmentObject(sessionManager)
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
