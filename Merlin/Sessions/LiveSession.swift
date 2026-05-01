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
// See: Developer Manual § "Session & State Management → LiveSession"
import Foundation
import SwiftUI

@MainActor
final class LiveSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let appState: AppState
    let skillsRegistry: SkillsRegistry
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

    init(projectRef: ProjectRef) {
        self.id = UUID()
        self.title = "New Session"
        self.createdAt = Date()
        self.appState = AppState(projectPath: projectRef.path)
        self.skillsRegistry = SkillsRegistry(projectPath: projectRef.path)
        self.appState.engine.skillsRegistry = self.skillsRegistry
        self.appState.engine.claudeMDContent = CLAUDEMDLoader.systemPromptBlock(projectPath: projectRef.path)
        self.appState.engine.memoriesContent = CLAUDEMDLoader.defaultMemoriesBlock()
        appState.engine.permissionMode = permissionMode
        appState.engine.toolRouter.stagingBuffer = stagingBufferStorage
        appState.engine.toolRouter.permissionMode = permissionMode
        appState.engine.onUsageUpdate = { [weak appState] tokens in
            Task { @MainActor in
                appState?.updateContextUsage(tokens)
            }
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
