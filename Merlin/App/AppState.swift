// AppState — top-level @MainActor observable for one project session.
//
// Owns: AgenticEngine, ProviderRegistry, AuthMemory, PRMonitor,
// tool log lines, screen capture state, context usage, and toolbar actions.
//
// activeProviderID.didSet keeps ProviderRegistry in sync and rebuilds
// the engine's provider instances via syncEngineProviders().
//
// See: Developer Manual § "Session & State Management → AppState"
@preconcurrency import Foundation
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

enum SlotRuntimeState: String, Sendable {
    case ready
    case busy
    case error
}

private let showAuthPopupForTestingFlag = "--show-auth-popup-for-testing"

private struct DisciplineToolArgs: Decodable {
    var projectPath: String?
}

@MainActor
final class AppState: ObservableObject {
    let projectPath: String
    private let initialActiveDomainIDs: [String]
    private var activeDomainIDs: [String]
    let registry = ProviderRegistry()
    let prMonitor = PRMonitor()
    @Published var engine: AgenticEngine!
    /// v2.2 Project Discipline Subsystem - central scanner coordinator. Built in init.
    let disciplineEngine: DisciplineEngine
    /// View-model backing the pending-attention chip + panel in ChatView.
    @Published var pendingAttention: PendingAttentionViewModel
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
    @Published private(set) var activeDomainDisplayName: String = SoftwareDomain().displayName

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
    @Published var slotRuntimeStates: [AgentSlot: SlotRuntimeState] = [:]

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
    private var providerKeyObserver: NSObjectProtocol?
    private var selectProviderObserver: NSObjectProtocol?
    private var pendingAuthContinuation: CheckedContinuation<AuthDecision, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var disciplineEventPollTask: Task<Void, Never>?
    private var calibrationCoordinatorCancellable: AnyCancellable?

