import Foundation

// MARK: - LoadParam

enum LoadParam: String, Hashable, Sendable, CaseIterable {
    case contextLength
    case gpuLayers
    case cpuThreads
    case flashAttention
    case cacheTypeK
    case cacheTypeV
    case ropeFrequencyBase
    case batchSize
    case useMmap
    case useMlock
}

// MARK: - LocalModelConfig

/// Load-time configuration for a local model. All fields optional - nil means "don't change".
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

struct RestartInstructions: Sendable {
    /// Ready-to-paste shell command to restart the server with the new config.
    var shellCommand: String
    /// Optional config file snippet (Modelfile, YAML, etc.).
    var configSnippet: String?
    var explanation: String
}

// MARK: - ModelManagerError

enum ModelManagerError: Error, Sendable {
    case requiresRestart(RestartInstructions)
    case providerUnavailable
    case reloadFailed(String)
    case parameterNotSupported(LoadParam)
}

// MARK: - LocalModelManagerProtocol

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
}
