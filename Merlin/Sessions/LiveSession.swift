// LiveSession — wires all per-session subsystems around an AppState.
//
// Created by SessionManager for each project window session. Responsibilities:
//   • Initialises AppState with the correct project path and constitution.md content
//   • Starts MCPBridge (launches MCP servers, registers their tools)
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
protocol SchedulerSession: AnyObject, Sendable {
    var permissionMode: PermissionMode { get set }
    func awaitMCPReady() async
    func runScheduledPrompt(_ prompt: String) async throws -> String
    func close() async
}

@MainActor
final class LiveSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    let appState: AppState
    let workspaceRuntime: WorkspaceRuntime
    let skillsRegistry: SkillsRegistry
    let chatViewModel = ChatViewModel()
    let subagentSidebar: SubagentSidebarViewModel
    let activeDomainIDs: [String]
    @Published private(set) var isClosed = false
    /// Set by SessionManager.restore() to record which store Session this live session
    /// was created from. Used by the sidebar to avoid restoring the same session twice.
    var originalSessionID: UUID?
    private let mcpBridge = MCPBridge()
    private let stagingBufferStorage = StagingBuffer()
    private let memoryEngine = MemoryEngine()
    private var lifecycleTasks: [Task<Void, Never>] = []
    private var mcpStartupTask: Task<Void, Never>?
    var permissionMode: PermissionMode = AppSettings.shared.defaultPermissionMode {
        didSet {
            appState.engine.permissionMode = permissionMode
            appState.engine.toolRouter.permissionMode = permissionMode
        }
    }
    let createdAt: Date

    init(projectRef: ProjectRef,
         initialMessages: [Message] = [],
         sessionStore: SessionStore? = nil,
         workspaceRuntime: WorkspaceRuntime? = nil,
         activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs) {
        self.id = UUID()
        self.workspaceRuntime = workspaceRuntime ?? (try! WorkspaceRuntime(rootURL: URL(fileURLWithPath: projectRef.path)))
        self.subagentSidebar = SubagentSidebarViewModel(parentSessionID: self.id)
        self.title = "New Session"
        self.createdAt = Date()
        self.activeDomainIDs = Self.inferredActiveDomainIDs(
            requested: activeDomainIDs,
            projectPath: projectRef.path
        )
        self.appState = AppState(
            projectPath: projectRef.path,
            activeDomainIDs: self.activeDomainIDs,
            workspaceRuntime: self.workspaceRuntime
        )
        self.skillsRegistry = SkillsRegistry(projectPath: projectRef.path)
        self.appState.engine.skillsRegistry = self.skillsRegistry
        self.appState.engine.constitutionContent = ConstitutionLoader.systemPromptBlock(projectPath: projectRef.path)
        self.appState.engine.memoriesContent = ConstitutionLoader.defaultMemoriesBlock()
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
        let initialRecord = Session(
            id: self.id,
            title: "New Session",
            messages: [],
            activeDomainIDs: self.activeDomainIDs
        )
        try? appState.sessionStore?.save(initialRecord)
        appState.sessionStore?.activeSessionID = self.id

        // Inject historical messages from a restored session.
        if !initialMessages.isEmpty {
            appState.engine.contextManager.load(initialMessages)
            chatViewModel.load(from: initialMessages)
        }
        chatViewModel.subagentSidebar = subagentSidebar

        let mcpToolRouter = appState.engine.toolRouter
        let mcpTask = Task { @MainActor [mcpBridge, projectPath = projectRef.path, mcpToolRouter] in
            let config = MCPConfig.merged(projectPath: projectPath)
            try? await mcpBridge.start(config: config,
                                       toolRouter: mcpToolRouter)
        }
        mcpStartupTask = mcpTask
        lifecycleTasks.append(mcpTask)

        // File-based message injection: poll ~/.merlin/inject.txt every 2 seconds.
        // When the file exists, post merlinInjectMessage so the active ChatView
        // submits it as a real user message (visible in the UI with full response).
        // Usage from shell: echo "your prompt" > ~/.merlin/inject.txt
        lifecycleTasks.append(Task { @MainActor in
            let injectURL = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.merlin/inject.txt")
            while Task.isCancelled == false {
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
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        })

        lifecycleTasks.append(Task {
            await self.memoryEngine.setProvider(self.resolveMemoryGenerationProvider())
            if AppSettings.shared.memoriesEnabled {
                let timeout = AppSettings.shared.memoryIdleTimeout
                let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
                let pendingDir = URL(fileURLWithPath: "\(home)/.merlin/memories/pending")
                let notificationEngine = NotificationEngine()
                await self.memoryEngine.setOnIdleFired { [weak appState] in
                    guard let appState else { return }
                    Task {
                        await self.memoryEngine.setProvider(self.resolveMemoryGenerationProvider())
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
        })
    }

    var stagingBuffer: StagingBuffer {
        appState.engine.toolRouter.stagingBuffer ?? stagingBufferStorage
    }

    func resolveMemoryGenerationProvider() -> any LLMProvider {
        appState.engine.provider(for: .execute)
            ?? appState.registry.primaryProvider
            ?? NullProvider()
    }

    /// Awaits completion of the background MCP-server startup — process launch,
    /// `tools/list`, and tool registration into ToolRegistry/ToolRouter. Callers
    /// that send a prompt programmatically (e.g. the eval harness) must await this
    /// first; otherwise the first turn races MCP registration and the model is
    /// offered no MCP tools.
    func awaitMCPReady() async {
        await mcpStartupTask?.value
        await appState.awaitRuntimePluginsReady()
    }

    func close() async {
        guard isClosed == false else {
            return
        }
        isClosed = true
        lifecycleTasks.forEach { $0.cancel() }
        lifecycleTasks.removeAll()
        appState.stopEngine()
        await mcpBridge.stop(toolRouter: appState.engine.toolRouter)
        await memoryEngine.stopIdleTimer()
    }

    deinit {
        lifecycleTasks.forEach { $0.cancel() }
    }

    private static func inferredActiveDomainIDs(
        requested ids: [String],
        projectPath: String
    ) -> [String] {
        var resolved = ids.isEmpty ? SoftwareDomain.defaultActiveDomainIDs : ids
        if ElectronicsDomain.projectLooksLikeElectronics(projectPath),
           !resolved.contains(ElectronicsDomain.defaultID) {
            resolved.append(ElectronicsDomain.defaultID)
        }
        return resolved
    }
}

@MainActor
extension LiveSession: SchedulerSession {
    func runScheduledPrompt(_ prompt: String) async throws -> String {
        var summary = ""
        for await event in appState.engine.send(userMessage: prompt) {
            switch event {
            case .text(let text):
                summary += text
            case .slotRuntimeState(let slot, let state):
                await appState.publishSlotRuntimeState(state, for: slot)
            case .error(let error):
                throw error
            default:
                break
            }
        }
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
