import Foundation

// MARK: - LoadParam

/// Load-time parameters that can be edited for a local model provider.
enum LoadParam: String, Hashable, Sendable, CaseIterable {
    /// Context window size: LM Studio `contextLength`, Ollama `num_ctx`, Jan `contextLength`,
    /// LocalAI `context_size`, Mistral.rs `--max-seq-len`, vLLM-Metal `--max-model-len`.
    case contextLength
    /// GPU offload depth: LM Studio `gpuLayers`, Ollama `num_gpu`, Jan `gpuLayers`,
    /// LocalAI `gpu_layers`, Mistral.rs `--gpu-layers`, vLLM-Metal `--gpu-layers`.
    case gpuLayers
    /// CPU thread count: LM Studio `cpuThreads`, Ollama `num_thread`, Jan `cpuThreads`,
    /// LocalAI `threads`, Mistral.rs `--cpu-threads`.
    case cpuThreads
    /// Flash-attention toggle: LM Studio `flashAttention`, Mistral.rs `--flash-attn`.
    case flashAttention
    /// K-side KV cache type: LM Studio `cacheTypeK`, vLLM-Metal `--kv-cache-dtype`.
    case cacheTypeK
    /// V-side KV cache type: LM Studio `cacheTypeV`.
    case cacheTypeV
    /// RoPE frequency base: LM Studio `ropeFrequencyBase`, Ollama `rope_frequency_base`,
    /// LocalAI `rope_frequency_base`, Mistral.rs `--rope-frequency-base`,
    /// vLLM-Metal `--rope-frequency-base`.
    case ropeFrequencyBase
    /// Micro-batch size: LM Studio `numBatch`, Ollama `num_batch`, LocalAI `batch_size`,
    /// Mistral.rs `--batch-size`, vLLM-Metal `--max-num-batched-tokens`.
    case batchSize
    /// Persistent mmap toggle: Ollama `use_mmap`, LocalAI `use_mmap`.
    case useMmap
    /// Persistent mlock toggle: Ollama `use_mlock`.
    case useMlock
}

// MARK: - LocalModelConfig

/// Load-time configuration for a local model.
/// Every field is optional; nil means "don't change this parameter".
struct LocalModelConfig: Sendable {
    var contextLength: Int?
    var gpuLayers: Int? // -1 = offload all layers to GPU
    var cpuThreads: Int?
    var flashAttention: Bool?
    var cacheTypeK: String? // "q4_0" | "q8_0" | "f16" | "f32"
    var cacheTypeV: String?
    var ropeFrequencyBase: Double?
    var batchSize: Int?
    var useMmap: Bool?
    var useMlock: Bool?
}

// MARK: - LlamaCppRuntimeSettings

/// Provider-specific runtime configuration for Merlin-managed llama.cpp launch guidance.
struct LlamaCppRuntimeSettings: Codable, Sendable, Equatable {
    var serverPath: String = "/opt/homebrew/bin/llama-server"
    var routerEnabled: Bool = true
    var modelsDir: String = "$HOME/Models/gguf"
    var modelsPresetPath: String = "$HOME/.config/llama.cpp/router-preset.ini"
    var modelPath: String = ""
    var modelAlias: String = ""
    var mmprojPath: String = ""
    var parallelSlots: Int?
    var ubatchSize: Int?
    var chatTemplate: String = ""
    var apiKey: String = ""
    var autoloadModels: Bool = true

    init() {}

    enum CodingKeys: String, CodingKey {
        case serverPath = "server_path"
        case routerEnabled = "router_enabled"
        case modelsDir = "models_dir"
        case modelsPresetPath = "models_preset_path"
        case modelPath = "model_path"
        case modelAlias = "model_alias"
        case mmprojPath = "mmproj_path"
        case parallelSlots = "parallel_slots"
        case ubatchSize = "ubatch_size"
        case chatTemplate = "chat_template"
        case apiKey = "api_key"
        case autoloadModels = "autoload_models"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverPath = try c.decodeIfPresent(String.self, forKey: .serverPath) ?? serverPath
        routerEnabled = try c.decodeIfPresent(Bool.self, forKey: .routerEnabled) ?? routerEnabled
        modelsDir = try c.decodeIfPresent(String.self, forKey: .modelsDir) ?? modelsDir
        modelsPresetPath = try c.decodeIfPresent(String.self, forKey: .modelsPresetPath) ?? modelsPresetPath
        modelPath = try c.decodeIfPresent(String.self, forKey: .modelPath) ?? modelPath
        modelAlias = try c.decodeIfPresent(String.self, forKey: .modelAlias) ?? modelAlias
        mmprojPath = try c.decodeIfPresent(String.self, forKey: .mmprojPath) ?? mmprojPath
        parallelSlots = try c.decodeIfPresent(Int.self, forKey: .parallelSlots)
        ubatchSize = try c.decodeIfPresent(Int.self, forKey: .ubatchSize)
        chatTemplate = try c.decodeIfPresent(String.self, forKey: .chatTemplate) ?? chatTemplate
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? apiKey
        autoloadModels = try c.decodeIfPresent(Bool.self, forKey: .autoloadModels) ?? autoloadModels
    }
}

