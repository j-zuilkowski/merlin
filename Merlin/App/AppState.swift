// AppState — top-level @MainActor observable for one project session.
//
// Owns: AgenticEngine, ProviderRegistry, AuthMemory, PRMonitor,
// tool log lines, screen capture state, context usage, and toolbar actions.
//
// activeProviderID.didSet keeps ProviderRegistry in sync and rebuilds
// the engine's provider instances via syncEngineProviders().
//
// See: Developer Manual § "Session & State Management → AppState"
import Foundation
import Combine
import SwiftUI

struct AuthRequest {
    var tool: String
    var argument: String
    var reasoningStep: String
    var suggestedPattern: String
    var resolve: (AuthDecision) -> Void
}

struct ToolLogLine: Identifiable {
    enum Source {
        case stdout
        case stderr
        case system
    }

    var id = UUID()
    var text: String
    var source: Source
    var timestamp: Date
}

enum ToolActivityState: String, Sendable {
    case idle
    case streaming
    case toolExecuting
}

private let showAuthPopupForTestingFlag = "--show-auth-popup-for-testing"

@MainActor
final class AppState: ObservableObject {
    let projectPath: String
    let registry = ProviderRegistry()
    let prMonitor = PRMonitor()
    @Published var engine: AgenticEngine!
    @Published var sessionStore: SessionStore!
    @Published var authMemory: AuthMemory
    @Published var showFirstLaunchSetup: Bool = false

    @Published var showAuthPopup: Bool = false
    @Published var pendingAuthRequest: AuthRequest? = nil

    @Published var toolLogLines: [ToolLogLine] = []

    @Published var lastScreenshot: (data: Data, timestamp: Date, sourceBundleID: String)? = nil
    @Published var contextUsage: ContextUsageTracker = ContextUsageTracker(contextWindowSize: 200_000)
    @Published var toolbarActionsList: [ToolbarAction] = []

    @Published var activeProviderID: String = "deepseek" {
        didSet {
            guard registry.activeProviderID != activeProviderID else { return }
            registry.activeProviderID = activeProviderID
            syncEngineProviders()
        }
    }
    @Published var thinkingModeActive: Bool = false
    @Published var toolActivityState: ToolActivityState = .idle

    let xcalibreClient: XcalibreClient
    let loraCoordinator = LoRACoordinator()
    let toolbarActions = ToolbarActionStore()
    private var registryCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var projectPathCancellable: AnyCancellable?
    private var ragRerankCancellable: AnyCancellable?
    private var ragChunkLimitCancellable: AnyCancellable?
    private var keepAwakeCancellable: AnyCancellable?
    private var githubTokenObserver: NSObjectProtocol?

