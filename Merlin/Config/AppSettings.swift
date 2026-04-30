import Foundation
import CoreServices
import SwiftUI

enum MessageDensity: String, CaseIterable, Codable, Sendable {
    case compact
    case comfortable
    case spacious
}

extension MessageDensity {
    var verticalPadding: CGFloat {
        switch self {
        case .compact:
            return 4
        case .comfortable:
            return 8
        case .spacious:
            return 12
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var autoCompact: Bool = false
    @Published var maxTokens: Int = 8_192
    @Published var keepAwake: Bool = false
    @Published var providerName: String = "anthropic"
    @Published var modelID: String = ""
    @Published var defaultPermissionMode: PermissionMode = .ask
    @Published var notificationsEnabled: Bool = true
    @Published var messageDensity: MessageDensity = .comfortable
    @Published var standingInstructions: String = ""
    @Published var hooks: [HookConfig] = []
    @Published var appearance: AppearanceSettings = AppearanceSettings()
    @Published var providers: [ProviderConfig] = ProviderRegistry.defaultProviders
    @Published var reasoningEnabledOverrides: [String: Bool] = [:]
    @Published var maxSubagentThreads: Int = 4
    @Published var maxSubagentDepth: Int = 2
    @Published var disabledSkillNames: [String] = []
    @Published var memoriesEnabled: Bool = false
    @Published var memoryIdleTimeout: TimeInterval = 300
    /// TOML key `memory.backend_id`. Default: `"local-vector"`. Selects the active MemoryBackendPlugin.
    @Published var memoryBackendID: String = "local-vector"
    @Published var projectPath: String = ""
    @Published var ragRerank: Bool = false
    @Published var ragChunkLimit: Int = 3
    /// TOML key `rag_freshness_threshold_days`. Memory chunks older than this many days are flagged as stale in GroundingReport.
    @Published var ragFreshnessThresholdDays: Int = 90
    /// TOML key `rag_min_grounding_score`. Average RAG score below this threshold makes GroundingReport.isWellGrounded false.
    @Published var ragMinGroundingScore: Double = 0.30
    /// TOML key `agent_circuit_breaker_threshold`. Default: `3`. `0` disables the circuit breaker entirely.
    @Published var agentCircuitBreakerThreshold: Int = 3
    /// TOML key `agent_circuit_breaker_mode`. Default: `"halt"`. `halt` stops the next turn cleanly; `warn` emits a system note and continues.
    @Published var agentCircuitBreakerMode: String = "halt"
    // MARK: - V6 LoRA self-training
    // All off / empty by default. loraAutoTrain and loraAutoLoad are sub-toggles that
    // only take effect when loraEnabled = true.
    @Published var loraEnabled: Bool = false
    @Published var loraAutoTrain: Bool = false
    @Published var loraAutoLoad: Bool = false
    @Published var loraMinSamples: Int = 50
    @Published var loraBaseModel: String = ""
    @Published var loraAdapterPath: String = ""
    @Published var loraServerURL: String = ""
    // MARK: - Inference defaults
    /// TOML key `temperature` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferenceTemperature: Double? = nil
    /// TOML key `max_tokens` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferenceMaxTokens: Int? = nil
    /// TOML key `top_p` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferenceTopP: Double? = nil
    /// TOML key `top_k` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferenceTopK: Int? = nil
    /// TOML key `min_p` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferenceMinP: Double? = nil
    /// TOML key `repeat_penalty` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferenceRepeatPenalty: Double? = nil
    /// TOML key `frequency_penalty` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferenceFrequencyPenalty: Double? = nil
    /// TOML key `presence_penalty` inside `[inference]`; default `nil` keeps provider behavior.
    @Published var inferencePresencePenalty: Double? = nil
    /// TOML key `seed` inside `[inference]`; default `nil` keeps provider randomness.
    @Published var inferenceSeed: Int? = nil
    /// TOML key `stop` inside `[inference]`; default `[]` leaves stop-sequence handling unchanged.
    @Published var inferenceStop: [String] = []
    @Published var xcalibreToken: String = ""
    @Published var slotAssignments: [AgentSlot: String] = [:]
    @Published var verifyCommand: String = ""
    @Published var checkCommand: String = ""
    @Published var activeDomainID: String = "software"
    @Published var maxPlanRetries: Int = 2
    @Published var maxLoopIterations: Int = 10

    var proposalApprover: ((SettingsProposal) async -> Bool)?

    private var fsStream: FSEventStreamRef?
    private var watchedURL: URL?

    struct InferenceDefaults: Sendable {
        var temperature: Double?
        var maxTokens: Int?
        var topP: Double?
        var topK: Int?
        var minP: Double?
        var repeatPenalty: Double?
        var frequencyPenalty: Double?
        var presencePenalty: Double?
        var seed: Int?
        var stop: [String]

        func apply(to request: inout CompletionRequest) {
            if request.temperature == nil { request.temperature = temperature }
            if request.maxTokens == nil { request.maxTokens = maxTokens }
            if request.topP == nil { request.topP = topP }
            if request.topK == nil { request.topK = topK }
            if request.minP == nil { request.minP = minP }
            if request.repeatPenalty == nil { request.repeatPenalty = repeatPenalty }
            if request.frequencyPenalty == nil { request.frequencyPenalty = frequencyPenalty }
            if request.presencePenalty == nil { request.presencePenalty = presencePenalty }
            if request.seed == nil { request.seed = seed }
            if request.stop == nil, !stop.isEmpty { request.stop = stop }
        }
    }

    private struct ConfigFile: Codable, Sendable {
        var autoCompact: Bool?
        var maxTokens: Int?
        var keepAwake: Bool?
        var providerName: String?
        var modelID: String?
        var defaultPermissionMode: PermissionMode?
        var notificationsEnabled: Bool?
        var messageDensity: MessageDensity?
        var standingInstructions: String?
        var hooks: [HookConfig]?
        var appearance: AppearanceSettings?
        var providers: [ProviderConfig]?
        var reasoningEnabledOverrides: [String: Bool]?
        var maxSubagentThreads: Int?
        var maxSubagentDepth: Int?
        var disabledSkillNames: [String]?
        var memoriesEnabled: Bool?
        var memoryIdleTimeout: TimeInterval?
        var memory: MemoryConfig?
        var projectPath: String?
        var ragRerank: Bool?
        var ragChunkLimit: Int?
        var ragFreshnessThresholdDays: Int?
        var ragMinGroundingScore: Double?
        var agentCircuitBreakerThreshold: Int?
        var agentCircuitBreakerMode: String?
        var lora: LoraConfig?
        var loraEnabled: Bool?
        var loraAutoTrain: Bool?
        var loraAutoLoad: Bool?
        var loraMinSamples: Int?
        var loraBaseModel: String?
        var loraAdapterPath: String?
        var loraServerURL: String?
        var inference: InferenceConfig?
        var xcalibreToken: String?
        var slots: [String: String]?
        var verifyCommand: String?
        var checkCommand: String?
        var activeDomainID: String?
        var planner: PlannerConfig?

        struct PlannerConfig: Codable, Sendable {
            var maxPlanRetries: Int?
            var maxLoopIterations: Int?

            enum CodingKeys: String, CodingKey {
                case maxPlanRetries = "max_plan_retries"
                case maxLoopIterations = "max_loop_iterations"
            }
        }

        struct LoraConfig: Codable, Sendable {
            var loraEnabled: Bool?
            var loraAutoTrain: Bool?
            var loraAutoLoad: Bool?
            var loraMinSamples: Int?
            var loraBaseModel: String?
            var loraAdapterPath: String?
            var loraServerURL: String?

            enum CodingKeys: String, CodingKey {
                case loraEnabled = "lora_enabled"
                case loraAutoTrain = "lora_auto_train"
                case loraAutoLoad = "lora_auto_load"
                case loraMinSamples = "lora_min_samples"
                case loraBaseModel = "lora_base_model"
                case loraAdapterPath = "lora_adapter_path"
                case loraServerURL = "lora_server_url"
            }
        }

        struct MemoryConfig: Codable, Sendable {
            var backendID: String?

            enum CodingKeys: String, CodingKey {
                case backendID = "backend_id"
            }
        }

        struct InferenceConfig: Codable, Sendable {
            var temperature: Double?
            var maxTokens: Int?
            var topP: Double?
            var topK: Int?
            var minP: Double?
            var repeatPenalty: Double?
            var frequencyPenalty: Double?
            var presencePenalty: Double?
            var seed: Int?
            var stop: [String]?

            enum CodingKeys: String, CodingKey {
                case temperature
                case maxTokens = "max_tokens"
                case topP = "top_p"
                case topK = "top_k"
                case minP = "min_p"
                case repeatPenalty = "repeat_penalty"
                case frequencyPenalty = "frequency_penalty"
                case presencePenalty = "presence_penalty"
                case seed
                case stop
            }
        }

        enum CodingKeys: String, CodingKey {
            case autoCompact = "auto_compact"
            case maxTokens = "max_tokens"
            case keepAwake = "keep_awake"
            case providerName = "provider_name"
            case modelID = "model_id"
            case defaultPermissionMode = "default_permission_mode"
            case notificationsEnabled = "notifications_enabled"
            case messageDensity = "message_density"
            case standingInstructions = "standing_instructions"
            case hooks
            case appearance
            case providers
            case reasoningEnabledOverrides = "model_capabilities"
            case maxSubagentThreads = "max_subagent_threads"
            case maxSubagentDepth = "max_subagent_depth"
            case disabledSkillNames = "disabled_skill_names"
            case memoriesEnabled = "memories_enabled"
            case memoryIdleTimeout = "memory_idle_timeout"
            case memory
            case projectPath = "project_path"
            case ragRerank = "rag_rerank"
            case ragChunkLimit = "rag_chunk_limit"
            case ragFreshnessThresholdDays = "rag_freshness_threshold_days"
            case ragMinGroundingScore = "rag_min_grounding_score"
            case agentCircuitBreakerThreshold = "agent_circuit_breaker_threshold"
            case agentCircuitBreakerMode = "agent_circuit_breaker_mode"
            case lora
            case loraEnabled = "lora_enabled"
            case loraAutoTrain = "lora_auto_train"
            case loraAutoLoad = "lora_auto_load"
            case loraMinSamples = "lora_min_samples"
            case loraBaseModel = "lora_base_model"
            case loraAdapterPath = "lora_adapter_path"
            case loraServerURL = "lora_server_url"
            case inference
            case xcalibreToken = "xcalibre_token"
            case slots
            case verifyCommand = "verify_command"
            case checkCommand = "check_command"
            case activeDomainID = "active_domain"
            case planner
        }
    }

    func load(from url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        let decoder = TOMLDecoder()
        let config = try decoder.decode(ConfigFile.self, from: source)
        apply(config)
    }

    func save(to url: URL) async throws {
        let content = serializedTOML()
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Applies stored inference defaults to a request, filling only nil fields.
    /// Per-request overrides always win because existing values are never replaced.
    func applyInferenceDefaults(to request: inout CompletionRequest) {
        inferenceDefaults.apply(to: &request)
    }

    var inferenceDefaults: InferenceDefaults {
        InferenceDefaults(
            temperature: inferenceTemperature,
            maxTokens: inferenceMaxTokens,
            topP: inferenceTopP,
            topK: inferenceTopK,
            minP: inferenceMinP,
            repeatPenalty: inferenceRepeatPenalty,
            frequencyPenalty: inferenceFrequencyPenalty,
            presencePenalty: inferencePresencePenalty,
            seed: inferenceSeed,
            stop: inferenceStop
        )
    }

    func serializedTOML() -> String {
        var lines: [String] = []
        lines.append("auto_compact = \(autoCompact)")
        lines.append("max_tokens = \(maxTokens)")
        lines.append("keep_awake = \(keepAwake)")
        lines.append("provider_name = \(quoted(providerName))")
        lines.append("model_id = \(quoted(modelID))")
        lines.append("default_permission_mode = \(quoted(defaultPermissionMode.rawValue))")
        lines.append("notifications_enabled = \(notificationsEnabled)")
        lines.append("message_density = \(quoted(messageDensity.rawValue))")
        lines.append("max_subagent_threads = \(maxSubagentThreads)")
        lines.append("max_subagent_depth = \(maxSubagentDepth)")
        if !xcalibreToken.isEmpty {
            lines.append("xcalibre_token = \(quoted(xcalibreToken))")
        }
        if disabledSkillNames.isEmpty == false {
            let quoted = disabledSkillNames.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("disabled_skill_names = [\(quoted)]")
        }
        if memoriesEnabled {
            lines.append("memories_enabled = true")
            lines.append("memory_idle_timeout = \(memoryIdleTimeout)")
        }
        lines.append("")
        lines.append("[memory]")
        lines.append("backend_id = \(quoted(memoryBackendID))")
        if projectPath.isEmpty == false {
            lines.append("project_path = \(quoted(projectPath))")
        }
        if ragRerank {
            lines.append("rag_rerank = true")
        }
        if ragChunkLimit != 3 {
            lines.append("rag_chunk_limit = \(ragChunkLimit)")
        }
        if ragFreshnessThresholdDays != 90 {
            lines.append("rag_freshness_threshold_days = \(ragFreshnessThresholdDays)")
        }
        if abs(ragMinGroundingScore - 0.30) > 0.001 {
            lines.append("rag_min_grounding_score = \(ragMinGroundingScore)")
        }
        if agentCircuitBreakerThreshold != 3 {
            lines.append("agent_circuit_breaker_threshold = \(agentCircuitBreakerThreshold)")
        }
        if agentCircuitBreakerMode != "halt" {
            lines.append("agent_circuit_breaker_mode = \(quoted(agentCircuitBreakerMode))")
        }
        if loraEnabled {
            lines.append("")
            lines.append("[lora]")
            lines.append("lora_enabled = true")
            if loraAutoTrain {
                lines.append("lora_auto_train = true")
            }
            if loraAutoLoad {
                lines.append("lora_auto_load = true")
            }
            if loraMinSamples != 50 {
                lines.append("lora_min_samples = \(loraMinSamples)")
            }
            if loraBaseModel.isEmpty == false {
                lines.append("lora_base_model = \(quoted(loraBaseModel))")
            }
            if loraAdapterPath.isEmpty == false {
                lines.append("lora_adapter_path = \(quoted(loraAdapterPath))")
            }
            if loraServerURL.isEmpty == false {
                lines.append("lora_server_url = \(quoted(loraServerURL))")
            }
        }
        var inferenceLines: [String] = []
        if let value = inferenceTemperature {
            inferenceLines.append("temperature = \(value)")
        }
        if let value = inferenceMaxTokens {
            inferenceLines.append("max_tokens = \(value)")
        }
        if let value = inferenceTopP {
            inferenceLines.append("top_p = \(value)")
        }
        if let value = inferenceTopK {
            inferenceLines.append("top_k = \(value)")
        }
        if let value = inferenceMinP {
            inferenceLines.append("min_p = \(value)")
        }
        if let value = inferenceRepeatPenalty {
            inferenceLines.append("repeat_penalty = \(value)")
        }
        if let value = inferenceFrequencyPenalty {
            inferenceLines.append("frequency_penalty = \(value)")
        }
        if let value = inferencePresencePenalty {
            inferenceLines.append("presence_penalty = \(value)")
        }
        if let value = inferenceSeed {
            inferenceLines.append("seed = \(value)")
        }
        if inferenceStop.isEmpty == false {
            let escaped = inferenceStop.map { quoted($0) }.joined(separator: ", ")
            inferenceLines.append("stop = [\(escaped)]")
        }
        if inferenceLines.isEmpty == false {
            // [inference] keys:
            // temperature, max_tokens, top_p, top_k, min_p, repeat_penalty,
            // frequency_penalty, presence_penalty, seed, stop
            lines.append("")
            lines.append("[inference]")
            lines.append(contentsOf: inferenceLines)
        }
        if slotAssignments.isEmpty == false {
            lines.append("")
            lines.append("[slots]")
            for slot in AgentSlot.allCases {
                if let providerID = slotAssignments[slot], !providerID.isEmpty {
                    lines.append("\(slot.rawValue) = \(quoted(providerID))")
                }
            }
        }
        if standingInstructions.isEmpty == false {
            lines.append("standing_instructions = \(quoted(standingInstructions))")
        }
        if !verifyCommand.isEmpty || !checkCommand.isEmpty || activeDomainID != "software" {
            lines.append("")
            lines.append("[domain]")
            lines.append("active_domain = \(quoted(activeDomainID))")
            if verifyCommand.isEmpty == false {
                lines.append("verify_command = \(quoted(verifyCommand))")
            }
            if checkCommand.isEmpty == false {
                lines.append("check_command = \(quoted(checkCommand))")
            }
        }
        if maxPlanRetries != 2 || maxLoopIterations != 10 {
            lines.append("")
            lines.append("[planner]")
            lines.append("max_plan_retries = \(maxPlanRetries)")
            lines.append("max_loop_iterations = \(maxLoopIterations)")
        }

        lines.append("")
        lines.append("[appearance]")
        lines.append("theme = \(quoted(appearance.theme.rawValue))")
        lines.append("font_size = \(appearance.fontSize)")
        lines.append("font_name = \(quoted(appearance.fontName))")
        if appearance.accentColorHex.isEmpty == false {
            lines.append("accent_color_hex = \(quoted(appearance.accentColorHex))")
        }
        lines.append("line_spacing = \(appearance.lineSpacing)")

        if providers.isEmpty == false {
            lines.append("")
            for provider in providers {
                lines.append("[[providers]]")
                lines.append("id = \(quoted(provider.id))")
                lines.append("displayName = \(quoted(provider.displayName))")
                lines.append("baseURL = \(quoted(provider.baseURL))")
                lines.append("model = \(quoted(provider.model))")
                if provider.systemPromptAddendum.isEmpty == false {
                    lines.append("system_prompt_addendum = \(quoted(provider.systemPromptAddendum))")
                }
                lines.append("isEnabled = \(provider.isEnabled)")
                lines.append("isLocal = \(provider.isLocal)")
                lines.append("supportsThinking = \(provider.supportsThinking)")
                lines.append("supportsVision = \(provider.supportsVision)")
                lines.append("kind = \(quoted(provider.kind.rawValue))")
                lines.append("")
            }
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
        }

        if reasoningEnabledOverrides.isEmpty == false {
            lines.append("")
            lines.append("[model_capabilities]")
            for key in reasoningEnabledOverrides.keys.sorted() {
                if let value = reasoningEnabledOverrides[key] {
                    lines.append("\(quoted(key)) = \(value)")
                }
            }
        }

        if hooks.isEmpty == false {
            lines.append("")
            for hook in hooks {
                lines.append("[[hooks]]")
                lines.append("event = \(quoted(hook.event))")
                lines.append("command = \(quoted(hook.command))")
                lines.append("enabled = \(hook.enabled)")
                lines.append("")
            }
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    func applyTOML(_ toml: String) {
        let decoder = TOMLDecoder()
        if let config = try? decoder.decode(ConfigFile.self, from: toml) {
            apply(config)
        }
        applyLoRASection(from: toml)
    }

    func propose(_ change: SettingsProposal) async -> Bool {
        guard let proposalApprover else {
            return false
        }

        let approved = await proposalApprover(change)
        if approved {
            apply(change)
        }
        return approved
    }

    func startWatching(url: URL) {
        stopWatching()
        watchedURL = url

        let directory = url.deletingLastPathComponent().path as CFString
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            let settings = Unmanaged<AppSettings>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                guard let watchedURL = settings.watchedURL else {
                    return
                }
                try? await settings.load(from: watchedURL)
            }
        }

        fsStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [directory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = fsStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    func stopWatching() {
        guard let stream = fsStream else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsStream = nil
    }

    private func apply(_ change: SettingsProposal) {
        switch change {
        case .setMaxTokens(let value):
            maxTokens = value
        case .setProviderName(let value):
            providerName = value
        case .setModelID(let value):
            modelID = value
        case .setAutoCompact(let value):
            autoCompact = value
        case .setStandingInstructions(let value):
            standingInstructions = value
        case .addHook(let value):
            hooks.append(value)
        case .removeHook(let event):
            hooks.removeAll { $0.event == event }
        }
    }

    private func apply(_ config: ConfigFile) {
        if let value = config.autoCompact {
            autoCompact = value
        }
        if let value = config.maxTokens {
            maxTokens = value
        }
        if let value = config.keepAwake {
            keepAwake = value
        }
        if let value = config.providerName {
            providerName = value
        }
        if let value = config.modelID {
            modelID = value
        }
        if let value = config.defaultPermissionMode {
            defaultPermissionMode = value
        }
        if let value = config.notificationsEnabled {
            notificationsEnabled = value
        }
        if let value = config.messageDensity {
            messageDensity = value
        }
        if let value = config.standingInstructions {
            standingInstructions = value
        }
        if let value = config.hooks {
            hooks = value
        }
        if let value = config.appearance {
            appearance = value
        }
        if let value = config.providers {
            providers = value
        }
        if let value = config.reasoningEnabledOverrides {
            reasoningEnabledOverrides = value
        }
        if let value = config.maxSubagentThreads {
            maxSubagentThreads = value
        }
        if let value = config.maxSubagentDepth {
            maxSubagentDepth = value
        }
        if let value = config.disabledSkillNames {
            disabledSkillNames = value
        }
        if let value = config.memoriesEnabled {
            memoriesEnabled = value
        }
        if let value = config.memoryIdleTimeout {
            memoryIdleTimeout = value
        }
        if let value = config.memory?.backendID {
            memoryBackendID = value
        }
        if let value = config.projectPath {
            projectPath = value
        }
        if let value = config.ragRerank {
            ragRerank = value
        }
        if let value = config.ragChunkLimit {
            ragChunkLimit = value
        }
        if let value = config.ragFreshnessThresholdDays {
            ragFreshnessThresholdDays = value
        }
        if let value = config.ragMinGroundingScore {
            ragMinGroundingScore = value
        }
        if let value = config.agentCircuitBreakerThreshold {
            agentCircuitBreakerThreshold = value
        }
        if let value = config.agentCircuitBreakerMode {
            agentCircuitBreakerMode = value
        }
        if let lora = config.lora {
            if let value = lora.loraEnabled {
                loraEnabled = value
            }
            if let value = lora.loraAutoTrain {
                loraAutoTrain = value
            }
            if let value = lora.loraAutoLoad {
                loraAutoLoad = value
            }
            if let value = lora.loraMinSamples {
                loraMinSamples = value
            }
            if let value = lora.loraBaseModel {
                loraBaseModel = value
            }
            if let value = lora.loraAdapterPath {
                loraAdapterPath = value
            }
            if let value = lora.loraServerURL {
                loraServerURL = value
            }
        }
        if let inference = config.inference {
            if let value = inference.temperature {
                inferenceTemperature = value
            }
            if let value = inference.maxTokens {
                inferenceMaxTokens = value
            }
            if let value = inference.topP {
                inferenceTopP = value
            }
            if let value = inference.topK {
                inferenceTopK = value
            }
            if let value = inference.minP {
                inferenceMinP = value
            }
            if let value = inference.repeatPenalty {
                inferenceRepeatPenalty = value
            }
            if let value = inference.frequencyPenalty {
                inferenceFrequencyPenalty = value
            }
            if let value = inference.presencePenalty {
                inferencePresencePenalty = value
            }
            if let value = inference.seed {
                inferenceSeed = value
            }
            inferenceStop = inference.stop ?? []
        }
        if let value = config.xcalibreToken {
            xcalibreToken = value
        }
        if let slots = config.slots {
            var assignments: [AgentSlot: String] = [:]
            for slot in AgentSlot.allCases {
                if let providerID = slots[slot.rawValue], !providerID.isEmpty {
                    assignments[slot] = providerID
                }
            }
            slotAssignments = assignments
        }
        if let value = config.verifyCommand {
            verifyCommand = value
        }
        if let value = config.checkCommand {
            checkCommand = value
        }
        if let value = config.activeDomainID {
            activeDomainID = value
        }
        if let planner = config.planner {
            if let value = planner.maxPlanRetries {
                maxPlanRetries = value
            }
            if let value = planner.maxLoopIterations {
                maxLoopIterations = value
            }
        }
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func applyLoRASection(from toml: String) {
        let lines = toml.split(separator: "\n", omittingEmptySubsequences: false)
        var inLoRASection = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[lora]" {
                inLoRASection = true
                continue
            }
            if line.hasPrefix("[") && line != "[lora]" {
                if inLoRASection {
                    break
                }
                continue
            }
            guard inLoRASection, !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            if let value = parsedBoolValue(from: line, key: "lora_enabled") {
                loraEnabled = value
            } else if let value = parsedBoolValue(from: line, key: "lora_auto_train") {
                loraAutoTrain = value
            } else if let value = parsedBoolValue(from: line, key: "lora_auto_load") {
                loraAutoLoad = value
            } else if let value = parsedIntValue(from: line, key: "lora_min_samples") {
                loraMinSamples = value
            } else if let value = parsedStringValue(from: line, key: "lora_base_model") {
                loraBaseModel = value
            } else if let value = parsedStringValue(from: line, key: "lora_adapter_path") {
                loraAdapterPath = value
            } else if let value = parsedStringValue(from: line, key: "lora_server_url") {
                loraServerURL = value
            }
        }
    }

    private func parsedBoolValue(from line: String, key: String) -> Bool? {
        guard line.hasPrefix("\(key) = ") else {
            return nil
        }
        let raw = String(line.dropFirst(key.count + 3))
        switch raw {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private func parsedIntValue(from line: String, key: String) -> Int? {
        guard line.hasPrefix("\(key) = ") else {
            return nil
        }
        let raw = String(line.dropFirst(key.count + 3))
        return Int(raw)
    }

    private func parsedStringValue(from line: String, key: String) -> String? {
        guard line.hasPrefix("\(key) = ") else {
            return nil
        }
        let raw = String(line.dropFirst(key.count + 3))
        return unquoted(raw)
    }

    private func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else {
            return value
        }
        let body = String(value.dropFirst().dropLast())
        return body
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
