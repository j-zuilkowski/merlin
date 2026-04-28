import SwiftUI

struct MerlinCommands: Commands {
    @FocusedObject var appState: AppState?
    @FocusedObject var registry: ProviderRegistry?
    @FocusedObject var sessionManager: SessionManager?
    @FocusedBinding(\.isEngineRunning) var isEngineRunning: Bool?
    @FocusedBinding(\.activeProviderID) var activeProviderID: String?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appState?.newSession()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Session") {
            Button("Stop") {
                appState?.stopEngine()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(isEngineRunning != true)
        }

        CommandMenu("Window") {
            Button("Pop Out Session") {
                guard let activeSession = sessionManager?.activeSession else { return }
                let session = Session(
                    id: activeSession.id,
                    title: activeSession.title,
                    createdAt: activeSession.createdAt,
                    messages: activeSession.appState.engine.contextManager.messages
                )
                FloatingWindowManager.shared.open(session: session, alwaysOnTop: true)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(sessionManager?.activeSession == nil)
        }

        CommandMenu("Provider") {
            let providers = ProviderRegistry.defaultProviders.filter(\.isEnabled)
            ForEach(providers) { config in
                Toggle(config.displayName, isOn: Binding(
                    get: { (activeProviderID ?? appState?.activeProviderID) == config.id },
                    set: { if $0 { activeProviderID = config.id } }
                ))
            }
        }

        CommandMenu("View") {
            Button("Toggle Terminal") {}
                .keyboardShortcut("`", modifiers: [.control])

            Button("Toggle Side Chat") {}
                .keyboardShortcut("/", modifiers: [.command, .shift])

            Button("Review Memories") {}
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }

}
