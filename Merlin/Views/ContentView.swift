import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ProviderRegistry

    @State private var showToolPane = false
    @State private var engineRunning = false

    var body: some View {
        HStack(spacing: 0) {
            ChatView()
                .frame(minWidth: 280, maxWidth: .infinity)

            if showToolPane {
                Divider()
                VSplitView {
                    ToolLogView()
                        .frame(minWidth: 260, minHeight: 160)
                    ScreenPreviewView()
                        .frame(minHeight: 160)
                }
                .frame(width: 300)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showToolPane.toggle()
                } label: {
                    Label("Tool Log", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
                .tint(showToolPane ? .accentColor : .secondary)
                .help("Toggle tool log")
            }
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
        .focusedObject(appState)
        .focusedObject(registry)
        .focusedValue(\.isEngineRunning, $engineRunning)
        .onChange(of: appState.toolActivityState) { _, state in
            engineRunning = state != .idle
        }
    }
}