    init(projectPath: String = "") {
        self.projectPath = projectPath
        let authStorePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Merlin/auth.json")
            .path

        authMemory = AuthMemory(storePath: authStorePath)
        xcalibreClient = XcalibreClient(token: AppSettings.shared.xcalibreToken)
        Self.installBuiltinSkills()
        Task { await ToolRegistry.shared.registerBuiltins() }
        Task {
            await AgentRegistry.shared.registerBuiltins()
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let agentsDir = URL(fileURLWithPath: "\(home)/.merlin/agents")
            try? await AgentRegistry.shared.loadDirectory(agentsDir)
        }

        let gate = AuthGate(memory: authMemory, presenter: self)
        let toolRouter = ToolRouter(authGate: gate)
        registerAllTools(router: toolRouter)

        toolRouter.register(name: "run_shell") { [weak self] args in
            struct RunShellArgs: Decodable {
                var command: String
                var cwd: String?
                var timeout_seconds: Int?
            }

            let decoded = try JSONDecoder().decode(RunShellArgs.self, from: Data(args.utf8))
            var stdout = ""
            var stderr = ""

            for try await line in ShellTool.stream(
                command: decoded.command,
                cwd: decoded.cwd,
                timeoutSeconds: decoded.timeout_seconds ?? 120
            ) {
                await MainActor.run {
                    self?.toolLogLines.append(ToolLogLine(
                        text: line.text,
                        source: line.source == .stdout ? .stdout : .stderr,
                        timestamp: Date()
                    ))
                }

                if line.source == .stdout {
                    stdout += line.text + "\n"
                } else {
                    stderr += line.text + "\n"
                }
            }

            return "exit:0\nstdout:\(stdout)\nstderr:\(stderr)"
        }

        let ctx = ContextManager()
        sessionStore = SessionStore()

        let initialProvider = registry.primaryProvider
            ?? DeepSeekProvider(apiKey: "", model: "deepseek-v4-pro")
        let vision = registry.visionProvider ?? LMStudioProvider()

        engine = AgenticEngine(
            proProvider: initialProvider,
            flashProvider: initialProvider,
            visionProvider: vision,
            toolRouter: toolRouter,
            contextManager: ctx,
            xcalibreClient: xcalibreClient
        )
        engine.currentProjectPath = AppSettings.shared.projectPath.isEmpty
            ? nil
            : AppSettings.shared.projectPath
        engine.ragRerank = AppSettings.shared.ragRerank
        engine.ragChunkLimit = AppSettings.shared.ragChunkLimit
        contextUsage = ContextUsageTracker(contextWindowSize: AppSettings.shared.maxTokens)
        engine.registry = registry
        engine.sessionStore = sessionStore
        engine.loraCoordinator = loraCoordinator
        syncEngineProviders()
        if let token = ConnectorCredentials.retrieve(service: "github"), !token.isEmpty {
            prMonitor.start(projectPath: projectPath, token: token)
        }
        githubTokenObserver = NotificationCenter.default.addObserver(
            forName: .merlinGitHubTokenChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartPRMonitor()
            }
        }
        Task {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let path = "\(home)/.merlin/toolbar-actions.json"
            await toolbarActions.load(from: path)
            toolbarActionsList = await toolbarActions.all()
        }
        Task { await xcalibreClient.probe() }
        Task { await registry.probeLocalProviders() }
        Task {
            let key = ConnectorCredentials.retrieve(service: "brave-search") ?? ""
            if !key.isEmpty {
                await ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: key)
            }
        }

        registryCancellable = registry.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncEngineProviders()
            }
        }

        // Receive provider selections posted by MerlinCommands.
        // NotificationCenter is used here because @FocusedBinding writes
        // inside CommandMenu are unreliable in the current SwiftUI/macOS runtime.
        NotificationCenter.default.addObserver(
            forName: .merlinSelectProvider,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let id = note.userInfo?["providerID"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.activeProviderID = id
            }
        }
        KeepAwakeManager.shared.apply(AppSettings.shared.keepAwake)
        keepAwakeCancellable = AppSettings.shared.$keepAwake
            .sink { KeepAwakeManager.shared.apply($0) }

        settingsCancellable = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncEngineProviders()
            }
        }

        projectPathCancellable = AppSettings.shared.$projectPath
            .dropFirst()
            .sink { [weak self] newPath in
                Task { @MainActor [weak self] in
                    self?.engine?.currentProjectPath = newPath.isEmpty ? nil : newPath
                }
            }

        ragRerankCancellable = AppSettings.shared.$ragRerank
            .dropFirst()
            .sink { [weak self] value in
                Task { @MainActor [weak self] in
                    self?.engine?.ragRerank = value
                }
            }

        ragChunkLimitCancellable = AppSettings.shared.$ragChunkLimit
            .dropFirst()
            .sink { [weak self] value in
                Task { @MainActor [weak self] in
                    self?.engine?.ragChunkLimit = value
                }
            }

        toolRouter.register(name: "rag_search") { [weak self] args in
            guard let client = self?.engine?.xcalibreClient else {
                return "RAG service not configured."
            }
            let projectPath = AppSettings.shared.projectPath
            return await RAGTools.search(
                args: args,
                client: client,
                projectPath: projectPath.isEmpty ? nil : projectPath
            )
        }

        toolRouter.register(name: "rag_list_books") { [weak self] _ in
            guard let client = self?.engine?.xcalibreClient else {
                return "RAG service not configured."
            }
            return await RAGTools.listBooks(client: client)
        }

        if registry.primaryProvider == nil {
            showFirstLaunchSetup = true
        }

        if ProcessInfo.processInfo.arguments.contains(showAuthPopupForTestingFlag) {
            pendingAuthRequest = AuthRequest(
                tool: "read_file",
                argument: "/Users/jon/Projects/App/Example.swift",
                reasoningStep: "Inspect the requested file before making a change.",
                suggestedPattern: "~/Projects/App/**",
                resolve: { _ in }
            )
            showAuthPopup = true
            showFirstLaunchSetup = false
        }
    }

    func resolveAuth(_ decision: AuthDecision) {
        pendingAuthRequest?.resolve(decision)
        pendingAuthRequest = nil
        showAuthPopup = false
    }

    func newSession() {
        engine.cancel()
        engine.contextManager.clear()
        toolLogLines.removeAll()
        toolActivityState = .idle
        thinkingModeActive = false
        NotificationCenter.default.post(name: .merlinNewSession, object: nil)
    }

    func stopEngine() {
        engine.cancel()
        toolActivityState = .idle
        thinkingModeActive = false
    }

    func updateContextUsage(_ tokens: Int) {
        contextUsage.update(usedTokens: tokens)
    }

    func restartPRMonitor() {
        prMonitor.stop()
        if let token = ConnectorCredentials.retrieve(service: "github"), !token.isEmpty {
            prMonitor.start(projectPath: projectPath, token: token)
        }
    }

    func reloadProviders() {
        syncEngineProviders()
    }

    static func installBuiltinSkills() {
        let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("Builtin")
            ?? builtinSkillsSourceURL()
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let destination = URL(fileURLWithPath: home).appendingPathComponent(".merlin/skills")
        let fm = FileManager.default
        guard let skills = try? fm.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) else { return }
        for skillDir in skills {
            let target = destination.appendingPathComponent(skillDir.lastPathComponent)
            guard !fm.fileExists(atPath: target.path) else { continue }
            try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try? fm.copyItem(at: skillDir, to: target)
        }
    }

    private static func builtinSkillsSourceURL() -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // Merlin
            .appendingPathComponent("Skills/Builtin")
    }

    private func syncEngineProviders() {
        let apiKey = registry.readAPIKey(for: "deepseek") ?? ""
        let fallbackPro = DeepSeekProvider(apiKey: apiKey, model: "deepseek-v4-pro")
        let fallbackFlash = DeepSeekProvider(apiKey: apiKey, model: "deepseek-v4-flash")
        if let primary = registry.primaryProvider {
            engine.proProvider = primary
            engine.flashProvider = primary
        } else {
            engine.proProvider = fallbackPro
            engine.flashProvider = fallbackFlash
        }
        engine.slotAssignments = AppSettings.shared.slotAssignments
        activeProviderID = registry.activeProviderID
        Task { await DomainRegistry.shared.setActiveDomain(id: AppSettings.shared.activeDomainID) }
    }
}

extension Notification.Name {
    static let merlinNewSession = Notification.Name("com.merlin.newSession")
    static let merlinGitHubTokenChanged = Notification.Name("com.merlin.githubTokenChanged")
    // Posted by MerlinCommands Provider menu — bypasses FocusedBinding unreliability
    static let merlinSelectProvider = Notification.Name("com.merlin.selectProvider")
    // Posted by File → New Session to open the project picker from Commands context
    static let merlinOpenPicker = Notification.Name("com.merlin.openPicker")
}

extension AppState: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        await withCheckedContinuation { continuation in
            pendingAuthRequest = AuthRequest(
                tool: tool,
                argument: argument,
                reasoningStep: "",
                suggestedPattern: suggestedPattern,
                resolve: { continuation.resume(returning: $0) }
            )
            showAuthPopup = true
        }
    }
}
