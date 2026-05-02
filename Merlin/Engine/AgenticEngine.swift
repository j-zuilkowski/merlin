// AgenticEngine — the central agentic loop for Merlin.
//
// Owns the LLM providers, ContextManager, and ToolRouter.
// Every user message enters via send() or invokeSkill(), which
// drive the recursive runLoop(). The loop streams AgentEvent
// values: text deltas, thinking blocks, tool call start/result
// pairs, subagent events, system notes, and RAG source attributions.
//
// V5+: runLoop() classifies task complexity, routes to the correct
// AgentSlot, runs the CriticEngine on final responses, records
// OutcomeSignals (including real diffAccepted/diffEditedOnAccept
// values from StagingBuffer), and gates local memory writes on
// the critic verdict.
//
// V6: calls LoRACoordinator.considerTraining() after each record();
// captures lastResponseText for OutcomeRecord prompt/response fields;
// loraProvider routes the execute slot through mlx_lm.server when
// a LoRA adapter is loaded.
//
// See: Developer Manual § "Engine — The Agentic Loop" and
//      § "Supervisor-Worker Engine" and § "LoRA Training Pipeline"
import Foundation

enum AgentEvent {
    case text(String)
    case thinking(String)
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case subagentStarted(id: UUID, agentName: String)
    case subagentUpdate(id: UUID, event: SubagentEvent)
    case systemNote(String)
    case ragSources([RAGChunk])
    /// Per-turn grounding confidence report. Emitted after RAG search even when
    /// `totalChunks == 0`, so callers can distinguish ungrounded from well-grounded turns.
    case groundingReport(GroundingReport)
    case error(Error)
}