    init(projectPath: String = "", activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs) {
        self.projectPath = projectPath
        let resolvedActiveDomainIDs = Self.inferredActiveDomainIDs(
            requested: activeDomainIDs,
            projectPath: projectPath
        )
        self.initialActiveDomainIDs = resolvedActiveDomainIDs
        self.activeDomainIDs = self.initialActiveDomainIDs
        // --- v2.2 Project Discipline Subsystem ---
        // Built early so the non-optional stored properties are initialised before any
        // self-using call. The pending-attention queue persists to <project>/.merlin.
        let disciplineStorePath = (projectPath.isEmpty
            ? FileManager.default.temporaryDirectory.path
            : projectPath) + "/.merlin/pending.json"
        // The seed adapters are installed asynchronously below; use the Swift stub as
        // the engine's adapter until a real .merlin/project.toml selection exists.
        let disciplineAdapter = ProjectAdapter.makeStub(language: "swift")
        disciplineEngine = DisciplineEngine(
            adapter: disciplineAdapter,
            phaseScanner: PhaseScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(),
            storePath: disciplineStorePath
        )
        pendingAttention = PendingAttentionViewModel(disciplineEngine: disciplineEngine)
        let authStorePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Merlin/auth.json")
            .path

        authMemory = AuthMemory(storePath: authStorePath)
        let configuredXcalibreToken = AppSettings.shared.xcalibreToken
        xcalibreClient = XcalibreClient(
            token: configuredXcalibreToken.isEmpty
                ? XcalibreClient.defaultToken()
                : configuredXcalibreToken)
        configureKAGBackend()
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
        let disciplineEngineForAdapter = disciplineEngine
        let projectPathForAdapter = projectPath
        Task {
            // Install + load the discipline seed adapters into ~/.merlin/adapters, then
            // resolve this project's real adapter from .merlin/project.toml and apply it
            // to the engine, replacing the bootstrap stub set above.
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let adaptersDir = "\(home)/.merlin/adapters"
            try? await AdapterRegistry.installSeedAdapters(into: adaptersDir)
            try? await AdapterRegistry.shared.loadFromDirectory(adaptersDir)
            let resolved = await DisciplineEngine.resolveProjectAdapter(
                projectPath: projectPathForAdapter)
            await disciplineEngineForAdapter.setAdapter(resolved)
        }

        let gate = AuthGate(memory: authMemory, presenter: self)
        let toolRouter = ToolRouter(authGate: gate)
        registerAllTools(
            router: toolRouter,
            visionProvider: { [weak self] in self?.engine?.provider(for: .vision) })
        configureCalibrationCoordinatorObservation()

        toolRouter.register(name: "run_shell") { [weak self] args in
            struct RunShellArgs: Decodable {
                var command: String
                var cwd: String?
                var timeout_seconds: Int?
            }

            let decoded = try JSONDecoder().decode(RunShellArgs.self, from: Data(args.utf8))
            var stdout = ""
            var stderr = ""
            var exitCode: Int32 = 0

            for try await line in ShellTool.stream(
                command: decoded.command,
                cwd: decoded.cwd,
                timeoutSeconds: decoded.timeout_seconds ?? 120
            ) {
                if let status = line.exitStatus {
                    exitCode = status
                    continue
                }

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

            return "exit:\(exitCode)\nstdout:\(stdout)\nstderr:\(stderr)"
        }

        toolRouter.register(name: "generate_api_docs") { [weak self] args in
            guard let self else { return "AppState unavailable." }
            let path = self.disciplineToolProjectPath(from: args)
            let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
            let out = try await APIDocGenerator().generate(projectPath: path, adapter: adapter)
            return "API docs generated: \(out)"
        }
        toolRouter.register(name: "generate_dev_guide") { [weak self] args in
            guard let self else { return "AppState unavailable." }
            let path = self.disciplineToolProjectPath(from: args)
            let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
            try await DevGuideGenerator().generate(projectPath: path, adapter: adapter)
            return "Developer guide updated."
        }
        toolRouter.register(name: "write_vale_styles") { [weak self] args in
            guard let self else { return "AppState unavailable." }
            let path = self.disciplineToolProjectPath(from: args)
            try await ValeStyleWriter().writeStyles(to: path + "/.vale/styles")
            return "Vale styles written to .vale/styles."
        }
        toolRouter.register(name: "scaffold_manual_coverage") { [weak self] args in
            guard let self else { return "AppState unavailable." }
            let path = self.disciplineToolProjectPath(from: args)
            let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
            let gaps = await ManualCoverageScanner().scan(projectPath: path, adapter: adapter)
            let writer = ManualSectionTemplateWriter()
            for gap in gaps {
                try await writer.write(gap: gap, to: path + "/docs/manual-coverage.md")
            }
            return "Scaffolded \(gaps.count) manual-coverage section(s)."
        }

        let ctx = ContextManager()
        sessionStore = SessionStore(projectPath: projectPath)

        engine = AgenticEngine(
            slotAssignments: AppSettings.shared.slotAssignments,
            activeDomainIDs: initialActiveDomainIDs,
            registry: registry,
            toolRouter: toolRouter,
            contextManager: ctx,
            xcalibreClient: xcalibreClient,
            // 3. Inject the active backend into the engine at init.
            memoryBackend: memoryRegistry.activePlugin
        )
        // Reset toolActivityState whenever the engine stops running so the sidebar
        // dot clears even if ChatView was torn down before its send loop completed.
        engine.$isRunning
            .filter { !$0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.toolActivityState != .idle else { return }
                self.toolActivityState = .idle
            }
            .store(in: &cancellables)
        // After every turn, run a discipline scan and refresh the pending-attention
        // chip. No-op for projects without a phases/ or .merlin/ tree.
        engine.$isRunning
            .filter { !$0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.projectPath.isEmpty else { return }
                let path = self.projectPath
                Task { [weak self] in
                    guard let self else { return }
                    _ = await self.disciplineEngine.scan(projectPath: path)
                    await self.disciplineEngine.runWeeklyOverrideReview()
                    await self.pendingAttention.refresh(projectPath: path)
                }
            }
            .store(in: &cancellables)
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
        engine.localModelManagers = localModelManagers
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
        syncEngineProviders(activeDomainIDs: initialActiveDomainIDs)
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

        // When Settings writes an API key its registry posts this; refresh our own
        // keyedProviderIDs from Keychain so the HUD updates without a restart.
        providerKeyObserver = NotificationCenter.default.addObserver(
            forName: .merlinProviderKeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.registry.refreshKeyedProviders()
            }
        }

        // Receive provider selections posted by MerlinCommands.
        // NotificationCenter is used here because @FocusedBinding writes
        // inside CommandMenu are unreliable in the current SwiftUI/macOS runtime.
        selectProviderObserver = NotificationCenter.default.addObserver(
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

        if !projectPath.isEmpty {
            startDisciplineEventPolling(projectPath: projectPath)
            // Auto-arm the discipline pre-commit gate for projects that opt into the
            // pre_commit layer; no Settings toggle required.
            Task {
                await DisciplineGateInstaller.installIfConfigured(projectPath: projectPath)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let note = await HookEngine.shared.runSessionStart(
                    projectPath: projectPath) {
                    self.toolLogLines.append(ToolLogLine(
                        text: note, source: .system, timestamp: Date()))
                }
                // Refresh the chip from any persisted findings.
                await self.pendingAttention.refresh(projectPath: projectPath)
            }
        }

        settingsCancellable = AppSettings.shared.objectWillChange.dropFirst().sink { [weak self] _ in
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

        if registry.primaryProvider == nil && registry.firstLaunchSetupCompleted == false {
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

        MerlinAppIntentsSupport.install(appState: self)
    }

    private func configureCalibrationCoordinatorObservation() {
        _ = calibrationCoordinator
        calibrationCoordinatorCancellable = calibrationCoordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    private func startDisciplineEventPolling(projectPath: String) {
        guard !projectPath.isEmpty else { return }
        disciplineEventPollTask?.cancel()
        let logPath = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".merlin/discipline-events.jsonl")
            .path
        let log = DisciplineEventLog(logPath: logPath)

        disciplineEventPollTask = Task { @MainActor [weak self] in
            var since = Date(timeIntervalSince1970: 0)
            while !Task.isCancelled {
                let events = await log.events(since: since)
                    .sorted { $0.timestamp < $1.timestamp }
                if let latest = events.map(\.timestamp).max() {
                    since = Date(timeInterval: 0.001, since: latest)
                }

                if !events.isEmpty {
                    guard let self else { return }
                    for event in events {
                        self.toolLogLines.append(ToolLogLine(
                            text: Self.disciplineToolLogText(for: event),
                            source: .system,
                            timestamp: event.timestamp
                        ))
                    }
                    await self.pendingAttention.refresh(projectPath: projectPath)
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func disciplineToolProjectPath(from args: String) -> String {
        let decoded = try? JSONDecoder().decode(DisciplineToolArgs.self, from: Data(args.utf8))
        if let requested = decoded?.projectPath, !requested.isEmpty {
            return requested
        }
        if let current = engine.currentProjectPath, !current.isEmpty {
            return current
        }
        if !projectPath.isEmpty {
            return projectPath
        }
        return AppSettings.shared.projectPath
    }

    private static func disciplineToolLogText(for event: DisciplineEvent) -> String {
        let status: String
        if let passed = event.passed {
            status = passed ? "passed" : "blocked"
        } else {
            status = event.detail
        }
        return "[discipline] \(event.subcommand): \(event.step) — \(status)"
    }

    deinit {
        disciplineEventPollTask?.cancel()
        if let githubTokenObserver {
            NotificationCenter.default.removeObserver(githubTokenObserver)
        }
        if let providerKeyObserver {
            NotificationCenter.default.removeObserver(providerKeyObserver)
        }
        if let selectProviderObserver {
            NotificationCenter.default.removeObserver(selectProviderObserver)
        }
        pendingAuthContinuation?.resume(returning: .deny)
        pendingAuthContinuation = nil
    }

    func resolveAuth(_ decision: AuthDecision) {
        let continuation = pendingAuthContinuation
        pendingAuthContinuation = nil
        pendingAuthRequest = nil
        showAuthPopup = false
        continuation?.resume(returning: decision)
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

    func startSessionFromAppIntent() {
        newSession()
    }

    func sendPromptFromAppIntent(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }

        for await _ in engine.send(userMessage: trimmed) {}
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

    var currentActiveDomainIDs: [String] {
        activeDomainIDs
    }

    var currentActiveDomainID: String {
        activeDomainIDs.first(where: { $0 != SoftwareDomain.defaultID }) ?? SoftwareDomain.defaultID
    }

    func suggestedDomainActivation(for message: String) -> DomainActivationSuggestion? {
        ElectronicsDomain.suggestedActivation(
            for: message,
            currentActiveDomainIDs: activeDomainIDs
        )
    }

    func setActiveDomains(_ ids: [String], persistAsDefault: Bool = false) async {
        let normalized = await DomainRegistry.shared.normalizedActiveDomainIDs(ids: ids)
        activeDomainIDs = normalized
        engine.activeDomainIDs = normalized
        activeDomainDisplayName = Self.fallbackDomainDisplayName(for: normalized)
        let domain = await DomainRegistry.shared.activeDomain(ids: normalized)
        activeDomainDisplayName = domain.displayName
        if persistAsDefault {
            AppSettings.shared.activeDomainIDs = normalized
        }
        persistActiveDomainsToCurrentSession(normalized)
    }

    func completeFirstLaunchSetup() {
        registry.markFirstLaunchSetupCompleted()
        showFirstLaunchSetup = false
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

    private static func fallbackDomainDisplayName(for ids: [String]) -> String {
        if ids.contains(ElectronicsDomain.defaultID) {
            return ElectronicsDomain().displayName
        }
        return SoftwareDomain().displayName
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

    private func persistActiveDomainsToCurrentSession(_ ids: [String]) {
        guard let sessionStore,
              let id = engine.sessionID ?? sessionStore.activeSessionID,
              let session = sessionStore.sessions.first(where: { $0.id == id }) else {
            return
        }
        var updated = session
        updated.activeDomainIDs = ids
        updated.updatedAt = Date()
        try? sessionStore.save(updated)
    }

    private func syncEngineProviders(activeDomainIDs: [String]? = nil) {
        rebuildLocalModelManagers()
        engine.registry = registry
        engine.slotAssignments = AppSettings.shared.slotAssignments
        activeProviderID = registry.activeProviderID
        if let activeConfig = registry.activeConfig, activeConfig.isLocal {
            activeLocalProviderID = activeConfig.localModelManagerID ?? activeConfig.id
        } else {
            activeLocalProviderID = nil
        }
        if let activeDomainIDs {
            self.activeDomainIDs = activeDomainIDs.isEmpty ? SoftwareDomain.defaultActiveDomainIDs : activeDomainIDs
        }
        engine.activeDomainIDs = self.activeDomainIDs
        activeDomainDisplayName = Self.fallbackDomainDisplayName(for: self.activeDomainIDs)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let domain = await DomainRegistry.shared.activeDomain(ids: self.activeDomainIDs)
            self.activeDomainDisplayName = domain.displayName
            await self.refreshParameterAdvisories()
        }
    }

    private func syncMemoryBackend() async {
        // Keep the active backend aligned with the persisted setting.
        memoryRegistry.setActive(pluginID: AppSettings.shared.memoryBackendID)
        let active = memoryRegistry.activePlugin
        await engine.setMemoryBackend(active)
    }

    func manager(for providerID: String) -> (any LocalModelManagerProtocol)? {
        localModelManagers[providerID]
    }

    func provider(for providerID: String) -> (any LLMProvider)? {
        registry.provider(for: providerID)
    }

    func providerConfig(for providerID: String) -> ProviderConfig? {
        // Direct match first.
        if let config = registry.providers.first(where: { $0.id == providerID }) {
            return config
        }
        // Virtual ID "backendID:modelID" — return backend config with model overridden.
        // This lets calibration use lmstudio:google/gemma-4-31b without a separate registry entry.
        if providerID.contains(":") {
            let parts = providerID.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let backendID = String(parts[0])
            let modelID   = String(parts[1])
            guard var config = registry.providers.first(where: { $0.id == backendID }) else { return nil }
            config.model = modelID
            return config
        }
        return nil
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
                let reloadedModelID = manager.reloadedModelID(afterApplying: config, to: advisory.modelID)
                registry.updateModel(reloadedModelID, for: providerID)
                await refreshParameterAdvisories(for: reloadedModelID)
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
        engine.localModelManagers = managers
    }

    // Map each local provider ID to its concrete manager. Unknown IDs and malformed URLs
    // fall back to NullModelManager so the Settings UI can still render safely.
    private func makeManager(for config: ProviderConfig) -> any LocalModelManagerProtocol {
        guard let url = normalizedLocalManagerBaseURL(for: config.baseURL) else {
            return NullModelManager(providerID: config.id)
        }

        if config.isLocal,
           config.kind == .openAICompatible,
           url.host?.lowercased() == "localhost",
           url.port == 1234 {
            return LMStudioModelManager(baseURL: url)
        }

        switch config.localModelManagerID ?? config.id {
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
        case "llamacpp":
            var runtime = AppSettings.shared.llamaCppRuntime
            runtime.apiKey = KeychainManager.readAPIKey(for: "llamacpp") ?? ""
            return LlamaCppModelManager(baseURL: url, runtimeSettings: runtime)
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

    private func configureKAGBackend() {
        if AppSettings.shared.kagEnabled {
            let xcalibreURL = AppSettings.shared.kagXcalibreURL
            if !xcalibreURL.isEmpty, let url = URL(string: xcalibreURL) {
                let token = AppSettings.shared.xcalibreToken
                let plugin = XcalibreKAGPlugin(baseURL: url, token: token)
                KAGBackendRegistry.shared.register(plugin)
            } else if let plugin = try? LocalKAGPlugin() {
                KAGBackendRegistry.shared.register(plugin)
            }
        }

        // Wire LLM provider access for post-turn triple extraction.
        KAGEngine.shared.providerFactory = { [weak self] in
            guard let self else { return nil }
            guard let provider = self.registry.provider(for: self.activeProviderID) else { return nil }
            let model: String
            if self.activeProviderID.contains(":") {
                model = String(self.activeProviderID.split(separator: ":", maxSplits: 1).last ?? "")
            } else {
                model = self.registry.providers
                    .first(where: { $0.id == self.activeProviderID })?.model ?? ""
            }
            return (provider, model)
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
    static let merlinToggleTerminal = Notification.Name("com.merlin.toggleTerminal")
    static let merlinToggleSideChat = Notification.Name("com.merlin.toggleSideChat")
    static let merlinReviewMemories = Notification.Name("com.merlin.reviewMemories")
    // Posted by the inject-file watcher when ~/.merlin/inject.txt is written.
    // userInfo["message"] contains the message string to submit to the active chat.
    static let merlinInjectMessage = Notification.Name("com.merlin.injectMessage")
    // Posted by ProviderRegistry.setAPIKey so other registry instances refresh from Keychain.
    static let merlinProviderKeyDidChange = Notification.Name("com.merlin.providerKeyDidChange")
}

extension AppState: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingAuthContinuation?.resume(returning: .deny)
                pendingAuthContinuation = continuation
                pendingAuthRequest = AuthRequest(
                    tool: tool,
                    argument: argument,
                    reasoningStep: "",
                    suggestedPattern: suggestedPattern,
                    resolve: { [weak self] decision in
                        Task { @MainActor in
                            self?.resolveAuth(decision)
                        }
                    }
                )
                showAuthPopup = true
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolveAuth(.deny)
            }
        }
    }
}
