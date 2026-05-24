// AgenticEngine — the central agentic loop. See Developer Manual § "Engine — The Agentic Loop".
import Foundation
import CryptoKit

enum EngineError: Error, Sendable {
    case preflightOverflow(estimated: Int, budget: Int)
}

enum PreflightOutcome: Equatable {
    case ok
    case wouldOverflow(estimated: Int, budget: Int)
}

enum AgentEvent {
    case text(String)
    case thinking(String)
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case subagentStarted(id: UUID, agentName: String)
    case subagentUpdate(id: UUID, event: SubagentEvent)
    case systemNote(String)
    case cleanStop(reason: String, summary: String)
    case ragSources([RAGChunk])
    /// Per-turn grounding confidence report. Emitted after RAG search even when
    /// `totalChunks == 0`, so callers can distinguish ungrounded from well-grounded turns.
    case groundingReport(GroundingReport)
    case error(Error)
}

extension CompletionChunk {
    static func assistant(_ text: String) -> CompletionChunk {
        CompletionChunk(delta: .init(content: text), finishReason: "stop")
    }
}

private actor CancellationState {
    private var finished = false

    func markFinished() -> Bool {
        guard finished == false else {
            return false
        }
        finished = true
        return true
    }
}

@MainActor
private final class AllowAllAuthPresenter: AuthPresenter {
    static let shared = AllowAllAuthPresenter()

    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        .allow
    }
}

