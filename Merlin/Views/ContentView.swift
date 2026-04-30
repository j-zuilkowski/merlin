import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ProviderRegistry

    @State private var showToolPane = false
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
        .sheet(isPresented: $appState.showFirstLaunchSetup) {
            FirstLaunchSetupView()
                .environmentObject(appState)
        }
        .sheet(item: Binding(
            get: { appState.calibrationCoordinator.sheet },
            set: { appState.calibrationCoordinator.sheet = $0 }
        )) { sheetState in
            switch sheetState {
            case .pickProvider(let providers):
                CalibrationProviderPickerView(availableProviders: providers) { selected in
                    Task { await appState.calibrationCoordinator.start(referenceProviderID: selected) }
                }
            case .running(let info):
                CalibrationProgressView(info: info)
            case .report(let report):
                CalibrationReportView(report: report) {
                    Task { await appState.calibrationCoordinator.applyAll() }
                }
            }
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