// MARK: - ModelManagerCapabilities

/// Declares whether a local provider can reload in-place and which load-time
/// parameters it honors when applying a configuration change.
struct ModelManagerCapabilities: Sendable {
    /// True if the provider can unload + reload with new config without a server restart.
    var canReloadAtRuntime: Bool
    /// The subset of LoadParam values this provider actually honours.
    var supportedLoadParams: Set<LoadParam>
    /// True when the manager targets a router-style server that can serve multiple models.
    var supportsRouterMode: Bool = false
    /// True when the manager can ask the running server to load a model at runtime.
    var supportsRuntimeModelLoad: Bool = false
    /// True when the manager can ask the running server to unload a model at runtime.
    var supportsRuntimeModelUnload: Bool = false
}

// MARK: - LoadedModelInfo

enum LoadedModelExposure: String, Sendable {
    /// The model is confirmed loaded in the current runtime process.
    case runtimeLoaded
    /// The model is being served by the current provider instance, but the backend
    /// does not distinguish "loaded now" from "servable now" at the API layer.
    case serverExposed
    /// The model came from a broader provider catalog/listing fallback rather than
    /// a runtime-loaded view.
    case catalogFallback
}

struct LoadedModelInfo: Sendable {
    var modelID: String
    /// Config fields the provider reported - unknown fields are nil.
    var knownConfig: LocalModelConfig
    /// Best-effort truth classification for what this provider is actually reporting.
    var exposure: LoadedModelExposure = .serverExposed
}

// MARK: - RestartInstructions

/// Human-readable restart guidance returned by restart-only providers.
struct RestartInstructions: Sendable {
    /// Ready-to-paste shell command to restart the server with the new config.
    var shellCommand: String
    /// Optional config file snippet (Modelfile, YAML, etc.) to copy into place first.
    var configSnippet: String?
    /// Short explanation of why a restart is required and what the user should do.
    var explanation: String
}

// MARK: - ModelManagerError

/// Errors emitted by local model managers while inspecting or applying load-time config.
enum ModelManagerError: Error, Sendable {
    /// The provider cannot apply this config without a restart; use the supplied instructions.
    case requiresRestart(RestartInstructions)
    /// The provider endpoint or local process was unavailable.
    case providerUnavailable
    /// The reload attempt failed after the provider accepted the request.
    case reloadFailed(String)
    /// The provider does not support this parameter at all.
    case parameterNotSupported(LoadParam)
    /// The selected manager does not implement this operation.
    case unsupportedOperation(String)
}

// MARK: - LocalModelManagerProtocol

/// Abstracts provider-specific reload behavior for local models.
///
/// `capabilities.canReloadAtRuntime` splits providers into two buckets: those
/// that can apply edits in-place via `reload(modelID:config:)`, and those that
/// can only return `RestartInstructions` for a manual restart flow.
protocol LocalModelManagerProtocol: Sendable {
    nonisolated var providerID: String { get }
    nonisolated var capabilities: ModelManagerCapabilities { get }

    /// Returns the models the provider can currently account for, plus a best-effort
    /// `exposure` value describing whether they are truly loaded, merely exposed by
    /// the running server instance, or coming from a broader catalog fallback.
    func loadedModels() async throws -> [LoadedModelInfo]

    /// Unloads the model and reloads it with the given config. Only params in
    /// `capabilities.supportedLoadParams` are applied; others are silently ignored.
    /// Throws `ModelManagerError.requiresRestart` if `canReloadAtRuntime` is false.
    func reload(modelID: String, config: LocalModelConfig) async throws

    /// Returns human-readable restart instructions for providers that cannot reload
    /// at runtime. Returns nil for providers that can reload at runtime.
    nonisolated func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions?

    /// Checks the model's loaded context length and reloads with a larger context if
    /// `minimumTokens` exceeds what is currently loaded. Returns the model ID callers
    /// should use for the current request after any reload-side retagging.
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws -> String

    /// Returns the model ID Merlin should use after a successful reload. Most
    /// providers keep the same model identifier; managers that materialize a new
    /// runtime tag (for example, Ollama Modelfile variants) override this.
    nonisolated func reloadedModelID(afterApplying config: LocalModelConfig, to modelID: String) -> String

    /// Ensures the target model is loaded in the running process.
    func ensureModelLoaded(modelID: String) async throws

    /// Attempts to unload the target model from the running process.
    func unloadModel(modelID: String) async throws
}

extension LocalModelManagerProtocol {
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws -> String { modelID }
    func reloadedModelID(afterApplying config: LocalModelConfig, to modelID: String) -> String { modelID }
    func ensureModelLoaded(modelID: String) async throws {
        throw ModelManagerError.unsupportedOperation(
            "\(providerID) does not support runtime model load operations."
        )
    }

    func unloadModel(modelID: String) async throws {
        throw ModelManagerError.unsupportedOperation(
            "\(providerID) does not support runtime model unload operations."
        )
    }
}
