import Foundation

/// vLLM-Metal manager.
///
/// This provider is restart-only. The restart instruction uses the OpenAI
/// compatible API server entry point and maps supported `LoadParam` values to
/// the corresponding `python -m vllm.entrypoints.openai.api_server` flags.
/// `@unchecked Sendable` rationale: stateless restart-instruction generator; no mutable shared state.
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
            throw ModelManagerError.reloadFailed("vLLM-Metal restart instructions unavailable for \(modelID)")
        }
        throw ModelManagerError.requiresRestart(instructions)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        let shellCommand = buildShellCommand(modelID: modelID, config: config)
        return RestartInstructions(
            shellCommand: shellCommand,
            configSnippet: nil,
            explanation: "vLLM-Metal reads these settings at server startup, so applying them requires a restart. The defaults below match Merlin's documented native launch path."
        )
    }

    private func buildShellCommand(modelID: String, config: LocalModelConfig) -> String {
        let servedModelName = modelID.isEmpty ? "qwen3-coder-30b-a3b-instruct" : modelID
        var parts = [
            "VLLM=\"${VLLM:-$HOME/.venv-vllm-metal/bin/vllm}\"",
            "MODEL_DIR=\"${MODEL_DIR:-$HOME/.lmstudio/models/lmstudio-community/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit}\"",
            "SERVED_MODEL_NAME=\"${SERVED_MODEL_NAME:-\(servedModelName)}\"",
            "\"$VLLM\"",
            "serve",
            "\"$MODEL_DIR\"",
            "--served-model-name", "\"$SERVED_MODEL_NAME\"",
            "--port", "8000",
            "--enforce-eager",
            "--enable-auto-tool-choice",
            "--tool-call-parser", "qwen3_coder"
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