@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    let checkpointStore = CheckpointStore()
    private let thinkingDetector = ThinkingModeDetector.self
    let toolRouter: ToolRouter
    /// KAGEngine used for triple extraction after each turn. Defaults to the
    /// process-wide singleton; injectable for testing.
    private let kagEngine: KAGEngine
    var xcalibreClient: (any XcalibreClientProtocol)?
    /// Local memory backend plugin for episodic writes and local memory RAG.
    /// This is separate from `xcalibreClient`, which remains book-content only.
    var memoryBackend: any MemoryBackendPlugin = NullMemoryPlugin()
    var loraCoordinator: LoRACoordinator?
    var parameterAdvisor: ModelParameterAdvisor?
    var loraProvider: (any LLMProvider)?
    var registry: ProviderRegistry?
    var skillsRegistry: SkillsRegistry?
    var activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs {
        didSet { _stablePrefixDirty = true }
    }
    var permissionMode: PermissionMode = .ask {
        didSet { _stablePrefixDirty = true }
    }
    var claudeMDContent: String = "" {
        didSet { _stablePrefixDirty = true }
    }
    /// SHA256 hex of the `claudeMDContent` that was most recently distilled.
    /// Empty string when no distillation has been performed yet.
    var claudeMDDistillHash: String = ""

    /// Compressed equivalent of `claudeMDContent` produced by `refreshDistilledClaudeMD(using:)`.
    /// Empty string until the first distillation completes.
    var claudeMDDistilledContent: String = ""
    var memoriesContent: String = "" {
        didSet { _stablePrefixDirty = true }
    }
    var standingInstructions: String = "" {
        didSet { _stablePrefixDirty = true }
    }
    var onUsageUpdate: ((Int) -> Void)?
    var onTitleUpdate: ((String) -> Void)?
    /// The UUID of the session record this engine saves into.
    /// Set by SessionManager immediately after creating the LiveSession.
    /// Used to look up the correct store record at turn-end, independent of
    /// SessionStore.activeSessionID which may be clobbered by concurrent saves.
    var sessionID: UUID?
    var onParameterAdvisoriesUpdate: ((String) -> Void)?
    var performanceTracker: any ModelPerformanceTrackerProtocol = ModelPerformanceTracker.shared
    var criticOverride: (any CriticEngineProtocol)?
    /// Maps provider base ID (e.g. "lmstudio") to its local model manager.
    /// Set by AppState at init and updated when providers change.
    var localModelManagers: [String: any LocalModelManagerProtocol] = [:]
    /// Set by AppState so advisory routing can pause the run loop while a local model reload is in flight.
    /// The handler clears `isReloadingModel` after the reload/restart attempt finishes.
    var onAdvisory: (@Sendable (ParameterAdvisory) async -> Void)?
    /// Stores the most recent critic verdict from runLoop for test inspection and memory-write gating.
    /// Reset to nil at the start of every runLoop invocation.
    /// When .fail, the backend memory write is suppressed at the end of the turn.
    var lastCriticVerdict: CriticResult?
    /// Counts consecutive turns where the critic returned `.fail`.
    /// Reset to 0 on `.pass` or `.skipped`, and reset by `AppState.newSession()`.
    var consecutiveCriticFailures: Int = 0
    var classifierOverride: (any PlannerEngineProtocol)?

    /// DPO queue for proposing training pairs. Injected in tests; defaults to the
    /// shared `~/.merlin/lora/pending/` queue in production.
    var dpoQueue: DPOQueue = DPOQueue()

    // MARK: - DPO capture state

    /// Stores the user prompt from the most recent completed turn (for DPO pairing).
    private var lastUserPrompt: String = ""
    /// Stores the model response from the most recent completed turn (for DPO pairing).
    private var lastModelResponse: String = ""
    /// Stores the model ID used in the most recent completed turn (for DPO pairing).
    private var lastModelID: String = ""

    /// Test-only override for the loop ceiling. When set, bypasses the adaptive calculation
    /// so tests can exercise near-ceiling and batch-split behaviour with a small iteration count.
    var maxIterationsOverride: Int?

    /// URL written by schedulePendingContinuation(). Override in tests to avoid touching
    /// the live ~/.merlin/inject.txt while Merlin is running.
    var continuationInjectURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".merlin/inject.txt")

    /// Checks whether the session still has the default title and, if so,
    /// generates one from the first user message and fires `onTitleUpdate`.
    /// Mutates `session.title` in place so the caller can persist it.
    func applyTitleUpdateIfNeeded(to session: inout Session) {
        guard session.title == "New Session" || session.title.isEmpty else { return }
        let generated = Session.generateTitle(from: session.messages)
        guard generated != "New Session" else { return }
        session.title = generated
        onTitleUpdate?(generated)
    }

    // MARK: - Loop continuation state

    /// Steps deferred from a batch-split plan. Written as a [CONTINUATION] inject
    /// after the current turn finishes. Cleared in schedulePendingContinuation().
    private var pendingContinuationSteps: [PlanStep] = []
    private var pendingContinuationOriginalTask: String = ""
    private var pendingContinuationCompletedCount: Int = 0
    private var continuationAborted: Bool = false

    // MARK: - Ceiling continuation

    /// How many times the engine has auto-continued after hitting the loop ceiling
    /// within the current user-initiated task. Prevents infinite ceiling bouncing.
    /// Resets when a fresh (non-continuation) user message starts a new turn.
    private var ceilingContinuationCount = 0
    /// Subagents spawned within the current user-initiated task. The local model
    /// tends to delegate compulsively instead of doing the work; once this hits
    /// `maxSpawnsPerTask`, further spawn_agent calls are rejected. Resets per task.
    private var spawnedSubagentCount = 0
    /// Hard per-task cap on subagent spawns — stops the 74-spawn runaway seen on
    /// S2. (A spawned subagent runs a single LLM completion and does not execute
    /// tools, so heavy delegation does no real work regardless.)
    private let maxSpawnsPerTask = 8

    /// Built-in tools a coding model can use to "fake" domain work — hand-writing a
    /// domain file, shelling out to a CLI, or delegating to context-free subagents —
    /// instead of calling a connected domain MCP server's tools. When an
    /// authoritative domain server is connected (see `improvisationGatedMCPServers`)
    /// these are withheld from the turn's tool list so the model is forced down the
    /// supported, verified MCP path. This is what makes S6 (KiCad) deterministic:
    /// the 4-bit execute model otherwise non-deterministically writes `.kicad_sch`
    /// by hand — and it reaches for *any* available file/shell tool, so all of them
    /// must go. `bash` and `run_shell` are both shell tools (gating only `run_shell`
    /// left `bash` as an escape hatch — the exact hole that failed an S6 run);
    /// `write_file`/`create_file` author files directly; `spawn_agent` delegates to
    /// subagents that run one LLM completion and execute no tools, so it does no
    /// real KiCad work and only burns the loop budget.
    private static let improvisationToolNames: Set<String> = [
        "run_shell", "bash", "write_file", "create_file", "spawn_agent"
    ]
    /// MCP servers whose tool set fully covers their domain's authoring workflow, so
    /// the generic file/shell tools are redundant and only invite improvisation.
    /// `kicad` exposes schematic/PCB/route/sim tools end to end — see
    /// merlin-kicad-mcp's KiCadTools (kicad_compile_project materializes the files).
    private static let improvisationGatedMCPServers: Set<String> = ["kicad"]

    private var activeContinuation: AsyncStream<AgentEvent>.Continuation?

    /// Maximum number of auto-continuations triggered by ceiling hits before the
    /// engine gives up and stops. Each continuation gets its own full loop budget.
    private let maxCeilingContinuations = 10

    // MARK: - Near-ceiling warning

    /// Non-nil while the engine is within nearCeilingThreshold iterations of the ceiling.
    /// Appended to the system prompt so the LLM knows to commit and wrap up.
    /// Reset to nil at turn end.
    var nearCeilingWarningAddendum: String?

    /// How many iterations from the ceiling triggers the near-ceiling warning.
    /// Exposed as a var so tests can set a larger value when maxIterations is small.
    /// Default is 8 — gives the LLM enough runway to commit and wrap up complex tasks.
    var nearCeilingThreshold = 8

    // Prefix cache — rebuilt only when source properties change.
    // nearCeilingWarningAddendum is excluded because it changes per loop iteration.
    var _stablePrefixDirty = true
    private var _stablePrefixCached = ""
    private var _stablePrefixCompressionEnabled = AppSettings.shared.promptCompressionEnabled

    var currentProjectPath: String? {
        didSet {
            guard currentProjectPath != oldValue else { return }
            _stablePrefixDirty = true
            let path = currentProjectPath ?? ""
            Task { [weak self] in
                guard let self else { return }
                let metrics = await self.sizeObserver.observe(path: path)
                await MainActor.run { self.projectSizeMetrics = metrics }
            }
        }
    }
    /// Most-recently observed size metrics for `currentProjectPath`.
    /// Updated in the background whenever `currentProjectPath` changes.
    var projectSizeMetrics: ProjectSizeMetrics = .default
    private let sizeObserver = ProjectSizeObserver()
    /// Mirrors AppSettings.ragRerank. Set at init and kept in sync by AppState.
    var ragRerank: Bool = false
    /// Mirrors AppSettings.ragChunkLimit. Clamped to 1...20 at call site.
    var ragChunkLimit: Int = 3
    /// True while AppState is applying a load-time advisory; pauseForReload() waits on this flag.
    var isReloadingModel: Bool = false
    private var hookEngine: HookEngine {
        HookEngine(hooks: AppSettings.shared.hooks)
    }
    var slotAssignments: [AgentSlot: String]

    weak var sessionStore: SessionStore?
    private var currentTask: Task<Void, Never>?
    @Published var isRunning: Bool = false

    init(slotAssignments: [AgentSlot: String] = [:],
         activeDomainIDs: [String] = SoftwareDomain.defaultActiveDomainIDs,
         registry: ProviderRegistry? = nil,
         toolRouter: ToolRouter,
         contextManager: ContextManager,
         xcalibreClient: (any XcalibreClientProtocol)? = nil,
         kagEngine: KAGEngine = .shared,
         memoryBackend: (any MemoryBackendPlugin)? = nil) {
        self.slotAssignments = slotAssignments
        self.activeDomainIDs = activeDomainIDs.isEmpty ? SoftwareDomain.defaultActiveDomainIDs : activeDomainIDs
        self.registry = registry
        self.toolRouter = toolRouter
        self.contextManager = contextManager
        self.xcalibreClient = xcalibreClient
        self.kagEngine = kagEngine
        if let memoryBackend {
            self.memoryBackend = memoryBackend
        }
    }

    convenience init() {
        let gate = AuthGate(memory: AuthMemory(storePath: "/dev/null"), presenter: AllowAllAuthPresenter.shared)
        self.init(
            slotAssignments: [:],
            registry: nil,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager(),
            xcalibreClient: nil,
            memoryBackend: nil
        )
    }

    /// Inject the active memory backend.
    func setMemoryBackend(_ backend: any MemoryBackendPlugin) async {
        memoryBackend = backend
    }

    /// Wire a single provider as pro/flash/vision for unit tests.
    func setRegistryForTesting(provider: any LLMProvider) {
        let config = ProviderConfig(
            id: provider.id,
            displayName: provider.id,
            baseURL: provider.baseURL.absoluteString,
            model: "",
            isEnabled: true,
            isLocal: true,
            supportsThinking: false,
            supportsVision: false,
            kind: .openAICompatible
        )
        let reg = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-test-registry-\(UUID().uuidString).json"),
            initialProviders: [config]
        )
        reg.add(provider)
        reg.activeProviderID = provider.id
        self.registry = reg
        self.slotAssignments = [.execute: provider.id, .reason: provider.id, .vision: provider.id]
    }

    func registerTool(_ name: String, handler: @escaping (String) async throws -> String) {
        toolRouter.register(name: name, handler: handler)
    }

    func invokeSkill(_ skill: Skill, arguments: String = "") -> AsyncStream<AgentEvent> {
        let body = skillsRegistry?.render(skill: skill, arguments: arguments)
            ?? SkillsRegistry.renderStatic(skill: skill, arguments: arguments)

        if skill.frontmatter.context == "fork" {
            return runFork(prompt: body)
        }

        var message = body
        if let role = skill.frontmatter.role {
            message = "@\(role.rawValue) \(message)"
        }
        if let complexity = skill.frontmatter.complexity {
            message = "#\(complexity.rawValue) \(message)"
        }

        return send(userMessage: message)
    }

    func buildSystemPromptForTesting(slot: AgentSlot = .execute) async -> String {
        await buildSystemPrompt(for: slot)
    }

    func currentAddendumHash(for slot: AgentSlot) async -> String {
        await combinedAddendum(for: slot).addendumHash
    }

    func offeredToolNamesForTesting() -> [String] {
        offeredTools().map { $0.function.name }
    }

    var currentModelID: String {
        modelID(for: resolvedProvider(for: .execute))
    }

    /// Returns the effective loop ceiling for the given complexity tier.
    ///
    /// Takes the larger of the adaptive ceiling (derived from observed project size)
    /// and `AppSettings.maxLoopIterations` so a user-configured higher value always wins.
    func effectiveLoopCeiling(for tier: ComplexityTier) -> Int {
        if let override = maxIterationsOverride { return override }
        return max(projectSizeMetrics.adaptiveCeiling(for: tier),
                   AppSettings.shared.maxLoopIterations)
    }

    /// Returns the provider assigned to the given slot, or nil if the slot cannot be resolved.
    /// `orchestrate` falls back to `reason` when not explicitly assigned.
    func provider(for slot: AgentSlot) -> (any LLMProvider)? {
        // LoRA provider overrides execute slot when active.
        if slot == .execute, let lora = loraProvider {
            return lora
        }

        let effectiveSlot: AgentSlot = (slot == .orchestrate && slotAssignments[.orchestrate] == nil)
            ? .reason : slot

        if let providerID = slotAssignments[effectiveSlot], !providerID.isEmpty,
           let resolved = registry?.provider(for: providerID) {
            return resolved
        }

        if effectiveSlot == .execute || effectiveSlot == .vision {
            return registry?.primaryProvider ?? NullProvider()
        }
        return nil
    }

    /// Determines which slot should handle this message.
    /// Checks `@slot` override annotation first, then vision keywords, then defaults to execute.
    func selectSlot(for message: String) -> AgentSlot {
        let lower = message.lowercased()

        // Explicit slot override annotations
        if lower.hasPrefix("@reason ") || lower.contains(" @reason ") { return .reason }
        if lower.hasPrefix("@execute ") || lower.contains(" @execute ") { return .execute }
        if lower.hasPrefix("@orchestrate ") || lower.contains(" @orchestrate ") { return .orchestrate }

        // Vision slot: whole-word match only.
        // "ui" is intentionally excluded — it appears as a substring in paths/names (e.g. "jonzu*ui*lkowski").
        // "screen" requires \b so it doesn't match inside "screensaver", filenames, etc.
        if AgenticEngine.looksLikeVisionRequest(lower) { return .vision }

        // Default: execute slot handles all other work
        return .execute
    }

    /// Returns true when the message clearly targets the vision provider — i.e. the
    /// whole turn should run on the (smaller) vision model rather than the execute
    /// model. This must be conservative: routing a coding/agentic task to the vision
    /// model cripples it. "click"/"button" are NOT used — they are ubiquitous in
    /// coding and UI-debug prompts (e.g. S1's "click every toolbar button"), which
    /// must run on the execute model; per-image work goes through the vision_query
    /// tool instead, which routes only that call to the vision slot.
    static func looksLikeVisionRequest(_ lower: String) -> Bool {
        // Exact-phrase keywords that are unambiguous without boundary checks.
        let phraseKeywords = ["screenshot", "take a picture", "capture the screen",
                              "describe the image", "what is in this image"]
        if phraseKeywords.contains(where: { lower.contains($0) }) { return true }
        // Word-boundary keywords: must appear as complete words.
        let wordKeywords = ["vision"]
        return wordKeywords.contains { keyword in
            (try? NSRegularExpression(pattern: "\\b\(keyword)\\b"))
                .map { $0.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil }
                ?? false
        }
    }

    private func resolvedProvider(for slot: AgentSlot) -> any LLMProvider {
        if let provider = provider(for: slot) {
            return provider
        }
        if let provider = provider(for: .execute) {
            return provider
        }
        return NullProvider()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
    }

    func pauseForReload() async {
        while isReloadingModel {
            // Poll at 500ms so the agent loop resumes quickly without busy-waiting.
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    func submitDiffComments(changeIDs: [UUID]) -> AsyncStream<AgentEvent> {
        guard let buffer = toolRouter.stagingBuffer else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let state = CancellationState()
                await withTaskCancellationHandler(operation: {
                    let message = await buffer.commentsAsAgentMessage(changeIDs)
                    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        await self.finishStream(continuation, interrupted: false, state: state)
                        return
                    }

                    do {
                        try await self.runLoop(userMessage: message, continuation: continuation, depth: 0)
                        await self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        await self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        await self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        await self.finishStream(continuation, interrupted: true, state: state)
                    }
                })
            }

            Task { @MainActor in
                self.isRunning = true
                self.currentTask = task
            }
        }
    }

    func send(userMessage: String) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let state = CancellationState()
                self.ceilingContinuationCount = 0
                if self.contextManager.messages.isEmpty {
                    self.checkpointStore.clear()
                }
                self.activeContinuation = continuation
                await withTaskCancellationHandler(operation: {
                    do {
                        let turnNumber = self.contextManager.messages.filter { $0.role == .user }.count + 1
                        let slot = self.selectSlot(for: userMessage)
                        TelemetryEmitter.shared.emit("engine.turn.start", data: [
                            "turn": turnNumber,
                            "slot": slot.rawValue,
                            "message_length": userMessage.count
                        ])
                        let provider = self.selectProvider(for: userMessage)
                        TelemetryEmitter.shared.emit("engine.provider.selected", data: [
                            "turn": turnNumber,
                            "slot": slot.rawValue,
                            "provider_id": provider.id
                        ])
                        try await self.runLoop(userMessage: userMessage, continuation: continuation, depth: 0)
                        await self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        await self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        await self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        await self.finishStream(continuation, interrupted: true, state: state)
                    }
                })
            }

            Task { @MainActor in
                self.isRunning = true
                self.currentTask = task
            }
        }
    }

    func execute(userMessage: String) -> AsyncStream<AgentEvent> {
        send(userMessage: userMessage)
    }

    /// Appends a system note to the active stream if a run is in progress; otherwise no-op.
    func emitSystemNote(_ text: String) {
        activeContinuation?.yield(.systemNote(text))
    }

    private func runFork(prompt: String) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let forkContext = ContextManager()
            let task = Task { @MainActor in
                let state = CancellationState()
                await withTaskCancellationHandler(operation: {
                    do {
                        try await self.runLoop(
                            userMessage: prompt,
                            continuation: continuation,
                            contextOverride: forkContext,
                            depth: 0
                        )
                        await self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        await self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        await self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        await self.finishStream(continuation, interrupted: true, state: state)
                    }
                })
            }

            Task { @MainActor in
                self.isRunning = true
                self.currentTask = task
            }
        }
    }

    private func finishStream(_ continuation: AsyncStream<AgentEvent>.Continuation,
                              interrupted: Bool,
                              state: CancellationState) async {
        guard await state.markFinished() else { return }
        if interrupted {
            continuation.yield(.systemNote("[Interrupted]"))
        }
        continuation.finish()
        activeContinuation = nil
        currentTask = nil
        isRunning = false
    }

    // MARK: - Core loop

    // runLoop is the recursive heart of the engine.
    // Each iteration: build request → stream provider → collect tool calls
    // → run hooks → dispatch tools → append results → repeat.
    // Exits when the provider produces no tool calls and no Stop hook requests continuation.
    // contextOverride is used by fork-context skill invocations to avoid polluting main history.
    private func runLoop(
        userMessage: String,
        continuation: AsyncStream<AgentEvent>.Continuation,
        contextOverride: ContextManager? = nil,
        depth: Int
    ) async throws {
        let context = contextOverride ?? contextManager
        let domain = await activeDomain()

        // DPO pair proposal: if this turn looks like a correction of the previous turn,
        // capture the previous prompt+response as a rejected pair awaiting user review.
        // Skipped for [CONTINUATION] injections and when dpoEnabled is off.
        if AppSettings.shared.dpoEnabled,
           !lastModelResponse.isEmpty,
           !userMessage.hasPrefix("[CONTINUATION]"),
           isCorrectionMessage(userMessage) {
            let entry = DPOPendingEntry(
                prompt: lastUserPrompt,
                chosen: "",          // user fills this in via the pending review queue
                rejected: lastModelResponse,
                modelID: lastModelID,
                timestamp: Date()
            )
            try? await dpoQueue.propose(entry: entry)
        }

        // [CONTINUATION] messages are produced by the engine's own plan-batching logic.
        // Skip re-classification and re-planning: treat as high-stakes so the ceiling is
        // generous, but needsPlanning=false to avoid re-decomposing the already-split task.
        let isContinuation = userMessage.hasPrefix("[CONTINUATION]")
        continuationAborted = false

        // Reset the ceiling-continuation counter whenever a genuine new user message
        // starts so the budget applies per task, not per session.
        if !isContinuation {
            ceilingContinuationCount = 0
            spawnedSubagentCount = 0
        }
        let classification: ClassifierResult
        if isContinuation {
            classification = ClassifierResult(needsPlanning: false, complexity: .highStakes, reason: "continuation turn")
        } else {
            classification = await classify(message: userMessage, domain: domain)
        }
        let workingSlot: AgentSlot = classification.complexity == .highStakes ? .reason : .execute

        let cbThreshold = AppSettings.shared.agentCircuitBreakerThreshold
        let cbMode = AppSettings.shared.agentCircuitBreakerMode
        if cbThreshold > 0, consecutiveCriticFailures >= cbThreshold, cbMode == "halt" {
            continuation.yield(.systemNote(
                "🛑 Halted after \(consecutiveCriticFailures) consecutive reliability failures. " +
                "Start a new session or adjust Settings → Providers before continuing."
            ))
            return
        }

        if let buffer = toolRouter.stagingBuffer {
            await buffer.resetSessionCounts()
        }

        var effectiveMessage = userMessage
        let preflightProvider = resolvedProvider(for: workingSlot)
        let basePreflightEstimate = approximateTokens(in: context)
        let memResults = (try? await memoryBackend.search(
            query: userMessage,
            topK: 5,
            projectPath: currentProjectPath
        )) ?? []
        let memoryDates = memResults.map { $0.chunk.createdAt }
        let memChunks = memResults.map { $0.toRAGChunk() }
        var bookChunks: [RAGChunk] = []

        // Merge the two RAG sources in order: local memory first, then book content.
        if let client = xcalibreClient {
            bookChunks = await client.searchChunks(
                query: userMessage,
                source: "all",
                bookIDs: nil,
                projectPath: currentProjectPath,
                limit: min(max(ragChunkLimit, 1), 20),
                rerank: ragRerank
            )
        }

        let ragChunks = memChunks + bookChunks
        let workingSet = WorkingSetBudget.derive(from: effectiveBudget(for: preflightProvider))
        let selectedRAGChunks = RAGSelector.selectChunks(
            candidates: ragChunks,
            budget: workingSet.ragInjectionCap,
            userCeiling: ragChunkLimit
        )
        let ragTokensUsed = selectedRAGChunks.reduce(0) { total, chunk in
            total + TokenEstimator.estimateText(chunk.text)
        }
        TelemetryEmitter.shared.emit("engine.rag.selected", data: [
            "candidate_count": ragChunks.count,
            "selected_count": selectedRAGChunks.count,
            "tokens_used": ragTokensUsed,
            "budget_cap": workingSet.ragInjectionCap
        ])

        let kagEnabled = AppSettings.shared.kagEnabled
        let kagHops = max(1, AppSettings.shared.kagHops)

        if kagEnabled {
            effectiveMessage = await RAGTools.buildEnrichedMessage(
                query: userMessage,
                chunks: selectedRAGChunks,
                registry: KAGBackendRegistry.shared,
                hops: kagHops,
                domainId: domain.id
            )
        } else if !selectedRAGChunks.isEmpty {
            effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: selectedRAGChunks)
        }

        if !selectedRAGChunks.isEmpty {
            continuation.yield(.ragSources(selectedRAGChunks))
        }

        TelemetryEmitter.shared.emit("engine.preflight.estimate", data: [
            "estimated_tokens": max(1, basePreflightEstimate + TokenEstimator.estimateText(effectiveMessage)),
            "provider_id": preflightProvider.id,
            "slot": workingSlot.rawValue
        ])

        let groundingReport = GroundingReport.build(
            ragChunks: selectedRAGChunks,
            memoryCreatedAts: memoryDates,
            freshnessThresholdDays: AppSettings.shared.ragFreshnessThresholdDays,
            minGroundingScore: AppSettings.shared.ragMinGroundingScore
        )
        continuation.yield(.groundingReport(groundingReport))

        if let augmented = await hookEngine.runUserPromptSubmit(prompt: effectiveMessage) {
            continuation.yield(.systemNote(augmented))
        }
        // Discipline: flag a feature request submitted without a phase NNa file, so the
        // project's TDD-first workflow is visible in the agent loop.
        if let disciplineProjectPath = currentProjectPath, !disciplineProjectPath.isEmpty {
            let promptCheck = await UserPromptDisciplineChecker().check(
                prompt: effectiveMessage, projectPath: disciplineProjectPath)
            if case .missingPhaseFile(let suggestion) = promptCheck {
                continuation.yield(.systemNote("⚠️ TDD discipline: \(suggestion)"))
            }
        }
        let hadCompactionBeforeTurn = context.compactionCount > 0
        let shouldHintCompaction = context.messages.count > 80
        var turnCompactionCount = context.compactionCount
        var didEmitCompactionNote = false
        func emitCompactionNoteIfNeeded() {
            guard !didEmitCompactionNote else { return }
            guard hadCompactionBeforeTurn || shouldHintCompaction || context.compactionCount != turnCompactionCount else { return }
            turnCompactionCount = context.compactionCount
            didEmitCompactionNote = true
            continuation.yield(.systemNote("[context compacted — old tool results summarised]"))
        }
        var batchPrompt = effectiveMessage
        var currentPlanStep: PlanStep? = nil

        // Compute the loop ceiling early so the planner batch-split logic can reference it.
        let maxIterations = max(1, effectiveLoopCeiling(for: classification.complexity))
        let planner = PlannerEngine(
            executeProvider: selectProvider(for: userMessage),
            orchestrateProvider: provider(for: .orchestrate),
            maxPlanRetries: AppSettings.shared.maxPlanRetries
        )
        // Only let an escalation route to providers actually wired to a slot —
        // those are configured and reachable. The registry also carries merely-
        // configured providers (e.g. a `vllm` entry with no server running);
        // routing an escalation to one of those kills the turn.
        //
        // `provider(for:)` yields compound ids (`backend:model`), but
        // `EscalationHandler` matches against `providersOrderedByBudget()`, which
        // keys on the bare backend id — so reduce each to its backend before the
        // colon, otherwise the viability set never intersects and escalation can
        // never route.
        let viableEscalationProviders = Set(
            [AgentSlot.execute, .reason, .orchestrate, .vision]
                .compactMap { provider(for: $0)?.id }
                .map { String($0.split(separator: ":", maxSplits: 1).first ?? Substring($0)) })
        // A capability escalation routes to the reason slot — Merlin's designated
        // stronger model — rather than the biggest-context one. (Budget ranking
        // would pick a local model loaded at a large context over a stronger
        // remote model.) Skip it when the reason slot is the execute slot itself.
        let reasonSlotAssignment = slotAssignments[.reason]
        let preferredEscalation = (reasonSlotAssignment != slotAssignments[.execute])
            ? reasonSlotAssignment : nil
        let escalation = EscalationHandler(
            planner: planner, registry: registry,
            viableProviderIDs: viableEscalationProviders,
            preferredEscalationProviderID: preferredEscalation)
        let originalSlotAssignment = slotAssignments[workingSlot]
        defer {
            if let originalSlotAssignment {
                slotAssignments[workingSlot] = originalSlotAssignment
            } else {
                slotAssignments.removeValue(forKey: workingSlot)
            }
        }

        if classification.needsPlanning {
            // Use classifierOverride for decompose when available (enables test injection
            // and keeps the override as a full PlannerEngineProtocol).
            let planSteps: [PlanStep]
            if let override = classifierOverride {
                planSteps = await override.decompose(task: userMessage, context: context.messages)
            } else {
                planSteps = await planner.decompose(task: userMessage, context: context.messages)
            }

            if !planSteps.isEmpty {
                let batches = groupParallelSteps(planSteps)
                let thisBatch = batches[0]
                let remainingBatches = Array(batches.dropFirst())
                pendingContinuationSteps = remainingBatches.flatMap { $0 }
                pendingContinuationOriginalTask = userMessage
                pendingContinuationCompletedCount = thisBatch.count

                let totalBatches = batches.count
                let stepList = thisBatch.enumerated()
                    .map { "  \($0.offset + 1). \($0.element.description)" }
                    .joined(separator: "\n")
                currentPlanStep = thisBatch.count == 1 ? thisBatch.first : nil
                let batchLabel = thisBatch.count > 1
                    ? "[Plan: executing \(thisBatch.count) parallel steps]\n\(stepList)"
                    : "[Plan batch 1/\(totalBatches): executing step 1/\(planSteps.count)]\n\(stepList)"
                continuation.yield(.systemNote(batchLabel))

                if thisBatch.count > 1 {
                    let stepDescriptions = thisBatch.enumerated()
                        .map { "Task \($0.offset + 1): \($0.element.description)" }
                        .joined(separator: "\n")
                    batchPrompt = """
                    \(effectiveMessage)

                    Execute the following independent tasks in parallel using spawn_agent for each:
                    \(stepDescriptions)
                    """
                } else if let onlyStep = thisBatch.first {
                    batchPrompt = effectiveMessage + "\n\nTask: " + onlyStep.description
                }
            }
        }

        // Compact before appending if session has grown large.
        // Skip for continuations: they depend on recent tool results staying intact.
        context.compactIfNeededBeforeRun(isContinuation: isContinuation)
        if contextOverride == nil {
            checkpointStore.save(messages: context.messages)
        }
        context.append(Message(role: .user, content: .text(batchPrompt), timestamp: Date()))
        emitCompactionNoteIfNeeded()

        lastCriticVerdict = nil
        let loopStart = Date()
        let turn = context.messages.filter { $0.role == .user }.count
        // lastResponseText captures the full assistant text from the last no-tool-call response.
        // Passed to performanceTracker.record() as the response field for LoRA training data.
        var lastResponseText = ""
        var capturedFinishReason: String?
        var totalToolCallCount = 0
        var loopCount = 0
        // Paths written via write_file during this turn — passed to CriticEngine for
        // cross-referencing so the critic can verify document content against the assistant text.
        var writtenFilePaths: [String] = []
        var criticRetryCount = 0
        var finalCriticResult: CriticResult? = nil
        var nearCeilingEmitted = false
        var recentProgressFlags: [Bool] = []
        // Verbatim-response fingerprints for the last few tool-calling turns. A
        // model that emits the same prose intro 3× over a 6-turn window is in a
        // non-converging loop — `recentProgressFlags` misses this because a turn
        // with text + tool calls counts as "progress" even when it is identical
        // to the turn before it. See the repetition-stall escalation below.
        var recentTurnFingerprints: [String] = []
        var didAttemptContextOverrunRecovery = false
        // Clean handoff when a `.routeToProvider` escalation hands the task to a
        // stronger provider. Two problems are fixed together:
        //  • Budget — escalation fires after a stall, so the routed-to provider
        //    would otherwise inherit only the dregs of the loop budget.
        //  • Context — it would inherit the stalled model's flailing history
        //    (S1: ~90 confused turns), which even a strong model can't debug from.
        // So: reset the loop budget AND rebuild the context to a clean handoff —
        // the original task plus an instruction to assess the project state
        // directly. File-level progress is preserved on disk, so nothing real is
        // lost; only the confused conversation is dropped. Bounded: EscalationHandler
        // caps the number of provider routes per turn.
        let prepareEscalationHandoff = {
            loopCount = 0
            nearCeilingEmitted = false
            self.nearCeilingWarningAddendum = nil
            recentProgressFlags.removeAll()
            recentTurnFingerprints.removeAll()
            context.clear()
            context.load(Self.escalationHandoffMessages(task: userMessage))
        }
        turnLoop: while true {
                await pauseForReload()
                guard loopCount < maxIterations else {
                    if ceilingContinuationCount < maxCeilingContinuations {
                        ceilingContinuationCount += 1
                        let remaining = maxCeilingContinuations - ceilingContinuationCount
                        continuation.yield(.systemNote(
                            "[Loop ceiling reached — scheduling continuation \(ceilingContinuationCount)/\(maxCeilingContinuations)]"
                        ))
                        let resumeMsg = """
                        [CONTINUATION] The previous turn reached its loop iteration limit mid-task. \
                        Resume from where you left off: run `git status` to check pending changes, \
                        review recent edits, then continue and complete any unfinished work. \
                        (\(remaining) ceiling continuation(s) remain if needed.)
                        """
                        try? resumeMsg.write(to: continuationInjectURL, atomically: true, encoding: .utf8)
                    } else {
                        continuation.yield(.systemNote(
                            "[Loop ceiling reached — max continuations (\(maxCeilingContinuations)) exhausted, stopping]"
                        ))
                    }
                    break
                }
                loopCount += 1

                // Warn the LLM (via system prompt addendum + visible note) when
                // the loop budget is nearly exhausted so it commits and wraps up.
                let loopsRemaining = maxIterations - loopCount
                if loopsRemaining <= nearCeilingThreshold && !nearCeilingEmitted {
                    nearCeilingEmitted = true
                    nearCeilingWarningAddendum = """
                    ⚠️ LOOP BUDGET CRITICAL: You have \(loopsRemaining) iteration(s) remaining \
                    in this turn. Immediately commit all pending work (git commit), save any \
                    in-progress files, and wrap up. Do not start new tasks.
                    """
                    continuation.yield(.systemNote(
                        "[⚠️ \(loopsRemaining) loop iteration(s) remaining — commit all pending work now]"
                    ))
                }

                let provider: any LLMProvider
                if workingSlot == .reason {
                    provider = resolvedProvider(for: .reason)
                } else {
                    provider = selectProvider(for: userMessage)
                }
                let requestModel = modelID(for: provider)
                let currentEscalationStep = makeEscalationStep(
                    task: batchPrompt,
                    complexity: classification.complexity,
                    budget: effectiveBudget(for: provider)
                )
                // Escalate as soon as the model has stalled — three consecutive
                // turns with no text, no thinking and no file writes. This no
                // longer waits for the near-ceiling budget to run out: escalating
                // early means the stronger provider takes over before ~90 turns of
                // flailing accumulate (and the handoff discards that history anyway).
                // Repetition stall: the model emitted the same prose response on
                // ≥3 of the last 6 tool-calling turns. `recentProgressFlags` does
                // not catch this — a turn with text + tool calls reads as progress
                // even when it is verbatim-identical to the one before it. A model
                // re-introducing itself ("I'll help you build, test, and fix…")
                // every turn is looping, not working. This is a capability failure,
                // so it escalates straight to a stronger provider (no refinement).
                var fingerprintCounts: [String: Int] = [:]
                for fingerprint in recentTurnFingerprints where fingerprint.isEmpty == false {
                    fingerprintCounts[fingerprint, default: 0] += 1
                }
                if let repeatCount = fingerprintCounts.values.filter({ $0 >= 3 }).max() {
                    let decision = await handleEscalation(
                        currentStep: currentEscalationStep,
                        reason: .repetitionStall(
                            repeats: repeatCount,
                            lastObservation: "model repeated the same response verbatim"
                        ),
                        escalation: escalation,
                        workingSlot: workingSlot,
                        context: context,
                        continuation: continuation,
                        originalTask: userMessage
                    )
                    switch decision {
                    case .continueWith:
                        continue turnLoop
                    case .routeToProvider:
                        prepareEscalationHandoff()
                        continue turnLoop
                    case .stop:
                        break turnLoop
                    }
                }
                if recentProgressFlags.count >= 3,
                   recentProgressFlags.suffix(3).allSatisfy({ $0 == false }) {
                    let decision = await handleEscalation(
                        currentStep: currentEscalationStep,
                        reason: .iterationCap(
                            loopCount: loopCount,
                            lastObservation: "no new tool calls or text in the last 3 iterations"
                        ),
                        escalation: escalation,
                        workingSlot: workingSlot,
                        context: context,
                        continuation: continuation,
                        originalTask: userMessage
                    )
                    switch decision {
                    case .continueWith:
                        continue turnLoop
                    case .routeToProvider:
                        prepareEscalationHandoff()
                        continue turnLoop
                    case .stop:
                        break turnLoop
                    }
                }
                // Check thinking support against the actual slot provider, not activeConfig.
                // activeConfig reflects activeProviderID (often the execute/Flash provider)
                // which may have supportsThinking=false even though the reason/orchestrate
                // slot provider (Pro) supports it.
                let providerSupportsThinking = registry?.config(for: provider.id)?.supportsThinking ?? false
                let useThinking = (workingSlot == .reason || workingSlot == .orchestrate)
                    && providerSupportsThinking
                    && thinkingDetector.shouldEnableThinking(for: userMessage)
                // Always pass reasoning_content back in history messages regardless of the
                // target provider. DeepSeek's API rule: if any prior assistant message was
                // generated with reasoning_content, ALL subsequent requests (including to
                // deepseek-chat/Flash) must include that reasoning_content in the history.
                // Stripping it causes HTTP 400 "reasoning_content must be passed back".
                // The `thinking` parameter in the request body is separately gated by
                // `useThinking` — so Flash never gets thinking: enabled, but it does need
                // to see reasoning_content from prior Pro turns in the history.
                let rawMessages = messagesForProvider()
                var request = CompletionRequest(
                    model: requestModel,
                    messages: rawMessages,
                    thinking: useThinking ? ThinkingModeDetector.config(for: userMessage) : nil
                )
                request.tools = offeredTools()
                AppSettings.shared.applyInferenceDefaults(to: &request)
                // Per-provider max_tokens override: takes precedence over the global default.
                // Allows each provider to use its documented output limit (e.g. 131 072 for
                // DeepSeek V4) without affecting local or other remote providers.
                if let providerMaxOutput = registry?.config(for: provider.id)?.maxOutputTokens {
                    request.maxTokens = providerMaxOutput
                }
                do {

                // Auto-resize the local model context if the request would overflow it.
                // Estimate tokens as body bytes / 4 + 20% headroom.
                let slotID = workingSlot == .reason
                    ? (slotAssignments[.reason] ?? "")
                    : (slotAssignments[workingSlot] ?? slotAssignments[.execute] ?? "")
                let baseProviderID = slotID.contains(":")
                    ? String(slotID.split(separator: ":", maxSplits: 1).first ?? Substring(slotID))
                    : slotID
                if let manager = localModelManagers[baseProviderID] {
                    let bodyBytes = (try? encodeRequest(request, baseURL: provider.baseURL,
                                                        model: provider.resolvedModelID))?.count ?? 0
                    // Conservative pre-flight estimate: 4.0 bytes/token (looser than
                    // ContextManager's 3.5 because this gates a context-length reload — over-reserve
                    // is cheap, under-reserve forces a re-load mid-turn), +20% headroom, +512-token floor.
                    let estimatedTokens = Int(Double(bodyBytes) / 4.0 * 1.2) + 512
                    let resizedModelID = (try? await manager.ensureContextLength(
                        modelID: provider.resolvedModelID,
                        minimumTokens: estimatedTokens
                    )) ?? provider.resolvedModelID
                    request.model = resizedModelID
                    if resizedModelID != provider.resolvedModelID {
                        registry?.updateModel(resizedModelID, for: baseProviderID)
                    }
                }

                // Pre-flight budget gate. Working-set caps are applied inside the
                // preflight path before the request is estimated.
                try await preflightPlanStep(
                    step: currentEscalationStep,
                    request: request,
                    provider: provider
                )

                // Engine-level retry for transient provider errors (429, 5xx, network drops).
                // 3 attempts total; provider already has its own internal retry loop for
                // governor-style throttling. This outer loop handles mid-run outages.
                let stream = try await Self.completeWithRetry(
                    provider: provider,
                    request: request,
                    maxAttempts: 3,
                    onRetry: { attempt, maxAttempts in
                        continuation.yield(.systemNote(
                            "Provider unavailable — retrying (\(attempt)/\(maxAttempts - 1))…"
                        ))
                    }
                )
                var assembled: [Int: (id: String, name: String, args: String)] = [:]
                var sawToolCall = false
                var fullText = ""
                var fullThinking = ""   // accumulated reasoning_content for context round-trip

                for try await chunk in stream {
                    if let reason = chunk.finishReason {
                        capturedFinishReason = reason
                    }
                    if let thinkingContent = chunk.delta?.thinkingContent, !thinkingContent.isEmpty {
                        continuation.yield(.thinking(thinkingContent))
                        fullThinking += thinkingContent
                    }
                    if let content = chunk.delta?.content, !content.isEmpty {
                        continuation.yield(.text(content))
                        fullText += content
                    }
                    if let toolCalls = chunk.delta?.toolCalls {
                        sawToolCall = true
                        for delta in toolCalls {
                            var entry = assembled[delta.index] ?? (id: "", name: "", args: "")
                            if let id = delta.id, !id.isEmpty {
                                entry.id = id
                            }
                            if let name = delta.function?.name, !name.isEmpty {
                                entry.name = name
                            }
                            entry.args += delta.function?.arguments ?? ""
                            assembled[delta.index] = entry
                        }
                    }
                }

                guard sawToolCall, !assembled.isEmpty else {
                    lastResponseText = fullText
                    if !fullText.isEmpty {
                        context.append(Message(
                            role: .assistant,
                            content: .text(fullText),
                            thinkingContent: fullThinking.isEmpty ? nil : fullThinking,
                            timestamp: Date()
                        ))
                        // Continuation abort: if the model signals the step is already done, clear
                        // the pending queue so no further continuation turns are scheduled.
                        // Also delete the inject file so no stale [CONTINUATION] can fire from disk.
                        if isContinuation && fullText.contains("[STEP_ALREADY_DONE]") {
                            continuationAborted = true
                            pendingContinuationSteps.removeAll()
                            try? FileManager.default.removeItem(at: continuationInjectURL)
                            continuation.yield(.systemNote(
                                "↩︎ Continuation step already done — remaining steps cancelled."
                            ))
                        }
                    }
                    // Fire critic when policy allows it. Resolver precedence is:
                    // skill directive -> step directive -> deterministic checks -> heuristic.
                    let isSubstantialOutput = fullText.count > 1500
                    let criticHeuristic = (
                        writtenFiles: !writtenFilePaths.isEmpty,
                        substantial: isSubstantialOutput,
                        complexity: classification.complexity
                    )
                    var criticDecision = CriticPolicyResolver.resolve(
                        skill: nil,
                        step: currentPlanStep,
                        heuristic: criticHeuristic,
                        classifierOverride: classifierOverride != nil
                    )
                    // A code project with a real build/test is always critiquable —
                    // the deterministic verification IS the point. The heuristic
                    // skips it when the agent edited via run_shell (writtenFilePaths
                    // empty); override that so the critic runs `xcodebuild test` /
                    // `cargo test`, catches red tests, and triggers a retry/escalation
                    // instead of the loop silently ending with the task unverified.
                    if criticDecision == .skip,
                       CriticEngine.hasAutoDetectableProject(at: currentProjectPath) {
                        criticDecision = .run
                    }
                    var shouldRunCritic = false
                    var criticSeedNote: String?
                    switch criticDecision {
                    case .skip:
                        TelemetryEmitter.shared.emit("critic.skipped.policy", data: [
                            "decision_source": criticSkipSource(
                                skill: nil,
                                step: currentPlanStep,
                                heuristic: criticHeuristic,
                                classifierOverride: classifierOverride != nil
                            )
                        ])
                    case .run:
                        shouldRunCritic = true
                    case .deterministicOnly:
                        if let currentPlanStep {
                            let checker = CriterionChecker(shellRunner: LiveShellRunner())
                            var allPassed = true
                            for criterion in currentPlanStep.successCriteria {
                                if await checker.check(criterion) == false {
                                    allPassed = false
                                    criticSeedNote = "Deterministic verification failed: \(describeCriticCriterion(criterion))"
                                    break
                                }
                            }
                            if allPassed {
                                TelemetryEmitter.shared.emit("critic.stage1.short_circuit", data: [
                                    "criteria_passed": currentPlanStep.successCriteria.count
                                ])
                            } else {
                                shouldRunCritic = true
                            }
                        }
                    }
                    if shouldRunCritic && AppSettings.shared.criticEnabled {
                        if let criticSeedNote {
                            context.append(Message(
                                role: .system,
                                content: .text(criticSeedNote),
                                timestamp: Date()
                            ))
                        }
                        // criticOverride bypasses the reason-provider guard (test injection).
                        // Without an override, require a real reason provider.
                        let hasAvailableCritic = criticOverride != nil || {
                            if let p = self.provider(for: .reason), !(p is NullProvider) { return true }
                            return false
                        }()
                        if hasAvailableCritic {
                            let critic = makeCritic(domain: domain)
                            let taskType = domain.taskTypes.first
                                ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
                            let maxRetries = AppSettings.shared.maxCriticRetries
                            let verdict = await critic.evaluate(
                                taskType: taskType,
                                output: fullText,
                                context: context.messages,
                                writtenFiles: writtenFilePaths
                            )
                            lastCriticVerdict = verdict
                            finalCriticResult = verdict
                            switch verdict {
                            case .pass, .skipped:
                                consecutiveCriticFailures = 0
                            case .fail:
                                break
                            }
                            switch verdict {
                            case .pass:
                                break
                            case .fail(let reason):
                                if criticRetryCount < maxRetries {
                                    criticRetryCount += 1
                                    // Surface the correction so the critic's work is
                                    // observable in the event stream, not just in context.
                                    continuation.yield(.systemNote(
                                        "[Critic: correction \(criticRetryCount)/\(maxRetries) — \(reason)]"
                                    ))
                                    context.append(Message(
                                        role: .user,
                                        content: .text(
                                            "[Critic correction (\(criticRetryCount)/\(maxRetries)): \(reason). Please address this issue and provide a corrected response.]"
                                        ),
                                        timestamp: Date()
                                    ))
                                    continue
                                } else {
                                    // Retry budget on the current model is spent.
                                    // Escalate the correction to a stronger provider
                                    // rather than abandoning the task. The
                                    // consecutive-failure counter is bumped ONLY when
                                    // escalation truly gives up — `.stop`. Bumping it
                                    // here unconditionally double-counted: a routed
                                    // provider that also exhausted its retries hit
                                    // this branch a second time, so a single failed
                                    // user-message turn could increment the counter
                                    // multiple times and trip the circuit breaker
                                    // (CircuitBreakerTests.testCounterIncrementsOn-
                                    // ConsecutiveFails caught this).
                                    continuation.yield(.systemNote(
                                        "[Critic: \(maxRetries) retries exhausted — escalating: \(reason)]"
                                    ))
                                    let escalationDecision = await handleEscalation(
                                        currentStep: currentEscalationStep,
                                        reason: .criticExhausted(reason: reason),
                                        escalation: escalation,
                                        workingSlot: workingSlot,
                                        context: context,
                                        continuation: continuation,
                                        originalTask: userMessage
                                    )
                                    switch escalationDecision {
                                    case .routeToProvider:
                                        // Clean handoff: the escalated model gets a
                                        // fresh context (`prepareEscalationHandoff`),
                                        // so no critic-correction note is appended —
                                        // it re-runs the tests and sees the failure.
                                        criticRetryCount = 0
                                        prepareEscalationHandoff()
                                        continue turnLoop
                                    case .continueWith:
                                        context.append(Message(
                                            role: .user,
                                            content: .text(
                                                "[Critic escalation: the previous model could not "
                                                + "satisfy the critic after \(maxRetries) retries — "
                                                + "\(reason). Address this issue and provide a "
                                                + "corrected response.]"
                                            ),
                                            timestamp: Date()
                                        ))
                                        criticRetryCount = 0
                                        continue turnLoop
                                    case .stop:
                                        consecutiveCriticFailures += 1
                                        break turnLoop
                                    }
                                }
                            case .skipped:
                                continuation.yield(.systemNote("[unverified — critic unavailable]"))
                            }
                        } else {
                            continuation.yield(.systemNote("[unverified — critic unavailable]"))
                        }
                    }

                    let shouldContinue = await hookEngine.runStop()
                    if shouldContinue, await hookEngine.hasStopHooks() {
                        context.append(Message(
                            role: .user,
                            content: .text("[Hook: continue]"),
                            timestamp: Date()
                        ))
                        continue
                    }
                    break
                }

                let calls = assembled.keys.sorted().map { index in
                    let item = assembled[index]!
                    return ToolCall(
                        id: item.id.isEmpty ? UUID().uuidString : item.id,
                        type: "function",
                        function: FunctionCall(name: item.name, arguments: item.args)
                    )
                }
                totalToolCallCount += calls.count

                for call in calls {
                    continuation.yield(.toolCallStarted(call))
                }

            // Append the assistant turn that declared the tool calls.
            // The OpenAI wire format requires: assistant(tool_calls) → tool(result).
            // reasoning_content (DeepSeek thinking) must also be echoed back or the
            // provider returns HTTP 400 "reasoning_content must be passed back".
                context.append(Message(
                    role: .assistant,
                    content: .text(""),
                    toolCalls: calls,
                    thinkingContent: fullThinking.isEmpty ? nil : fullThinking,
                    timestamp: Date()
                ))

                toolRouter.permissionMode = permissionMode
                // Gated-improvisation enforcement. When an authoritative domain MCP
                // server is connected, the improvisation tools are withheld from the
                // offered list — but the 4-bit execute model emits `run_shell`/
                // `write_file`/`spawn_agent` calls from training memory anyway, and
                // the engine would otherwise run them (the handlers stay registered).
                // Reject those calls with a tool result that steers the model back to
                // the `mcp:` tools. This is what makes S6 (KiCad) deterministic: the
                // model has no executable path around the domain server's tools.
                let gatedTools = gatedImprovisationToolNames()
                var spawnCalls: [ToolCall] = []
                var regularCalls: [ToolCall] = []
                for call in calls {
                    if gatedTools.contains(call.function.name) {
                        let rejection = ToolResult(
                            toolCallId: call.id,
                            content: "`\(call.function.name)` is not available for "
                                + "this task. A domain MCP server is connected — "
                                + "author every domain file and run every domain "
                                + "operation through its `mcp:` tools (offered to you "
                                + "this turn). Do not shell out, hand-write files, or "
                                + "spawn subagents; call the `mcp:` tools directly.",
                            isError: true)
                        continuation.yield(.toolCallResult(rejection))
                        context.append(Message(
                            role: .tool,
                            content: .text(rejection.content),
                            toolCallId: call.id,
                            timestamp: Date()))
                    } else if call.function.name.hasPrefix("mcp:"),
                              !toolRouter.isAllowedMCPTool(named: call.function.name, activeDomainIDs: activeDomainIDs) {
                        let rejection = ToolResult(
                            toolCallId: call.id,
                            content: "`\(call.function.name)` is not available for the active domain set. "
                                + "Switch to the matching domain before calling this MCP tool, or use "
                                + "the tools offered for the current session domain.",
                            isError: true)
                        continuation.yield(.toolCallResult(rejection))
                        context.append(Message(
                            role: .tool,
                            content: .text(rejection.content),
                            toolCallId: call.id,
                            timestamp: Date()))
                    } else if call.function.name == "spawn_agent" {
                        spawnCalls.append(call)
                    } else {
                        regularCalls.append(call)
                    }
                }
                // Enforce the per-task subagent cap. Over-budget spawn_agent calls
                // are rejected with a tool result that tells the model to finish the
                // task itself — the local model otherwise delegates without bound.
                var allowedSpawnCalls: [ToolCall] = []
                for call in spawnCalls {
                    if spawnedSubagentCount < maxSpawnsPerTask {
                        spawnedSubagentCount += 1
                        allowedSpawnCalls.append(call)
                    } else {
                        let rejection = ToolResult(
                            toolCallId: call.id,
                            content: "spawn_agent budget exhausted — \(maxSpawnsPerTask) "
                                + "subagents already spawned for this task. Do NOT spawn "
                                + "more agents. Complete the remaining work yourself now "
                                + "with your own tools (run_shell, read_file, write_file, "
                                + "edit_file) and verify it.",
                            isError: true)
                        continuation.yield(.toolCallResult(rejection))
                        context.append(Message(
                            role: .tool,
                            content: .text(rejection.content),
                            toolCallId: call.id,
                            timestamp: Date()))
                    }
                }
                await handleSpawnAgents(
                    allowedSpawnCalls,
                    depth: depth,
                    continuation: continuation,
                    context: context
                )
                await dispatchRegularCalls(
                    regularCalls,
                    turn: turn,
                    loopCount: loopCount,
                    writtenFilePaths: &writtenFilePaths,
                    continuation: continuation,
                    context: context,
                    emitCompactionNoteIfNeeded: emitCompactionNoteIfNeeded
                )
                // Prompt compression: mid-loop LLM summarisation.
                // Threshold check, exchange extraction, one-shot provider call, and compact happen inside.
                // A turn that made tool calls IS progress — the model acted, even
                // if it produced no prose. Omitting `calls` here made a model that
                // was legitimately building/testing/reading (tool-only turns)
                // register as stalled, mis-firing the no-progress escalation.
                let turnHadProgress = !fullText.isEmpty || !fullThinking.isEmpty
                    || !writtenFilePaths.isEmpty || !calls.isEmpty
                recentProgressFlags.append(turnHadProgress)
                if recentProgressFlags.count > 3 {
                    recentProgressFlags.removeFirst(recentProgressFlags.count - 3)
                }
                // Record this turn's fingerprint for repetition-stall detection.
                // Combines the prose prefix and the tool-call signature so we
                // catch both kinds of loop: a model re-introducing itself
                // verbatim each turn AND a model stuck running the same tool
                // call over and over (the latter previously slipped past
                // `recentProgressFlags` because tool calls register as
                // progress). A productive model varies *either* its narration
                // or its tool-call args; only a genuinely stuck loop repeats
                // both. Args are truncated to 200 chars to bound the key size
                // and tolerate trivial whitespace drift.
                let textKey = String(
                    fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased().prefix(80))
                let toolKey = calls
                    .map { "\($0.function.name):\(String($0.function.arguments.prefix(200)))" }
                    .sorted()
                    .joined(separator: "|")
                let turnFingerprint = textKey.isEmpty && toolKey.isEmpty
                    ? "" : "\(textKey)##\(toolKey)"
                recentTurnFingerprints.append(turnFingerprint)
                if recentTurnFingerprints.count > 6 {
                    recentTurnFingerprints.removeFirst(recentTurnFingerprints.count - 6)
                }
                context.compactAfterToolBurst()
                emitCompactionNoteIfNeeded()
                } catch {
                if let pe = error as? ProviderError, pe.isContextLengthExceeded {
                    if didAttemptContextOverrunRecovery {
                        var data: [String: TelemetryValue] = [
                            "turn": .int(turn),
                            "slot": .string(workingSlot.rawValue),
                            "provider_id": .string(selectProvider(for: userMessage).id),
                            "error_domain": .string((pe as NSError).domain),
                            "error_code": .int((pe as NSError).code)
                        ]
                        if case .httpError(let statusCode, let body, _) = pe {
                            data["error_status"] = .int(statusCode)
                            data["error_body"] = .string(RedactedString.redacted(String(body.prefix(500))))
                        }
                        TelemetryEmitter.shared.emit("engine.turn.error", data: data)

                        let decision = await handleEscalation(
                            currentStep: currentEscalationStep,
                            reason: .preflightOverflow(
                                estimated: TokenEstimator.estimate(
                                    request: request,
                                    baseURL: provider.baseURL,
                                    modelID: provider.resolvedModelID
                                ),
                                budget: effectiveBudget(for: provider).usableInputTokens
                            ),
                            escalation: escalation,
                            workingSlot: workingSlot,
                            context: context,
                            continuation: continuation,
                            originalTask: userMessage
                        )
                        switch decision {
                        case .continueWith:
                            continue turnLoop
                        case .routeToProvider:
                            prepareEscalationHandoff()
                            continue turnLoop
                        case .stop:
                            break turnLoop
                        }
                    } else {
                        continuation.yield(.systemNote("[context overrun — last-ditch compaction]"))
                        context.forceCompaction()
                        context.append(Message(
                            role: .user,
                            content: .text("""
                            [CONTEXT_OVERRUN_RECOVERY] Continue from the interrupted task. \
                            Do not restart completed work. Finish the task from the current compacted state.
                            """),
                            timestamp: Date()
                        ))
                        didAttemptContextOverrunRecovery = true
                        continue turnLoop
                    }
                } else if let overflow = error as? EngineError {
                    switch overflow {
                    case .preflightOverflow(let estimated, let budget):
                        let decision = await handleEscalation(
                            currentStep: currentEscalationStep,
                            reason: .preflightOverflow(estimated: estimated, budget: budget),
                            escalation: escalation,
                            workingSlot: workingSlot,
                            context: context,
                            continuation: continuation,
                            originalTask: userMessage
                        )
                        switch decision {
                        case .continueWith:
                            continue turnLoop
                        case .routeToProvider:
                            prepareEscalationHandoff()
                            continue turnLoop
                        case .stop:
                            break turnLoop
                        }
                    }
                } else {
                    throw error
                }
            }

        if contextOverride == nil,
           let id = sessionID,
           let store = sessionStore,
           let session = store.sessions.first(where: { $0.id == id }) {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            applyTitleUpdateIfNeeded(to: &updated)
            try? store.save(updated)
        }

        let taskType = domain.taskTypes.first
            ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
        // diffAccepted and diffEditedOnAccept are real values from StagingBuffer counters
        // (acceptedCount, rejectedCount, editedOnAcceptCount), not hardcoded placeholders.
        let stagingAccepted: Int
        let stagingRejected: Int
        let stagingEdited: Int
        if let buffer = toolRouter.stagingBuffer {
            stagingAccepted = await buffer.acceptedCount
            stagingRejected = await buffer.rejectedCount
            stagingEdited = await buffer.editedOnAcceptCount
        } else {
            stagingAccepted = 0
            stagingRejected = 0
            stagingEdited = 0
        }
        // Derive stage1Passed from the final critic verdict:
        //   .pass    → true  (verification succeeded)
        //   .fail    → false (retries exhausted with no pass)
        //   .skipped → nil   (no verification backend or critic disabled)
        //   nil (critic never ran) → nil
        let stage1PassedSignal: Bool? = {
            switch finalCriticResult {
            case .pass:             return true
            case .fail:             return false
            case .skipped, nil:     return nil
            }
        }()
        let signals = OutcomeSignals(
            stage1Passed: stage1PassedSignal,
            stage2Score: nil,
            diffAccepted: stagingRejected == 0 || stagingAccepted > 0,
            diffEditedOnAccept: stagingEdited > 0,
            criticRetryCount: criticRetryCount,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: await currentAddendumHash(for: workingSlot),
            finishReason: capturedFinishReason
        )
        // Use the resolved provider's id when the slot has no explicit assignment.
        // An empty string causes all records to accumulate in a single "records-.json"
        // file that bloats unboundedly and causes a multi-minute save on every turn.
        let trackerModelID = slotAssignments[workingSlot] ?? resolvedProvider(for: workingSlot).id

        // Capture for potential DPO pairing on the next turn.
        lastUserPrompt = userMessage
        lastModelResponse = lastResponseText
        lastModelID = trackerModelID

        await performanceTracker.record(
            modelID: trackerModelID,
            taskType: taskType,
            signals: signals,
            prompt: userMessage,
            response: lastResponseText
        )
        let trackerRecords = await performanceTracker.records(for: trackerModelID, taskType: taskType)
        if AppSettings.shared.loraEnabled, AppSettings.shared.loraAutoTrain,
           let coordinator = loraCoordinator {
            await coordinator.considerTraining(
                tracker: performanceTracker,
                minSamples: AppSettings.shared.loraMinSamples,
                baseModel: AppSettings.shared.loraBaseModel,
                adapterOutputPath: AppSettings.shared.loraAdapterPath
            )
        }

        if let trackerRecord = trackerRecords.last, let advisor = parameterAdvisor {
            let advisories = await advisor.checkRecord(trackerRecord)
            for advisory in advisories {
                // Mark the loop as paused until AppState finishes the local reload or restart flow.
                isReloadingModel = advisory.kind == .contextLengthTooSmall
                await onAdvisory?(advisory)
            }
            if trackerRecords.count % 10 == 0 {
                _ = await advisor.analyze(records: Array(trackerRecords.suffix(20)), modelID: trackerRecord.modelID)
            }
            onParameterAdvisoriesUpdate?(trackerRecord.modelID)
        }

        if AppSettings.shared.memoriesEnabled {
            if case .fail = lastCriticVerdict {
                // Critic failure suppresses the episodic backend write for this turn.
            } else {
                let summary = context.messages
                    .filter { $0.role == .assistant }
                    .compactMap { if case .text(let t) = $0.content { return t } else { return nil } }
                    .joined(separator: "\n")
                    .prefix(2000)
                if !summary.isEmpty {
                    // Preserve the critic gating while redirecting the write to the local backend.
                    let chunk = MemoryChunk(
                        content: String(summary),
                        chunkType: "episodic",
                        sessionID: sessionStore?.activeSession?.id.uuidString,
                        projectPath: currentProjectPath
                    )
                    try? await memoryBackend.write(chunk)
                }
            }
        }

        if cbThreshold > 0, consecutiveCriticFailures >= cbThreshold, cbMode == "warn" {
            continuation.yield(.systemNote(
                "⚠️ Reliability check failed \(consecutiveCriticFailures) time\(consecutiveCriticFailures == 1 ? "" : "s") consecutively. " +
                "Output quality may be degraded. Check Settings → Providers for suggestions."
            ))
        }

        onUsageUpdate?(approximateTokens(in: context))
        let turnMs = Date().timeIntervalSince(loopStart) * 1000
        TelemetryEmitter.shared.emit("engine.turn.complete", durationMs: turnMs, data: [
            "turn": turn,
            "slot": workingSlot.rawValue,
            "provider_id": selectProvider(for: userMessage).id,
            "total_duration_ms": turnMs,
            "tool_call_count": totalToolCallCount,
            "loop_count": loopCount
        ])

        // KAG: schedule triple extraction from the completed assistant response.
        if AppSettings.shared.kagEnabled, !lastResponseText.isEmpty {
            kagEngine.scheduleExtraction(from: lastResponseText, domain: domain.id)
        }

        // Reset near-ceiling addendum so it doesn't bleed into the next turn.
        nearCeilingWarningAddendum = nil

        // If this turn processed a batch-split plan, write the remaining steps
        // as a [CONTINUATION] inject so the engine picks them up automatically.
        // Abort guard: if the model signalled [STEP_ALREADY_DONE], skip scheduling
        // so no further continuation turns fire for already-completed work.
        if !pendingContinuationSteps.isEmpty && !continuationAborted {
            schedulePendingContinuation()
        }
    }
    }

    /// Groups plan steps into execution batches.
    /// Adjacent parallel-safe steps are merged into one batch (up to maxParallelSteps).
    /// Sequential steps (parallelSafe == false) are always their own batch.
    /// Internal for test access.
    func groupParallelSteps(_ steps: [PlanStep], maxParallelSteps: Int = 4) -> [[PlanStep]] {
        var batches: [[PlanStep]] = []
        var currentBatch: [PlanStep] = []

        for step in steps {
            if step.parallelSafe && currentBatch.allSatisfy(\.parallelSafe) && currentBatch.count < maxParallelSteps {
                currentBatch.append(step)
            } else {
                if !currentBatch.isEmpty {
                    batches.append(currentBatch)
                }
                currentBatch = [step]
            }
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }
        return batches
    }

    // MARK: - Plan continuation

    /// Writes the next batch of deferred plan steps to the inject URL as a [CONTINUATION]
    /// message. Only writes one batch per call — remaining steps stay in
    /// `pendingContinuationSteps` so the post-turn hook schedules the next batch
    /// automatically at the end of every continuation turn, forming a correct chain.
    private func schedulePendingContinuation() {
        guard !pendingContinuationSteps.isEmpty else { return }

        let batches = groupParallelSteps(pendingContinuationSteps)
        guard let thisBatch = batches.first else { return }
        let stillRemaining = Array(batches.dropFirst()).flatMap { $0 }

        let completedCount   = pendingContinuationCompletedCount
        let originalTask     = pendingContinuationOriginalTask

        // Advance state: keep remaining steps for the NEXT continuation turn.
        // pendingContinuationOriginalTask is intentionally preserved.
        pendingContinuationSteps          = stillRemaining
        pendingContinuationCompletedCount = completedCount + thisBatch.count

        let stepList = thisBatch.enumerated()
            .map { "  \(completedCount + $0.offset + 1). \($0.element.description)" }
            .joined(separator: "\n")

        let executionInstruction: String
        if thisBatch.count > 1 {
            let taskList = thisBatch.enumerated()
                .map { "Task \($0.offset + 1): \($0.element.description)" }
                .joined(separator: "\n")
            executionInstruction = """
            Execute the following independent tasks in parallel using spawn_agent for each:
            \(taskList)
            """
        } else {
            executionInstruction = "Task: \(thisBatch[0].description)"
        }

        let message = """
        [CONTINUATION] Steps 1–\(completedCount) of the following task are complete. \
        Execute the next \(thisBatch.count) step(s) now:
        \(stepList)

        Original task: \(originalTask)
        \(executionInstruction)
        If this step is already complete, respond with [STEP_ALREADY_DONE] and take no further action.
        """

        try? message.write(to: continuationInjectURL, atomically: true, encoding: .utf8)

        TelemetryEmitter.shared.emit("engine.continuation.scheduled", data: [
            "completed_steps": completedCount,
            "batch_steps": thisBatch.count,
            "remaining_steps": stillRemaining.count
        ])
    }

    /// Returns true when `message` starts with a phrase that signals the user
    /// is correcting a previous response. Heuristic — false positives are harmless
    /// (DPO items go into a pending queue awaiting user review anyway).
    private func isCorrectionMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        let keywords = [
            "that's wrong", "thats wrong",
            "that is wrong", "that is incorrect",
            "that's incorrect", "thats incorrect",
            "no, ", "no that", "not quite",
            "actually,", "actually that",
            "you're wrong", "youre wrong",
            "wrong,", "wrong.", "incorrect,", "incorrect.",
            "please fix", "fix this", "fix the",
            "that doesn't", "that doesnt",
            "that isn't", "that isnt",
            "that won't", "that wont",
        ]
        return keywords.contains { lower.hasPrefix($0) || lower.contains(": \($0)") }
    }

    private func makeCritic(domain: any DomainPlugin) -> any CriticEngineProtocol {
        if let override = criticOverride {
            return override
        }
        let reasonSlotID = slotAssignments[.reason] ?? ""
        let baseProviderID = reasonSlotID.contains(":")
            ? String(reasonSlotID.split(separator: ":", maxSplits: 1).first ?? Substring(""))
            : reasonSlotID
        let manager = localModelManagers[baseProviderID]
        return CriticEngine(
            verificationBackend: domain.verificationBackend,
            reasonProvider: provider(for: .reason),
            modelManager: manager,
            projectPath: currentProjectPath
        )
    }

    private func criticSkipSource(
        skill: SkillFrontmatter?,
        step: PlanStep?,
        heuristic: (writtenFiles: Bool, substantial: Bool, complexity: ComplexityTier),
        classifierOverride: Bool
    ) -> String {
        if skill?.critic == .skip {
            return "skill"
        }
        if classifierOverride {
            return "heuristic"
        }
        if step?.requiresCritic == .skip {
            return "step"
        }
        return "heuristic"
    }

    private func describeCriticCriterion(_ criterion: StepCriterion) -> String {
        switch criterion {
        case .prose(let text):
            return "prose(\(text))"
        case .buildSucceeds:
            return "buildSucceeds"
        case .testsPass(let scheme):
            return "testsPass(\(scheme ?? "nil"))"
        case .fileExists(let path):
            return "fileExists(\(path))"
        case .regexMatch(let pattern, let target):
            return "regexMatch(\(pattern), \(target.rawValue))"
        case .shellExitZero(let command):
            return "shellExitZero(\(command))"
        }
    }

    private func makeEscalationStep(
        task: String,
        complexity: ComplexityTier,
        budget: ProviderBudget
    ) -> PlanStep {
        let tokenBudget = max(PlanStep.defaultTokenBudget, budget.usableInputTokens)
        return PlanStep(
            description: task,
            successCriteria: [.prose("complete the requested work")],
            complexity: complexity,
            parallelSafe: false,
            tokenBudget: tokenBudget,
            requiresCritic: .optional,
            minContextRequired: tokenBudget
        )
    }

    private func escalationReasonLabel(_ reason: EscalationReason) -> String {
        switch reason {
        case .iterationCap(let loopCount, let lastObservation):
            return "iteration cap reached after \(loopCount) loop(s); last observation: \(lastObservation)"
        case .preflightOverflow(let estimated, let budget):
            return "preflight overflow (\(estimated) > \(budget))"
        case .criticExhausted(let reason):
            return "critic retries exhausted: \(reason)"
        case .repetitionStall(let repeats, let lastObservation):
            return "repetition stall — same response \(repeats)× without progress; last observation: \(lastObservation)"
        }
    }

    /// The clean context handed to a stronger provider on a `.routeToProvider`
    /// escalation: the original task plus an instruction to assess the project
    /// state directly rather than trust the stalled prior model's conversation.
    /// The flailing history is deliberately discarded — file-level progress lives
    /// on disk, so the escalated model re-assessing loses nothing real.
    static func escalationHandoffMessages(task: String) -> [Message] {
        [
            Message(role: .user, content: .text(task), timestamp: Date()),
            Message(role: .user, content: .text(
                "[ESCALATION HANDOFF] A previous model attempted this task and "
                + "stalled without completing it. You are a more capable model "
                + "taking over. Do NOT rely on any prior conversation — assess the "
                + "current state of the project directly (build it, run its tests, "
                + "read the relevant files) and complete the task from there."),
                timestamp: Date())
        ]
    }

    private func progressSummary(for messages: [Message]) -> String {
        let recent = messages.suffix(3)
        guard recent.isEmpty == false else {
            return "- no progress recorded"
        }
        return recent.enumerated().map { index, message in
            let text = message.content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = text.isEmpty ? "(empty)" : String(text.prefix(120))
            return "- \(index + 1). \(message.role.rawValue): \(snippet)"
        }.joined(separator: "\n")
    }

    private func appendEscalationSteps(
        _ replacementSteps: [PlanStep],
        originalTask: String,
        context: ContextManager
    ) {
        let stepList = replacementSteps.enumerated()
            .map { "  \($0.offset + 1). \($0.element.description)" }
            .joined(separator: "\n")
        let message = """
        [ESCALATION] Continue with the following refined steps:
        \(stepList)

        Original task: \(originalTask)
        Execute these steps in order and keep the work scoped to the refined plan.
        """
        context.append(Message(role: .user, content: .text(message), timestamp: Date()))
    }

    private func buildCleanStopNote(
        reason: String,
        suggestion: String,
        progressSummary: String
    ) -> String {
        """
        ⛔ Cannot continue: \(reason). Suggested: \(suggestion). Progress so far:
        \(progressSummary)
        """
    }

    private func handleEscalation(
        currentStep: PlanStep,
        reason: EscalationReason,
        escalation: EscalationHandler,
        workingSlot: AgentSlot,
        context: ContextManager,
        continuation: AsyncStream<AgentEvent>.Continuation,
        originalTask: String
    ) async -> EscalationDecision {
        let data: [String: TelemetryValue] = [
            "reason": .string(escalationReasonLabel(reason)),
            "step": .string(currentStep.description),
            "token_budget": .int(currentStep.tokenBudget)
        ]
        TelemetryEmitter.shared.emit("engine.escalation.start", data: data)
        let decision = await escalation.escalateOrStop(
            currentStep: currentStep,
            reason: reason,
            context: context.messages
        )

        switch decision {
        case .continueWith(let replacementSteps):
            continuation.yield(.systemNote(
                "[Escalation] Refining into \(replacementSteps.count) substep(s)"
            ))
            appendEscalationSteps(replacementSteps, originalTask: originalTask, context: context)
        case .routeToProvider(let providerID, _):
            slotAssignments[workingSlot] = providerID
            continuation.yield(.systemNote("Step too large for current model; switching to \(providerID)"))
        case .stop(let message):
            let label = escalationReasonLabel(reason)
            let progress = progressSummary(for: context.messages)
            continuation.yield(.cleanStop(reason: label, summary: message))
            continuation.yield(.systemNote(
                buildCleanStopNote(reason: label, suggestion: message, progressSummary: progress)
            ))
        }

        return decision
    }

    private func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        if let classifierOverride {
            return await classifierOverride.classify(message: message, domain: domain)
        }
        return localClassification(message: message, domain: domain)
    }

    private func localClassification(message: String, domain: any DomainPlugin) -> ClassifierResult {
        let lower = message.lowercased()

        if lower.hasPrefix("#high-stakes ") || lower.hasPrefix("#high-stakes") {
            return ClassifierResult(needsPlanning: true, complexity: .highStakes, reason: "high-stakes override")
        }
        if lower.hasPrefix("#standard ") || lower.hasPrefix("#standard") {
            return ClassifierResult(needsPlanning: true, complexity: .standard, reason: "standard override")
        }
        if lower.hasPrefix("#routine ") || lower.hasPrefix("#routine") {
            return ClassifierResult(needsPlanning: false, complexity: .routine, reason: "routine override")
        }

        let planningKeywords = [
            "refactor",
            "migrate",
            "implement",
            "build",
            "create",
            "add",
            "update",
            "rewrite",
            "design",
            "change",
            "fix",
            // Document / analysis generation
            "generate",
            "produce",
            "write",
            "analyse",
            "analyze",
            "explore",
            "document",
            "report",
            "summarize",
            "summarise",
            "list all",
            "list the",
            "compare"
        ]
        if planningKeywords.contains(where: { lower.contains($0) }) {
            return ClassifierResult(needsPlanning: true, complexity: .standard, reason: "heuristic planning keyword")
        }

        return ClassifierResult(needsPlanning: false, complexity: .routine, reason: "heuristic routine")
    }

    private func inputDictionary(from arguments: String) -> [String: String] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dictionary = json as? [String: Any] else {
            return [:]
        }

        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = String(describing: pair.value)
        }
    }

    /// Dispatches all regular (non-spawn_agent) tool calls for one loop iteration.
    ///
    /// Three-phase approach:
    ///   1. Sequential pre-hooks  — preserves hook side-effect ordering
    ///   2. Batch parallel dispatch — passes all allowed calls to ToolRouter at once
    ///   3. Sequential context updates — preserves OpenAI wire-format message ordering
    func dispatchRegularCalls(
        _ calls: [ToolCall],
        turn: Int,
        loopCount: Int,
        writtenFilePaths: inout [String],
        continuation: AsyncStream<AgentEvent>.Continuation,
        context: ContextManager? = nil,
        emitCompactionNoteIfNeeded: (() -> Void)? = nil
    ) async {
        guard !calls.isEmpty else { return }

        struct PrehookOutcome {
            let call: ToolCall
            let denied: ToolResult?
            let writtenPath: String?
        }

        // Phase 1 — sequential pre-hooks
        var prehookOutcomes: [PrehookOutcome] = []
        prehookOutcomes.reserveCapacity(calls.count)
        for call in calls {
            let input = inputDictionary(from: call.function.arguments)
            let decision = await hookEngine.runPreToolUse(toolName: call.function.name, input: input)
            switch decision {
            case .deny(let reason):
                let denied = ToolResult(
                    toolCallId: call.id,
                    content: "Blocked by hook: \(reason)",
                    isError: true
                )
                prehookOutcomes.append(PrehookOutcome(call: call, denied: denied, writtenPath: nil))
            case .allow:
                let path: String? = call.function.name == "write_file" ? input["path"] : nil
                prehookOutcomes.append(PrehookOutcome(call: call, denied: nil, writtenPath: path))
            }
        }

        // Phase 2 — batch parallel dispatch
        let allowedCalls = prehookOutcomes.compactMap { $0.denied == nil ? $0.call : nil }
        let batchStart = Date()
        let batchResults: [ToolResult]
        if allowedCalls.isEmpty {
            batchResults = []
        } else {
            for call in allowedCalls {
                TelemetryEmitter.shared.emit("engine.tool.dispatched", data: [
                    "turn": turn,
                    "tool_name": call.function.name,
                    "loop": loopCount
                ])
            }
            batchResults = await toolRouter.dispatch(allowedCalls)
        }
        let batchMs = Date().timeIntervalSince(batchStart) * 1000
        let resultByID = Dictionary(uniqueKeysWithValues: batchResults.map { ($0.toolCallId, $0) })

        // Phase 3 — sequential context updates (original call order)
        let targetContext = context ?? contextManager
        for outcome in prehookOutcomes {
            let result: ToolResult
            if let denied = outcome.denied {
                result = denied
            } else if let matched = resultByID[outcome.call.id] {
                result = matched
                if result.isError {
                    TelemetryEmitter.shared.emit("engine.tool.error", durationMs: batchMs, data: [
                        "turn": turn,
                        "tool_name": outcome.call.function.name,
                        "loop": loopCount,
                        "error_domain": "tool_dispatch"
                    ])
                } else {
                    TelemetryEmitter.shared.emit("engine.tool.complete", durationMs: batchMs, data: [
                        "turn": turn,
                        "tool_name": outcome.call.function.name,
                        "loop": loopCount,
                        "duration_ms": batchMs,
                        "result_bytes": result.content.utf8.count
                    ])
                }
            } else {
                continue
            }

            if let path = outcome.writtenPath, !path.isEmpty {
                writtenFilePaths.append(path)
            }

            continuation.yield(.toolCallResult(result))
            targetContext.append(Message(
                role: .tool,
                content: .text(result.content),
                toolCallId: result.toolCallId,
                timestamp: Date()
            ))
            emitCompactionNoteIfNeeded?()

            if let note = await hookEngine.runPostToolUse(
                toolName: outcome.call.function.name,
                result: result.content
            ) {
                continuation.yield(.systemNote(note))
                targetContext.append(Message(role: .system, content: .text(note), timestamp: Date()))
                emitCompactionNoteIfNeeded?()
            }
        }
    }

    /// Launches all spawn_agent calls concurrently and forwards their events to the shared
    /// continuation. All subagents run in parallel; this returns after every stream ends.
    func handleSpawnAgents(
        _ calls: [ToolCall],
        depth: Int,
        continuation: AsyncStream<AgentEvent>.Continuation,
        context: ContextManager? = nil
    ) async {
        guard !calls.isEmpty else { return }
        let targetContext = context ?? contextManager

        struct SpawnArgs: Decodable {
            var agent: String
            var task: String
            var context: String?

            enum CodingKeys: String, CodingKey {
                case agent
                case task
                case prompt
                case context
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                agent = try container.decode(String.self, forKey: .agent)
                if let taskValue = try container.decodeIfPresent(String.self, forKey: .task) {
                    task = taskValue
                } else {
                    task = try container.decode(String.self, forKey: .prompt)
                }
                context = try container.decodeIfPresent(String.self, forKey: .context)
            }

            var prompt: String {
                let trimmedContext = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard trimmedContext.isEmpty == false else { return task }
                return "\(trimmedContext)\n\n\(task)"
            }
        }

        struct SubagentPlan: Sendable {
            let toolCallId: String
            let agentID: UUID
            let agentName: String
            let events: AsyncStream<SubagentEvent>
            let start: @Sendable () async -> Void
        }

        func forwardSubagentEvents(
            _ plan: SubagentPlan,
            continuation: AsyncStream<AgentEvent>.Continuation
        ) async throws -> ToolResult {
            var summary = ""
            await plan.start()
            for await event in plan.events {
                if case .failed(let error) = event {
                    throw error
                }
                if case .completed(let text) = event {
                    summary = text
                }
                continuation.yield(.subagentUpdate(id: plan.agentID, event: event))
            }
            return ToolResult(
                toolCallId: plan.toolCallId,
                content: summary.isEmpty ? "Subagent completed." : summary,
                isError: false
            )
        }

        var plans: [SubagentPlan] = []
        for call in calls {
            guard let args = try? JSONDecoder().decode(SpawnArgs.self, from: Data(call.function.arguments.utf8)),
                  depth < AppSettings.shared.maxSubagentDepth else {
                continue
            }

            let knownNames = await AgentRegistry.shared.knownNames()
            let requestedDefinition = await AgentRegistry.shared.definition(named: args.agent)
            if requestedDefinition == nil {
                let known = knownNames.sorted().joined(separator: ", ")
                continuation.yield(.systemNote(
                    "[spawn_agent warning] unknown agent '\(args.agent)' — falling back to 'explorer'. " +
                    "Known agents: \(known.isEmpty ? "(none registered)" : known)"
                ))
            }
            let fallbackDefinition = await AgentRegistry.shared.definition(named: "explorer")
            let definition = requestedDefinition ?? fallbackDefinition ?? AgentDefinition.defaultDefinition
            let agentID = UUID()
            continuation.yield(.subagentStarted(id: agentID, agentName: args.agent))

            let subagentProvider = resolvedProvider(for: .orchestrate)
            let fallbackModel = modelID(for: subagentProvider)
            let hookEngine = HookEngine(hooks: AppSettings.shared.hooks)
            let toolDefinitionsProvider: SubagentToolDefinitionsProvider = { [weak self] in
                self?.offeredTools() ?? ToolRegistry.shared.all()
            }
            let regularToolExecutor: SubagentToolExecutor = { [weak self] call in
                guard let self else {
                    return ToolResult(
                        toolCallId: call.id,
                        content: "Parent engine is unavailable.",
                        isError: true
                    )
                }
                return await self.toolRouter.dispatch([call]).first ?? ToolResult(
                    toolCallId: call.id,
                    content: "Tool dispatch returned no result.",
                    isError: true
                )
            }

            switch definition.role {
            case .worker:
                guard let projectPath = currentProjectPath, projectPath.isEmpty == false else {
                    continuation.yield(.systemNote(
                        "[subagent '\(args.agent)' failed] worker agents require an active project path."
                    ))
                    continue
                }
                let workerStagingBuffer = StagingBuffer()
                let worker = WorkerSubagentEngine(
                    definition: definition,
                    prompt: args.prompt,
                    provider: subagentProvider,
                    fallbackModel: fallbackModel,
                    hookEngine: hookEngine,
                    depth: depth + 1,
                    worktreeManager: WorktreeManager.shared,
                    repoURL: URL(fileURLWithPath: projectPath),
                    stagingBuffer: workerStagingBuffer,
                    toolDefinitionsProvider: toolDefinitionsProvider,
                    toolExecutor: { [weak self] call in
                        guard let self else {
                            return ToolResult(
                                toolCallId: call.id,
                                content: "Parent engine is unavailable.",
                                isError: true
                            )
                        }
                        return await self.toolRouter.dispatch(
                            [call],
                            stagingBufferOverride: workerStagingBuffer
                        ).first ?? ToolResult(
                            toolCallId: call.id,
                            content: "Tool dispatch returned no result.",
                            isError: true
                        )
                    }
                )
                plans.append(SubagentPlan(
                    toolCallId: call.id,
                    agentID: agentID,
                    agentName: args.agent,
                    events: worker.events,
                    start: { await worker.start() }
                ))
            case .explorer, .default:
                let subagent = SubagentEngine(
                    definition: definition,
                    prompt: args.prompt,
                    provider: subagentProvider,
                    fallbackModel: fallbackModel,
                    hookEngine: hookEngine,
                    depth: depth + 1,
                    toolDefinitionsProvider: toolDefinitionsProvider,
                    toolExecutor: regularToolExecutor
                )
                plans.append(SubagentPlan(
                    toolCallId: call.id,
                    agentID: agentID,
                    agentName: args.agent,
                    events: subagent.events,
                    start: { await subagent.start() }
                ))
            }
        }

        await withTaskGroup(of: ToolResult.self) { group in
            for plan in plans {
                group.addTask { [continuation] in
                    do {
                        return try await forwardSubagentEvents(plan, continuation: continuation)
                    } catch {
                        continuation.yield(.systemNote(
                            "[subagent '\(plan.agentName)' failed] \(error.localizedDescription)"
                        ))
                        return ToolResult(
                            toolCallId: plan.toolCallId,
                            content: "[subagent '\(plan.agentName)' failed] \(error.localizedDescription)",
                            isError: true
                        )
                    }
                }
            }

            for await result in group {
                continuation.yield(.toolCallResult(result))
                targetContext.append(Message(
                    role: .tool,
                    content: .text(result.content),
                    toolCallId: result.toolCallId,
                    timestamp: Date()
                ))
            }
        }
    }

    func shouldUseThinking(for message: String) -> Bool {
        if let registry {
            guard let activeConfig = registry.activeConfig else { return false }
            return activeConfig.supportsThinking && thinkingDetector.shouldEnableThinking(for: message)
        }
        return thinkingDetector.shouldEnableThinking(for: message)
    }

    // Provider selection always routes through slot assignments + registry fallback.
    private func selectProvider(for message: String) -> any LLMProvider {
        let slot = selectSlot(for: message)
        return provider(for: slot) ?? registry?.primaryProvider ?? NullProvider()
    }

    private func modelID(for provider: any LLMProvider) -> String {
        if let registry, let config = registry.providers.first(where: { $0.id == provider.id }) {
            return config.model.isEmpty ? provider.id : config.model
        }
        // Virtual provider IDs encode the model in the suffix.
        if provider.id.contains(":"),
           let modelID = provider.id.split(separator: ":", maxSplits: 1).last {
            return String(modelID)
        }
        return provider.id
    }

    private func messagesForProvider() -> [Message] {
        return messagesWithSystem(contextManager.messagesForProvider())
    }

    func messagesWithSystem(_ messages: [Message]) -> [Message] {
        let systemPrompt = buildSystemPrompt()
        guard !systemPrompt.isEmpty else { return messages }

        let systemMessage = Message(role: .system, content: .text(systemPrompt), timestamp: Date())
        if messages.first?.role == .system {
            var updated = messages
            updated[0] = systemMessage
            return updated
        } else {
            return [systemMessage] + messages
        }
    }

    private func buildSystemPrompt() -> String {
        var result = buildStablePrefix()
        if let warning = nearCeilingWarningAddendum {
            result += "\n\n" + warning
        }
        return result
    }

    /// Returns the stable (cacheable) portion of the system prompt.
    /// Excludes nearCeilingWarningAddendum, which varies per loop iteration.
    /// Internal for test access.
    func buildStablePrefix() -> String {
        let compressionEnabled = AppSettings.shared.promptCompressionEnabled
        if !_stablePrefixDirty && _stablePrefixCompressionEnabled == compressionEnabled {
            return _stablePrefixCached
        }
        var parts: [String] = []

        // CLAUDE.md: use distilled version when compression is on and distillation has run.
        if !claudeMDContent.isEmpty {
            let mdToUse = compressionEnabled && !claudeMDDistilledContent.isEmpty
                ? claudeMDDistilledContent
                : claudeMDContent
            parts.append(mdToUse)
        }
        if !memoriesContent.isEmpty {
            parts.append(memoriesContent)
        }
        if permissionMode == .plan {
            parts.append(PermissionMode.planSystemPrompt)
        }
        if let path = currentProjectPath {
            parts.append("Working directory: \(path)\nAlways use this path when accessing project files unless the user specifies otherwise.")
        }

        // Core system prompt: use distilled version when compression is on.
        let corePrompt = compressionEnabled
            ? AgenticEngine.distilledCoreSystemPrompt
            : AgenticEngine.coreSystemPrompt
        parts.append(corePrompt)

        if !standingInstructions.isEmpty {
            parts.append(standingInstructions)
        }
        _stablePrefixCached = parts.joined(separator: "\n\n")
        _stablePrefixCompressionEnabled = compressionEnabled
        _stablePrefixDirty = false
        return _stablePrefixCached
    }

    /// Distils `claudeMDContent` using `provider` when the content has changed since the last
    /// distillation. Uses a SHA256 hash of the content as a cache key — the provider is called
    /// at most once per unique `claudeMDContent` value. No-op when content is empty or unchanged.
    func refreshDistilledClaudeMD(using provider: any LLMProvider) async {
        guard !claudeMDContent.isEmpty else { return }
        let currentHash = sha256Hex(claudeMDContent)
        guard currentHash != claudeMDDistillHash else { return }

        let systemMsg = Message(
            role: .system,
            content: .text(
                "Compress the following CLAUDE.md into a token-efficient shorthand that preserves all " +
                "constraints, rules, and technical details. Use abbreviations, symbols, and dense phrasing. " +
                "Output only the compressed text — no preamble."
            ),
            timestamp: Date()
        )
        let userMsg = Message(role: .user, content: .text(claudeMDContent), timestamp: Date())
        var request = CompletionRequest(model: provider.resolvedModelID, messages: [systemMsg, userMsg])
        request.tools = []
        request.maxTokens = 1_024

        do {
            let stream = try await PreflightGuard.complete(request, provider: provider)
            var result = ""
            for try await chunk in stream {
                if let text = chunk.delta?.content { result += text }
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                claudeMDDistilledContent = trimmed
                claudeMDDistillHash = currentHash
            }
        } catch {
            // Distillation failed — keep previous distilled content (or empty); do not update hash.
            // buildStablePrefix() will fall back to the original claudeMDContent.
        }
    }

    /// Returns the lowercase hex SHA256 digest of `string`.
    private func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Exposed for testing — returns the full system prompt including dynamic suffix.
    func buildSystemPromptForTesting() -> String {
        buildSystemPrompt()
    }

    private static var coreSystemPrompt: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return """
        You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.

        Today's date is \(today).

        ## Efficient file exploration
        For large codebases, prefer targeted access over bulk reading:
        - Use `search_files` or `run_shell` with `grep -r`, `rg`, or `find` to locate relevant files first.
        - Use `run_shell` with `grep`, `sed`, or `awk` to extract specific sections rather than reading entire files with `read_file`.
        - Use `read_file` for files you know are relevant; avoid reading every file in a directory sequentially.
        - For understanding project structure, `list_directory` with recursive=true gives the full tree without reading file contents.
        """
    }

    /// Token-efficient distilled version of `coreSystemPrompt`.
    /// Encodes the same constraints in ~6 compact lines (~80 tokens) vs 18 prose lines (~350 tokens).
    /// Used by `buildStablePrefix()` when `AppSettings.shared.promptCompressionEnabled` is true.
    static var distilledCoreSystemPrompt: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return """
        Merlin=macOS agentic coder. Date:\(today).
        FILE: search_files/run_shell(grep/rg/find)→locate→read_file(targeted). list_directory(recursive)→structure.
        PREFER: tools>prose. Responses concise. Avoid sequential bulk reads.
        """
    }

    /// Exposed for test comparison against `distilledCoreSystemPrompt`. Identical to `coreSystemPrompt`.
    static var coreSystemPromptForTesting: String { coreSystemPrompt }

    private func buildSystemPrompt(for slot: AgentSlot) async -> String {
        var result = buildStablePrefix()
        if let warning = nearCeilingWarningAddendum {
            result += "\n\n" + warning
        }
        let addendum = await combinedAddendum(for: slot)
        if !addendum.isEmpty {
            result += "\n\n" + addendum
        }
        return result
    }

    private func buildAddendum(for slot: AgentSlot) -> String {
        let effectiveSlot = slot == .orchestrate && slotAssignments[.orchestrate] == nil ? .reason : slot
        guard let providerID = slotAssignments[effectiveSlot],
              let config = registry?.providers.first(where: { $0.id == providerID }) else {
            return ""
        }
        return config.systemPromptAddendum
    }

    /// Names of the MCP servers whose tools are currently registered (connected),
    /// parsed from the `mcp:<server>:<tool>` definition names.
    private func connectedMCPServerNames() -> Set<String> {
        toolRouter.connectedMCPServerNames(activeDomainIDs: activeDomainIDs)
    }

    /// The improvisation tools currently *withheld* from the model — non-empty only
    /// when an authoritative domain MCP server (`improvisationGatedMCPServers`) is
    /// connected. Empty otherwise, so non-domain tasks keep the full tool set.
    private func gatedImprovisationToolNames() -> Set<String> {
        connectedMCPServerNames().isDisjoint(with: Self.improvisationGatedMCPServers)
            ? []
            : Self.improvisationToolNames
    }

    /// The tool list offered to the model for one turn: every built-in tool plus
    /// every connected MCP tool. When an authoritative domain MCP server is
    /// connected (`improvisationGatedMCPServers`), the improvisation tools
    /// (`improvisationToolNames`) are filtered out so the model cannot hand-write
    /// domain files or shell out around the server's verified tools — the lever
    /// that makes S6 (KiCad) deterministic rather than a coin-flip on tool choice.
    ///
    /// Filtering the *offered* list is necessary but not sufficient: the 4-bit
    /// execute model emits calls to `run_shell`/`write_file`/etc. from training
    /// memory even when they are absent from the menu. `runLoop` therefore also
    /// rejects calls to `gatedImprovisationToolNames()` at dispatch time.
    ///
    /// Once the per-task subagent budget (`maxSpawnsPerTask`) is spent, `spawn_agent`
    /// is also withheld. Over-budget spawns are rejected anyway, but leaving the tool
    /// on the menu lets the 4-bit model *thrash* — an S2 run burned its entire 30-min
    /// budget emitting 30+ rejected `spawn_agent` calls. Removing it from the menu
    /// forces the model to do the remaining work itself, the same lever as S6.
    ///
    /// The result is deduplicated by tool name: `MCPBridge.start` registers each
    /// MCP tool into BOTH `ToolRegistry.shared` and the `toolRouter`, so a raw
    /// `ToolRegistry.shared.all() + toolRouter.mcpToolDefinitions()` would list
    /// every `mcp:*` tool twice and bloat every request's tool array.
    private func offeredTools() -> [ToolDefinition] {
        var withheld = gatedImprovisationToolNames()
        if spawnedSubagentCount >= maxSpawnsPerTask {
            withheld.insert("spawn_agent")
        }
        let builtins = withheld.isEmpty
            ? ToolRegistry.shared.all()
            : ToolRegistry.shared.all().filter { !withheld.contains($0.function.name) }
        var seen = Set<String>()
        return (builtins + toolRouter.mcpToolDefinitions(activeDomainIDs: activeDomainIDs))
            .filter { seen.insert($0.function.name).inserted }
    }

    private func combinedAddendum(for slot: AgentSlot) async -> String {
        var parts: [String] = []
        let providerAddendum = buildAddendum(for: slot)
        if !providerAddendum.isEmpty {
            parts.append(providerAddendum)
        }

        let scopedDomains = await DomainRegistry.shared.scopedDomains(ids: activeDomainIDs)
        var seenDomainAddenda = Set<String>()
        for domain in scopedDomains {
            guard let domainAddendum = domain.systemPromptAddendum,
                  !domainAddendum.isEmpty,
                  seenDomainAddenda.insert(domainAddendum).inserted else {
                continue
            }
            parts.append(domainAddendum)
        }

        // When MCP tool servers are connected, the model must be told to use them —
        // a coding model otherwise hand-writes domain files (.kicad_sch) or shells
        // out instead of calling the `mcp:<server>:*` tools, which is what made S6
        // (KiCad) non-deterministic.
        let mcpServers = Array(connectedMCPServerNames()).sorted()
        if !mcpServers.isEmpty {
            var steer = """
            Connected MCP tool servers: \(mcpServers.joined(separator: ", ")). Their \
            tools are named `mcp:<server>:*`. When the task is in a connected \
            server's domain (e.g. a `kicad` server covers KiCad schematics, PCB \
            layout, routing, and simulation), you MUST use that server's `mcp:` \
            tools to do the work. Do NOT hand-write domain files (.kicad_sch, \
            .kicad_pcb, netlists) or invoke domain CLIs through run_shell — the MCP \
            tools are the supported, verified path and other approaches will not \
            pass verification.
            """
            let gated = mcpServers.filter {
                Self.improvisationGatedMCPServers.contains($0)
            }
            if !gated.isEmpty {
                steer += """
                \n\nNote: for the \(gated.joined(separator: ", ")) domain the \
                shell tools (`bash`, `run_shell`), the file-authoring tools \
                (`write_file`, `create_file`), and `spawn_agent` are intentionally \
                unavailable this turn — the `mcp:` tools are the only supported way \
                to do this domain's work. Call them directly yourself; do not look \
                for a shell or a subagent to do it.
                """
            }
            parts.append(steer)
        }

        return parts.joined(separator: "\n\n")
    }

    private func activeDomain() async -> any DomainPlugin {
        await DomainRegistry.shared.activeDomain(ids: activeDomainIDs)
    }

    private func approximateTokens(in context: ContextManager) -> Int {
        context.messages.reduce(0) { total, message in
            switch message.content {
            case .text(let text):
                return total + text.count / 4
            case .parts(let parts):
                return total + parts.reduce(0) { subtotal, part in
                    switch part {
                    case .text(let text):
                        return subtotal + text.count / 4
                    case .imageURL:
                        return subtotal
                    }
                }
            }
        }
    }

    // MARK: - Pre-flight gate

    /// Estimates the token cost of `request` against the provider's configured budget.
    /// When the estimate exceeds the budget, triggers `compactWithSummaryIfNeeded` and
    /// re-estimates. If still over, throws `EngineError.preflightOverflow`.
    /// Emits `engine.preflight.ok`, `engine.preflight.compacted`, or `engine.preflight.overflow`.
    @discardableResult
    func preflightCheck(
        request: CompletionRequest,
        provider: any LLMProvider
    ) async throws -> PreflightOutcome {
        await applyWorkingSetCapsBeforeSend(provider: provider)
        let budget = effectiveBudget(for: provider)
        let estimated = TokenEstimator.estimate(
            request: request,
            baseURL: provider.baseURL,
            modelID: provider.resolvedModelID
        )

        if estimated <= budget.usableInputTokens {
            TelemetryEmitter.shared.emit("engine.preflight.ok", data: [
                "estimated": estimated,
                "budget": budget.usableInputTokens
            ])
            return .ok
        }

        await contextManager.compactWithSummaryIfNeeded(provider: provider)
        let reEstimated = TokenEstimator.estimate(
            request: request,
            baseURL: provider.baseURL,
            modelID: provider.resolvedModelID
        )

        if reEstimated <= budget.usableInputTokens {
            TelemetryEmitter.shared.emit("engine.preflight.compacted", data: [
                "estimated": reEstimated,
                "budget": budget.usableInputTokens
            ])
            return .ok
        }

        TelemetryEmitter.shared.emit("engine.preflight.overflow", data: [
            "estimated": reEstimated,
            "budget": budget.usableInputTokens
        ])
        throw EngineError.preflightOverflow(estimated: reEstimated, budget: budget.usableInputTokens)
    }

    func applyWorkingSetCapsBeforeSend(provider: any LLMProvider) async {
        let budget = effectiveBudget(for: provider)
        let caps = WorkingSetBudget.derive(from: budget)
        await contextManager.applyWorkingSetCaps(caps)
    }

    @discardableResult
    func preflightPlanStep(
        step: PlanStep,
        request: CompletionRequest,
        provider: any LLMProvider
    ) async throws -> PreflightOutcome {
        _ = step
        return try await preflightCheck(request: request, provider: provider)
    }

    private func effectiveBudget(for provider: any LLMProvider) -> ProviderBudget {
        // `.preflightSafe` guards against a degenerate persisted/configured budget
        // (usableInputTokens <= 0), which would otherwise overflow every preflight
        // check and kill the run on its first request.
        (registry?.config(for: provider.id)?.budget ?? .conservative).preflightSafe
    }

    // MARK: - Provider retry

    /// Calls `provider.complete` up to `maxAttempts` times, retrying on retriable
    /// `ProviderError`s with back-off. On each retry `onRetry(attempt, maxAttempts)`
    /// is called so the caller can surface a status note to the UI.
    /// Non-retriable errors are re-thrown immediately without retry.
    private static func completeWithRetry(
        provider: any LLMProvider,
        request: CompletionRequest,
        maxAttempts: Int,
        onRetry: @Sendable (Int, Int) -> Void
    ) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        var attempt = 0
        var lastError: Error = URLError(.unknown)
        while attempt < maxAttempts {
            attempt += 1
            do {
                let budget = await ContextBudgetResolver.shared.usableInputTokens(for: provider)
                return try await provider.complete(
                    request: PreflightGuard.fit(request, usableInputTokens: budget)
                )
            } catch let pe as ProviderError where pe.isRetriable && attempt < maxAttempts {
                lastError = pe
                onRetry(attempt, maxAttempts)
                try await Task.sleep(for: .seconds(pe.retryDelay))
            } catch {
                // Non-retriable ProviderError, exhausted retries, or non-ProviderError — throw.
                throw error
            }
        }
        throw lastError
    }
}
