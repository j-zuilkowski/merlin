import SwiftUI

struct MerlinCommands: Commands {
    @FocusedObject var appState: AppState?
    @FocusedObject var registry: ProviderRegistry?

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
            .disabled(!canStop)
        }

        CommandMenu("Provider") {
            if let registry {
                ForEach(registry.providers.filter(\.isEnabled)) { config in
                    Toggle(config.displayName, isOn: Binding(
                        get: { registry.activeProviderID == config.id },
                        set: { if $0 { registry.activeProviderID = config.id } }
                    ))
                }
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

    private var canStop: Bool {
        guard let state = appState?.toolActivityState else { return false }
        return state == .streaming || state == .toolExecuting
    }
}