private final class CancellationState: @unchecked Sendable {
    var finished = false
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
    private let thinkingDetector = ThinkingModeDetector.self
    let toolRouter: ToolRouter
    var xcalibreClient: (any XcalibreClientProtocol)?
    /// Local memory backend plugin for episodic writes and local memory RAG.
    /// This is separate from `xcalibreClient`, which remains book-content only.
    var memoryBackend: any MemoryBackendPlugin = NullMemoryPlugin()
    var loraCoordinator: LoRACoordinator?
    var parameterAdvisor: ModelParameterAdvisor?
    var loraProvider: (any LLMProvider)?
    var registry: ProviderRegistry?
    var skillsRegistry: SkillsRegistry?
    var permissionMode: PermissionMode = .ask
    var claudeMDContent: String = ""
    var memoriesContent: String = ""
    var onUsageUpdate: ((Int) -> Void)?
    var onParameterAdvisoriesUpdate: ((String) -> Void)?
    var performanceTracker: any ModelPerformanceTrackerProtocol = ModelPerformanceTracker.shared
    var criticOverride: (any CriticEngineProtocol)?
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
    var currentProjectPath: String? {
        didSet {
            guard currentProjectPath != oldValue else { return }
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
         registry: ProviderRegistry? = nil,
         toolRouter: ToolRouter,
         contextManager: ContextManager,
         xcalibreClient: (any XcalibreClientProtocol)? = nil,
         memoryBackend: (any MemoryBackendPlugin)? = nil) {
        self.slotAssignments = slotAssignments
        self.registry = registry
        self.toolRouter = toolRouter
        self.contextManager = contextManager
        self.xcalibreClient = xcalibreClient
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

    var currentModelID: String {
        modelID(for: resolvedProvider(for: .execute))
    }

    /// Returns the effective loop ceiling for the given complexity tier.
    ///
    /// Takes the larger of the adaptive ceiling (derived from observed project size)
    /// and `AppSettings.maxLoopIterations` so a user-configured higher value always wins.
    func effectiveLoopCeiling(for tier: ComplexityTier) -> Int {
        max(projectSizeMetrics.adaptiveCeiling(for: tier),
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

        // No slot assignment — only the execute slot falls back to the registry primary provider.
        // Reason, vision, and orchestrate return nil when not explicitly configured so callers
        // can distinguish "no provider assigned" from "active primary provider".
        guard effectiveSlot == .execute else { return nil }
        return registry?.primaryProvider
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

    /// Returns true when the message clearly targets the vision provider.
    /// Uses word-boundary matching (\b) to avoid false positives from substrings
    /// inside file paths or user names (e.g. "jonz**ui**lkowski" must not match "ui").
    static func looksLikeVisionRequest(_ lower: String) -> Bool {
        // Exact-phrase keywords that are unambiguous without boundary checks.
        let phraseKeywords = ["screenshot", "take a picture", "capture the screen"]
        if phraseKeywords.contains(where: { lower.contains($0) }) { return true }
        // Word-boundary keywords: must appear as complete words.
        let wordKeywords = ["screen", "vision", "click", "button"]
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
                        self.finishStream(continuation, interrupted: false, state: state)
                        return
                    }

                    do {
                        try await self.runLoop(userMessage: message, continuation: continuation, depth: 0)
                        self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        self.finishStream(continuation, interrupted: true, state: state)
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
                        self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        self.finishStream(continuation, interrupted: true, state: state)
                    }
                })
            }

            Task { @MainActor in
                self.isRunning = true
                self.currentTask = task
            }
        }
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
                        self.finishStream(continuation, interrupted: false, state: state)
                    } catch is CancellationError {
                        self.finishStream(continuation, interrupted: true, state: state)
                    } catch {
                        continuation.yield(.error(error))
                        self.finishStream(continuation, interrupted: false, state: state)
                    }
                }, onCancel: {
                    Task { @MainActor in
                        self.finishStream(continuation, interrupted: true, state: state)
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
                              state: CancellationState) {
        guard !state.finished else { return }
        state.finished = true
        if interrupted {
            continuation.yield(.systemNote("[Interrupted]"))
        }
        continuation.finish()
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
        let domain = await DomainRegistry.shared.activeDomain()
        let classification = await classify(message: userMessage, domain: domain)
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
        let memResults = (try? await memoryBackend.search(query: userMessage, topK: 5)) ?? []
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

        if !ragChunks.isEmpty {
            effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: ragChunks)
            continuation.yield(.ragSources(ragChunks))
        }

        let groundingReport = GroundingReport.build(
            ragChunks: ragChunks,
            memoryCreatedAts: memoryDates,
            freshnessThresholdDays: AppSettings.shared.ragFreshnessThresholdDays,
            minGroundingScore: AppSettings.shared.ragMinGroundingScore
        )
        continuation.yield(.groundingReport(groundingReport))

        if let augmented = await hookEngine.runUserPromptSubmit(prompt: effectiveMessage) {
            continuation.yield(.systemNote(augmented))
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
        context.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))
        emitCompactionNoteIfNeeded()

        if classification.needsPlanning {
            let planner = PlannerEngine(
                executeProvider: selectProvider(for: userMessage),
                orchestrateProvider: provider(for: .orchestrate),
                maxPlanRetries: AppSettings.shared.maxPlanRetries
            )
            let planSteps = await planner.decompose(task: userMessage, context: context.messages)
            if !planSteps.isEmpty {
                continuation.yield(.systemNote("[Plan: \(planSteps.count) steps]"))
            }
        }

        lastCriticVerdict = nil
        let loopStart = Date()
        let turn = context.messages.filter { $0.role == .user }.count
        // lastResponseText captures the full assistant text from the last no-tool-call response.
        // Passed to performanceTracker.record() as the response field for LoRA training data.
        var lastResponseText = ""
        var capturedFinishReason: String?
        var totalToolCallCount = 0
        var loopCount = 0
        let maxIterations = max(1, effectiveLoopCeiling(for: classification.complexity))
        do {
            while true {
                await pauseForReload()
                guard loopCount < maxIterations else {
                    continuation.yield(.systemNote("[Loop ceiling reached — stopping]"))
                    break
                }
                loopCount += 1

                let provider: any LLMProvider
                if workingSlot == .reason {
                    provider = resolvedProvider(for: .reason)
                } else {
                    provider = selectProvider(for: userMessage)
                }
                let requestModel = modelID(for: provider)
                let useThinking = (workingSlot == .reason || workingSlot == .orchestrate) && shouldUseThinking(for: userMessage)
                var request = CompletionRequest(
                    model: requestModel,
                    messages: messagesForProvider(),
                    thinking: useThinking ? ThinkingModeDetector.config(for: userMessage) : nil
                )
                request.tools = ToolRegistry.shared.all() + toolRouter.mcpToolDefinitions()
                AppSettings.shared.applyInferenceDefaults(to: &request)

                let stream = try await provider.complete(request: request)
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
                    }
                    if classification.complexity != .routine,
                       (classifierOverride != nil || classification.complexity == .highStakes) {
                        if let reasonProvider = self.provider(for: .reason),
                           !(reasonProvider is NullProvider) {
                            let critic = makeCritic(domain: domain)
                            let taskType = domain.taskTypes.first
                                ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
                            let verdict = await critic.evaluate(
                                taskType: taskType,
                                output: fullText,
                                context: context.messages
                            )
                            lastCriticVerdict = verdict
                            switch verdict {
                            case .pass, .skipped:
                                consecutiveCriticFailures = 0
                            case .fail:
                                consecutiveCriticFailures += 1
                            }
                            switch verdict {
                            case .pass:
                                break
                            case .fail(let reason):
                                continuation.yield(.systemNote("[Critic: \(reason)]"))
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
                var regularCalls: [ToolCall] = []
                for call in calls {
                    if call.function.name == "spawn_agent" {
                        await handleSpawnAgent(call: call, depth: depth, continuation: continuation)
                        continue
                    }
                    regularCalls.append(call)
                }

                for call in regularCalls {
                    let input = inputDictionary(from: call.function.arguments)

                    let hookDecision = await hookEngine.runPreToolUse(
                        toolName: call.function.name,
                        input: input
                    )
                    switch hookDecision {
                    case .deny(let reason):
                        let denied = ToolResult(
                            toolCallId: call.id,
                            content: "Blocked by hook: \(reason)",
                            isError: true
                        )
                        continuation.yield(.toolCallResult(denied))
                        context.append(Message(
                            role: .tool,
                            content: .text(denied.content),
                            toolCallId: denied.toolCallId,
                            timestamp: Date()
                        ))
                        continue
                    case .allow:
                        break
                    }

                    TelemetryEmitter.shared.emit("engine.tool.dispatched", data: [
                        "turn": turn,
                        "tool_name": call.function.name,
                        "loop": loopCount
                    ])
                    let toolStart = Date()
                    let results = await toolRouter.dispatch([call])
                    guard let result = results.first else { continue }
                    let toolMs = Date().timeIntervalSince(toolStart) * 1000
                    if result.isError {
                        TelemetryEmitter.shared.emit("engine.tool.error", durationMs: toolMs, data: [
                            "turn": turn,
                            "tool_name": call.function.name,
                            "loop": loopCount,
                            "error_domain": "tool_dispatch"
                        ])
                    } else {
                        TelemetryEmitter.shared.emit("engine.tool.complete", durationMs: toolMs, data: [
                            "turn": turn,
                            "tool_name": call.function.name,
                            "loop": loopCount,
                            "duration_ms": toolMs,
                            "result_bytes": result.content.utf8.count
                        ])
                    }
                    continuation.yield(.toolCallResult(result))
                    context.append(Message(
                        role: .tool,
                        content: .text(result.content),
                        toolCallId: result.toolCallId,
                        timestamp: Date()
                    ))
                    emitCompactionNoteIfNeeded()

                    if let note = await hookEngine.runPostToolUse(
                        toolName: call.function.name,
                        result: result.content
                    ) {
                        continuation.yield(.systemNote(note))
                        context.append(Message(role: .system, content: .text(note), timestamp: Date()))
                        emitCompactionNoteIfNeeded()
                    }
                }
            }
        } catch {
            TelemetryEmitter.shared.emit("engine.turn.error", data: [
                "turn": turn,
                "slot": workingSlot.rawValue,
                "provider_id": selectProvider(for: userMessage).id,
                "error_domain": (error as NSError).domain,
                "error_code": (error as NSError).code
            ])
            throw error
        }

        if contextOverride == nil, let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            try? sessionStore?.save(updated)
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
        let signals = OutcomeSignals(
            stage1Passed: nil,
            stage2Score: nil,
            diffAccepted: stagingRejected == 0 || stagingAccepted > 0,
            diffEditedOnAccept: stagingEdited > 0,
            criticRetryCount: 0,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: await currentAddendumHash(for: workingSlot),
            finishReason: capturedFinishReason
        )
        let trackerModelID = slotAssignments[workingSlot] ?? ""
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
    }

    private func makeCritic(domain: any DomainPlugin) -> any CriticEngineProtocol {
        if let override = criticOverride {
            return override
        }
        return CriticEngine(
            verificationBackend: domain.verificationBackend,
            reasonProvider: provider(for: .reason)
        )
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
            "fix"
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

    private func handleSpawnAgent(
        call: ToolCall,
        depth: Int,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        struct SpawnArgs: Decodable {
            var agent: String
            var prompt: String
        }

        guard let args = try? JSONDecoder().decode(SpawnArgs.self, from: Data(call.function.arguments.utf8)),
              depth < AppSettings.shared.maxSubagentDepth else {
            return
        }

        let requestedDefinition = await AgentRegistry.shared.definition(named: args.agent)
        let fallbackDefinition = await AgentRegistry.shared.definition(named: "explorer")
        let definition = requestedDefinition ?? fallbackDefinition ?? AgentDefinition.defaultDefinition
        let agentID = UUID()
        continuation.yield(.subagentStarted(id: agentID, agentName: args.agent))

        let provider = resolvedProvider(for: .orchestrate)
        let hookEngine = HookEngine(hooks: AppSettings.shared.hooks)
        let subagent = SubagentEngine(
            definition: definition,
            prompt: args.prompt,
            provider: provider,
            hookEngine: hookEngine,
            depth: depth + 1
        )

        let stream = subagent.events
        await subagent.start()
        for await event in stream {
            continuation.yield(.subagentUpdate(id: agentID, event: event))
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
        var parts: [String] = []
        if !claudeMDContent.isEmpty {
            parts.append(claudeMDContent)
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
        parts.append(AgenticEngine.coreSystemPrompt)
        return parts.joined(separator: "\n\n")
    }

    private static let coreSystemPrompt = """
        You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.

        ## Efficient file exploration
        For large codebases, prefer targeted access over bulk reading:
        - Use `search_files` or `run_shell` with `grep -r`, `rg`, or `find` to locate relevant files first.
        - Use `run_shell` with `grep`, `sed`, or `awk` to extract specific sections rather than reading entire files with `read_file`.
        - Use `read_file` for files you know are relevant; avoid reading every file in a directory sequentially.
        - For understanding project structure, `list_directory` with recursive=true gives the full tree without reading file contents.
        """

    private func buildSystemPrompt(for slot: AgentSlot) async -> String {
        var parts: [String] = []
        if !claudeMDContent.isEmpty {
            parts.append(claudeMDContent)
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
        parts.append(AgenticEngine.coreSystemPrompt)

        let addendum = await combinedAddendum(for: slot)
        if !addendum.isEmpty {
            parts.append(addendum)
        }

        return parts.joined(separator: "\n\n")
    }

    private func buildAddendum(for slot: AgentSlot) -> String {
        let effectiveSlot = slot == .orchestrate && slotAssignments[.orchestrate] == nil ? .reason : slot
        guard let providerID = slotAssignments[effectiveSlot],
              let config = registry?.providers.first(where: { $0.id == providerID }) else {
            return ""
        }
        return config.systemPromptAddendum
    }

    private func combinedAddendum(for slot: AgentSlot) async -> String {
        var parts: [String] = []
        let providerAddendum = buildAddendum(for: slot)
        if !providerAddendum.isEmpty {
            parts.append(providerAddendum)
        }

        let domain = await DomainRegistry.shared.activeDomain()
        if let domainAddendum = domain.systemPromptAddendum, !domainAddendum.isEmpty {
            parts.append(domainAddendum)
        }

        return parts.joined(separator: "\n\n")
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
}
