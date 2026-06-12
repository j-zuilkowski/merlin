import SwiftUI

extension ShapeStyle where Self == Color {
    /// De-emphasized text/icon colour that still meets WCAG AA contrast. SwiftUI's
    /// system `.secondary` / `.tertiary` styles fall short on small text — the
    /// accessibility audit flags them — so this keeps visual hierarchy while passing.
    static var accessibleSecondary: Color { Color.primary.opacity(0.75) }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ProviderRegistry

    // Starts open under the UI-test launch flag so MerlinUITests can see the
    // tool-log pane; otherwise collapsed by default.
    @State private var showToolPane =
        ProcessInfo.processInfo.arguments.contains("--open-test-project")
        && ProcessInfo.processInfo.arguments.contains("--accessibility-audit-fixture") == false
    @State private var engineRunning = false
    @State private var activeProviderID = ""

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
                    TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.settingsButton)
                    showToolPane.toggle()
                } label: {
                    Label("Tool Log", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
                .tint(showToolPane ? .accentColor : .accessibleSecondary)
                .help("Toggle tool log")
                .accessibilityIdentifier(AccessibilityID.settingsButton)
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
        .sheet(isPresented: $appState.showReasonOverridePopup) {
            if let pending = appState.pendingReasonOverrideRequest {
                ReasonOverridePopupView(
                    request: pending.request,
                    onDecision: { appState.resolveReasonOverride($0) }
                )
            }
        }
        .sheet(isPresented: $appState.showFirstLaunchSetup) {
            FirstLaunchSetupView()
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.calibrationCoordinator.sheet != nil },
            set: { if !$0 { appState.calibrationCoordinator.dismiss() } }
        )) {
            // Single persistent sheet — state switching happens inside so SwiftUI
            // never has to dismiss + re-present (which silently drops the new sheet).
            CalibrationFlowView(coordinator: appState.calibrationCoordinator)
        }
        .focusedObject(appState)
        .focusedObject(registry)
        .focusedValue(\.isEngineRunning, $engineRunning)
        .focusedValue(\.activeProviderID, Binding(
            get: { activeProviderID },
            set: { activeProviderID = $0; registry.activeProviderID = $0 }
        ))
        .onChange(of: appState.toolActivityState) { _, state in
            engineRunning = state != .idle
        }
        .onChange(of: registry.activeProviderID) { _, id in
            activeProviderID = id
        }
        .onAppear {
            activeProviderID = registry.activeProviderID
        }
    }
}
