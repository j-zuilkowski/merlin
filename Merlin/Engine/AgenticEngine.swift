// AgenticEngine — the central agentic loop for Merlin.
//
// Owns the LLM providers, ContextManager, and ToolRouter.
// Every user message enters via send() or invokeSkill(), which
// drive the recursive runLoop(). The loop streams AgentEvent
// values: text deltas, thinking blocks, tool call start/result
// pairs, subagent events, and system notes.
//
// See: Developer Manual § "Engine — The Agentic Loop"
import Foundation

enum AgentEvent {
    case text(String)
    case thinking(String)
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case subagentStarted(id: UUID, agentName: String)
    case subagentUpdate(id: UUID, event: SubagentEvent)
    case systemNote(String)
    case error(Error)
}

private final class CancellationState: @unchecked Sendable {
    var finished = false
}

@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let thinkingDetector = ThinkingModeDetector.self
    var proProvider: any LLMProvider
    var flashProvider: any LLMProvider
    private var visionProvider: any LLMProvider
    let toolRouter: ToolRouter
    var xcalibreClient: (any XcalibreClientProtocol)?
    var registry: ProviderRegistry?
    var skillsRegistry: SkillsRegistry?
    var permissionMode: PermissionMode = .ask
    var claudeMDContent: String = ""
    var memoriesContent: String = ""
    var onUsageUpdate: ((Int) -> Void)?
    var performanceTracker: any ModelPerformanceTrackerProtocol = ModelPerformanceTracker.shared
    var criticOverride: (any CriticEngineProtocol)?
    var classifierOverride: (any PlannerEngineProtocol)?
    var currentProjectPath: String?
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
         xcalibreClient: (any XcalibreClientProtocol)? = nil) {
        self.proProvider = NullProvider()
        self.flashProvider = NullProvider()
        self.visionProvider = NullProvider()
        self.slotAssignments = slotAssignments
        self.registry = registry
        self.toolRouter = toolRouter
        self.contextManager = contextManager
        self.xcalibreClient = xcalibreClient
    }

    convenience init(proProvider: any LLMProvider,
                     flashProvider: any LLMProvider,
                     visionProvider: any LLMProvider,
                     toolRouter: ToolRouter,
                     contextManager: ContextManager,
                     xcalibreClient: (any XcalibreClientProtocol)? = nil) {
        self.init(
            slotAssignments: [:],
            registry: nil,
            toolRouter: toolRouter,
            contextManager: contextManager,
            xcalibreClient: xcalibreClient
        )
        self.proProvider = proProvider
        self.flashProvider = flashProvider
        self.visionProvider = visionProvider
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

    /// Returns the provider assigned to the given slot, or nil if the slot cannot be resolved.
    /// `orchestrate` falls back to `reason` when not explicitly assigned.
    func provider(for slot: AgentSlot) -> (any LLMProvider)? {
        let effectiveSlot: AgentSlot
        if slot == .orchestrate, slotAssignments[.orchestrate] == nil {
            effectiveSlot = .reason
        } else {
            effectiveSlot = slot
        }

        if let providerID = slotAssignments[effectiveSlot],
           let registry {
            return registry.provider(for: providerID)
        }

        switch effectiveSlot {
        case .execute:
            return proProvider
        case .reason, .orchestrate:
            return flashProvider
        case .vision:
            return visionProvider
        }
    }

    /// Determines which slot should handle this message.
    /// Checks `@slot` override annotation first, then vision keywords, then defaults to execute.
    func selectSlot(for message: String) -> AgentSlot {
        let lower = message.lowercased()

        // Explicit slot override annotations
        if lower.hasPrefix("@reason ") || lower.contains(" @reason ") { return .reason }
        if lower.hasPrefix("@execute ") || lower.contains(" @execute ") { return .execute }
        if lower.hasPrefix("@orchestrate ") || lower.contains(" @orchestrate ") { return .orchestrate }

        // Vision keywords
        let visionKeywords = ["screenshot", "screen", "vision", "ui", "click", "button"]
        if visionKeywords.contains(where: { lower.contains($0) }) { return .vision }

        // Default: execute slot handles all other work
        return .execute
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

        var effectiveMessage = userMessage
        if let client = xcalibreClient {
            let chunks = await client.searchChunks(
                query: userMessage,
                source: "all",
                bookIDs: nil,
                projectPath: currentProjectPath,
                limit: 3,
                rerank: false
            )
            if !chunks.isEmpty {
                effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
                continuation.yield(.systemNote("Library: \(chunks.count) passage\(chunks.count == 1 ? "" : "s") retrieved"))
            }
        }
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

        if classification.needsPlanning, let classifierOverride {
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

        var loopCount = 0
        let maxIterations = max(1, classification.needsPlanning ? AppSettings.shared.maxLoopIterations : AppSettings.shared.maxLoopIterations)

        while true {
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
            let request = CompletionRequest(
                model: requestModel,
                messages: messagesForProvider(),
                thinking: useThinking ? ThinkingModeDetector.config(for: userMessage) : nil
            )

            let stream = try await provider.complete(request: request)
            var assembled: [Int: (id: String, name: String, args: String)] = [:]
            var sawToolCall = false
            var fullText = ""

            for try await chunk in stream {
                if let thinkingContent = chunk.delta?.thinkingContent, !thinkingContent.isEmpty {
                    continuation.yield(.thinking(thinkingContent))
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

            for call in calls {
                continuation.yield(.toolCallStarted(call))
            }

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

                let results = await toolRouter.dispatch([call])
                guard let result = results.first else { continue }
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

        if contextOverride == nil, let session = sessionStore?.activeSession {
            var updated = session
            updated.messages = context.messages
            updated.updatedAt = Date()
            try? sessionStore?.save(updated)
        }

        let taskType = domain.taskTypes.first
            ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
        let signals = OutcomeSignals(
            stage1Passed: nil,
            stage2Score: nil,
            diffAccepted: true,
            diffEditedOnAccept: false,
            criticRetryCount: 0,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: await currentAddendumHash(for: workingSlot)
        )
        await performanceTracker.record(
            modelID: slotAssignments[workingSlot] ?? "",
            taskType: taskType,
            signals: signals
        )

        if let client = xcalibreClient, AppSettings.shared.memoriesEnabled {
            let summary = context.messages
                .filter { $0.role == .assistant }
                .compactMap { if case .text(let t) = $0.content { return t } else { return nil } }
                .joined(separator: "\n")
                .prefix(2000)
            if !summary.isEmpty {
                _ = await client.writeMemoryChunk(
                    text: String(summary),
                    chunkType: "episodic",
                    sessionID: sessionStore?.activeSession?.id.uuidString,
                    projectPath: currentProjectPath,
                    tags: []
                )
            }
        }

        onUsageUpdate?(approximateTokens(in: context))
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

    // Heuristic provider selection: vision keywords → visionProvider,
    // action keywords → flashProvider, everything else → proProvider.
    // ProviderRegistry overrides take precedence when the user has selected a provider.
    private func selectProvider(for message: String) -> any LLMProvider {
        let slot = selectSlot(for: message)
        let lower = message.lowercased()

        if lower.hasPrefix("@reason ") || lower.contains(" @reason ") ||
            lower.hasPrefix("@execute ") || lower.contains(" @execute ") ||
            lower.hasPrefix("@orchestrate ") || lower.contains(" @orchestrate ") {
            if let provider = provider(for: slot) {
                return provider
            }
        }

        let visionKeywords = ["screenshot", "screen", "vision", "ui", "click", "button"]
        if visionKeywords.contains(where: { lower.contains($0) }) {
            return provider(for: .vision) ?? visionProvider
        }

        if shouldUseThinking(for: message) {
            return proProvider
        }

        if ["read", "write", "run", "list", "build", "open", "create", "delete", "move", "show"].contains(where: { lower.contains($0) }) {
            return flashProvider
        }

        if let provider = provider(for: slot) {
            return provider
        }

        return proProvider
    }

    private func modelID(for provider: any LLMProvider) -> String {
        if let registry, let config = registry.providers.first(where: { $0.id == provider.id }) {
            if config.model.isEmpty, config.id == "lmstudio" {
                return LMStudioProvider().model
            }
            return config.model.isEmpty ? provider.id : config.model
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
        parts.append("You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.")
        return parts.joined(separator: "\n\n")
    }

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
        parts.append("You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.")

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
