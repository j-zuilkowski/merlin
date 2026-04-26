import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HSplitView {
            ChatView()
                .frame(minWidth: 500)

            VSplitView {
                ToolLogView()
                    .frame(minWidth: 280, minHeight: 200)

                ScreenPreviewView()
                    .frame(minHeight: 200)
            }
            .frame(width: 320)
        }
        .sheet(isPresented: $appState.showAuthPopup) {
            if let req = appState.pendingAuthRequest {
                AuthPopupView(
                    tool: req.tool,
                    argument: req.argument,
                    reasoningStep: req.reasoningStep,
                    suggestedPattern: req.suggestedPattern,
                    onDecision: { appState.resolveAuth($0) }
                )
            }
        }
    }
}
