import SwiftUI

struct SideChatPane: View {
    @Binding var isVisible: Bool
    @StateObject private var appState = AppState(projectPath: "")
    @StateObject private var skillsRegistry = SkillsRegistry(projectPath: "")

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isVisible {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(skillsRegistry)
                    .environmentObject(appState.registry)
            } else {
                placeholder
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.engine.skillsRegistry = skillsRegistry
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
