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
    /// Published so the UI can present a restart-instructions sheet after a reload request requires it.
    @Published var pendingRestartInstructions: RestartInstructions? = nil

    @Published var activeProviderID: String = "deepseek" {
        didSet {
            guard registry.activeProviderID != activeProviderID else { return }
            registry.activeProviderID = activeProviderID
            syncEngineProviders()
        }
    }
    @Published var parameterAdvisories: [ParameterAdvisory] = []
    @Published var thinkingModeActive: Bool = false
    @Published var toolActivityState: ToolActivityState = .idle

    let xcalibreClient: XcalibreClient
    /// Registry of all MemoryBackendPlugin implementations.
    /// AppState registers the built-in local backend at init, selects the persisted
    /// setting, and injects the active plugin into AgenticEngine.
    let memoryRegistry = MemoryBackendRegistry()
    /// Local model managers keyed by providerID; rebuilt from ProviderRegistry at init and whenever providers change.
    var localModelManagers: [String: any LocalModelManagerProtocol] = [:]
    /// The active local provider ID derived when the user selects a local provider in Settings → Providers.
    var activeLocalProviderID: String? = nil
    let loraCoordinator = LoRACoordinator()
    let parameterAdvisor = ModelParameterAdvisor()
    /// Lazily created so CalibrationCoordinator can hold a weak reference back to AppState.
    lazy var calibrationCoordinator: CalibrationCoordinator = CalibrationCoordinator(appState: self)
    let toolbarActions = ToolbarActionStore()
    private var registryCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var projectPathCancellable: AnyCancellable?
    private var ragRerankCancellable: AnyCancellable?
    private var ragChunkLimitCancellable: AnyCancellable?
    private var loraProviderCancellable: AnyCancellable?
    private var keepAwakeCancellable: AnyCancellable?
    private var githubTokenObserver: NSObjectProtocol?

    init(projectPath: String = "") {
        self.projectPath = projectPath
        let authStorePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Merlin/auth.json")
            .path

        authMemory = AuthMemory(storePath: authStorePath)
        xcalibreClient = XcalibreClient(token: AppSettings.shared.xcalibreToken)
        // 1. Register the built-in local backend.
        let vectorPlugin = LocalVectorPlugin(
            databasePath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".merlin/memory.sqlite").path,
            embeddingProvider: NLContextualEmbeddingProvider()
        )
        // 2. Select the persisted memory backend ID.
        memoryRegistry.register(vectorPlugin)
        memoryRegistry.setActive(pluginID: AppSettings.shared.memoryBackendID)
        Self.installBuiltinSkills()
        ToolRegistry.shared.registerBuiltins()
        // Idempotent registration; calling this once at init makes /calibrate available to the registry.
        CalibrationCoordinator.registerSkill()
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
            xcalibreClient: xcalibreClient,
            // 3. Inject the active backend into the engine at init.
            memoryBackend: memoryRegistry.activePlugin
        )
        // Prefer the open project's path; fall back to the global config.toml setting.
        let resolvedPath = projectPath.isEmpty ? AppSettings.shared.projectPath : projectPath
        engine.currentProjectPath = resolvedPath.isEmpty ? nil : resolvedPath
        engine.ragRerank = AppSettings.shared.ragRerank
        engine.ragChunkLimit = AppSettings.shared.ragChunkLimit
        // contextWindowSize stays at the declaration default (200_000); AppSettings.maxTokens
        // is the max *output* tokens per request, not the model's context window size.
        engine.registry = registry
        engine.sessionStore = sessionStore
        engine.loraCoordinator = loraCoordinator
        engine.parameterAdvisor = parameterAdvisor
        rebuildLocalModelManagers()
        engine.onParameterAdvisoriesUpdate = { [weak self] modelID in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshParameterAdvisories(for: modelID)
            }
        }
        engine.onAdvisory = { [weak self] advisory in
            guard let self else { return }
            await self.handleAdvisory(advisory)
        }
        refreshLoRAProvider(
            enabled: AppSettings.shared.loraEnabled,
            autoLoad: AppSettings.shared.loraAutoLoad,
            serverURL: AppSettings.shared.loraServerURL,
            adapterPath: AppSettings.shared.loraAdapterPath
        )
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
        Task {
            await registry.probeAndFetchModels()
            await registry.fetchAllModels()
        }
        let key = ConnectorCredentials.retrieve(service: "brave-search") ?? ""
        if !key.isEmpty {
            ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: key)
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

        Task { [weak self] in
            await self?.refreshParameterAdvisories()
        }

        settingsCancellable = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncEngineProviders()
                await self?.syncMemoryBackend()
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

        loraProviderCancellable = Publishers.CombineLatest4(
            AppSettings.shared.$loraEnabled,
            AppSettings.shared.$loraAutoLoad,
            AppSettings.shared.$loraServerURL,
            AppSettings.shared.$loraAdapterPath
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] enabled, autoLoad, serverURL, adapterPath in
            self?.refreshLoRAProvider(
                enabled: enabled,
                autoLoad: autoLoad,
                serverURL: serverURL,
                adapterPath: adapterPath
            )
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
        // Reset the circuit breaker counter so a new session always starts clean.
        engine.consecutiveCriticFailures = 0
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
        rebuildLocalModelManagers()
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
        if let activeConfig = registry.activeConfig, activeConfig.isLocal {
            activeLocalProviderID = activeConfig.localModelManagerID ?? activeConfig.id
        } else {
            activeLocalProviderID = nil
        }
        Task { await DomainRegistry.shared.setActiveDomain(id: AppSettings.shared.activeDomainID) }
        Task { [weak self] in
            await self?.refreshParameterAdvisories()
        }
    }

    private func syncMemoryBackend() async {
        // Keep the active backend aligned with the persisted setting.
        memoryRegistry.setActive(pluginID: AppSettings.shared.memoryBackendID)
        let active = memoryRegistry.activePlugin
        await engine.setMemoryBackend(active)
    }

    /// Returns the local model manager for a providerID, if one exists.
    func manager(for providerID: String) -> (any LocalModelManagerProtocol)? {
        localModelManagers[providerID]
    }

    /// Returns the registered provider instance for a provider ID.
    func provider(for providerID: String) -> (any LLMProvider)? {
        registry.provider(for: providerID)
    }

    func providerConfig(for providerID: String) -> ProviderConfig? {
        registry.providers.first { $0.id == providerID }
    }

    /// Enabled provider configurations in the current registry state.
    var configuredProviders: [ProviderConfig] {
        registry.providers.filter(\.isEnabled)
    }

    var activeModelID: String {
        engine.currentModelID
    }

    /// Applies an advisory to either the active local model or AppSettings inference defaults.
    /// `.contextLengthTooSmall` reloads the local manager and may surface restart instructions.
    /// `.maxTokensTooLow` raises `AppSettings.inferenceMaxTokens`.
    /// `.temperatureUnstable` lowers `AppSettings.inferenceTemperature`.
    /// `.repetitiveOutput` raises `AppSettings.inferenceRepeatPenalty`.
    func applyAdvisory(_ advisory: ParameterAdvisory) async throws {
        switch advisory.kind {
        case .contextLengthTooSmall:
            let suggested = Int(advisory.suggestedValue.components(separatedBy: .whitespaces).first ?? "") ?? 16_384
            var config = LocalModelConfig()
            config.contextLength = suggested

            guard let providerID = activeLocalProviderID ?? registry.activeConfig?.id,
                  let manager = localModelManagers[providerID] else {
                throw ModelManagerError.providerUnavailable
            }

            pendingRestartInstructions = nil
            do {
                try await manager.reload(modelID: advisory.modelID, config: config)
            } catch ModelManagerError.requiresRestart(let instructions) {
                pendingRestartInstructions = instructions
                throw ModelManagerError.requiresRestart(instructions)
            }

        case .maxTokensTooLow:
            let suggested = Int(advisory.suggestedValue.components(separatedBy: .whitespaces).first ?? "") ?? 2_048
            AppSettings.shared.inferenceMaxTokens = suggested

        case .temperatureUnstable:
            let current = AppSettings.shared.inferenceTemperature ?? 0.7
            AppSettings.shared.inferenceTemperature = max(0.1, current - 0.1)

        case .repetitiveOutput:
            let current = AppSettings.shared.inferenceRepeatPenalty ?? 1.0
            if current < 1.1 {
                AppSettings.shared.inferenceRepeatPenalty = 1.15
            }
        }
    }

    private func refreshParameterAdvisories() async {
        await refreshParameterAdvisories(for: engine.currentModelID)
    }

    private func refreshParameterAdvisories(for modelID: String) async {
        parameterAdvisories = await parameterAdvisor.currentAdvisories(for: modelID)
    }

    private func refreshLoRAProvider(
        enabled: Bool,
        autoLoad: Bool,
        serverURL: String,
        adapterPath: String
    ) {
        guard enabled,
              autoLoad,
              !serverURL.isEmpty,
              !adapterPath.isEmpty,
              FileManager.default.fileExists(atPath: adapterPath),
              let url = URL(string: serverURL) else {
            engine.loraProvider = nil
            return
        }

        engine.loraProvider = OpenAICompatibleProvider(
            id: "lora-local",
            baseURL: url,
            apiKey: nil,
            modelID: "lora-adapter"
        )
    }

    private func rebuildLocalModelManagers() {
        var managers: [String: any LocalModelManagerProtocol] = [:]
        for config in registry.providers where config.isLocal {
            managers[config.id] = makeManager(for: config)
        }
        localModelManagers = managers
    }

    // Map each local provider ID to its concrete manager. Unknown IDs and malformed URLs
    // fall back to NullModelManager so the Settings UI can still render safely.
    private func makeManager(for config: ProviderConfig) -> any LocalModelManagerProtocol {
        guard let url = normalizedLocalManagerBaseURL(for: config.baseURL) else {
            return NullModelManager(providerID: config.id)
        }

        switch config.localModelManagerID ?? config.id {
        case "lmstudio":
            return LMStudioModelManager(baseURL: url)
        case "ollama":
            return OllamaModelManager(baseURL: url)
        case "jan":
            return JanModelManager(baseURL: url)
        case "localai":
            return LocalAIModelManager(baseURL: url)
        case "mistralrs":
            return MistralRSModelManager(baseURL: url)
        case "vllm":
            return VLLMModelManager(baseURL: url)
        default:
            // Unknown local provider IDs use a NullModelManager rather than failing the settings UI.
            return NullModelManager(providerID: config.id)
        }
    }

    private func normalizedLocalManagerBaseURL(for baseURL: String) -> URL? {
        let string = baseURL.hasPrefix("http") ? baseURL : "http://\(baseURL)"
        guard var url = URL(string: string) else {
            return nil
        }
        if url.path.hasSuffix("/v1") {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func handleAdvisory(_ advisory: ParameterAdvisory) async {
        engine.isReloadingModel = advisory.kind == .contextLengthTooSmall
        defer { engine.isReloadingModel = false }

        do {
            try await applyAdvisory(advisory)
        } catch ModelManagerError.requiresRestart(let instructions) {
            pendingRestartInstructions = instructions
        } catch {
            // Advisory application is best-effort. Other errors are intentionally ignored here.
        }
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
