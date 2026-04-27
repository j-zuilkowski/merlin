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
    var permissionMode: PermissionMode = .ask {
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
        appState.engine.toolRouter.stagingBuffer = stagingBufferStorage
        appState.engine.toolRouter.permissionMode = permissionMode

        Task { @MainActor [mcpBridge, projectPath = projectRef.path] in
            let config = MCPConfig.merged(projectPath: projectPath)
            try? await mcpBridge.start(config: config,
                                       toolRouter: appState.engine.toolRouter)
        }

        Task {
            await self.memoryEngine.setProvider(appState.engine.flashProvider)
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
