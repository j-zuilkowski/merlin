// MerlinCommands — application-level menu commands.
//
// Uses @FocusedObject for reference-type state (AppState, WorkspaceCoordinator)
// and @FocusedBinding for value-type state (isEngineRunning, activeProviderID).
// Both are wired in ContentView via .focusedObject() and .focusedValue().
//
// See: Developer Manual § "UI Architecture → FocusedValues"
import SwiftUI

struct MerlinCommands: Commands {
    @FocusedObject var appState: AppState?
    @FocusedObject var registry: ProviderRegistry?
    @FocusedObject var coordinator: WorkspaceCoordinator?
    @FocusedBinding(\.isEngineRunning) var isEngineRunning: Bool?
    @FocusedBinding(\.activeProviderID) var activeProviderID: String?
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Merlin") {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Project Workspace") {
                coordinator?.showingProjectPicker = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(coordinator == nil)
        }

        CommandMenu("Session") {
            Button("Stop") {
                appState?.stopEngine()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(isEngineRunning != true)

            Divider()

            Button("Compact Context") {
                appState?.engine.contextManager.forceCompaction()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(coordinator?.activeSession == nil)
        }

        CommandMenu("Window") {
            Button("Pop Out Session") {
                guard let activeSession = coordinator?.activeSession else { return }
                let session = Session(
                    id: activeSession.id,
                    title: activeSession.title,
                    createdAt: activeSession.createdAt,
                    messages: activeSession.appState.engine.contextManager.messages
                )
                FloatingWindowManager.shared.open(session: session, alwaysOnTop: true)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(coordinator?.activeSession == nil)
        }

        CommandMenu("Provider") {
            // Read providers and active ID directly from disk so this menu always
            // reflects the user's actual Settings configuration — not a stale snapshot.
            // Selection posts a notification; AppState observes it and updates the engine.
            let providers = ProviderRegistry.persistedEnabledProviders()
            let currentID = ProviderRegistry.persistedActiveProviderID()
            ForEach(providers) { config in
                Button {
                    NotificationCenter.default.post(
                        name: .merlinSelectProvider,
                        object: nil,
                        userInfo: ["providerID": config.id]
                    )
                } label: {
                    HStack {
                        Text(config.displayName)
                        if config.id == currentID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        CommandMenu("View") {
            Button("Toggle Terminal") {
                NotificationCenter.default.post(name: .merlinToggleTerminal, object: nil)
            }
                .keyboardShortcut("`", modifiers: [.control])

            Button("Toggle Side Chat") {
                NotificationCenter.default.post(name: .merlinToggleSideChat, object: nil)
            }
                .keyboardShortcut("/", modifiers: [.command, .shift])

            Button("Review Memories") {
                NotificationCenter.default.post(name: .merlinReviewMemories, object: nil)
            }
                .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Conversation") {
                copyConversation()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(coordinator?.activeSession == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Merlin User Guide") {
                openHelp(.userGuide)
            }
            .keyboardShortcut("?", modifiers: .command)

            Button("Developer Manual") {
                openHelp(.developerManual)
            }
        }
    }

    private func copyConversation() {
        guard let session = coordinator?.activeSession else { return }
        let messages = session.appState.engine.contextManager.messages
        let lines: [String] = messages.compactMap { msg in
            let roleLabel: String
            switch msg.role {
            case .user:      roleLabel = "User"
            case .assistant: roleLabel = "Assistant"
            case .tool:      return nil   // skip raw tool results
            case .system:    return nil   // skip system/injection notes
            }
            let body: String
            switch msg.content {
            case .text(let s):
                body = s
            case .parts(let parts):
                body = parts.compactMap {
                    if case .text(let s) = $0 { return s }
                    return nil
                }.joined(separator: "\n")
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "\(roleLabel): \(body)"
        }
        let full = lines.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
    }

    private func openHelp(_ document: HelpDocument) {
        HelpWindowManager.shared.open(document)
    }

}
