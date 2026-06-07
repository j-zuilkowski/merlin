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
    case slotRuntimeState(AgentSlot, SlotRuntimeState)
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

struct ReasonExecutionOverrideRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    var providerID: String
    var reason: String
    var suggestion: String
    var progressSummary: String
    var originalTask: String

    init(
        id: UUID = UUID(),
        providerID: String,
        reason: String,
        suggestion: String,
        progressSummary: String,
        originalTask: String
    ) {
        self.id = id
        self.providerID = providerID
        self.reason = reason
        self.suggestion = suggestion
        self.progressSummary = progressSummary
        self.originalTask = originalTask
    }
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

private actor EscalationDecisionCapture {
    private var decision: EscalationDecision?

    func set(_ decision: EscalationDecision) {
        self.decision = decision
    }

    func get() -> EscalationDecision? {
        decision
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
    private var forcedElectronicsWorkflowLock = false
    var permissionMode: PermissionMode = .ask {
        didSet { _stablePrefixDirty = true }
    }
    var constitutionContent: String = "" {
        didSet { _stablePrefixDirty = true }
    }
    /// SHA256 hex of the `constitutionContent` that was most recently distilled.
    /// Empty string when no distillation has been performed yet.
    var constitutionDistillHash: String = ""

    /// Compressed equivalent of `constitutionContent` produced by `refreshDistilledConstitution(using:)`.
    /// Empty string until the first distillation completes.
    var constitutionDistilledContent: String = ""
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
    /// Presents a one-shot user override when an executable provider is stuck.
    /// Reason remains advisory unless this closure returns true for the current stop.
    var onReasonOverrideRequest: ((ReasonExecutionOverrideRequest) async -> Bool)?
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
    private var pendingContinuationAllSteps: [PlanStep] = []
    private var pendingContinuationOriginalTask: String = ""
    private var pendingContinuationCompletedCount: Int = 0
    private var pendingContinuationVerifiedCompletedCount: Int = 0
    private var pendingContinuationUsesEvidenceGate: Bool = false
    private var pendingContinuationEvidence: [ContinuationToolEvidence] = []
    private var pendingContinuationBlockedReason: String?
    private var latestVerifiedDesignIntentArtifactPath: String?
    private var latestVerifiedCircuitIRArtifactPath: String?
    private var latestVerifiedComponentMatrixArtifactPath: String?
    private var latestVerifiedFootprintAssignmentArtifactPath: String?
    private var pendingRepairableElectronicsHandoff: ElectronicsRepairHandoff?
    private var latestFocusedElectronicsHandoffToolName: String?
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
    /// domain file, shelling out to a CLI, inspecting unrelated app UI, opening Xcode,
    /// or delegating to context-free subagents instead of calling a connected domain
    /// backend's tools. When an authoritative domain backend is connected, these are
    /// withheld from the turn's tool list so the model is forced down the supported,
    /// verified path. Read-only file inspection stays available so a domain task can
    /// still load user-authored requirements and project context before calling the
    /// domain tools. This is what makes S6 (KiCad) deterministic:
    /// the 4-bit execute model otherwise non-deterministically writes `.kicad_sch`
    /// by hand — and it reaches for *any* available file/shell tool, so all of them
    /// must go. `bash` and `run_shell` are both shell tools (gating only `run_shell`
    /// left `bash` as an escape hatch — the exact hole that failed an S6 run);
    /// `write_file`/`create_file` author files directly; `spawn_agent` delegates to
    /// subagents that run one LLM completion and execute no tools, so it does no
    /// real KiCad work and only burns the loop budget.
    private static let improvisationToolNames: Set<String> = [
        "run_shell", "bash", "write_file", "create_file", "spawn_agent",
        "app_launch", "app_quit", "app_focus", "app_list_running",
        "ui_inspect", "ui_find_element", "ui_get_element_value", "ui_click",
        "ui_double_click", "ui_right_click", "ui_drag", "ui_type", "ui_key",
        "ui_scroll", "ui_screenshot",
        "xcode_build", "xcode_test", "xcode_clean", "xcode_derived_data_clean",
        "xcode_open_file", "xcode_xcresult_parse", "xcode_simulator_list",
        "xcode_simulator_boot", "xcode_simulator_screenshot",
        "xcode_simulator_install", "xcode_spm_resolve", "xcode_spm_list",
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

    private struct ContinuationToolEvidence: Sendable {
        let toolName: String
        let arguments: String
        let output: String
    }

    private struct ElectronicsRepairHandoff {
        let toolName: String
        let message: String
        let telemetry: [String: Any]
    }

    private enum ElectronicsContinuationRequirement: Equatable {
        case requirementsInspection
        case designIntent
        case designIntentApproval
        case circuitIR
        case componentSelection
        case footprintAssignment
        case schematic
        case boardProfile
        case netClasses
        case placement
        case routing
        case erc
        case drc
        case simulation
        case fabrication
        case bom
        case electronicsTool
        case generic
    }

    private static let electronicsReadOnlyInspectionToolNames: Set<String> = [
        "read_file", "list_directory", "search_files",
    ]

    private static let focusedElectronicsToolNames: [String] = [
        "kicad_ingest_schematic",
        "kicad_build_intent_model",
        "kicad_approve_design_intent",
        "kicad_generate_circuit_ir",
        "kicad_select_components",
        "kicad_revise_component_selection",
        "kicad_prepare_libraries",
        "kicad_assign_footprints",
        "kicad_compile_project",
        "kicad_run_erc",
        "kicad_apply_board_profile",
        "kicad_generate_net_classes",
        "kicad_place_components",
        "kicad_route_pass",
        "kicad_run_drc",
        "kicad_generate_spice_scenario",
        "kicad_run_spice",
        "kicad_evaluate_simulation",
        "kicad_export_fab",
        "kicad_prepare_vendor_order",
        "kicad_package_release",
    ]

    // MARK: - Near-ceiling warning

    /// Non-nil while the engine is within nearCeilingThreshold iterations of the ceiling.
    /// Appended to the system prompt so the LLM knows to wrap up the active turn.
    /// Reset to nil at turn end.
    var nearCeilingWarningAddendum: String?

    /// How many iterations from the ceiling triggers the near-ceiling warning.
    /// Exposed as a var so tests can set a larger value when maxIterations is small.
    /// Default is 2 so normal multi-tool domain runs are not nudged into premature
    /// wrap-up behavior after their first tool call.
    var nearCeilingThreshold = 2

    // Prefix cache — rebuilt only when source properties change.
    // nearCeilingWarningAddendum is excluded because it changes per loop iteration.
    var _stablePrefixDirty = true
    private var _stablePrefixCached = ""
    private var _stablePrefixCompressionEnabled = AppSettings.shared.promptCompressionEnabled
    private var _stablePrefixCAGSignature = ""
    private static let maxPinnedCAGDocuments = 8
    private static let maxPinnedCAGDocumentBytes = 64 * 1024

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

    func authoritativeToolCallNamesForTesting(_ names: [String]) -> [String] {
        let calls = names.enumerated().map { index, name in
            ToolCall(
                id: "call-\(index)",
                type: "function",
                function: FunctionCall(name: name, arguments: "{}")
            )
        }
        return authoritativeElectronicsWorkflowCalls(from: calls).map(\.function.name)
    }

    func promoteElectronicsDomainForTesting(message: String) async {
        await promoteElectronicsDomainIfIntentDetected(in: message)
    }

    func requestedStopBoundaryMatchesForTesting(task: String, toolName: String) -> Bool {
        requestedStopBoundary(in: task, matchesToolNamed: toolName)
    }

    func handleEscalationForTesting(
        currentStep: PlanStep,
        reason: EscalationReason,
        escalation: EscalationHandler,
        workingSlot: AgentSlot = .execute,
        originalTask: String = "test task"
    ) async -> (EscalationDecision, [AgentEvent]) {
        var captured: [AgentEvent] = []
        let decisionCapture = EscalationDecisionCapture()
        let stream = AsyncStream<AgentEvent> { continuation in
            Task { @MainActor in
                let decision = await self.handleEscalation(
                    currentStep: currentStep,
                    reason: reason,
                    escalation: escalation,
                    workingSlot: workingSlot,
                    context: self.contextManager,
                    continuation: continuation,
                    originalTask: originalTask
                )
                await decisionCapture.set(decision)
                continuation.finish()
            }
        }
        for await event in stream {
            captured.append(event)
        }
        let decision = await decisionCapture.get() ?? .stop(message: "test escalation did not return")
        return (decision, captured)
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
        if lower.hasPrefix("@vision ") || lower.contains(" @vision ") { return .vision }

        // Vision slot: whole-word match only.
        // "ui" is intentionally excluded — it appears as a substring in paths/names (e.g. "jonzu*ui*lkowski").
        // "screen" requires \b so it doesn't match inside "screensaver", filenames, etc.
        if AgenticEngine.looksLikeVisionRequest(lower) { return .vision }

        // Default: execute slot handles all other work
        return .execute
    }

    /// Main agent turns are executable loops: they receive tools and may dispatch
    /// side-effecting work. The reason slot is advisory only, so a requested
    /// reason turn must run through execute. Orchestrate can run only when it has
    /// an explicit provider; its registry fallback is reason, which is not an
    /// executable turn provider.
    private func executableTurnSlot(for requestedSlot: AgentSlot) -> AgentSlot {
        switch requestedSlot {
        case .reason:
            return .execute
        case .orchestrate:
            return slotAssignments[.orchestrate] == nil ? .execute : .orchestrate
        case .execute, .vision:
            return requestedSlot
        }
    }

    private func reasonOverrideProviderID() -> String? {
        if let assigned = slotAssignments[.reason], assigned.isEmpty == false {
            return assigned
        }
        guard let provider = provider(for: .reason), !(provider is NullProvider) else {
            return nil
        }
        return provider.id
    }

    private func promoteElectronicsDomainIfIntentDetected(in message: String) async {
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID) == false,
              ElectronicsDomain.suggestedActivation(
                for: message,
                currentActiveDomainIDs: activeDomainIDs
              ) != nil else {
            return
        }

        let normalized = await DomainRegistry.shared.normalizedActiveDomainIDs(
            ids: activeDomainIDs + [ElectronicsDomain.defaultID]
        )
        guard normalized != activeDomainIDs else { return }
        activeDomainIDs = normalized
        forcedElectronicsWorkflowLock = true
        persistActiveDomainIDsToCurrentSession(normalized)
        TelemetryEmitter.shared.emit("engine.domain.auto_promoted", data: [
            "domain": "electronics",
            "active_domain_ids": normalized.joined(separator: ",")
        ])
    }

    private func persistActiveDomainIDsToCurrentSession(_ ids: [String]) {
        guard let id = sessionID,
              let store = sessionStore,
              let session = store.sessions.first(where: { $0.id == id }) else {
            return
        }
        var updated = session
        updated.activeDomainIDs = ids
        updated.updatedAt = Date()
        try? store.save(updated)
    }

    /// Returns true when the message clearly targets the vision provider — i.e. the
    /// whole turn should run on the (smaller) vision model rather than the execute
    /// model. This must be conservative: routing a coding/agentic task to the vision
    /// model cripples it. "click"/"button" are NOT used — they are ubiquitous in
    /// coding and UI-debug prompts (e.g. S1's "click every toolbar button"), which
    /// must run on the execute model; per-image work goes through the vision_query
    /// tool instead, which routes only that call to the vision slot.
    static func looksLikeVisionRequest(_ lower: String) -> Bool {
        if lower.count > 500 {
            let agenticWorkflowHints = [
                "workflow", "generate", "design", "implement", "write a final report",
                "kicad", "spice", "gerber", "bom", "artifact"
            ]
            if agenticWorkflowHints.contains(where: { lower.contains($0) }) {
                return false
            }
        }

        // Exact-phrase keywords that are unambiguous without boundary checks.
        let phraseKeywords = ["take a screenshot", "take a picture", "capture the screen",
                              "describe the image", "what is in this image",
                              "look at the screen", "inspect the screen",
                              "read the screenshot", "analyze the screenshot"]
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
                        let slot = self.executableTurnSlot(for: self.selectSlot(for: userMessage))
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
            forcedElectronicsWorkflowLock = false
            latestVerifiedDesignIntentArtifactPath = nil
            latestVerifiedCircuitIRArtifactPath = nil
            latestVerifiedComponentMatrixArtifactPath = nil
            latestVerifiedFootprintAssignmentArtifactPath = nil
            latestFocusedElectronicsHandoffToolName = nil
            pendingRepairableElectronicsHandoff = nil
        }
        if isContinuation {
            recordInternalElectronicsContinuationEvidence(from: userMessage)
        }
        await promoteElectronicsDomainIfIntentDetected(in: userMessage)
        let domain = await activeDomain()
        let classification: ClassifierResult
        if isContinuation {
            classification = ClassifierResult(needsPlanning: false, complexity: .highStakes, reason: "continuation turn")
        } else {
            classification = await classify(message: userMessage, domain: domain)
        }
        let workingSlot = executableTurnSlot(for: selectSlot(for: userMessage))
        continuation.yield(.slotRuntimeState(workingSlot, .busy))

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
            if bookChunks.isEmpty {
                var seenChunkIDs = Set<String>()
                for query in RAGQueryFallbackPlanner.queries(from: userMessage) {
                    let fallback = await client.searchChunks(
                        query: query,
                        source: "all",
                        bookIDs: nil,
                        projectPath: currentProjectPath,
                        limit: min(max(ragChunkLimit * 2, 1), 20),
                        rerank: ragRerank
                    )
                    for chunk in fallback where seenChunkIDs.insert(chunk.chunkID).inserted {
                        bookChunks.append(chunk)
                    }
                    if bookChunks.count >= min(max(ragChunkLimit, 1), 20) {
                        break
                    }
                }
            }
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
        // Discipline: flag a feature request submitted without a task NNa file, so the
        // project's TDD-first workflow is visible in the agent loop.
        if let disciplineProjectPath = currentProjectPath, !disciplineProjectPath.isEmpty {
            let promptCheck = await UserPromptDisciplineChecker().check(
                prompt: effectiveMessage, projectPath: disciplineProjectPath)
            if case .missingTaskFile(let suggestion) = promptCheck {
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
        var electronicsToolInvocationCorrectionCount = 0

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
        var executableEscalationSlots: [AgentSlot] = [.execute, .vision]
        if slotAssignments[.orchestrate] != nil {
            executableEscalationSlots.append(.orchestrate)
        }
        let viableEscalationProviders = Set(
            executableEscalationSlots
                .compactMap { provider(for: $0)?.id }
                .map { String($0.split(separator: ":", maxSplits: 1).first ?? Substring($0)) })
        let escalation = EscalationHandler(
            planner: planner, registry: registry,
            viableProviderIDs: viableEscalationProviders,
            preferredEscalationProviderID: nil)
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
                continuation.yield(.slotRuntimeState(.orchestrate, .busy))
                defer { continuation.yield(.slotRuntimeState(.orchestrate, .ready)) }
                planSteps = await override.decompose(task: userMessage, context: context.messages)
            } else {
                continuation.yield(.slotRuntimeState(.orchestrate, .busy))
                defer { continuation.yield(.slotRuntimeState(.orchestrate, .ready)) }
                planSteps = await planner.decompose(task: userMessage, context: context.messages)
            }

            if !planSteps.isEmpty {
                let evidenceGateContinuations = shouldEvidenceGateContinuations(for: planSteps)
                let batches = groupParallelSteps(
                    planSteps,
                    maxParallelSteps: evidenceGateContinuations ? 1 : 4
                )
                let thisBatch = batches[0]
                let remainingBatches = Array(batches.dropFirst())
                pendingContinuationAllSteps = planSteps
                pendingContinuationSteps = remainingBatches.flatMap { $0 }
                pendingContinuationOriginalTask = userMessage
                pendingContinuationCompletedCount = thisBatch.count
                pendingContinuationVerifiedCompletedCount = 0
                pendingContinuationEvidence.removeAll()
                pendingContinuationBlockedReason = nil
                pendingContinuationUsesEvidenceGate = evidenceGateContinuations

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
                // the loop budget is nearly exhausted so it wraps up the active turn.
                let loopsRemaining = maxIterations - loopCount
                if loopsRemaining <= nearCeilingThreshold && !nearCeilingEmitted {
                    nearCeilingEmitted = true
                    nearCeilingWarningAddendum = """
                    ⚠️ LOOP BUDGET CRITICAL: You have \(loopsRemaining) iteration(s) remaining \
                    in this turn. Finish the current required action, save any in-progress \
                    files if you changed files, and wrap up. Do not start unrelated tasks.
                    """
                    continuation.yield(.systemNote(
                        "[⚠️ \(loopsRemaining) loop iteration(s) remaining — finish current action and wrap up]"
                    ))
                }

                let provider = resolvedProvider(for: workingSlot)
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
                request.cachePolicy = AppSettings.shared.cagEnabled ? .ephemeral : .disabled
                if AppSettings.shared.cagEnabled {
                    request.systemPromptSegments = buildCAGSystemPromptSegments()
                }
                request.tools = CAGToolOrdering.stable(offeredTools())
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
                    if manager.capabilities.supportsRuntimeModelLoad {
                        try await manager.ensureModelLoaded(modelID: request.model)
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

                if !sawToolCall,
                   assembled.isEmpty,
                   let textToolCalls = TextEncodedToolCallParser.parse(
                    fullText,
                    offeredToolNames: Set(offeredTools().map(\.function.name))
                        .union(toolRouter.registeredRoutes().map(\.toolName))
                   ),
                   !textToolCalls.isEmpty {
                    sawToolCall = true
                    for (index, call) in textToolCalls.enumerated() {
                        assembled[index] = (
                            id: call.id,
                            name: call.function.name,
                            args: call.function.arguments
                        )
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

                    if shouldForceElectronicsToolInvocation(
                        originalTask: userMessage,
                        responseText: fullText
                    ) || shouldForceElectronicsToolInvocationForEvidenceGate() {
                        if electronicsToolInvocationCorrectionCount < 2 {
                            electronicsToolInvocationCorrectionCount += 1
                            let availableTools = availableElectronicsToolNamesForCorrection()
                            let toolList = availableTools.isEmpty
                                ? "No electronics tools are currently offered."
                                : "Available electronics tools: \(availableTools.joined(separator: ", "))."
                            continuation.yield(.systemNote(
                                "[electronics workflow guard: read-only/prose response cannot satisfy requested electronics tool boundary]"
                            ))
                            context.append(Message(
                                role: .user,
                                content: .text("""
                                [ELECTRONICS_TOOL_REQUIRED] The task is not complete. A read-only inspection or narrative \
                                blocker is not a real electronics/KiCad tool invocation. \(toolList)

                                Call a real offered electronics tool now. For the first design-intent step, call \
                                `kicad_build_intent_model` with the requirements/spec artifact path and a board profile. \
                                Use `workflow.requirements_to_pcb` only for an explicit full end-to-end completion run. \
                                Do not describe GUI setup, provider setup, or future steps as a substitute for the tool call. \
                                If no electronics tool is offered, respond exactly `[ELECTRONICS_TOOLS_UNAVAILABLE]`.
                                """),
                                timestamp: Date()
                            ))
                            continue turnLoop
                        }

                        continuationAborted = true
                        pendingContinuationSteps.removeAll()
                        try? FileManager.default.removeItem(at: continuationInjectURL)
                        continuation.yield(.cleanStop(
                            reason: "electronics workflow stalled",
                            summary: "Stopped because the active electronics workflow produced prose after read-only inspection instead of invoking an offered electronics/KiCad tool."
                        ))
                        break turnLoop
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
                                if !pendingContinuationSteps.isEmpty {
                                    pendingContinuationSteps.removeAll()
                                    continuationAborted = true
                                    try? FileManager.default.removeItem(at: continuationInjectURL)
                                    continuation.yield(.systemNote(
                                        "[verification passed - clearing remaining continuations]"
                                    ))
                                }
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

                let modelCalls = assembled.keys.sorted().map { index in
                    let item = assembled[index]!
                    return ToolCall(
                        id: item.id.isEmpty ? UUID().uuidString : item.id,
                        type: "function",
                        function: FunctionCall(name: item.name, arguments: item.args)
                    )
                }
                if let blockedCalls = electronicsWorkflowLockBlockedCalls(in: modelCalls),
                   !blockedCalls.isEmpty {
                    totalToolCallCount += modelCalls.count
                    for call in modelCalls {
                        continuation.yield(.toolCallStarted(call))
                    }
                    context.append(Message(
                        role: .assistant,
                        content: .text(""),
                        toolCalls: modelCalls,
                        thinkingContent: fullThinking.isEmpty ? nil : fullThinking,
                        timestamp: Date()
                    ))
                    for call in blockedCalls {
                        let rejection = electronicsWorkflowLockRejection(for: call)
                        continuation.yield(.toolCallResult(rejection))
                        context.append(Message(
                            role: .tool,
                            content: .text(rejection.content),
                            toolCallId: call.id,
                            timestamp: Date()))
                    }
                    continuationAborted = true
                    pendingContinuationSteps.removeAll()
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    let names = blockedCalls.map(\.function.name).joined(separator: ", ")
                    continuation.yield(.cleanStop(
                        reason: "electronics workflow drift",
                        summary: "Stopped because the active electronics workflow attempted unapproved tool(s): \(names)."
                    ))
                    break turnLoop
                }

                let calls = redirectedElectronicsHandoffCalls(
                    from: authoritativeElectronicsWorkflowCalls(from: modelCalls)
                )
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
                                + "this task. A domain backend is connected — "
                                + "author every domain file and run every domain "
                                + "operation through the offered domain tools "
                                + "(`kicad_*` or `mcp:<server>:*`). Do not shell out, "
                                + "hand-write files, or spawn subagents; call the "
                                + "domain tools directly.",
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
                + "with the still-available read-only file tools for context, "
                + "then the domain tools for domain work. Do not use shell or "
                + "file-authoring tools (run_shell, write_file, "
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
                if let blockedCalls = electronicsWorkflowLockBlockedCalls(in: regularCalls),
                   !blockedCalls.isEmpty {
                    for call in blockedCalls {
                        let rejection = electronicsWorkflowLockRejection(for: call)
                        continuation.yield(.toolCallResult(rejection))
                        context.append(Message(
                            role: .tool,
                            content: .text(rejection.content),
                            toolCallId: call.id,
                            timestamp: Date()))
                    }
                    continuationAborted = true
                    pendingContinuationSteps.removeAll()
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    let names = blockedCalls.map(\.function.name).joined(separator: ", ")
                    continuation.yield(.cleanStop(
                        reason: "electronics workflow drift",
                        summary: "Stopped because the active electronics workflow attempted unapproved tool(s): \(names)."
                    ))
                    break turnLoop
                }
                if let requiredToolName = requiredElectronicsHandoffToolName(),
                   !regularCalls.contains(where: { $0.function.name == requiredToolName }) {
                    for call in regularCalls {
                        let rejection = electronicsRequiredHandoffRejection(
                            for: call,
                            requiredToolName: requiredToolName
                        )
                        continuation.yield(.toolCallResult(rejection))
                        context.append(Message(
                            role: .tool,
                            content: .text(rejection.content),
                            toolCallId: call.id,
                            timestamp: Date()))
                    }
                    if electronicsToolInvocationCorrectionCount < 2 {
                        electronicsToolInvocationCorrectionCount += 1
                        continuation.yield(.systemNote(
                            "[electronics workflow guard: wrong handoff tool - retrying exact required tool]"
                        ))
                        context.append(Message(
                            role: .user,
                            content: .text("""
                            [ELECTRONICS_HANDOFF_TOOL_REQUIRED] The current electronics continuation cannot proceed with read-only inspection, toolchain/version checks, or a different KiCad tool.

                            Next required electronics handoff tool: `\(requiredToolName)`.
                            Call exactly `\(requiredToolName)` now with structured arguments from the already-read requirements/spec artifact. Do not call `read_file`, `list_directory`, `search_files`, `kicad_check_version`, or workflow completion routes for this handoff.
                            """),
                            timestamp: Date()
                        ))
                        continue turnLoop
                    }

                    continuationAborted = true
                    pendingContinuationSteps.removeAll()
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    continuation.yield(.cleanStop(
                        reason: "electronics workflow stalled",
                        summary: "Stopped because the active electronics workflow repeatedly avoided the required handoff tool `\(requiredToolName)`."
                    ))
                    break turnLoop
                }
                if let blockedCalls = electronicsHandoffDriftBlockedCalls(in: regularCalls),
                   !blockedCalls.isEmpty {
                    for call in blockedCalls {
                        let rejection = electronicsHandoffDriftRejection(for: call)
                        continuation.yield(.toolCallResult(rejection))
                        context.append(Message(
                            role: .tool,
                            content: .text(rejection.content),
                            toolCallId: call.id,
                            timestamp: Date()))
                    }
                    continuationAborted = true
                    pendingContinuationSteps.removeAll()
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    let names = blockedCalls.map(\.function.name).joined(separator: ", ")
                    continuation.yield(.cleanStop(
                        reason: "electronics workflow handoff drift",
                        summary: "Stopped because a DesignIntent artifact already exists and the workflow attempted stale handoff call(s): \(names)."
                    ))
                    break turnLoop
                }
                let regularResults = await dispatchRegularCalls(
                    regularCalls,
                    turn: turn,
                    loopCount: loopCount,
                    writtenFilePaths: &writtenFilePaths,
                    continuation: continuation,
                    context: context,
                    emitCompactionNoteIfNeeded: emitCompactionNoteIfNeeded
                )
                recordContinuationEvidence(calls: regularCalls, results: regularResults)
                if scheduleRepairableElectronicsVerificationContinuationIfNeeded() {
                    continuation.yield(.systemNote(
                        "[electronics verification diagnostics received - scheduling repair handoff]"
                    ))
                    break turnLoop
                }
                if scheduleFocusedElectronicsHandoffContinuationIfNeeded() {
                    continuation.yield(.systemNote(
                        "[electronics DesignIntent artifact verified - scheduling next focused handoff]"
                    ))
                    break turnLoop
                }
                if scheduleImplicitElectronicsHandoffContinuationIfNeeded(for: userMessage) {
                    continuation.yield(.systemNote(
                        "[electronics DesignIntent artifact verified - scheduling next handoff]"
                    ))
                    break turnLoop
                }
                if pendingContinuationUsesEvidenceGate,
                   activeDomainIDs.contains(ElectronicsDomain.defaultID),
                   let blockedReason = pendingContinuationBlockedReason {
                    finalCriticResult = .fail(reason: blockedReason)
                    pendingContinuationSteps.removeAll()
                    continuationAborted = true
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    continuation.yield(.cleanStop(
                        reason: "electronics workflow blocked",
                        summary: "Stopped because the current electronics evidence gate failed. \(blockedReason)"
                    ))
                    break turnLoop
                }
                if shouldCompleteFocusedElectronicsHandoffSlice() {
                    finalCriticResult = .pass
                    consecutiveCriticFailures = 0
                    pendingContinuationSteps.removeAll()
                    continuationAborted = true
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    continuation.yield(.cleanStop(
                        reason: "focused electronics handoff complete",
                        summary: "Focused electronics handoff stopped after verified Circuit IR artifact evidence."
                    ))
                    break turnLoop
                }
                if pendingContinuationUsesEvidenceGate,
                   activeDomainIDs.contains(ElectronicsDomain.defaultID),
                   let currentPlanStep,
                   electronicsStepVerified(currentPlanStep),
                   !pendingContinuationSteps.isEmpty {
                    continuation.yield(.systemNote(
                        "[electronics evidence verified for current step - scheduling next verified continuation]"
                    ))
                    schedulePendingContinuation()
                    break turnLoop
                }
                if shouldScheduleEvidenceGatedContinuationAfterToolBatch() {
                    continuation.yield(.systemNote(
                        "[electronics evidence still missing for current step - rescheduling first unverified step]"
                    ))
                    scheduleEvidenceGatedContinuation()
                    break turnLoop
                }
                if let failure = blockingElectronicsToolFailure(calls: regularCalls, results: regularResults) {
                    finalCriticResult = .fail(reason: failure.content)
                    pendingContinuationSteps.removeAll()
                    continuationAborted = true
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    continuation.yield(.cleanStop(
                        reason: "electronics workflow blocked",
                        summary: "Stopped after \(failure.toolName) returned a blocking electronics result. \(failure.content)"
                    ))
                    break turnLoop
                }
                if hasTerminalElectronicsWorkflowCompletion(calls: regularCalls, results: regularResults) {
                    finalCriticResult = .pass
                    consecutiveCriticFailures = 0
                    pendingContinuationSteps.removeAll()
                    continuationAborted = true
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    continuation.yield(.systemNote(
                        "[electronics workflow complete after verified workflow result - stopping]"
                    ))
                    break turnLoop
                }
                if hasSatisfiedRequestedStopBoundary(
                    originalTask: userMessage,
                    calls: regularCalls,
                    results: regularResults
                ) {
                    pendingContinuationSteps.removeAll()
                    continuationAborted = true
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    continuation.yield(.systemNote(
                        "[requested stop boundary satisfied after tool result - stopping]"
                    ))
                    break turnLoop
                }
                if await shouldStopAfterPostToolVerification(
                    calls: regularCalls,
                    results: regularResults,
                    context: context,
                    domain: domain,
                    writtenFiles: writtenFilePaths,
                    continuation: continuation
                ) {
                    finalCriticResult = .pass
                    consecutiveCriticFailures = 0
                    pendingContinuationSteps.removeAll()
                    continuationAborted = true
                    try? FileManager.default.removeItem(at: continuationInjectURL)
                    break turnLoop
                }
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
                            "provider_id": .string(provider.id),
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
                isReloadingModel = advisory.kind == .contextLengthTooSmall || advisory.kind == .llamaCppRuntimeUntuned
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
            "provider_id": resolvedProvider(for: workingSlot).id,
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
        if pendingContinuationUsesEvidenceGate,
           !pendingContinuationAllSteps.isEmpty,
           !continuationAborted {
            scheduleEvidenceGatedContinuation()
        } else if !pendingContinuationSteps.isEmpty && !continuationAborted {
            schedulePendingContinuation()
        } else if !continuationAborted {
            _ = scheduleImplicitElectronicsHandoffContinuationIfNeeded(for: userMessage)
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

        if pendingContinuationUsesEvidenceGate {
            scheduleEvidenceGatedContinuation()
            return
        }

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

    private func scheduleEvidenceGatedContinuation() {
        let planSteps = pendingContinuationAllSteps.isEmpty
            ? pendingContinuationSteps
            : pendingContinuationAllSteps
        guard !planSteps.isEmpty else { return }

        if let blockedReason = pendingContinuationBlockedReason {
            pendingContinuationSteps.removeAll()
            try? FileManager.default.removeItem(at: continuationInjectURL)
            TelemetryEmitter.shared.emit("engine.continuation.evidence_blocked", data: [
                "reason": blockedReason
            ])
            return
        }

        let verifiedCount = verifiedElectronicsCompletedPrefix(in: planSteps)
        pendingContinuationVerifiedCompletedCount = verifiedCount
        pendingContinuationCompletedCount = verifiedCount

        guard verifiedCount < planSteps.count else {
            pendingContinuationSteps.removeAll()
            try? FileManager.default.removeItem(at: continuationInjectURL)
            TelemetryEmitter.shared.emit("engine.continuation.evidence_complete", data: [
                "verified_steps": verifiedCount
            ])
            return
        }

        let pendingSteps = Array(planSteps.dropFirst(verifiedCount))
        pendingContinuationSteps = pendingSteps
        let batches = groupParallelSteps(pendingSteps, maxParallelSteps: 1)
        guard let thisBatch = batches.first else { return }
        let stillRemaining = Array(pendingSteps.dropFirst(thisBatch.count))
        let originalTask = pendingContinuationOriginalTask

        let stepList = thisBatch.enumerated()
            .map { "  \(verifiedCount + $0.offset + 1). \($0.element.description)" }
            .joined(separator: "\n")
        let verifiedSummary = verifiedCount == 0
            ? "No planned electronics workflow steps have verified completion evidence yet."
            : "Steps 1-\(verifiedCount) have verified tool/artifact evidence."

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
        let requestedHandoffTool = explicitFocusedElectronicsToolName(
            for: "",
            steps: thisBatch
        )
        let handoffInstruction = electronicsHandoffInstruction(
            requestedToolName: requestedHandoffTool
        ) ?? ""
        let focusedToolInstruction: String
        if let requestedHandoffTool {
            focusedToolInstruction = """
            The current focused electronics slice explicitly names `\(requestedHandoffTool)`. Preserve that requested tool boundary; do not substitute earlier DesignIntent or Circuit IR handoff tools.
            """
        } else {
            focusedToolInstruction = """
            For focused DesignIntent approval or Circuit IR slices, use the explicit `kicad_build_intent_model`, `kicad_approve_design_intent`, and `kicad_generate_circuit_ir` tool path instead.
            """
        }

        let message = """
        [CONTINUATION] \(verifiedSummary) Continue from the first unverified electronics step:
        \(stepList)

        Original task: \(originalTask)
        \(executionInstruction)
        \(handoffInstruction)
        `workflow.requirements_to_pcb` is a completion/verification route: call it only after structured evidence paths exist for DesignIntent, Circuit IR, component selection, footprints, KiCad schematic/PCB, and required ERC/DRC/SPICE/BOM artifacts. Do not call it with requirements text alone.
        \(focusedToolInstruction)
        Do not use app/UI tools for electronics workflow execution; use the electronics workflow or `kicad_*` tools.
        Evidence gate: read-only inspection tools and KiCad/version health checks do not satisfy DesignIntent, schematic, simulation, fabrication, or BOM steps. If the current step needs generated electronics artifacts, call an artifact-producing electronics workflow or `kicad_*` tool now.
        Do not claim a schematic, simulation, fabrication export, or BOM step is complete unless the relevant KiCad/SPICE artifact evidence exists in tool results.
        If this step is already complete, respond with [STEP_ALREADY_DONE] and take no further action.
        """

        try? message.write(to: continuationInjectURL, atomically: true, encoding: .utf8)

        TelemetryEmitter.shared.emit("engine.continuation.evidence_scheduled", data: [
            "verified_steps": verifiedCount,
            "batch_steps": thisBatch.count,
            "remaining_steps": stillRemaining.count
        ])
    }

    private func scheduleImplicitElectronicsHandoffContinuationIfNeeded(for userMessage: String) -> Bool {
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID),
              pendingContinuationBlockedReason == nil,
              pendingContinuationAllSteps.isEmpty,
              pendingContinuationSteps.isEmpty,
              latestDesignIntentArtifactPath() != nil,
              electronicsDownstreamHandoffRequested(in: userMessage)
        else { return false }

        let circuitIRVerified = electronicsStepVerified(PlanStep(
            description: "Generate Circuit IR",
            successCriteria: "Circuit IR artifact exists",
            complexity: .standard
        ))
        guard !circuitIRVerified else { return false }

        pendingContinuationUsesEvidenceGate = true
        pendingContinuationOriginalTask = userMessage
        pendingContinuationCompletedCount = 0
        pendingContinuationVerifiedCompletedCount = 0
        pendingContinuationAllSteps = [
            PlanStep(
                description: "Approve DesignIntent using the generated artifact path",
                successCriteria: "DesignIntent approved",
                complexity: .standard
            ),
            PlanStep(
                description: "Generate Circuit IR from approved DesignIntent",
                successCriteria: "Circuit IR artifact exists",
                complexity: .standard
            ),
        ]
        scheduleEvidenceGatedContinuation()
        return true
    }

    private func scheduleFocusedElectronicsHandoffContinuationIfNeeded() -> Bool {
        guard pendingContinuationUsesEvidenceGate,
              activeDomainIDs.contains(ElectronicsDomain.defaultID),
              pendingContinuationBlockedReason == nil,
              let designIntentPath = latestDesignIntentArtifactPath(),
              let nextTool = nextFocusedElectronicsHandoffToolName(),
              nextTool != "kicad_build_intent_model"
        else { return false }
        guard !focusedElectronicsStopBoundaryReached(before: nextTool) else {
            pendingContinuationSteps.removeAll()
            pendingContinuationAllSteps.removeAll()
            try? FileManager.default.removeItem(at: continuationInjectURL)
            TelemetryEmitter.shared.emit("engine.continuation.focused_handoff_suppressed", data: [
                "tool_name": nextTool,
                "reason": "explicit_stop_boundary",
            ])
            return false
        }

        let taskDescription: String
        let handoffInstruction: String
        var telemetry: [String: Any] = [
            "tool_name": nextTool,
            "design_intent_path": designIntentPath,
        ]
        switch nextTool {
        case "kicad_approve_design_intent":
            taskDescription = "Approve DesignIntent using the generated artifact path"
            handoffInstruction = "The next assistant tool call must be exactly `kicad_approve_design_intent` with `design_intent_path` set to the existing artifact path."
        case "kicad_generate_circuit_ir":
            taskDescription = "Generate Circuit IR from approved DesignIntent"
            handoffInstruction = "The next assistant tool call must be exactly `kicad_generate_circuit_ir` with `design_intent_path` set to the existing artifact path."
        case "kicad_select_components":
            guard let circuitIRPath = latestCircuitIRArtifactPath() else { return false }
            taskDescription = "Select components using the approved DesignIntent and generated Circuit IR"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_select_components` with this JSON shape:
            {"design_intent_path":"\(designIntentPath)","circuit_ir_path":"\(circuitIRPath)","live_catalog_providers":["mouser","digikey"],"live_catalog_result_limit":3}
            """
            telemetry["circuit_ir_path"] = circuitIRPath
        case "kicad_revise_component_selection":
            guard let componentMatrixPath = latestAnyComponentMatrixArtifactPath() else { return false }
            let circuitIRPath = latestCircuitIRArtifactPath()
            taskDescription = "Revise blocked component selection with catalog evidence"
            if let circuitIRPath {
                handoffInstruction = """
                The next assistant tool call must be exactly `kicad_revise_component_selection` with this JSON shape:
                {"design_intent_path":"\(designIntentPath)","circuit_ir_path":"\(circuitIRPath)","component_matrix_path":"\(componentMatrixPath)","live_catalog_providers":["mouser","digikey"],"live_catalog_result_limit":3}
                """
                telemetry["circuit_ir_path"] = circuitIRPath
            } else {
                handoffInstruction = """
                The next assistant tool call must be exactly `kicad_revise_component_selection` with this JSON shape:
                {"design_intent_path":"\(designIntentPath)","component_matrix_path":"\(componentMatrixPath)","live_catalog_providers":["mouser","digikey"],"live_catalog_result_limit":3}
                """
            }
            telemetry["component_matrix_path"] = componentMatrixPath
        case "kicad_assign_footprints":
            guard let circuitIRPath = latestCircuitIRArtifactPath(),
                  let componentMatrixPath = latestComponentMatrixArtifactPath()
            else { return false }
            taskDescription = "Assign footprints from verified Circuit IR and component matrix evidence"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_assign_footprints` with this JSON shape:
            {"design_intent_path":"\(designIntentPath)","circuit_ir_path":"\(circuitIRPath)","component_matrix_path":"\(componentMatrixPath)"}
            """
            telemetry["circuit_ir_path"] = circuitIRPath
            telemetry["component_matrix_path"] = componentMatrixPath
        case "kicad_compile_project":
            guard let circuitIRPath = latestCircuitIRArtifactPath(),
                  let componentMatrixPath = latestComponentMatrixArtifactPath(),
                  let footprintAssignmentPath = latestFootprintAssignmentArtifactPath()
            else { return false }
            taskDescription = "Compile KiCad schematic and PCB from verified Circuit IR, component matrix, and footprint evidence"
            let outputDirectory = electronicsKiCadOutputDirectoryPath()
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_compile_project` with this JSON shape:
            {"design_intent_path":"\(designIntentPath)","circuit_ir_path":"\(circuitIRPath)","component_matrix_path":"\(componentMatrixPath)","footprint_assignment_path":"\(footprintAssignmentPath)","output_directory":"\(outputDirectory)"}
            """
            telemetry["circuit_ir_path"] = circuitIRPath
            telemetry["component_matrix_path"] = componentMatrixPath
            telemetry["footprint_assignment_path"] = footprintAssignmentPath
        case "kicad_apply_board_profile":
            guard let projectPath = latestKiCadProjectArtifactPath() else { return false }
            taskDescription = "Apply the board fabrication profile to verified KiCad PCB evidence"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_apply_board_profile` with this JSON shape:
            {"project_path":"\(projectPath)","fabricator_profile_id":"jlcpcb_2layer_default"}
            """
            telemetry["project_path"] = projectPath
        case "kicad_generate_net_classes":
            taskDescription = "Generate PCB net classes from the approved DesignIntent"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_generate_net_classes` with this JSON shape:
            {"design_intent_path":"\(designIntentPath)"}
            """
        case "kicad_place_components":
            guard let projectPath = latestKiCadProjectArtifactPath() else { return false }
            taskDescription = "Place PCB components using verified KiCad project evidence"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_place_components` with this JSON shape:
            {"project_path":"\(projectPath)"}
            """
            telemetry["project_path"] = projectPath
        case "kicad_route_pass":
            guard let projectPath = latestKiCadProjectArtifactPath() else { return false }
            taskDescription = "Route the PCB using verified KiCad project evidence"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_route_pass` with this JSON shape:
            {"project_path":"\(projectPath)"}
            """
            telemetry["project_path"] = projectPath
        case "kicad_run_erc":
            guard let projectPath = latestKiCadProjectArtifactPath() else { return false }
            taskDescription = "Run ERC and require passing ERC evidence before downstream steps"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_run_erc` with this JSON shape:
            {"project_path":"\(projectPath)"}
            Do not mark ERC complete if the result has diagnostics, violations, blocked status, or repair next-actions.
            """
            telemetry["project_path"] = projectPath
        case "kicad_run_drc":
            guard let projectPath = latestKiCadProjectArtifactPath() else { return false }
            taskDescription = "Run DRC and require passing DRC evidence before fabrication or BOM"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_run_drc` with this JSON shape:
            {"project_path":"\(projectPath)"}
            Do not mark DRC complete if the result has diagnostics, violations, blocked status, or repair next-actions.
            """
            telemetry["project_path"] = projectPath
        case "kicad_generate_spice_scenario":
            guard let projectPath = latestKiCadProjectArtifactPath() else { return false }
            taskDescription = "Generate a runnable SPICE scenario deck from verified KiCad project evidence"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_generate_spice_scenario` with this JSON shape:
            {"project_path":"\(projectPath)","design_intent_path":"\(designIntentPath)","circuit_ir_path":"\(latestCircuitIRArtifactPath() ?? "")"}
            Do not create the scenario with `run_shell`.
            """
            telemetry["project_path"] = projectPath
        case "kicad_run_spice":
            guard let projectPath = latestKiCadProjectArtifactPath(),
                  let scenarioPath = latestSimulationScenarioArtifactPath()
            else { return false }
            taskDescription = "Run SPICE using the generated scenario deck artifact"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_run_spice` with this JSON shape:
            {"project_path":"\(projectPath)","scenario_path":"\(scenarioPath)"}
            """
            telemetry["project_path"] = projectPath
            telemetry["scenario_path"] = scenarioPath
        case "kicad_export_fab":
            guard let projectPath = latestKiCadProjectArtifactPath() else { return false }
            let outputDirectory = electronicsFabricationOutputDirectoryPath()
            taskDescription = "Export Gerbers and drill files only after verification gates pass"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_export_fab` with this JSON shape:
            {"project_path":"\(projectPath)","output_directory":"\(outputDirectory)","fabricator_profile_id":"jlcpcb_2layer_default"}
            """
            telemetry["project_path"] = projectPath
            telemetry["output_directory"] = outputDirectory
        case "kicad_prepare_vendor_order":
            guard let bomPath = latestBOMArtifactPath() else { return false }
            taskDescription = "Prepare vendor BOM package from real BOM artifact evidence"
            handoffInstruction = """
            The next assistant tool call must be exactly `kicad_prepare_vendor_order` with this JSON shape:
            {"normalized_bom_path":"\(bomPath)","vendor_id":"Digi-Key","quantity":1}
            """
            telemetry["normalized_bom_path"] = bomPath
        default:
            taskDescription = "Continue electronics handoff with \(nextTool)"
            handoffInstruction = "The next assistant tool call must be exactly `\(nextTool)` with required artifact paths from this continuation."
        }

        let message = """
        [CONTINUATION] Verified electronics artifact evidence exists. Continue the next focused electronics handoff.

        Original task: \(pendingContinuationOriginalTask)
        Task: \(taskDescription)
        Existing DesignIntent artifact: \(designIntentPath)
        Next required electronics handoff tool: `\(nextTool)`.
        \(handoffInstruction)
        Do not call `read_file`, `list_directory`, `search_files`, `kicad_check_version`, or workflow completion routes for this handoff.
        Do not call `kicad_build_intent_model` again for this DesignIntent.
        """

        latestFocusedElectronicsHandoffToolName = nextTool
        try? message.write(to: continuationInjectURL, atomically: true, encoding: .utf8)
        TelemetryEmitter.shared.emit("engine.continuation.focused_handoff_scheduled", data: telemetry)
        return true
    }

    private func focusedElectronicsStopBoundaryReached(before nextTool: String) -> Bool {
        let text = pendingContinuationOriginalTask.lowercased()
        guard text.contains("stop") || text.contains("only") || text.contains("do not generate") else {
            return false
        }
        switch nextTool {
        case "kicad_assign_footprints":
            return (text.contains("component matrix") || text.contains("component_matrix"))
                && (text.contains("stop after") || text.contains("stop once") || text.contains("stop when"))
                || text.contains("do not generate footprints")
                || text.contains("do not assign footprints")
        case "kicad_compile_project":
            return (text.contains("footprint") || text.contains("footprint_assignment"))
                && (text.contains("stop after") || text.contains("stop once") || text.contains("stop when"))
                || text.contains("do not generate schematic")
                || text.contains("do not generate pcb")
        case "kicad_run_erc", "kicad_apply_board_profile", "kicad_generate_net_classes", "kicad_place_components", "kicad_route_pass":
            return text.contains("do not generate pcb")
                || text.contains("do not run erc")
                || text.contains("stop after schematic")
                || text.contains("stop after project")
        case "kicad_run_drc", "kicad_generate_spice_scenario", "kicad_run_spice", "kicad_export_fab", "kicad_prepare_vendor_order":
            return text.contains("do not generate gerbers")
                || text.contains("do not generate bom")
                || text.contains("do not run spice")
                || text.contains("stop after drc")
                || text.contains("stop after simulation")
        default:
            return false
        }
    }

    private func scheduleRepairableElectronicsVerificationContinuationIfNeeded() -> Bool {
        guard pendingContinuationUsesEvidenceGate,
              activeDomainIDs.contains(ElectronicsDomain.defaultID),
              pendingContinuationBlockedReason == nil,
              let handoff = pendingRepairableElectronicsHandoff
        else { return false }

        pendingRepairableElectronicsHandoff = nil
        try? handoff.message.write(to: continuationInjectURL, atomically: true, encoding: .utf8)
        TelemetryEmitter.shared.emit("engine.continuation.repair_handoff_scheduled", data: handoff.telemetry)
        return true
    }

    private func repairableElectronicsVerificationHandoff(
        from evidence: ContinuationToolEvidence
    ) -> ElectronicsRepairHandoff? {
        let actions = electronicsNextActions(inJSONText: evidence.output)
        guard !actions.isEmpty,
              let nextTool = repairHandoffToolName(for: evidence.toolName, actions: actions)
        else { return nil }

        let arguments = repairHandoffArguments(for: nextTool, evidence: evidence)
        guard !arguments.isEmpty else { return nil }
        let argumentsJSON = jsonObjectString(arguments)

        var telemetry: [String: Any] = [
            "tool_name": nextTool,
            "source_tool_name": evidence.toolName,
            "next_actions": actions,
        ]
        for (key, value) in arguments {
            telemetry[key] = value
        }

        let message = """
        [CONTINUATION] KiCad verification diagnostics produced repair next-actions. Continue the repair loop without marking the verification gate complete.

        Original task: \(pendingContinuationOriginalTask)
        Source verification tool: `\(evidence.toolName)`
        Next required electronics repair tool: `\(nextTool)`.
        The next assistant tool call must be exactly `\(nextTool)` with this JSON shape:
        \(argumentsJSON)
        Do not claim ERC, DRC, or SPICE verification passed until the corresponding check is rerun and returns verified pass evidence.
        Do not call workflow completion routes or downstream fabrication/BOM/report tools until the repair loop has passed.
        """

        return ElectronicsRepairHandoff(toolName: nextTool, message: message, telemetry: telemetry)
    }

    private func repairHandoffToolName(for sourceToolName: String, actions: [String]) -> String? {
        let mapped = actions.compactMap { KiCadRuntimeEvidencePipeline.toolName(forNextAction: $0) }
        switch sourceToolName {
        case "kicad_run_erc":
            return mapped.first { $0 == "kicad_repair_erc_from_diagnostics" }
        case "kicad_repair_erc_from_diagnostics":
            return mapped.first { $0 == "kicad_apply_erc_repair_patch" }
        case "kicad_apply_erc_repair_patch":
            return mapped.first { $0 == "kicad_run_erc" }
        case "kicad_run_drc":
            return mapped.first { $0 == "kicad_repair_drc_from_diagnostics" }
        case "kicad_repair_drc_from_diagnostics":
            return mapped.first { $0 == "kicad_apply_drc_repair_patch" }
        case "kicad_apply_drc_repair_patch":
            return mapped.first { $0 == "kicad_run_drc" }
        case "kicad_run_spice":
            return mapped.first { $0 == "kicad_repair_spice_from_diagnostics" }
        case "kicad_repair_spice_from_diagnostics":
            return mapped.first { $0 == "kicad_apply_spice_repair_patch" }
        case "kicad_apply_spice_repair_patch":
            return mapped.first { $0 == "kicad_run_spice" }
        default:
            return nil
        }
    }

    private func repairHandoffArguments(
        for nextTool: String,
        evidence: ContinuationToolEvidence
    ) -> [String: String] {
        switch nextTool {
        case "kicad_repair_erc_from_diagnostics":
            return compactStringDictionary([
                "erc_report_path": artifactPath(
                    from: evidence,
                    directKeys: ["erc_report_path", "ercReportPath"],
                    kindNeedles: ["erc_report"],
                    pathNeedles: ["erc-report", "erc_report"]
                ),
                "circuit_ir_path": circuitIRArtifactPath(from: evidence) ?? latestCircuitIRArtifactPath(),
            ])
        case "kicad_apply_erc_repair_patch":
            return compactStringDictionary([
                "erc_repair_plan_path": artifactPath(
                    from: evidence,
                    directKeys: ["erc_repair_plan_path", "ercRepairPlanPath"],
                    kindNeedles: ["erc_repair_plan"],
                    pathNeedles: ["erc-repair", "erc_repair"]
                ),
                "schematic_path": artifactPath(
                    from: evidence,
                    directKeys: ["schematic_path", "schematicPath", "kicad_schematic_path"],
                    kindNeedles: ["kicad_schematic", "schematic"],
                    pathNeedles: [".kicad_sch", "schematic"]
                ),
                "project_path": artifactPath(
                    from: evidence,
                    directKeys: ["project_path", "projectPath", "kicad_project_path"],
                    kindNeedles: ["kicad_project", "project"],
                    pathNeedles: [".kicad_pro"]
                ),
            ])
        case "kicad_run_erc":
            return compactStringDictionary([
                "project_path": artifactPath(
                    from: evidence,
                    directKeys: ["project_path", "projectPath", "kicad_project_path"],
                    kindNeedles: ["kicad_project", "project"],
                    pathNeedles: [".kicad_pro"]
                ),
            ])
        case "kicad_repair_drc_from_diagnostics":
            return compactStringDictionary([
                "drc_report_path": artifactPath(
                    from: evidence,
                    directKeys: ["drc_report_path", "drcReportPath"],
                    kindNeedles: ["drc_report"],
                    pathNeedles: ["drc-report", "drc_report"]
                ),
            ])
        case "kicad_apply_drc_repair_patch":
            return compactStringDictionary([
                "drc_repair_plan_path": artifactPath(
                    from: evidence,
                    directKeys: ["drc_repair_plan_path", "drcRepairPlanPath"],
                    kindNeedles: ["drc_repair_plan"],
                    pathNeedles: ["drc-repair", "drc_repair"]
                ),
                "project_path": artifactPath(
                    from: evidence,
                    directKeys: ["project_path", "projectPath", "kicad_project_path"],
                    kindNeedles: ["kicad_project", "project"],
                    pathNeedles: [".kicad_pro"]
                ),
            ])
        case "kicad_run_drc":
            return compactStringDictionary([
                "project_path": artifactPath(
                    from: evidence,
                    directKeys: ["project_path", "projectPath", "kicad_project_path"],
                    kindNeedles: ["kicad_project", "project"],
                    pathNeedles: [".kicad_pro"]
                ),
            ])
        case "kicad_repair_spice_from_diagnostics":
            return compactStringDictionary([
                "spice_measurements_path": artifactPath(
                    from: evidence,
                    directKeys: ["spice_measurements_path", "spiceMeasurementsPath", "measurements_path"],
                    kindNeedles: ["spice_measurements", "measurements"],
                    pathNeedles: ["spice", "measurements"]
                ),
                "scenario_path": artifactPath(
                    from: evidence,
                    directKeys: ["scenario_path", "scenarioPath"],
                    kindNeedles: ["simulation_scenario", "scenario"],
                    pathNeedles: ["scenario"]
                ),
            ])
        case "kicad_apply_spice_repair_patch":
            return compactStringDictionary([
                "spice_repair_plan_path": artifactPath(
                    from: evidence,
                    directKeys: ["spice_repair_plan_path", "spiceRepairPlanPath"],
                    kindNeedles: ["spice_repair_plan"],
                    pathNeedles: ["spice-repair", "spice_repair"]
                ),
                "scenario_path": artifactPath(
                    from: evidence,
                    directKeys: ["scenario_path", "scenarioPath"],
                    kindNeedles: ["simulation_scenario", "scenario"],
                    pathNeedles: ["scenario"]
                ),
            ])
        case "kicad_run_spice":
            return compactStringDictionary([
                "project_path": artifactPath(
                    from: evidence,
                    directKeys: ["project_path", "projectPath", "kicad_project_path"],
                    kindNeedles: ["kicad_project", "project"],
                    pathNeedles: [".kicad_pro"]
                ),
                "scenario_path": artifactPath(
                    from: evidence,
                    directKeys: ["scenario_path", "scenarioPath"],
                    kindNeedles: ["simulation_scenario", "scenario"],
                    pathNeedles: ["scenario"]
                ),
            ])
        default:
            return [:]
        }
    }

    private func compactStringDictionary(_ pairs: [String: String?]) -> [String: String] {
        pairs.reduce(into: [:]) { result, pair in
            guard let value = pair.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return }
            result[pair.key] = value
        }
    }

    private func jsonObjectString(_ dictionary: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.sortedKeys]
        ) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonObjectFromToolText(_ text: String) -> Any? {
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }

        var startIndex = text.startIndex
        while startIndex < text.endIndex {
            let startCharacter = text[startIndex]
            guard startCharacter == "{" || startCharacter == "[" else {
                startIndex = text.index(after: startIndex)
                continue
            }

            var stack: [Character] = []
            var inString = false
            var escaped = false
            var cursor = startIndex
            while cursor < text.endIndex {
                let character = text[cursor]
                if inString {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        inString = false
                    }
                } else {
                    switch character {
                    case "\"":
                        inString = true
                    case "{", "[":
                        stack.append(character)
                    case "}":
                        guard stack.last == "{" else { break }
                        stack.removeLast()
                    case "]":
                        guard stack.last == "[" else { break }
                        stack.removeLast()
                    default:
                        break
                    }

                    if stack.isEmpty {
                        let endIndex = text.index(after: cursor)
                        let candidate = String(text[startIndex..<endIndex])
                        if let data = candidate.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) {
                            return json
                        }
                        break
                    }
                }
                cursor = text.index(after: cursor)
            }

            startIndex = text.index(after: startIndex)
        }

        return nil
    }

    private func electronicsDownstreamHandoffRequested(in message: String) -> Bool {
        let lower = message.lowercased()
        let markers = [
            "circuitir", "circuit ir", "circuit_ir",
            "component selection", "component-selection",
            "footprint", "schematic", "pcb", "kicad",
            "erc", "drc", "spice", "gerber", "fabrication", "fab",
            "bom", "verification slice", "requirements-to-pcb"
        ]
        return markers.contains { lower.contains($0) }
    }

    private func electronicsHandoffInstruction(requestedToolName: String?) -> String? {
        guard let designIntentPath = latestDesignIntentArtifactPath() else { return nil }
        let nextTool = nextFocusedElectronicsHandoffToolName()
        if let requestedToolName,
           requestedToolName != nextTool {
            return """
            Existing DesignIntent artifact: \(designIntentPath)
            Do not call `kicad_build_intent_model` again for this DesignIntent, and do not reread the original spec as a substitute for the requested electronics tool.
            Current focused slice explicitly names `\(requestedToolName)`. Preserve that requested tool boundary; do not substitute `kicad_approve_design_intent` or `kicad_generate_circuit_ir` unless this slice explicitly asks for them.
            """
        }
        let exactToolInstruction = nextTool.map {
            if $0 == "kicad_select_components",
               let circuitIRPath = latestCircuitIRArtifactPath() {
                return """
                Next required electronics handoff tool: `kicad_select_components`.
                The next assistant tool call must be exactly `kicad_select_components` with `design_intent_path` set to the existing DesignIntent path, `circuit_ir_path` set to \(circuitIRPath), and `live_catalog_providers` set to ["mouser","digikey"].
                """
            }
            if $0 == "kicad_compile_project",
               let circuitIRPath = latestCircuitIRArtifactPath(),
               let componentMatrixPath = latestComponentMatrixArtifactPath(),
               let footprintAssignmentPath = latestFootprintAssignmentArtifactPath() {
                let outputDirectory = electronicsKiCadOutputDirectoryPath()
                return """
                Next required electronics handoff tool: `kicad_compile_project`.
                The next assistant tool call must be exactly `kicad_compile_project` with `design_intent_path` set to the existing DesignIntent path, `circuit_ir_path` set to \(circuitIRPath), `component_matrix_path` set to \(componentMatrixPath), `footprint_assignment_path` set to \(footprintAssignmentPath), and `output_directory` set to \(outputDirectory).
                """
            }
            if $0 == "kicad_generate_spice_scenario",
               let projectPath = latestKiCadProjectArtifactPath() {
                return """
                Next required electronics handoff tool: `kicad_generate_spice_scenario`.
                The next assistant tool call must be exactly `kicad_generate_spice_scenario` with `project_path` set to \(projectPath). Do not create the scenario with `run_shell`.
                """
            }
            if $0 == "kicad_run_spice",
               let projectPath = latestKiCadProjectArtifactPath(),
               let scenarioPath = latestSimulationScenarioArtifactPath() {
                return """
                Next required electronics handoff tool: `kicad_run_spice`.
                The next assistant tool call must be exactly `kicad_run_spice` with `project_path` set to \(projectPath) and `scenario_path` set to \(scenarioPath). Do not create or modify scenario files with `run_shell`.
                """
            }
            return """
            Next required electronics handoff tool: `\($0)`.
            The next assistant tool call must be exactly `\($0)` with `design_intent_path` set to the existing artifact path. Do not call `read_file`, `list_directory`, or `search_files` at this handoff boundary.
            """
        } ?? ""
        return """
        Existing DesignIntent artifact: \(designIntentPath)
        Do not call `kicad_build_intent_model` again for this DesignIntent, and do not reread the original spec as a substitute for the next electronics tool.
        \(exactToolInstruction)
        """
    }

    private func explicitFocusedElectronicsToolName(
        for task: String,
        steps: [PlanStep] = []
    ) -> String? {
        let stepText = steps
            .map { "\($0.description) \($0.proseSummary)" }
            .joined(separator: " ")
        return explicitFocusedElectronicsToolName(in: "\(task) \(stepText)")
    }

    private func explicitFocusedElectronicsToolName(in text: String) -> String? {
        let lower = text.lowercased()
        return Self.focusedElectronicsToolNames.first { toolName in
            let spacedName = toolName.replacingOccurrences(of: "_", with: " ")
            return lower.contains("`\(toolName)`")
                || lower.contains(toolName)
                || lower.contains(spacedName)
        }
    }

    private func shouldEvidenceGateContinuations(for steps: [PlanStep]) -> Bool {
        let text = steps
            .map { "\($0.description) \($0.proseSummary)" }
            .joined(separator: " ")
            .lowercased()
        let keywords = [
            "electronics", "kicad", "pcb", "schematic", "spice",
            "gerber", "drill", "fabrication", "bom", "bill of materials",
            "digikey", "digi-key", "mouser", "toolchain", "design intent",
            "designintent", "design-intent", "circuit ir", "circuit_ir",
            "circuitir"
        ]
        return keywords.contains { text.contains($0) }
    }

    private func recordContinuationEvidence(calls: [ToolCall], results: [ToolResult]) {
        guard pendingContinuationUsesEvidenceGate || activeDomainIDs.contains(ElectronicsDomain.defaultID) else { return }
        let callsByID = Dictionary(uniqueKeysWithValues: calls.map { ($0.id, $0) })
        for result in results {
            guard let call = callsByID[result.toolCallId] else { continue }
            let toolName = call.function.name
            guard pendingContinuationUsesEvidenceGate || isKiCadTool(toolName) || isWorkflowTool(toolName) else { continue }
            let rawText = "\(toolName) \(call.function.arguments) \(result.content)"
            if pendingContinuationUsesEvidenceGate,
               electronicsRequirementsInspectionFailureBlocksContinuation(toolName: toolName, result: result) {
                pendingContinuationBlockedReason = result.content
                pendingContinuationSteps.removeAll()
                try? FileManager.default.removeItem(at: continuationInjectURL)
                continue
            }
            guard !result.isError else { continue }
            if pendingContinuationUsesEvidenceGate,
               isWorkflowTool(toolName),
               !isCompleteElectronicsWorkflowReport(result.content) {
                pendingContinuationBlockedReason = result.content
                pendingContinuationSteps.removeAll()
                try? FileManager.default.removeItem(at: continuationInjectURL)
                continue
            }
            let evidence = ContinuationToolEvidence(
                toolName: toolName,
                arguments: call.function.arguments,
                output: result.content
            )
            if pendingContinuationUsesEvidenceGate,
               let repairHandoff = repairableElectronicsVerificationHandoff(from: evidence) {
                pendingContinuationEvidence.append(evidence)
                recordLatestElectronicsArtifactPaths(from: evidence)
                pendingRepairableElectronicsHandoff = repairHandoff
                continue
            }
            if pendingContinuationUsesEvidenceGate,
               electronicsToolResultBlocksContinuation(toolName: toolName, result: result, rawText: rawText) {
                pendingContinuationBlockedReason = electronicsBlockedContinuationReason(
                    toolName: toolName,
                    content: result.content
                )
                pendingContinuationSteps.removeAll()
                try? FileManager.default.removeItem(at: continuationInjectURL)
                continue
            }
            pendingContinuationEvidence.append(evidence)
            recordLatestElectronicsArtifactPaths(from: evidence)
        }
    }

    private func recordLatestElectronicsArtifactPaths(from evidence: ContinuationToolEvidence) {
        if let designIntentPath = designIntentArtifactPath(from: evidence) {
            latestVerifiedDesignIntentArtifactPath = designIntentPath
        }
        if let circuitIRPath = circuitIRArtifactPath(from: evidence) {
            latestVerifiedCircuitIRArtifactPath = circuitIRPath
        }
        if let componentMatrixPath = completeComponentMatrixArtifactPath(from: evidence) {
            latestVerifiedComponentMatrixArtifactPath = componentMatrixPath
        }
        if let footprintAssignmentPath = footprintAssignmentArtifactPath(from: evidence) {
            latestVerifiedFootprintAssignmentArtifactPath = footprintAssignmentPath
        }
    }

    private func electronicsBlockedContinuationReason(toolName: String, content: String) -> String {
        guard toolName == "kicad_revise_component_selection",
              let object = jsonObjectFromToolText(content) as? [String: Any] else {
            return content
        }
        let warningCode = warningCode(in: object) ?? "COMPONENT_SELECTION_REVISION_BLOCKED"
        let questionLines = clarificationQuestions(in: object).map { question in
            "Question \(question.id): \(question.prompt)"
        }
        let evidenceLines = componentSelectionRevisionEvidenceLines(in: object)
        guard !questionLines.isEmpty || !evidenceLines.isEmpty else { return content }
        return ([warningCode] + questionLines + evidenceLines).joined(separator: "\n")
    }

    private struct ParsedClarificationQuestion {
        var id: String
        var prompt: String
    }

    private func clarificationQuestions(in object: [String: Any]) -> [ParsedClarificationQuestion] {
        guard let questions = object["questions"] as? [[String: Any]] else { return [] }
        return questions.compactMap { question in
            guard let prompt = question["prompt"] as? String else { return nil }
            let id = question["id"] as? String ?? "component-selection-question"
            return ParsedClarificationQuestion(id: id, prompt: prompt)
        }
    }

    private func warningCode(in object: [String: Any]) -> String? {
        guard let warnings = object["warnings"] as? [[String: Any]] else { return nil }
        return warnings.compactMap { $0["code"] as? String }.first
    }

    private func componentSelectionRevisionEvidenceLines(in object: [String: Any]) -> [String] {
        var lines: [String] = []
        if let handoff = object["handoff"] as? [String: Any] {
            if let original = handoff["original_component_matrix_path"] as? String {
                lines.append("Original blocked component matrix: \(original)")
            }
            if let revised = handoff["component_matrix_path"] as? String {
                lines.append("Revised component matrix: \(revised)")
            }
        }
        if !lines.contains(where: { $0.hasPrefix("Revised component matrix:") }),
           let artifacts = object["artifacts"] as? [[String: Any]],
           let revised = artifacts.first(where: { artifact in
               (artifact["kind"] as? String)?.contains("component_matrix") ?? false
           })?["path"] as? String {
            lines.append("Revised component matrix: \(revised)")
        }
        return lines
    }

    private func recordInternalElectronicsContinuationEvidence(from message: String) {
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID),
              message.hasPrefix("[CONTINUATION]"),
              message.contains("verified electronics artifact evidence")
                || message.contains("verified tool/artifact evidence")
        else { return }

        let evidence = ContinuationToolEvidence(
            toolName: "internal_continuation",
            arguments: "",
            output: message
        )
        if !pendingContinuationEvidence.contains(where: {
            $0.toolName == evidence.toolName && $0.output == evidence.output
        }) {
            pendingContinuationEvidence.append(evidence)
        }
        if let designIntentPath = designIntentArtifactPath(from: evidence) {
            latestVerifiedDesignIntentArtifactPath = designIntentPath
        }
        if let circuitIRPath = circuitIRArtifactPath(from: evidence) {
            latestVerifiedCircuitIRArtifactPath = circuitIRPath
        }
        if let componentMatrixPath = completeComponentMatrixArtifactPath(from: evidence) {
            latestVerifiedComponentMatrixArtifactPath = componentMatrixPath
        }
        if let footprintAssignmentPath = footprintAssignmentArtifactPath(from: evidence) {
            latestVerifiedFootprintAssignmentArtifactPath = footprintAssignmentPath
        }
        if let toolName = focusedElectronicsToolNameForContinuationTask(in: message)
            ?? explicitFocusedElectronicsToolName(in: message) {
            latestFocusedElectronicsHandoffToolName = toolName
        }
    }

    private func focusedElectronicsToolNameForContinuationTask(in message: String) -> String? {
        guard let taskText = continuationTaskText(in: message) else { return nil }
        switch electronicsRequirement(forText: taskText) {
        case .designIntent:
            return "kicad_build_intent_model"
        case .designIntentApproval:
            return "kicad_approve_design_intent"
        case .circuitIR:
            return "kicad_generate_circuit_ir"
        case .componentSelection:
            return "kicad_select_components"
        case .footprintAssignment:
            return "kicad_assign_footprints"
        case .schematic:
            return "kicad_compile_project"
        case .boardProfile:
            return "kicad_apply_board_profile"
        case .netClasses:
            return "kicad_generate_net_classes"
        case .placement:
            return "kicad_place_components"
        case .routing:
            return "kicad_route_pass"
        case .erc:
            return "kicad_run_erc"
        case .drc:
            return "kicad_run_drc"
        case .simulation:
            return "kicad_run_spice"
        case .fabrication:
            return "kicad_export_fab"
        case .bom:
            return "kicad_prepare_vendor_order"
        default:
            return nil
        }
    }

    private func continuationTaskText(in message: String) -> String? {
        guard let taskRange = message.range(of: "Task:") else { return nil }
        let afterTask = message[taskRange.upperBound...]
        let endMarkers = [
            "`workflow.",
            "workflow.",
            "Evidence gate:",
            "Do not claim",
            "If this step",
        ]
        let endIndex = endMarkers
            .compactMap { marker in afterTask.range(of: marker)?.lowerBound }
            .min() ?? afterTask.endIndex
        let taskText = afterTask[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return taskText.isEmpty ? nil : taskText
    }

    private func verifiedElectronicsCompletedPrefix(in steps: [PlanStep]) -> Int {
        var completed = 0
        for step in steps {
            guard electronicsStepVerified(step) else { break }
            completed += 1
        }
        return completed
    }

    private func shouldCompleteFocusedElectronicsHandoffSlice() -> Bool {
        guard pendingContinuationUsesEvidenceGate,
              activeDomainIDs.contains(ElectronicsDomain.defaultID),
              pendingContinuationBlockedReason == nil
        else { return false }

        let planSteps = pendingContinuationAllSteps.isEmpty
            ? pendingContinuationSteps
            : pendingContinuationAllSteps
        guard !planSteps.isEmpty else { return false }

        let requirements = planSteps.map { electronicsRequirement(for: $0) }
        let hasCircuitIRStep = requirements.contains { requirement in
            if case .circuitIR = requirement { return true }
            return false
        }
        let hasDownstreamStep = requirements.contains { requirement in
            switch requirement {
            case .footprintAssignment, .schematic, .boardProfile, .netClasses, .placement,
                 .routing, .erc, .drc, .simulation, .fabrication, .bom:
                return true
            default:
                return false
            }
        }
        guard hasCircuitIRStep, !hasDownstreamStep else { return false }

        let verifiedCount = verifiedElectronicsCompletedPrefix(in: planSteps)
        guard verifiedCount >= planSteps.count else { return false }
        return electronicsStepVerified(PlanStep(
            description: "Generate Circuit IR",
            successCriteria: "Circuit IR artifact exists",
            complexity: .standard
        ))
    }

    private func shouldScheduleEvidenceGatedContinuationAfterToolBatch() -> Bool {
        guard pendingContinuationUsesEvidenceGate,
              activeDomainIDs.contains(ElectronicsDomain.defaultID),
              pendingContinuationBlockedReason == nil
        else { return false }

        let planSteps = pendingContinuationAllSteps.isEmpty
            ? pendingContinuationSteps
            : pendingContinuationAllSteps
        guard !planSteps.isEmpty else { return false }

        let verifiedCount = verifiedElectronicsCompletedPrefix(in: planSteps)
        guard verifiedCount < planSteps.count else { return false }

        if latestDesignIntentArtifactPath() != nil,
           nextFocusedElectronicsHandoffToolName() != nil {
            return false
        }

        return true
    }

    private func electronicsStepVerified(_ step: PlanStep) -> Bool {
        let requirement = electronicsRequirement(for: step)
        switch requirement {
        case .requirementsInspection:
            return pendingContinuationEvidence.contains { evidence in
                ["read_file", "list_directory", "search_files"].contains(evidence.toolName)
            }
        case .designIntent:
            return pendingContinuationEvidence.contains { evidence in
                guard isKiCadTool(evidence.toolName) else { return false }
                let text = evidenceText(evidence)
                return designIntentArtifactPath(from: evidence) != nil
                    || text.contains("design_intent")
                    || text.contains("designintent")
            }
        case .designIntentApproval:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_approve_design_intent" else { return false }
                let text = evidenceText(evidence)
                return text.contains("approved")
                    || text.contains("\"status\":\"ok\"")
                    || text.contains("\"status\": \"ok\"")
                    || text.contains("\"approved\":true")
                    || text.contains("\"approved\": true")
            }
        case .circuitIR:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_generate_circuit_ir" else { return false }
                let text = evidenceText(evidence)
                return circuitIRArtifactPath(from: evidence) != nil
                    || latestCircuitIRArtifactPath() != nil
                    || text.contains("circuit_ir")
                    || text.contains("circuitir")
                    || text.contains(".json")
            }
        case .componentSelection:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_select_components" else { return false }
                let text = evidenceText(evidence)
                return completeComponentMatrixArtifactPath(from: evidence) != nil
                    || latestComponentMatrixArtifactPath() != nil
                    || ((text.contains("component_matrix") || text.contains("componentmatrix"))
                        && extractedPaths(from: rawEvidenceText(evidence)).contains {
                            ComponentMatrixEvidence.isCompleteSelectionArtifact(atPath: $0)
                        })
            }
        case .footprintAssignment:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_assign_footprints" else { return false }
                let text = evidenceText(evidence)
                return footprintAssignmentArtifactPath(from: evidence) != nil
                    || text.contains("footprint_assignment")
                    || text.contains("footprintassignment")
            }
        case .schematic:
            return pendingContinuationEvidence.contains { evidence in
                guard isKiCadTool(evidence.toolName) else { return false }
                let text = evidenceText(evidence)
                return text.contains(".kicad_sch")
                    || text.contains("kicad_schematic")
                    || text.contains("\"schematic\"")
                    || evidence.toolName == "kicad_compile_project"
            }
        case .boardProfile:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_apply_board_profile" else { return false }
                let text = evidenceText(evidence)
                return text.contains("board_profile")
                    || text.contains("\"profile\"")
                    || text.contains("\"status\":\"applied\"")
                    || text.contains("\"status\": \"applied\"")
                    || text.contains("\"status\":\"complete\"")
                    || text.contains("\"status\": \"complete\"")
            }
        case .netClasses:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_generate_net_classes" else { return false }
                let text = evidenceText(evidence)
                return text.contains("net_classes")
                    || text.contains("netclasses")
                    || text.contains("\"classes\"")
                    || text.contains("\"status\":\"complete\"")
                    || text.contains("\"status\": \"complete\"")
            }
        case .placement:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_place_components" else { return false }
                let text = evidenceText(evidence)
                return text.contains("placement_plan")
                    || text.contains("placement-report")
                    || text.contains("\"status\":\"complete\"")
                    || text.contains("\"status\": \"complete\"")
            }
        case .routing:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_route_pass" else { return false }
                let text = evidenceText(evidence)
                return !text.contains("\"status\":\"blocked\"")
                    && !text.contains("\"status\": \"blocked\"")
                    && (text.contains("route")
                        || text.contains("routing")
                        || text.contains("routed")
                        || text.contains("\"status\":\"complete\"")
                        || text.contains("\"status\": \"complete\""))
            }
        case .erc:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_run_erc" else { return false }
                return verificationGatePassed(evidence, reportNeedle: "erc_report")
            }
        case .drc:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_run_drc" else { return false }
                return verificationGatePassed(evidence, reportNeedle: "drc_report")
            }
        case .simulation:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_run_spice"
                    || evidence.toolName == "kicad_evaluate_simulation"
                else { return false }
                let text = evidenceText(evidence)
                let rawText = rawEvidenceText(evidence)
                return text.contains("spice_measurements")
                    || text.contains("spice")
                    || hasExistingPathEvidence(in: rawText, extensions: ["log", "raw", "csv"])
            }
        case .fabrication:
            return pendingContinuationEvidence.contains { evidence in
                guard evidence.toolName == "kicad_export_fab"
                    || evidence.toolName == "kicad_package_release"
                else { return false }
                let text = evidenceText(evidence)
                let rawText = rawEvidenceText(evidence)
                return text.contains("gerber")
                    || text.contains("drill")
                    || text.contains("fabrication_package")
                    || hasExistingPathEvidence(in: rawText, extensions: ["gbr", "gbl", "gtl", "drl", "zip"])
            }
        case .bom:
            return pendingContinuationEvidence.contains { evidence in
                let text = evidenceText(evidence)
                let rawText = rawEvidenceText(evidence)
                guard evidence.toolName == "kicad_prepare_vendor_order"
                    || evidence.toolName == "kicad_export_fab"
                    || (isWorkflowTool(evidence.toolName) && text.contains("bom"))
                else { return false }
                return textContainsVendorBOMEvidence(text)
                    || extractedPaths(from: rawText).contains { pathContainsVendorBOMEvidence($0) }
            }
        case .electronicsTool:
            return pendingContinuationEvidence.contains { isKiCadTool($0.toolName) }
        case .generic:
            return false
        }
    }

    private func electronicsRequirement(for step: PlanStep) -> ElectronicsContinuationRequirement {
        let text = "\(step.description) \(step.proseSummary)".lowercased()
        return electronicsRequirement(forText: text)
    }

    private func electronicsRequirement(forText rawText: String) -> ElectronicsContinuationRequirement {
        let text = rawText.lowercased()
        if (text.contains("read") || text.contains("parse") || text.contains("inspect") || text.contains("load"))
            && (text.contains("spec") || text.contains("requirements")) {
            return .requirementsInspection
        }
        if text.contains("kicad_select_components")
            || text.contains("select_components")
            || text.contains("component selection")
            || text.contains("select component")
            || text.contains("select real-world component")
            || text.contains("select real world component")
            || text.contains("component catalog")
            || text.contains("component catalogs")
            || (text.contains("select") && text.contains("component") && text.contains("catalog"))
            || text.contains("matching circuitir specifications")
            || text.contains("component matrix") {
            return .componentSelection
        }
        if text.contains("kicad_assign_footprints")
            || text.contains("assign_footprints")
            || text.contains("footprint assignment")
            || text.contains("assign footprint")
            || text.contains("assign footprints")
            || text.contains("footprint_assignment") {
            return .footprintAssignment
        }
        if text.contains("circuit ir") || text.contains("circuit_ir") || text.contains("circuitir") {
            return .circuitIR
        }
        if text.contains("schematic")
            || text.contains("kicad_sch")
            || text.contains("kicad schematic")
            || text.contains("compile_project")
            || text.contains("compile project")
            || text.contains("compile kicad")
            || text.contains("create kicad project")
            || text.contains("initialize schematic")
            || text.contains("schematic and pcb") {
            return .schematic
        }
        if text.contains("bom") || text.contains("bill of materials")
            || text.contains("digikey") || text.contains("digi-key") || text.contains("mouser") {
            return .bom
        }
        if text.contains("spice") || text.contains("simulation") || text.contains("simulate") {
            return .simulation
        }
        if text.contains("erc") || text.contains("electrical rules") || text.contains("electrical rule") {
            return .erc
        }
        if text.contains("drc") || text.contains("design rules") || text.contains("design rule") {
            return .drc
        }
        if text.contains("gerber") || text.contains("drill") || text.contains("fabricat")
            || text.contains("fab ") || text.contains("cam") {
            return .fabrication
        }
        if text.contains("route") || text.contains("routing") || text.contains("autoroute")
            || text.contains("ratsnest") || text.contains("connectivity") {
            return .routing
        }
        if (text.contains("place") || text.contains("placement"))
            && (text.contains("component") || text.contains("footprint") || text.contains("pcb")) {
            return .placement
        }
        if text.contains("board profile") || text.contains("apply profile")
            || text.contains("fabricator profile") || text.contains("jlcpcb") {
            return .boardProfile
        }
        if text.contains("net class") || text.contains("net classes") || text.contains("netclass") {
            return .netClasses
        }
        if text.contains("kicad_approve_design_intent")
            || text.contains("approve_design_intent")
            || text.contains("review_and_approve_design_intent")
            || (text.contains("approve")
                && (text.contains("designintent")
                    || text.contains("design intent")
                    || text.contains("design-intent")
                    || text.contains("design_intent"))) {
            return .designIntentApproval
        }
        if text.contains("designintent") || text.contains("design intent")
            || text.contains("design-intent")
            || text.contains("kicad_build_intent_model")
            || text.contains("build_intent")
            || text.contains("intent model") {
            return .designIntent
        }
        if ["electronics", "amplifier", "class a", "class-a", "mains", "transformer"]
            .contains(where: { text.contains($0) }) {
            return .electronicsTool
        }
        return .generic
    }

    private func isKiCadTool(_ name: String) -> Bool {
        name.hasPrefix("kicad_")
            || name.hasPrefix("mcp:kicad:")
            || name == ElectronicsWorkflowRoute.requirementsToPCB.rawValue
            || name == ElectronicsWorkflowRoute.schematicToPCB.rawValue
    }

    private func isWorkflowTool(_ name: String) -> Bool {
        name == ElectronicsWorkflowRoute.requirementsToPCB.rawValue
            || name == ElectronicsWorkflowRoute.schematicToPCB.rawValue
    }

    private func electronicsToolResultBlocksContinuation(toolName: String, result: ToolResult, rawText: String) -> Bool {
        guard isKiCadTool(toolName) else { return false }
        if result.isError { return true }
        let text = rawText.lowercased()
        if toolName == "kicad_select_components",
           extractedPaths(from: rawText).contains(where: { path in
               let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
               guard name.contains("component_matrix") || name.contains("componentmatrix") else { return false }
               return ComponentMatrixEvidence.selectionState(atPath: path) != .complete
           }) {
            let hasRevisionNextAction = electronicsNextActions(inJSONText: rawText).contains { action in
                action == "revise_component_selection"
                    || action == "component_selection_revision"
                    || action == "kicad_revise_component_selection"
            } || text.contains("revise_component_selection")
                || text.contains("component_selection_revision")
                || text.contains("kicad_revise_component_selection")
            return !hasRevisionNextAction
        }
        return text.contains("blocked_verification_gate")
            || text.contains("\"status\":\"blocked\"")
            || text.contains("\"status\": \"blocked\"")
            || text.contains("\"status\":\"blocked_")
            || text.contains("\"status\": \"blocked_")
            || text.contains("blocked_artifact")
            || text.contains("blocked_footprints")
            || text.contains("blocked_input_quality")
            || text.contains("blocked_library")
            || text.contains("blocked_project_file")
            || text.contains("blocked_tooling")
            || text.contains("\"blockedreasons\":[\"")
            || text.contains("\"blockedreasons\": [\"")
            || text.contains("\"blocked_reasons\":[\"")
            || text.contains("\"blocked_reasons\": [\"")
    }

    private func electronicsRequirementsInspectionFailureBlocksContinuation(
        toolName: String,
        result: ToolResult
    ) -> Bool {
        guard result.isError,
              Self.electronicsReadOnlyInspectionToolNames.contains(toolName),
              let requirement = firstUnverifiedElectronicsRequirement()
        else { return false }
        if case .requirementsInspection = requirement {
            return true
        }
        return false
    }

    private func firstUnverifiedElectronicsRequirement() -> ElectronicsContinuationRequirement? {
        let planSteps = pendingContinuationAllSteps.isEmpty
            ? pendingContinuationSteps
            : pendingContinuationAllSteps
        guard !planSteps.isEmpty else { return nil }
        let verifiedCount = verifiedElectronicsCompletedPrefix(in: planSteps)
        guard verifiedCount < planSteps.count else { return nil }
        return electronicsRequirement(for: planSteps[verifiedCount])
    }

    private func blockingElectronicsToolFailure(
        calls: [ToolCall],
        results: [ToolResult]
    ) -> (toolName: String, content: String)? {
        guard electronicsWorkflowLockIsActive() else { return nil }
        let callsByID = Dictionary(uniqueKeysWithValues: calls.map { ($0.id, $0) })
        for result in results {
            guard let call = callsByID[result.toolCallId] else { continue }
            let toolName = call.function.name
            let rawText = "\(toolName) \(call.function.arguments) \(result.content)"
            guard electronicsToolResultBlocksContinuation(
                toolName: toolName,
                result: result,
                rawText: rawText
            ) else { continue }
            return (toolName, result.content)
        }
        return nil
    }

    private func evidenceText(_ evidence: ContinuationToolEvidence) -> String {
        rawEvidenceText(evidence).lowercased()
    }

    private func rawEvidenceText(_ evidence: ContinuationToolEvidence) -> String {
        "\(evidence.toolName) \(evidence.arguments) \(evidence.output)"
    }

    private func verificationGatePassed(_ evidence: ContinuationToolEvidence, reportNeedle: String) -> Bool {
        let text = evidenceText(evidence)
        guard !text.contains("\"status\":\"blocked\""),
              !text.contains("\"status\": \"blocked\""),
              !text.contains("blocked_verification_gate"),
              !text.contains("\"violations\":["),
              !text.contains("\"violations\": ["),
              !text.contains("repair_erc_from_diagnostics"),
              !text.contains("repair_drc_from_diagnostics")
        else { return false }

        return text.contains(reportNeedle)
            || text.contains("\"status\":\"complete\"")
            || text.contains("\"status\": \"complete\"")
            || text.contains("\"status\":\"pass\"")
            || text.contains("\"status\": \"pass\"")
            || text.contains("\"blocking_violations\":0")
            || text.contains("\"blocking_violations\": 0")
    }

    private func latestDesignIntentArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = designIntentArtifactPath(from: evidence) {
                return path
            }
        }
        return latestVerifiedDesignIntentArtifactPath
            ?? latestProjectElectronicsArtifactPath(kindNeedles: ["design_intent", "designintent"])
    }

    private func latestCircuitIRArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = circuitIRArtifactPath(from: evidence) {
                return path
            }
        }
        return latestVerifiedCircuitIRArtifactPath
            ?? latestProjectElectronicsArtifactPath(kindNeedles: ["circuit_ir", "circuitir"])
    }

    private func latestComponentMatrixArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = completeComponentMatrixArtifactPath(from: evidence) {
                return path
            }
        }
        if let path = latestVerifiedComponentMatrixArtifactPath,
           ComponentMatrixEvidence.isCompleteSelectionArtifact(atPath: path) {
            return path
        }
        guard let path = latestProjectElectronicsArtifactPath(kindNeedles: ["component_matrix", "componentmatrix"]),
              ComponentMatrixEvidence.isCompleteSelectionArtifact(atPath: path) else {
            return nil
        }
        return path
    }

    private func latestAnyComponentMatrixArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = componentMatrixArtifactPath(from: evidence) {
                return path
            }
        }
        if let path = latestProjectElectronicsArtifactPath(kindNeedles: ["component_matrix", "componentmatrix"]) {
            return path
        }
        return latestVerifiedComponentMatrixArtifactPath
    }

    private func latestFootprintAssignmentArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = footprintAssignmentArtifactPath(from: evidence) {
                return path
            }
        }
        return latestVerifiedFootprintAssignmentArtifactPath
            ?? latestProjectElectronicsArtifactPath(kindNeedles: ["footprint_assignment", "footprintassignment"])
    }

    private func latestProjectElectronicsArtifactPath(kindNeedles: [String]) -> String? {
        guard let currentProjectPath else { return nil }
        let artifactDirectory = URL(fileURLWithPath: currentProjectPath)
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: artifactDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return files
            .compactMap { url -> (URL, Date)? in
                let name = url.lastPathComponent.lowercased()
                guard kindNeedles.contains(where: { name.contains($0) }) else { return nil }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
            .path
    }

    private func latestKiCadProjectArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = artifactPath(
                from: evidence,
                directKeys: ["project_path", "projectPath", "kicad_project_path", "kicadProjectPath"],
                kindNeedles: ["kicad_project", "project"],
                pathNeedles: [".kicad_pro"]
            ) {
                return path
            }
        }
        return nil
    }

    private func latestSimulationScenarioArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = artifactPath(
                from: evidence,
                directKeys: ["simulation_scenario_path", "simulationScenarioPath", "scenario_path", "scenarioPath"],
                kindNeedles: ["simulation_scenario", "scenario"],
                pathNeedles: [".cir", ".sp"]
            ) {
                return path
            }
        }
        return nil
    }

    private func latestBOMArtifactPath() -> String? {
        for evidence in pendingContinuationEvidence.reversed() {
            if let path = artifactPath(
                from: evidence,
                directKeys: ["normalized_bom_path", "normalizedBOMPath", "bom_path", "bomPath"],
                kindNeedles: ["normalized_bom", "bom"],
                pathNeedles: ["bom"]
            ),
               pathContainsVendorBOMEvidence(path) {
                return path
            }
        }
        return nil
    }

    private func electronicsKiCadOutputDirectoryPath() -> String {
        if let currentProjectPath, currentProjectPath.isEmpty == false {
            return URL(fileURLWithPath: currentProjectPath, isDirectory: true)
                .appendingPathComponent("kicad", isDirectory: true)
                .path
        }
        for artifactPath in [
            latestDesignIntentArtifactPath(),
            latestCircuitIRArtifactPath(),
            latestComponentMatrixArtifactPath(),
            latestFootprintAssignmentArtifactPath(),
        ].compactMap({ $0 }) {
            if let range = artifactPath.range(of: "/.merlin/", options: .backwards) {
                let rootPath = String(artifactPath[..<range.lowerBound])
                if rootPath.isEmpty == false {
                    return URL(fileURLWithPath: rootPath, isDirectory: true)
                        .appendingPathComponent("kicad", isDirectory: true)
                        .path
                }
            }
        }
        return FileManager.default.currentDirectoryPath + "/kicad"
    }

    private func electronicsFabricationOutputDirectoryPath() -> String {
        if let currentProjectPath, currentProjectPath.isEmpty == false {
            return URL(fileURLWithPath: currentProjectPath, isDirectory: true)
                .appendingPathComponent("fab", isDirectory: true)
                .path
        }
        for artifactPath in [latestKiCadProjectArtifactPath(), latestBOMArtifactPath()].compactMap({ $0 }) {
            if let range = artifactPath.range(of: "/.merlin/", options: .backwards) {
                let rootPath = String(artifactPath[..<range.lowerBound])
                if rootPath.isEmpty == false {
                    return URL(fileURLWithPath: rootPath, isDirectory: true)
                        .appendingPathComponent("fab", isDirectory: true)
                        .path
                }
            }
        }
        return FileManager.default.currentDirectoryPath + "/fab"
    }

    private func designIntentArtifactPath(from evidence: ContinuationToolEvidence) -> String? {
        let rawText = rawEvidenceText(evidence)
        if let path = designIntentArtifactPath(fromJSONText: evidence.output) {
            return path
        }
        if let path = designIntentArtifactPath(fromJSONText: evidence.arguments) {
            return path
        }
        if rawText.lowercased().contains("design_intent"),
           let path = extractedArtifactPaths(from: rawText).first(where: {
               $0.lowercased().contains("design_intent") || $0.lowercased().contains("designintent")
           }) {
            return path
        }
        return nil
    }

    private func designIntentArtifactPath(fromJSONText text: String) -> String? {
        guard let json = jsonObjectFromToolText(text) else { return nil }
        return designIntentArtifactPath(fromJSONObject: json)
    }

    private func designIntentArtifactPath(fromJSONObject json: Any) -> String? {
        if let dictionary = json as? [String: Any] {
            if let direct = dictionary["design_intent_path"] as? String, !direct.isEmpty {
                return direct
            }
            if let direct = dictionary["designIntentPath"] as? String, !direct.isEmpty {
                return direct
            }
            if let artifact = dictionary["artifact"],
               let path = designIntentArtifactPath(fromArtifactObject: artifact) {
                return path
            }
            if let artifacts = dictionary["artifacts"] as? [Any] {
                for artifact in artifacts {
                    if let path = designIntentArtifactPath(fromArtifactObject: artifact) {
                        return path
                    }
                }
            }
            for value in dictionary.values {
                if let path = designIntentArtifactPath(fromJSONObject: value) {
                    return path
                }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let path = designIntentArtifactPath(fromJSONObject: value) {
                    return path
                }
            }
        }
        return nil
    }

    private func designIntentArtifactPath(fromArtifactObject artifact: Any) -> String? {
        guard let dictionary = artifact as? [String: Any] else { return nil }
        let kind = (dictionary["kind"] as? String ?? dictionary["type"] as? String ?? "")
            .lowercased()
        guard kind.contains("design_intent") || kind.contains("designintent") else { return nil }
        if let path = dictionary["path"] as? String, !path.isEmpty {
            return path
        }
        if let url = dictionary["url"] as? String, !url.isEmpty {
            return URL(string: url)?.path ?? url
        }
        return nil
    }

    private func circuitIRArtifactPath(from evidence: ContinuationToolEvidence) -> String? {
        let rawText = rawEvidenceText(evidence)
        if let path = circuitIRArtifactPath(fromJSONText: evidence.output) {
            return path
        }
        if let path = circuitIRArtifactPath(fromJSONText: evidence.arguments) {
            return path
        }
        if rawText.lowercased().contains("circuit_ir"),
           let path = extractedArtifactPaths(from: rawText).first(where: {
               $0.lowercased().contains("circuit_ir") || $0.lowercased().contains("circuitir")
           }) {
            return path
        }
        return nil
    }

    private func circuitIRArtifactPath(fromJSONText text: String) -> String? {
        guard let json = jsonObjectFromToolText(text) else { return nil }
        return circuitIRArtifactPath(fromJSONObject: json)
    }

    private func circuitIRArtifactPath(fromJSONObject json: Any) -> String? {
        if let dictionary = json as? [String: Any] {
            if let direct = dictionary["circuit_ir_path"] as? String, !direct.isEmpty {
                return direct
            }
            if let direct = dictionary["circuitIRPath"] as? String, !direct.isEmpty {
                return direct
            }
            if let artifact = dictionary["artifact"],
               let path = circuitIRArtifactPath(fromArtifactObject: artifact) {
                return path
            }
            if let artifacts = dictionary["artifacts"] as? [Any] {
                for artifact in artifacts {
                    if let path = circuitIRArtifactPath(fromArtifactObject: artifact) {
                        return path
                    }
                }
            }
            for value in dictionary.values {
                if let path = circuitIRArtifactPath(fromJSONObject: value) {
                    return path
                }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let path = circuitIRArtifactPath(fromJSONObject: value) {
                    return path
                }
            }
        }
        return nil
    }

    private func circuitIRArtifactPath(fromArtifactObject artifact: Any) -> String? {
        guard let dictionary = artifact as? [String: Any] else { return nil }
        let kind = (dictionary["kind"] as? String ?? dictionary["type"] as? String ?? "")
            .lowercased()
        guard kind.contains("circuit_ir") || kind.contains("circuitir") else { return nil }
        if let path = dictionary["path"] as? String, !path.isEmpty {
            return path
        }
        if let url = dictionary["url"] as? String, !url.isEmpty {
            return URL(string: url)?.path ?? url
        }
        return nil
    }

    private func componentMatrixArtifactPath(from evidence: ContinuationToolEvidence) -> String? {
        artifactPath(
            from: evidence,
            directKeys: ["component_matrix_path", "componentMatrixPath"],
            kindNeedles: ["component_matrix", "componentmatrix"],
            pathNeedles: ["component_matrix", "componentmatrix"]
        )
    }

    private func completeComponentMatrixArtifactPath(from evidence: ContinuationToolEvidence) -> String? {
        guard let path = componentMatrixArtifactPath(from: evidence),
              ComponentMatrixEvidence.isCompleteSelectionArtifact(atPath: path) else {
            return nil
        }
        return path
    }

    private func footprintAssignmentArtifactPath(from evidence: ContinuationToolEvidence) -> String? {
        artifactPath(
            from: evidence,
            directKeys: ["footprint_assignment_path", "footprintAssignmentPath"],
            kindNeedles: ["footprint_assignment", "footprintassignment"],
            pathNeedles: ["footprint_assignment", "footprintassignment"]
        )
    }

    private func artifactPath(
        from evidence: ContinuationToolEvidence,
        directKeys: [String],
        kindNeedles: [String],
        pathNeedles: [String]
    ) -> String? {
        if let path = artifactPath(fromJSONText: evidence.output, directKeys: directKeys, kindNeedles: kindNeedles) {
            return path
        }
        if let path = artifactPath(fromJSONText: evidence.arguments, directKeys: directKeys, kindNeedles: kindNeedles) {
            return path
        }
        let rawText = rawEvidenceText(evidence)
        let lowerRawText = rawText.lowercased()
        if kindNeedles.contains(where: { lowerRawText.contains($0) }),
           let path = extractedArtifactPaths(from: rawText).first(where: { path in
               let lowerPath = path.lowercased()
               return pathNeedles.contains { lowerPath.contains($0) }
           }) {
            return path
        }
        return nil
    }

    private func artifactPath(
        fromJSONText text: String,
        directKeys: [String],
        kindNeedles: [String]
    ) -> String? {
        guard let json = jsonObjectFromToolText(text) else { return nil }
        return artifactPath(fromJSONObject: json, directKeys: directKeys, kindNeedles: kindNeedles)
    }

    private func artifactPath(
        fromJSONObject json: Any,
        directKeys: [String],
        kindNeedles: [String]
    ) -> String? {
        if let dictionary = json as? [String: Any] {
            for key in directKeys {
                if let direct = dictionary[key] as? String, !direct.isEmpty {
                    return direct
                }
            }
            if let artifact = dictionary["artifact"],
               let path = artifactPath(fromArtifactObject: artifact, kindNeedles: kindNeedles) {
                return path
            }
            if let artifacts = dictionary["artifacts"] as? [Any] {
                for artifact in artifacts {
                    if let path = artifactPath(fromArtifactObject: artifact, kindNeedles: kindNeedles) {
                        return path
                    }
                }
            }
            for value in dictionary.values {
                if let path = artifactPath(fromJSONObject: value, directKeys: directKeys, kindNeedles: kindNeedles) {
                    return path
                }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let path = artifactPath(fromJSONObject: value, directKeys: directKeys, kindNeedles: kindNeedles) {
                    return path
                }
            }
        }
        return nil
    }

    private func artifactPath(fromArtifactObject artifact: Any, kindNeedles: [String]) -> String? {
        guard let dictionary = artifact as? [String: Any] else { return nil }
        let kind = (dictionary["kind"] as? String ?? dictionary["type"] as? String ?? "")
            .lowercased()
        guard kindNeedles.contains(where: { kind.contains($0) }) else { return nil }
        if let path = dictionary["path"] as? String, !path.isEmpty {
            return path
        }
        if let url = dictionary["url"] as? String, !url.isEmpty {
            return URL(string: url)?.path ?? url
        }
        return nil
    }

    private func textContainsVendorBOMEvidence(_ text: String) -> Bool {
        text.contains("digikey")
            || text.contains("digi-key")
            || text.contains("mouser")
            || text.contains("mpn")
            || text.contains("manufacturer_part")
            || text.contains("vendor_part")
    }

    private func pathContainsVendorBOMEvidence(_ path: String) -> Bool {
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        guard fileName.contains("bom"),
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return false }
        return textContainsVendorBOMEvidence(text.lowercased())
    }

    private func hasExistingPathEvidence(in text: String, extensions: Set<String>) -> Bool {
        extractedPaths(from: text).contains { path in
            let url = URL(fileURLWithPath: path)
            if extensions.contains(url.pathExtension.lowercased()),
               FileManager.default.fileExists(atPath: path) {
                return true
            }
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let entries = try? FileManager.default.contentsOfDirectory(atPath: path)
            else { return false }
            return entries.contains { entry in
                extensions.contains(URL(fileURLWithPath: entry).pathExtension.lowercased())
            }
        }
    }

    private func extractedPaths(from text: String) -> [String] {
        let pattern = #"/[A-Za-z0-9_\-./ ]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[swiftRange])
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:)}]\"'"))
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func extractedArtifactPaths(from text: String) -> [String] {
        let pattern = #"/[^\s,;:)}\]\"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[swiftRange])
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)}]\"'"))
            guard !trimmed.isEmpty else { return nil }
            return trimmed
        }
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

    private func shouldStopAfterPostToolVerification(
        calls: [ToolCall],
        results: [ToolResult],
        context: ContextManager,
        domain: any DomainPlugin,
        writtenFiles: [String],
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async -> Bool {
        guard AppSettings.shared.criticEnabled else { return false }
        guard hasSuccessfulVerificationResult(calls: calls, results: results) else { return false }
        let hasAvailableCritic = criticOverride != nil || {
            if let p = self.provider(for: .reason), !(p is NullProvider) { return true }
            return false
        }()
        guard hasAvailableCritic else { return false }

        let critic = makeCritic(domain: domain)
        let taskType = domain.taskTypes.first
            ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
        let verificationOutput = results
            .filter { !$0.isError }
            .map(\.content)
            .joined(separator: "\n\n")
        let verdict = await critic.evaluate(
            taskType: taskType,
            output: verificationOutput,
            context: context.messages,
            writtenFiles: writtenFiles
        )
        lastCriticVerdict = verdict
        switch verdict {
        case .pass:
            continuation.yield(.systemNote(
                "[verification passed after tool result - stopping]"
            ))
            return true
        case .fail, .skipped:
            return false
        }
    }

    private func hasSuccessfulVerificationResult(calls: [ToolCall], results: [ToolResult]) -> Bool {
        let callsByID = Dictionary(uniqueKeysWithValues: calls.map { ($0.id, $0) })
        for result in results where !result.isError {
            guard let call = callsByID[result.toolCallId] else { continue }
            let name = call.function.name.lowercased()
            let args = call.function.arguments.lowercased()
            let output = result.content.lowercased()
            let isVerificationTool = name == "xcode_test"
                || name == "swift_test"
                || name == "cargo_test"
                || ((name == "run_shell" || name == "bash")
                    && ((args.contains("xcodebuild") && args.contains(" test"))
                        || args.contains("cargo test")
                        || args.contains("swift test")))
            guard isVerificationTool else { continue }
            if output.contains("test succeeded")
                || output.contains("tests passed")
                || (output.contains("test suite") && output.contains("passed"))
                || (output.contains("executed") && output.contains("0 failures"))
                || output.contains("test result: ok")
                || (output.contains("0 failed") && output.contains("passed")) {
                return true
            }
        }
        return false
    }

    private func hasTerminalElectronicsWorkflowCompletion(calls: [ToolCall], results: [ToolResult]) -> Bool {
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID) else { return false }
        let callsByID = Dictionary(uniqueKeysWithValues: calls.map { ($0.id, $0) })
        for result in results where !result.isError {
            guard let call = callsByID[result.toolCallId],
                  call.function.name == ElectronicsWorkflowRoute.requirementsToPCB.rawValue
                    || call.function.name == ElectronicsWorkflowRoute.schematicToPCB.rawValue
            else { continue }
            if isCompleteElectronicsWorkflowReport(result.content) {
                return true
            }
        }
        return false
    }

    private func hasSatisfiedRequestedStopBoundary(
        originalTask: String,
        calls: [ToolCall],
        results: [ToolResult]
    ) -> Bool {
        guard requestedStopBoundaryIsPresent(in: originalTask) else { return false }
        let callsByID = Dictionary(uniqueKeysWithValues: calls.map { ($0.id, $0) })
        for result in results where !result.isError {
            guard let call = callsByID[result.toolCallId] else { continue }
            if requestedStopBoundary(in: originalTask, matchesToolNamed: call.function.name) {
                return true
            }
        }
        return false
    }

    private func requestedStopBoundaryIsPresent(in task: String) -> Bool {
        let lower = task.lowercased()
        return lower.contains("stop after")
            || lower.contains("stop immediately after")
            || lower.contains("stop once")
            || lower.contains("stop when")
            || lower.contains("stop at")
    }

    private func requestedStopBoundary(in task: String, matchesToolNamed toolName: String) -> Bool {
        let lower = task.lowercased()
        let stopPhrases = ["stop immediately after", "stop after", "stop once", "stop when", "stop at"]
        let stopWindows = stopPhrases.flatMap { phrase -> [Substring] in
            var windows: [Substring] = []
            var searchStart = lower.startIndex
            while let range = lower.range(of: phrase, range: searchStart..<lower.endIndex) {
                let end = lower.index(range.lowerBound, offsetBy: 320, limitedBy: lower.endIndex) ?? lower.endIndex
                windows.append(lower[range.lowerBound..<end])
                searchStart = range.upperBound
            }
            return windows
        }
        guard !stopWindows.isEmpty else { return false }

        if requestedDesignProducingStopBoundary(in: stopWindows) {
            return isDesignProducingElectronicsTool(toolName)
        }

        if isKiCadTool(toolName),
           stopWindows.contains(where: { window in
               (window.contains("kicad") || window.contains("electronics"))
                   && (window.contains("tool") || window.contains("plugin") || window.contains("invocation"))
           }) {
            return true
        }

        let aliases = stopBoundaryAliases(for: toolName)
        return stopWindows.contains { window in
            aliases.contains { alias in
                guard alias.count >= 4 else { return false }
                return window.contains(alias)
            }
        }
    }

    private func requestedDesignProducingStopBoundary(in stopWindows: [Substring]) -> Bool {
        stopWindows.contains { window in
            window.contains("design-producing")
                || window.contains("design producing")
                || window.contains("design generation")
                || window.contains("first design")
                || window.contains("intent/model")
                || window.contains("intent model")
                || window.contains("circuit ir")
                || window.contains("component selection")
                || window.contains("pcb workflow")
        }
    }

    private func isDesignProducingElectronicsTool(_ name: String) -> Bool {
        let normalized = name
            .replacingOccurrences(of: "mcp:kicad:", with: "")
            .lowercased()
        return [
            "kicad_ingest_schematic",
            "kicad_build_intent_model",
            "kicad_generate_circuit_ir",
            "kicad_select_components",
            "kicad_revise_component_selection",
            "kicad_prepare_libraries",
            "kicad_assign_footprints",
            "kicad_compile_project",
            "kicad_apply_board_profile",
            "kicad_generate_net_classes",
            "kicad_place_components",
            "kicad_route_pass",
            ElectronicsWorkflowRoute.requirementsToPCB.rawValue,
            ElectronicsWorkflowRoute.schematicToPCB.rawValue,
        ].contains(normalized)
    }

    private func stopBoundaryAliases(for toolName: String) -> Set<String> {
        let lower = toolName.lowercased()
        let spaced = lower.replacingOccurrences(of: "_", with: " ")
        var aliases: Set<String> = [lower, spaced]

        let words = spaced
            .split(separator: " ")
            .map(String.init)
            .filter { word in
                ![
                    "kicad", "workflow", "generate", "build", "create", "run",
                    "export", "prepare", "approve", "select", "assign"
                ].contains(word)
            }
        if !words.isEmpty {
            aliases.insert(words.joined(separator: " "))
        }
        if words.count > 1 {
            aliases.insert(words.suffix(2).joined(separator: " "))
        }
        return aliases
    }

    private func shouldForceElectronicsToolInvocation(
        originalTask: String,
        responseText: String
    ) -> Bool {
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID),
              requestedStopBoundaryIsPresent(in: originalTask),
              originalTask.lowercased().contains("first"),
              originalTask.lowercased().contains("tool")
                || originalTask.lowercased().contains("plugin")
                || originalTask.lowercased().contains("kicad"),
              !pendingContinuationEvidence.contains(where: {
                  requestedStopBoundary(in: originalTask, matchesToolNamed: $0.toolName)
              })
        else { return false }

        let available = availableElectronicsToolNamesForCorrection()
        guard !available.isEmpty else { return false }

        let lowerResponse = responseText.lowercased()
        return lowerResponse.contains("cannot")
            || lowerResponse.contains("blocker")
            || lowerResponse.contains("would require")
            || lowerResponse.contains("would occur")
            || lowerResponse.contains("first actual")
            || pendingContinuationEvidence.contains { evidence in
                Self.electronicsReadOnlyInspectionToolNames.contains(evidence.toolName)
            }
    }

    private func shouldForceElectronicsToolInvocationForEvidenceGate() -> Bool {
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID),
              pendingContinuationUsesEvidenceGate,
              pendingContinuationBlockedReason == nil,
              hasVerifiedRequirementsInspectionEvidence()
        else { return false }

        let planSteps = pendingContinuationAllSteps.isEmpty
            ? pendingContinuationSteps
            : pendingContinuationAllSteps
        guard !planSteps.isEmpty else { return false }

        let verifiedCount = verifiedElectronicsCompletedPrefix(in: planSteps)
        guard verifiedCount < planSteps.count else { return false }

        switch electronicsRequirement(for: planSteps[verifiedCount]) {
        case .designIntent, .designIntentApproval, .circuitIR, .componentSelection,
             .footprintAssignment, .schematic, .boardProfile, .netClasses,
             .placement, .routing, .erc, .drc, .simulation, .fabrication,
             .bom, .electronicsTool:
            return true
        case .requirementsInspection, .generic:
            return false
        }
    }

    private func availableElectronicsToolNamesForCorrection() -> [String] {
        offeredTools()
            .map(\.function.name)
            .filter { isKiCadTool($0) }
            .sorted()
    }

    private func isCompleteElectronicsWorkflowReport(_ content: String) -> Bool {
        guard let object = jsonObjectFromToolText(content) as? [String: Any],
              let status = object["status"] as? String,
              status == KiCadStatus.complete.rawValue
        else { return false }

        let blockedReasons = (object["blockedReasons"] as? [Any])
            ?? (object["blocked_reasons"] as? [Any])
            ?? []
        guard blockedReasons.isEmpty else { return false }

        let artifacts = object["artifacts"] as? [Any] ?? []
        let gates = object["gates"] as? [Any] ?? []
        return !artifacts.isEmpty && !gates.isEmpty
    }

    private func authoritativeElectronicsWorkflowCalls(from calls: [ToolCall]) -> [ToolCall] {
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID),
              let workflow = calls.first(where: {
                  $0.function.name == ElectronicsWorkflowRoute.requirementsToPCB.rawValue
                      || $0.function.name == ElectronicsWorkflowRoute.schematicToPCB.rawValue
              })
        else { return calls }
        return [workflow]
    }

    private func electronicsWorkflowLockBlockedCalls(in calls: [ToolCall]) -> [ToolCall]? {
        guard electronicsWorkflowLockIsActive() else { return nil }
        return calls.filter { !isAllowedDuringElectronicsWorkflowLock($0) }
    }

    private func electronicsWorkflowLockIsActive() -> Bool {
        forcedElectronicsWorkflowLock || activeDomainIDs.contains(ElectronicsDomain.defaultID)
    }

    private func toolDomainIDsForCurrentTurn() -> [String] {
        guard forcedElectronicsWorkflowLock,
              activeDomainIDs.contains(ElectronicsDomain.defaultID) == false else {
            return activeDomainIDs
        }
        var ids = activeDomainIDs
        ids.append(ElectronicsDomain.defaultID)
        return ids
    }

    private func isAllowedDuringElectronicsWorkflowLock(_ call: ToolCall) -> Bool {
        let toolName = call.function.name
        return isAllowedDuringElectronicsWorkflowLock(toolName: toolName)
            || isStructuredEvidenceWorkflowCall(call)
    }

    private func isAllowedDuringElectronicsWorkflowLock(toolName: String) -> Bool {
        Self.electronicsReadOnlyInspectionToolNames.contains(toolName)
            || toolName.hasPrefix("kicad_")
            || toolName.hasPrefix("mcp:kicad:")
            || toolName == "verify.electronics"
    }

    private func isStructuredEvidenceWorkflowCall(_ call: ToolCall) -> Bool {
        guard call.function.name == ElectronicsWorkflowRoute.requirementsToPCB.rawValue
            || call.function.name == ElectronicsWorkflowRoute.schematicToPCB.rawValue
        else { return false }

        let input = inputDictionary(from: call.function.arguments)
        let evidenceKeys = [
            "evidence",
            "evidence_artifacts",
            "design_intent_path",
            "circuit_ir_path",
            "schematic_path",
            "pcb_path",
            "erc_report_path",
            "drc_report_path",
            "spice_measurements_path",
            "bom_path",
        ]
        return evidenceKeys.contains { key in
            guard let value = input[key] else { return false }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func electronicsWorkflowLockRejection(for call: ToolCall) -> ToolResult {
        ToolResult(
            toolCallId: call.id,
            content: "`\(call.function.name)` is not approved while the electronics workflow lock is active. "
                + "Use read_file/list_directory/search_files for inspection and `kicad_*` tools for "
                + "DesignIntent, Circuit IR, schematic, SPICE, fabrication, BOM, and verification work. "
                + "Workflow completion routes require structured artifact/evidence paths and cannot run from requirements text alone. "
                + "Automatic continuation stopped so the workflow cannot advance from narrative drift.",
            isError: true
        )
    }

    private func requiredElectronicsHandoffToolName() -> String? {
        guard electronicsWorkflowLockIsActive(),
              pendingContinuationUsesEvidenceGate,
              pendingContinuationBlockedReason == nil
        else { return nil }

        guard hasVerifiedRequirementsInspectionEvidence() else { return nil }

        let planSteps = pendingContinuationAllSteps.isEmpty
            ? pendingContinuationSteps
            : pendingContinuationAllSteps
        let requirements = planSteps.map { electronicsRequirement(for: $0) }
        let needsDesignIntent = requirements.contains { requirement in
            if case .designIntent = requirement { return true }
            return false
        }
        let needsDownstreamDesignArtifact = requirements.contains { requirement in
            switch requirement {
            case .designIntent, .designIntentApproval, .circuitIR, .componentSelection,
                 .footprintAssignment, .schematic, .boardProfile, .netClasses, .placement,
                 .routing, .erc, .drc, .simulation, .fabrication, .bom:
                return true
            default:
                return false
            }
        }
        let originalRequestsBuildIntent = explicitFocusedElectronicsToolName(
            for: pendingContinuationOriginalTask,
            steps: []
        ) == "kicad_build_intent_model"
        if latestDesignIntentArtifactPath() == nil,
           latestFocusedElectronicsHandoffToolName == "kicad_build_intent_model" {
            return "kicad_build_intent_model"
        }
        if latestDesignIntentArtifactPath() == nil,
           needsDownstreamDesignArtifact || needsDesignIntent || originalRequestsBuildIntent {
            return "kicad_build_intent_model"
        }

        if let nextTool = nextFocusedElectronicsHandoffToolName() {
            return nextTool
        }

        guard latestDesignIntentArtifactPath() == nil else { return nil }

        let requestedToolName = explicitFocusedElectronicsToolName(
            for: pendingContinuationOriginalTask,
            steps: pendingContinuationAllSteps.isEmpty ? pendingContinuationSteps : pendingContinuationAllSteps
        )
        guard requestedToolName == "kicad_build_intent_model",
              !electronicsStepVerified(PlanStep(
                  description: "Build DesignIntent",
                  successCriteria: "DesignIntent artifact exists",
                  complexity: .standard
              ))
        else { return nil }

        return "kicad_build_intent_model"
    }

    private func hasVerifiedRequirementsInspectionEvidence() -> Bool {
        pendingContinuationEvidence.contains { evidence in
            Self.electronicsReadOnlyInspectionToolNames.contains(evidence.toolName)
        }
    }

    private func electronicsRequiredHandoffRejection(
        for call: ToolCall,
        requiredToolName: String
    ) -> ToolResult {
        ToolResult(
            toolCallId: call.id,
            content: "`\(call.function.name)` cannot satisfy this electronics continuation. "
                + "The next verified handoff must be `\(requiredToolName)`. "
                + "Read-only inspection and toolchain/version checks do not complete artifact-producing electronics steps. "
                + "Automatic continuation will retry the exact required tool boundary.",
            isError: true
        )
    }

    private func electronicsHandoffDriftBlockedCalls(in calls: [ToolCall]) -> [ToolCall]? {
        guard electronicsWorkflowLockIsActive(),
              latestDesignIntentArtifactPath() != nil
        else { return nil }
        return calls.filter { call in
            if call.function.name == "kicad_build_intent_model" {
                return true
            }
            guard Self.electronicsReadOnlyInspectionToolNames.contains(call.function.name) else {
                return false
            }
            let input = inputDictionary(from: call.function.arguments)
            let inspectedText = input.values.joined(separator: " ").lowercased()
            return inspectedText.contains("spec.md")
                || inspectedText.contains("/spec")
                || inspectedText.contains("requirements")
        }
    }

    private func electronicsHandoffDriftRejection(for call: ToolCall) -> ToolResult {
        let designIntentPath = latestDesignIntentArtifactPath() ?? "<existing DesignIntent artifact>"
        let requestedToolName = explicitFocusedElectronicsToolName(
            for: pendingContinuationOriginalTask,
            steps: pendingContinuationAllSteps.isEmpty ? pendingContinuationSteps : pendingContinuationAllSteps
        )
        let continuationInstruction: String
        if let requestedToolName {
            continuationInstruction = "Continue the verified handoff by calling `\(requestedToolName)` with the required artifact paths and structured arguments for that tool."
        } else {
            continuationInstruction = "Continue the verified handoff by calling `kicad_approve_design_intent` with `design_intent_path` set to that path, or `kicad_generate_circuit_ir` with the same `design_intent_path` after approval."
        }
        return ToolResult(
            toolCallId: call.id,
            content: "`\(call.function.name)` cannot be used for this electronics continuation because "
                + "a DesignIntent artifact already exists at \(designIntentPath). Do not reread the original "
                + "spec or rebuild DesignIntent. \(continuationInstruction) "
                + "Automatic continuation stopped so the workflow cannot falsely advance.",
            isError: true
        )
    }

    private func redirectedElectronicsHandoffCalls(from calls: [ToolCall]) -> [ToolCall] {
        calls.map { call in
            normalizedFocusedElectronicsHandoffCall(for: call)
                ?? redirectedElectronicsHandoffCall(for: call)
                ?? call
        }
    }

    private func normalizedFocusedElectronicsHandoffCall(for call: ToolCall) -> ToolCall? {
        guard electronicsWorkflowLockIsActive(),
              let designIntentPath = latestDesignIntentArtifactPath(),
              let nextToolName = expectedFocusedElectronicsHandoffToolName(),
              call.function.name == nextToolName
        else { return nil }
        if let requestedToolName = explicitFocusedElectronicsToolName(
            for: pendingContinuationOriginalTask,
            steps: pendingContinuationAllSteps.isEmpty ? pendingContinuationSteps : pendingContinuationAllSteps
        ), requestedToolName != nextToolName {
            return nil
        }
        guard let argumentObject = focusedElectronicsHandoffArguments(
            for: nextToolName,
            designIntentPath: designIntentPath,
            baseArguments: call.function.arguments
        ) else { return nil }
        return electronicsHandoffToolCall(from: call, toolName: nextToolName, arguments: argumentObject)
    }

    private func redirectedElectronicsHandoffCall(for call: ToolCall) -> ToolCall? {
        guard electronicsWorkflowLockIsActive(),
              Self.electronicsReadOnlyInspectionToolNames.contains(call.function.name),
              let designIntentPath = latestDesignIntentArtifactPath(),
              let nextToolName = expectedFocusedElectronicsHandoffToolName()
        else { return nil }
        if let requestedToolName = explicitFocusedElectronicsToolName(
            for: pendingContinuationOriginalTask,
            steps: pendingContinuationAllSteps.isEmpty ? pendingContinuationSteps : pendingContinuationAllSteps
        ), requestedToolName != nextToolName {
            return nil
        }

        let input = inputDictionary(from: call.function.arguments)
        let inspectedText = input.values.joined(separator: " ").lowercased()
        guard inspectedText.contains("spec.md")
            || inspectedText.contains("/spec")
            || inspectedText.contains("requirements")
        else { return nil }

        guard let argumentObject = focusedElectronicsHandoffArguments(
            for: nextToolName,
            designIntentPath: designIntentPath,
            baseArguments: "{}"
        ) else { return nil }
        return electronicsHandoffToolCall(from: call, toolName: nextToolName, arguments: argumentObject)
    }

    private func focusedElectronicsHandoffArguments(
        for nextToolName: String,
        designIntentPath: String,
        baseArguments: String
    ) -> [String: Any]? {
        var argumentObject = jsonArgumentObject(from: baseArguments)
        argumentObject["design_intent_path"] = designIntentPath
        if nextToolName == "kicad_select_components",
           let circuitIRPath = latestCircuitIRArtifactPath() {
            argumentObject["circuit_ir_path"] = circuitIRPath
            argumentObject["live_catalog_providers"] = ["mouser", "digikey"]
            argumentObject["live_catalog_result_limit"] = 3
        }
        if nextToolName == "kicad_revise_component_selection",
           let componentMatrixPath = latestAnyComponentMatrixArtifactPath() {
            argumentObject["component_matrix_path"] = componentMatrixPath
            argumentObject["live_catalog_providers"] = ["mouser", "digikey"]
            argumentObject["live_catalog_result_limit"] = 3
            if let circuitIRPath = latestCircuitIRArtifactPath() {
                argumentObject["circuit_ir_path"] = circuitIRPath
            }
        }
        if nextToolName == "kicad_compile_project",
           let circuitIRPath = latestCircuitIRArtifactPath(),
           let componentMatrixPath = latestComponentMatrixArtifactPath(),
           let footprintAssignmentPath = latestFootprintAssignmentArtifactPath() {
            argumentObject["circuit_ir_path"] = circuitIRPath
            argumentObject["component_matrix_path"] = componentMatrixPath
            argumentObject["footprint_assignment_path"] = footprintAssignmentPath
            if (argumentObject["output_directory"] as? String)?.isEmpty ?? true {
                argumentObject["output_directory"] = electronicsKiCadOutputDirectoryPath()
            }
        }
        if nextToolName == "kicad_assign_footprints",
           let circuitIRPath = latestCircuitIRArtifactPath(),
           let componentMatrixPath = latestComponentMatrixArtifactPath() {
            argumentObject["circuit_ir_path"] = circuitIRPath
            argumentObject["component_matrix_path"] = componentMatrixPath
        }
        if ["kicad_apply_board_profile", "kicad_place_components", "kicad_route_pass",
            "kicad_run_erc", "kicad_run_drc", "kicad_export_fab"].contains(nextToolName),
           let projectPath = latestKiCadProjectArtifactPath() {
            argumentObject["project_path"] = projectPath
        }
        if nextToolName == "kicad_apply_board_profile" {
            argumentObject["fabricator_profile_id"] = argumentObject["fabricator_profile_id"] as? String ?? "jlcpcb_2layer_default"
        }
        if nextToolName == "kicad_generate_net_classes" {
            argumentObject["design_intent_path"] = designIntentPath
        }
        if nextToolName == "kicad_export_fab" {
            argumentObject["output_directory"] = argumentObject["output_directory"] as? String ?? electronicsFabricationOutputDirectoryPath()
            argumentObject["fabricator_profile_id"] = argumentObject["fabricator_profile_id"] as? String ?? "jlcpcb_2layer_default"
        }
        if nextToolName == "kicad_prepare_vendor_order",
           let bomPath = latestBOMArtifactPath() {
            argumentObject["normalized_bom_path"] = bomPath
            argumentObject["vendor_id"] = argumentObject["vendor_id"] as? String ?? "Digi-Key"
            argumentObject["quantity"] = argumentObject["quantity"] as? Int ?? 1
        }
        if nextToolName == "kicad_generate_spice_scenario",
           let projectPath = latestKiCadProjectArtifactPath() {
            argumentObject["project_path"] = projectPath
            if let circuitIRPath = latestCircuitIRArtifactPath() {
                argumentObject["circuit_ir_path"] = circuitIRPath
            }
        }
        if nextToolName == "kicad_run_spice",
           let projectPath = latestKiCadProjectArtifactPath(),
           let scenarioPath = latestSimulationScenarioArtifactPath() {
            argumentObject["project_path"] = projectPath
            argumentObject["scenario_path"] = scenarioPath
        }
        return argumentObject
    }

    private func electronicsHandoffToolCall(
        from call: ToolCall,
        toolName: String,
        arguments argumentObject: [String: Any]
    ) -> ToolCall {
        let argumentsData = try? JSONSerialization.data(
            withJSONObject: argumentObject,
            options: [.sortedKeys]
        )
        let arguments = argumentsData.flatMap { String(data: $0, encoding: .utf8) }
            ?? call.function.arguments
        return ToolCall(
            id: call.id,
            type: call.type,
            function: FunctionCall(name: toolName, arguments: arguments)
        )
    }

    private func jsonArgumentObject(from arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let dictionary = json as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private func expectedFocusedElectronicsHandoffToolName() -> String? {
        nextFocusedElectronicsHandoffToolName() ?? latestFocusedElectronicsHandoffToolName
    }

    private func nextFocusedElectronicsHandoffToolName() -> String? {
        let planSteps = pendingContinuationAllSteps.isEmpty
            ? pendingContinuationSteps
            : pendingContinuationAllSteps
        let requirements = planSteps.map { electronicsRequirement(for: $0) }
        let nextRequirement = firstUnverifiedElectronicsRequirement()

        let needsDesignIntent = requirements.contains { requirement in
            if case .designIntent = requirement { return true }
            return false
        }
        if needsDesignIntent,
           latestDesignIntentArtifactPath() == nil,
           !electronicsStepVerified(PlanStep(
               description: "Build DesignIntent",
               successCriteria: "DesignIntent artifact exists",
               complexity: .standard
           )) {
            return "kicad_build_intent_model"
        }

        let designIntentApprovalStep = PlanStep(
            description: "Approve DesignIntent",
            successCriteria: "DesignIntent approved",
            complexity: .standard
        )
        if nextRequirement == .designIntentApproval,
           !electronicsStepVerified(designIntentApprovalStep) {
            return "kicad_approve_design_intent"
        }
        if latestDesignIntentArtifactPath() != nil,
           pendingDesignIntentApprovalNextAction(),
           !electronicsStepVerified(designIntentApprovalStep) {
            return "kicad_approve_design_intent"
        }

        if nextRequirement == .circuitIR,
           !electronicsStepVerified(PlanStep(
               description: "Generate Circuit IR",
               successCriteria: "Circuit IR artifact exists",
               complexity: .standard
           )) {
            return "kicad_generate_circuit_ir"
        }

        if latestAnyComponentMatrixArtifactPath() != nil,
           pendingComponentSelectionRevisionNextAction() {
            return "kicad_revise_component_selection"
        }

        if nextRequirement == .componentSelection,
           latestCircuitIRArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Select components",
               successCriteria: "Component matrix artifact exists",
               complexity: .standard
           )) {
            return "kicad_select_components"
        }
        if latestCircuitIRArtifactPath() != nil,
           pendingCircuitIRComponentSelectionNextAction(),
           !electronicsStepVerified(PlanStep(
               description: "Select components",
               successCriteria: "Component matrix artifact exists",
               complexity: .standard
           )) {
            return "kicad_select_components"
        }

        if nextRequirement == .footprintAssignment,
           latestCircuitIRArtifactPath() != nil,
           latestComponentMatrixArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Assign footprints",
               successCriteria: "Footprint assignment artifact exists",
               complexity: .standard
           )) {
            return "kicad_assign_footprints"
        }
        if latestComponentMatrixArtifactPath() != nil,
           pendingComponentSelectionFootprintNextAction(),
           !electronicsStepVerified(PlanStep(
               description: "Assign footprints",
               successCriteria: "Footprint assignment artifact exists",
               complexity: .standard
           )) {
            return "kicad_assign_footprints"
        }

        if nextRequirement == .schematic,
           latestCircuitIRArtifactPath() != nil,
           latestComponentMatrixArtifactPath() != nil,
           latestFootprintAssignmentArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Create KiCad schematic and PCB files",
               successCriteria: "KiCad schematic artifact exists",
               complexity: .standard
           )) {
            return "kicad_compile_project"
        }

        if nextRequirement == .erc,
           latestKiCadProjectArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Run ERC",
               successCriteria: "ERC report passes",
               complexity: .standard
           )) {
            return "kicad_run_erc"
        }

        if nextRequirement == .boardProfile,
           latestKiCadProjectArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Apply board profile",
               successCriteria: "Board profile artifact exists",
               complexity: .standard
           )) {
            return "kicad_apply_board_profile"
        }

        if nextRequirement == .netClasses,
           latestDesignIntentArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Generate net classes",
               successCriteria: "Net class artifact exists",
               complexity: .standard
           )) {
            return "kicad_generate_net_classes"
        }

        if nextRequirement == .placement,
           latestKiCadProjectArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Place components",
               successCriteria: "Placement artifact exists",
               complexity: .standard
           )) {
            return "kicad_place_components"
        }

        if nextRequirement == .routing,
           latestKiCadProjectArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Route PCB",
               successCriteria: "Routing artifact exists",
               complexity: .standard
           )) {
            return "kicad_route_pass"
        }

        if nextRequirement == .drc,
           latestKiCadProjectArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Run DRC",
               successCriteria: "DRC report passes",
               complexity: .standard
           )) {
            return "kicad_run_drc"
        }

        let simulationStep = PlanStep(
            description: "Run SPICE simulation",
            successCriteria: "SPICE measurement artifact exists",
            complexity: .standard
        )
        if nextRequirement == .simulation,
           latestKiCadProjectArtifactPath() != nil,
           latestSimulationScenarioArtifactPath() == nil,
           !electronicsStepVerified(simulationStep) {
            return "kicad_generate_spice_scenario"
        }
        if nextRequirement == .simulation,
           latestKiCadProjectArtifactPath() != nil,
           latestSimulationScenarioArtifactPath() != nil,
           !electronicsStepVerified(simulationStep) {
            return "kicad_run_spice"
        }

        if nextRequirement == .fabrication,
           latestKiCadProjectArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Export Gerbers and drill files",
               successCriteria: "Gerber and drill artifacts exist",
               complexity: .standard
           )) {
            return "kicad_export_fab"
        }

        if nextRequirement == .bom,
           latestBOMArtifactPath() != nil,
           !electronicsStepVerified(PlanStep(
               description: "Prepare vendor BOM",
               successCriteria: "Vendor BOM artifact exists",
               complexity: .standard
           )) {
            return "kicad_prepare_vendor_order"
        }

        return nil
    }

    private func pendingDesignIntentApprovalNextAction() -> Bool {
        pendingContinuationEvidence.contains { evidence in
            guard evidence.toolName == "kicad_build_intent_model" else { return false }
            return electronicsNextActions(inJSONText: evidence.output).contains { action in
                action == "review_and_approve_design_intent"
                    || action == "approve_design_intent"
                    || action == "kicad_approve_design_intent"
            }
        }
    }

    private func pendingCircuitIRComponentSelectionNextAction() -> Bool {
        pendingContinuationEvidence.contains { evidence in
            guard evidence.toolName == "kicad_generate_circuit_ir" else { return false }
            return electronicsNextActions(inJSONText: evidence.output).contains { action in
                action == "select_components"
                    || action == "component_selection"
                    || action == "kicad_select_components"
            }
        }
    }

    private func pendingComponentSelectionFootprintNextAction() -> Bool {
        pendingContinuationEvidence.contains { evidence in
            guard evidence.toolName == "kicad_select_components" else { return false }
            return electronicsNextActions(inJSONText: evidence.output).contains { action in
                action == "assign_footprints"
                    || action == "footprint_assignment"
                    || action == "kicad_assign_footprints"
            }
        }
    }

    private func pendingComponentSelectionRevisionNextAction() -> Bool {
        pendingContinuationEvidence.contains { evidence in
            guard evidence.toolName == "kicad_select_components" else { return false }
            return electronicsNextActions(inJSONText: evidence.output).contains { action in
                action == "revise_component_selection"
                    || action == "component_selection_revision"
                    || action == "kicad_revise_component_selection"
            }
        }
    }

    private func electronicsNextActions(inJSONText text: String) -> [String] {
        guard let json = jsonObjectFromToolText(text) else { return [] }
        return electronicsNextActions(inJSONObject: json)
    }

    private func electronicsNextActions(inJSONObject json: Any) -> [String] {
        if let dictionary = json as? [String: Any] {
            var actions: [String] = []
            for key in ["nextActions", "next_actions"] {
                if let values = dictionary[key] as? [String] {
                    actions.append(contentsOf: values)
                } else if let values = dictionary[key] as? [Any] {
                    actions.append(contentsOf: values.compactMap { $0 as? String })
                }
            }
            for value in dictionary.values {
                actions.append(contentsOf: electronicsNextActions(inJSONObject: value))
            }
            return actions.map { $0.lowercased() }
        }
        if let array = json as? [Any] {
            return array.flatMap { electronicsNextActions(inJSONObject: $0) }
        }
        return []
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
            if let providerID = reasonOverrideProviderID(),
               let requestOverride = onReasonOverrideRequest {
                let request = ReasonExecutionOverrideRequest(
                    providerID: providerID,
                    reason: label,
                    suggestion: message,
                    progressSummary: progress,
                    originalTask: originalTask
                )
                let requestedTelemetry: [String: TelemetryValue] = [
                    "provider_id": .string(providerID),
                    "reason": .string(label)
                ]
                TelemetryEmitter.shared.emit("engine.reason_override.requested", data: requestedTelemetry)
                if await requestOverride(request) {
                    slotAssignments[workingSlot] = providerID
                    let approvedTelemetry: [String: TelemetryValue] = [
                        "provider_id": .string(providerID),
                        "working_slot": .string(workingSlot.rawValue)
                    ]
                    TelemetryEmitter.shared.emit("engine.reason_override.approved", data: approvedTelemetry)
                    continuation.yield(.systemNote(
                        "[Reason override approved — using \(providerID) once for the stuck handoff]"
                    ))
                    return .routeToProvider(
                        providerID: providerID,
                        reason: "user approved one-shot reason override after: \(label)"
                    )
                }
                let deniedTelemetry: [String: TelemetryValue] = [
                    "provider_id": .string(providerID),
                    "reason": .string(label)
                ]
                TelemetryEmitter.shared.emit("engine.reason_override.denied", data: deniedTelemetry)
            }
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
    /// Three-task approach:
    ///   1. Sequential pre-hooks  — preserves hook side-effect ordering
    ///   2. Batch parallel dispatch — passes all allowed calls to ToolRouter at once
    ///   3. Sequential context updates — preserves OpenAI wire-format message ordering
    @discardableResult
    func dispatchRegularCalls(
        _ calls: [ToolCall],
        turn: Int,
        loopCount: Int,
        writtenFilePaths: inout [String],
        continuation: AsyncStream<AgentEvent>.Continuation,
        context: ContextManager? = nil,
        emitCompactionNoteIfNeeded: (() -> Void)? = nil
    ) async -> [ToolResult] {
        guard !calls.isEmpty else { return [] }

        struct PrehookOutcome {
            let call: ToolCall
            let denied: ToolResult?
            let writtenPath: String?
        }

        // Task 1 — sequential pre-hooks
        var prehookOutcomes: [PrehookOutcome] = []
        prehookOutcomes.reserveCapacity(calls.count)
        for call in calls {
            if electronicsWorkflowLockIsActive(),
               !isAllowedDuringElectronicsWorkflowLock(call) {
                prehookOutcomes.append(PrehookOutcome(
                    call: call,
                    denied: electronicsWorkflowLockRejection(for: call),
                    writtenPath: nil
                ))
                continue
            }
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

        // Task 2 — batch parallel dispatch
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

        // Task 3 — sequential context updates (original call order)
        let targetContext = context ?? contextManager
        var orderedResults: [ToolResult] = []
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
            orderedResults.append(result)

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
        return orderedResults
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
                            stagingBufferOverride: workerStagingBuffer,
                            permissionModeOverride: .autoAccept
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
        let slot = executableTurnSlot(for: selectSlot(for: message))
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
        buildCAGSystemPromptSegments().merged
    }

    func buildCAGSystemPromptSegments() -> CAGSystemPromptSegments {
        CAGSystemPromptSegments(cacheable: buildStablePrefix(), hot: buildHotSystemSuffix())
    }

    private func buildHotSystemSuffix() -> String {
        let settings = AppSettings.shared
        var parts: [String] = []
        if settings.cagEnabled, !settings.cagPinConstitution, !constitutionContent.isEmpty {
            let mdToUse = settings.promptCompressionEnabled && !constitutionDistilledContent.isEmpty
                ? constitutionDistilledContent
                : constitutionContent
            parts.append(mdToUse)
        }
        if let warning = nearCeilingWarningAddendum {
            parts.append(warning)
        }
        return parts.joined(separator: "\n\n")
    }

    /// Returns the stable (cacheable) portion of the system prompt.
    /// Excludes nearCeilingWarningAddendum, which varies per loop iteration.
    /// Internal for test access.
    func buildStablePrefix() -> String {
        let settings = AppSettings.shared
        let compressionEnabled = settings.promptCompressionEnabled
        let cagSignature = [
            settings.cagEnabled ? "enabled" : "disabled",
            settings.cagPinConstitution ? "pin-claude" : "skip-claude",
            settings.cagPinnedTaskDocs.joined(separator: "\u{1f}")
        ].joined(separator: "\u{1e}")
        if !_stablePrefixDirty,
           _stablePrefixCompressionEnabled == compressionEnabled,
           _stablePrefixCAGSignature == cagSignature {
            return _stablePrefixCached
        }
        var parts: [String] = []

        if let path = currentProjectPath {
            parts.append("""
            AUTHORITATIVE PROJECT ROOT: \(path)
            All project file, shell, build, test, and search operations for this session must use this directory or a child path unless the user explicitly gives a different path. Do not inspect Merlin's own source repository when the active project root is different.
            """)
        }

        // constitution.md: use distilled version when compression is on and distillation has run.
        if !constitutionContent.isEmpty && (!settings.cagEnabled || settings.cagPinConstitution) {
            let mdToUse = compressionEnabled && !constitutionDistilledContent.isEmpty
                ? constitutionDistilledContent
                : constitutionContent
            parts.append(mdToUse)
        }
        if settings.cagEnabled {
            parts.append(contentsOf: pinnedCAGDocumentContents(settings.cagPinnedTaskDocs))
        }
        if !memoriesContent.isEmpty {
            parts.append(memoriesContent)
        }
        if permissionMode == .plan {
            parts.append(PermissionMode.planSystemPrompt)
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
        _stablePrefixCAGSignature = cagSignature
        _stablePrefixDirty = false
        return _stablePrefixCached
    }

    private func pinnedCAGDocumentContents(_ paths: [String]) -> [String] {
        guard !paths.isEmpty else { return [] }
        let baseURL = currentProjectPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return paths.sorted().prefix(Self.maxPinnedCAGDocuments).compactMap { rawPath in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let url: URL
            if trimmed.hasPrefix("/") {
                url = URL(fileURLWithPath: trimmed).standardizedFileURL
            } else if let baseURL {
                url = baseURL.appendingPathComponent(trimmed).standardizedFileURL
            } else {
                url = URL(fileURLWithPath: trimmed).standardizedFileURL
            }
            if let baseURL {
                let basePath = baseURL.standardizedFileURL.path
                guard url.path == basePath || url.path.hasPrefix(basePath + "/") else {
                    return "Pinned CAG document skipped: \(trimmed)\nReason: outside current project."
                }
            }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return "Pinned CAG document skipped: \(trimmed)\nReason: not a regular file."
            }
            guard (values.fileSize ?? 0) <= Self.maxPinnedCAGDocumentBytes else {
                return "Pinned CAG document skipped: \(trimmed)\nReason: file exceeds 64 KiB limit."
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return "Pinned CAG document: \(trimmed)\n\n\(text)"
        }
    }

    /// Distils `constitutionContent` using `provider` when the content has changed since the last
    /// distillation. Uses a SHA256 hash of the content as a cache key — the provider is called
    /// at most once per unique `constitutionContent` value. No-op when content is empty or unchanged.
    func refreshDistilledConstitution(using provider: any LLMProvider) async {
        guard !constitutionContent.isEmpty else { return }
        let currentHash = sha256Hex(constitutionContent)
        guard currentHash != constitutionDistillHash else { return }

        let systemMsg = Message(
            role: .system,
            content: .text(
                "Compress the following constitution.md into a token-efficient shorthand that preserves all " +
                "constraints, rules, and technical details. Use abbreviations, symbols, and dense phrasing. " +
                "Output only the compressed text — no preamble."
            ),
            timestamp: Date()
        )
        let userMsg = Message(role: .user, content: .text(constitutionContent), timestamp: Date())
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
                constitutionDistilledContent = trimmed
                constitutionDistillHash = currentHash
            }
        } catch {
            // Distillation failed — keep previous distilled content (or empty); do not update hash.
            // buildStablePrefix() will fall back to the original constitutionContent.
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
        toolRouter.connectedMCPServerNames(activeDomainIDs: toolDomainIDsForCurrentTurn())
    }

    /// The improvisation tools currently *withheld* from the model — non-empty when
    /// an authoritative backend is connected. For active electronics work, the
    /// stricter workflow lock below withholds all non-inspection/non-KiCad tools even
    /// when the backend is late or unavailable, so general Xcode/shell/UI tools cannot
    /// become a false substitute.
    private func gatedImprovisationToolNames() -> Set<String> {
        hasAuthoritativeDomainTools() ? Self.improvisationToolNames : []
    }

    private func hasAuthoritativeDomainTools() -> Bool {
        if !connectedMCPServerNames().isDisjoint(with: Self.improvisationGatedMCPServers) {
            return true
        }
        guard activeDomainIDs.contains(ElectronicsDomain.defaultID) else { return false }
        return toolRouter.workspaceToolDefinitions(activeDomainIDs: activeDomainIDs)
            .contains { $0.function.name.hasPrefix("kicad_") }
    }

    /// The tool list offered to the model for one turn: every built-in tool plus
    /// every connected MCP/workspace tool. When an authoritative domain backend is
    /// connected, the improvisation tools
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
        let toolDomainIDs = toolDomainIDsForCurrentTurn()
        let builtins = withheld.isEmpty
            ? ToolRegistry.shared.all()
            : ToolRegistry.shared.all().filter { !withheld.contains($0.function.name) }
        var seen = Set<String>()
        let available = (
            builtins
            + toolRouter.mcpToolDefinitions(activeDomainIDs: toolDomainIDs)
            + toolRouter.workspaceToolDefinitions(activeDomainIDs: toolDomainIDs)
        )
            .filter { seen.insert($0.function.name).inserted }
        guard electronicsWorkflowLockIsActive() else { return available }
        return available.filter { isAllowedDuringElectronicsWorkflowLock(toolName: $0.function.name) }
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
                (`write_file`, `create_file`), app/UI automation tools, and \
                `spawn_agent` are intentionally unavailable this turn. Read-only \
                file tools remain available for requirements and project context; \
                the `mcp:` tools are the only supported way to do this domain's \
                authoring and verification work. Call them directly yourself; do \
                not look for a shell or a subagent to do it.
                """
            }
            parts.append(steer)
        }

        let toolDomainIDs = toolDomainIDsForCurrentTurn()
        if toolRouter.hasWorkspaceTools(activeDomainIDs: toolDomainIDs),
           toolDomainIDs.contains(ElectronicsDomain.defaultID) {
            parts.append("""
            Connected workspace plugin tools are available for the active electronics \
            domain. Use the `kicad_*` tools directly for KiCad schematics, PCB \
            layout, routing, simulation, verification, and fabrication outputs. Do \
            NOT hand-write domain files (.kicad_sch, .kicad_pcb, netlists) or invoke \
            KiCad through shell commands when a `kicad_*` tool covers the step. The \
            shell tools (`bash`, `run_shell`), file-authoring tools (`write_file`, \
            `create_file`), app/UI automation tools, and `spawn_agent` are intentionally \
            unavailable for this domain workflow. Read-only file tools remain \
            available for requirements and project context.
            """)
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

enum TextEncodedToolCallParser {
    static func parse(_ text: String, offeredToolNames: Set<String>) -> [ToolCall]? {
        guard text.contains("<function="), text.contains("</function>") else {
            return nil
        }
        let functionPattern = #"<function=([A-Za-z0-9_:\.\-]+)>\s*(.*?)\s*</function>"#
        guard let functionRegex = try? NSRegularExpression(
            pattern: functionPattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = functionRegex.matches(in: text, options: [], range: range)
        let calls = matches.compactMap { match -> ToolCall? in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text)
            else {
                return nil
            }
            let name = String(text[nameRange])
            guard offeredToolNames.contains(name) else {
                return nil
            }
            let body = String(text[bodyRange])
            let parameters = parseParameters(body)
            guard !parameters.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]),
                  let arguments = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            return ToolCall(
                id: UUID().uuidString,
                type: "function",
                function: FunctionCall(name: name, arguments: arguments)
            )
        }
        return calls.isEmpty ? nil : calls
    }

    private static func parseParameters(_ body: String) -> [String: String] {
        let parameterPattern = #"<parameter=([A-Za-z0-9_\-]+)>\s*(.*?)\s*</parameter>"#
        guard let parameterRegex = try? NSRegularExpression(
            pattern: parameterPattern,
            options: [.dotMatchesLineSeparators]
        ) else {
            return [:]
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var parameters: [String: String] = [:]
        for match in parameterRegex.matches(in: body, options: [], range: range) {
            guard match.numberOfRanges == 3,
                  let keyRange = Range(match.range(at: 1), in: body),
                  let valueRange = Range(match.range(at: 2), in: body)
            else {
                continue
            }
            let key = String(body[keyRange])
            let value = String(body[valueRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parameters[key] = value
        }
        return parameters
    }
}
