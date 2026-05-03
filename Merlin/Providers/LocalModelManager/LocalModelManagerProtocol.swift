import Foundation

// MARK: - LoadParam

/// Load-time parameters that can be edited for a local model provider.
enum LoadParam: String, Hashable, Sendable, CaseIterable {
    /// Context window size: LM Studio `contextLength`, Ollama `num_ctx`, Jan `contextLength`,
    /// LocalAI `context_size`, Mistral.rs `--max-seq-len`, vLLM `--max-model-len`.
    case contextLength
    /// GPU offload depth: LM Studio `gpuLayers`, Ollama `num_gpu`, Jan `gpuLayers`,
    /// LocalAI `gpu_layers`, Mistral.rs `--gpu-layers`, vLLM `--gpu-layers`.
    case gpuLayers
    /// CPU thread count: LM Studio `cpuThreads`, Ollama `num_thread`, Jan `cpuThreads`,
    /// LocalAI `threads`, Mistral.rs `--cpu-threads`.
    case cpuThreads
    /// Flash-attention toggle: LM Studio `flashAttention`, Mistral.rs `--flash-attn`.
    case flashAttention
    /// K-side KV cache type: LM Studio `cacheTypeK`, vLLM `--kv-cache-dtype`.
    case cacheTypeK
    /// V-side KV cache type: LM Studio `cacheTypeV`.
    case cacheTypeV
    /// RoPE frequency base: LM Studio `ropeFrequencyBase`, Ollama `rope_frequency_base`,
    /// LocalAI `rope_frequency_base`, Mistral.rs `--rope-frequency-base`,
    /// vLLM `--rope-frequency-base`.
    case ropeFrequencyBase
    /// Micro-batch size: LM Studio `numBatch`, Ollama `num_batch`, LocalAI `batch_size`,
    /// Mistral.rs `--batch-size`, vLLM `--max-num-batched-tokens`.
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

// MARK: - ModelManagerCapabilities

/// Declares whether a local provider can reload in-place and which load-time
/// parameters it honors when applying a configuration change.
struct ModelManagerCapabilities: Sendable {
    /// True if the provider can unload + reload with new config without a server restart.
    var canReloadAtRuntime: Bool
    /// The subset of LoadParam values this provider actually honours.
    var supportedLoadParams: Set<LoadParam>
}

// MARK: - LoadedModelInfo

struct LoadedModelInfo: Sendable {
    var modelID: String
    /// Config fields the provider reported - unknown fields are nil.
    var knownConfig: LocalModelConfig
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

    /// Returns currently loaded models with whatever config the provider reports.
    func loadedModels() async throws -> [LoadedModelInfo]

    /// Unloads the model and reloads it with the given config. Only params in
    /// `capabilities.supportedLoadParams` are applied; others are silently ignored.
    /// Throws `ModelManagerError.requiresRestart` if `canReloadAtRuntime` is false.
    func reload(modelID: String, config: LocalModelConfig) async throws

    /// Returns human-readable restart instructions for providers that cannot reload
    /// at runtime. Returns nil for providers that can reload at runtime.
    nonisolated func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions?

    /// Checks the model's loaded context length and reloads with a larger context if
    /// `minimumTokens` exceeds what is currently loaded. No-op for providers that do
    /// not support runtime context inspection.
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws
}

extension LocalModelManagerProtocol {
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws {}
}
