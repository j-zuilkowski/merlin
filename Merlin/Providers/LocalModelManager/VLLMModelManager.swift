import Foundation

/// vLLM manager.
///
/// This provider is restart-only. The restart instruction uses the OpenAI
/// compatible API server entry point and maps supported `LoadParam` values to
/// the corresponding `python -m vllm.entrypoints.openai.api_server` flags.
final class VLLMModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "vllm"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers, .ropeFrequencyBase, .batchSize, .cacheTypeK]
    )

    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = normalizedOpenAICompatibleBaseURL(baseURL).appendingPathComponent("models")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }

        struct ModelEntry: Decodable { let id: String }
        struct Response: Decodable { let data: [ModelEntry] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.map { LoadedModelInfo(modelID: $0.id, knownConfig: LocalModelConfig()) }
    }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        guard let instructions = restartInstructions(modelID: modelID, config: config) else {
            throw ModelManagerError.reloadFailed("vLLM restart instructions unavailable for \(modelID)")
        }
        throw ModelManagerError.requiresRestart(instructions)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        let shellCommand = buildShellCommand(modelID: modelID, config: config)
        return RestartInstructions(
            shellCommand: shellCommand,
            configSnippet: nil,
            explanation: "vLLM reads these settings at server startup, so applying them requires a restart."
        )
    }

    private func buildShellCommand(modelID: String, config: LocalModelConfig) -> String {
        var parts = [
            "python -m vllm.entrypoints.openai.api_server",
            "--model", shellQuote(modelID)
        ]
        if let value = config.contextLength {
            parts += ["--max-model-len", "\(value)"]
        }
        if let value = config.gpuLayers {
            parts += ["--gpu-layers", "\(value)"]
        }
        if let value = config.ropeFrequencyBase {
            parts += ["--rope-frequency-base", "\(value)"]
        }
        if let value = config.batchSize {
            parts += ["--max-num-batched-tokens", "\(value)"]
        }
        if let value = config.cacheTypeK {
            parts += ["--kv-cache-dtype", shellQuote(value)]
        }
        return parts.joined(separator: " ")
    }
}
