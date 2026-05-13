// LiveSession — wires all per-session subsystems around an AppState.
//
// Created by SessionManager for each project window session. Responsibilities:
//   • Initialises AppState with the correct project path and CLAUDE.md content
//   • Starts MCPBridge (launches MCP servers, registers their tools)
//   • Starts ThreadAutomationEngine for cron-based automations
//   • Starts MemoryEngine idle timer (generates summaries on inactivity)
//
// permissionMode.didSet propagates the new mode to both AgenticEngine
// and ToolRouter so they stay in sync.
//
// initialMessages: pre-loads a prior session's history into the ContextManager.
// sessionStore: when provided, replaces the AppState-owned store so all live
//   sessions for a project share one store instance.
//
// See: Developer Manual § "Session & State Management → LiveSession"
import Foundation
import SwiftUI

@MainActor
final class LiveSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let appState: AppState
    let skillsRegistry: SkillsRegistry
    let chatViewModel = ChatViewModel()
    /// Set by SessionManager.restore() to record which store Session this live session
    /// was created from. Used by the sidebar to avoid restoring the same session twice.
    var originalSessionID: UUID?
    private let mcpBridge = MCPBridge()
    private let stagingBufferStorage = StagingBuffer()
    private let memoryEngine = MemoryEngine()
    private let automationStore = ThreadAutomationStore()
    private let automationEngine = ThreadAutomationEngine()
    var permissionMode: PermissionMode = AppSettings.shared.defaultPermissionMode {
        didSet {
            appState.engine.permissionMode = permissionMode
            appState.engine.toolRouter.permissionMode = permissionMode
        }
    }
    let createdAt: Date

    init(projectRef: ProjectRef,
         initialMessages: [Message] = [],
         sessionStore: SessionStore? = nil) {
        self.id = UUID()
        self.title = "New Session"
        self.createdAt = Date()
        self.appState = AppState(projectPath: projectRef.path)
        self.skillsRegistry = SkillsRegistry(projectPath: projectRef.path)
        self.appState.engine.skillsRegistry = self.skillsRegistry
        self.appState.engine.claudeMDContent = CLAUDEMDLoader.systemPromptBlock(projectPath: projectRef.path)
        self.appState.engine.memoriesContent = CLAUDEMDLoader.defaultMemoriesBlock()
        self.appState.engine.standingInstructions = AppSettings.shared.standingInstructions
        appState.engine.permissionMode = permissionMode
        appState.engine.toolRouter.stagingBuffer = stagingBufferStorage
        appState.engine.toolRouter.permissionMode = permissionMode
        appState.engine.onUsageUpdate = { [weak appState] tokens in
            Task { @MainActor in
                appState?.updateContextUsage(tokens)
            }
        }
        appState.engine.onTitleUpdate = { [weak self] newTitle in
            Task { @MainActor in
                self?.title = newTitle
            }
        }

        // Replace per-AppState store with the shared project-level store if provided.
        if let sessionStore {
            appState.sessionStore = sessionStore
            appState.engine.sessionStore = sessionStore
        }

        // Register this LiveSession as an active record in the store so the engine's
        // session-save and title-generation paths (which use sessionStore.activeSession)
        // operate on the correct session from the first turn onward.
        let initialRecord = Session(id: self.id, title: "New Session", messages: [])
        try? appState.sessionStore?.save(initialRecord)
        appState.sessionStore?.activeSessionID = self.id

        // Inject historical messages from a restored session.
        if !initialMessages.isEmpty {
            appState.engine.contextManager.load(initialMessages)
            chatViewModel.load(from: initialMessages)
        }

        Task { @MainActor [mcpBridge, projectPath = projectRef.path] in
            let config = MCPConfig.merged(projectPath: projectPath)
            try? await mcpBridge.start(config: config,
                                       toolRouter: appState.engine.toolRouter)
        }

        Task {
            let store = automationStore
            let engine = automationEngine
            let agenticEngine = appState.engine
            await engine.setOnFire { @Sendable [weak agenticEngine] _, prompt in
                Task { @MainActor in
                    guard let engine = agenticEngine else { return }
                    for await _ in engine.send(userMessage: prompt) {}
                }
            }
            await engine.start(store: store)
        }

        // File-based message injection: poll ~/.merlin/inject.txt every 2 seconds.
        // When the file exists, post merlinInjectMessage so the active ChatView
        // submits it as a real user message (visible in the UI with full response).
        // Usage from shell: echo "your prompt" > ~/.merlin/inject.txt
        Task { @MainActor in
            let injectURL = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.merlin/inject.txt")
            while true {
                if let data = try? Data(contentsOf: injectURL),
                   let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    try? FileManager.default.removeItem(at: injectURL)
                    NotificationCenter.default.post(
                        name: .merlinInjectMessage,
                        object: nil,
                        userInfo: ["message": text]
                    )
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }

        Task {
            let memoryProvider = appState.engine.provider(for: .reason) ?? NullProvider()
            await self.memoryEngine.setProvider(memoryProvider)
            if AppSettings.shared.memoriesEnabled {
                let timeout = AppSettings.shared.memoryIdleTimeout
                let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
                let pendingDir = URL(fileURLWithPath: "\(home)/.merlin/memories/pending")
                let notificationEngine = NotificationEngine()
                await self.memoryEngine.setOnIdleFired { [weak appState] in
                    guard let appState else { return }
                    Task {
                        let messages = await appState.engine.contextManager.messages
                        try? await self.memoryEngine.generateAndNotify(
                            messages: messages,
                            pendingDir: pendingDir,
                            notificationEngine: notificationEngine
                        )
                    }
                }
                await self.memoryEngine.startIdleTimer(timeout: timeout)
            }
        }
    }

    var stagingBuffer: StagingBuffer {
        appState.engine.toolRouter.stagingBuffer ?? stagingBufferStorage
    }
}
