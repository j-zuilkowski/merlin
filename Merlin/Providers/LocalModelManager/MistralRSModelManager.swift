import Foundation

/// Mistral.rs manager.
///
/// This provider is restart-only. The restart command maps each supported
/// `LoadParam` to the corresponding `mistralrs-server` CLI flag.
/// `@unchecked Sendable` rationale: stateless restart-instruction generator; no mutable shared state.
final class MistralRSModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "mistralrs"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads, .ropeFrequencyBase, .flashAttention, .batchSize]
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
            throw ModelManagerError.reloadFailed("Mistral.rs restart instructions unavailable for \(modelID)")
        }
        throw ModelManagerError.requiresRestart(instructions)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        let shellCommand = buildShellCommand(modelID: modelID, config: config)
        return RestartInstructions(
            shellCommand: shellCommand,
            configSnippet: nil,
            explanation: "Mistral.rs is configured at startup and requires a restart to apply load-time model parameters. The defaults below match Merlin's documented native launch path."
        )
    }

    private func buildShellCommand(modelID: String, config: LocalModelConfig) -> String {
        var parts = [
            "MISTRALRS=\"${MISTRALRS:-$HOME/.cargo/bin/mistralrs}\"",
            "HF_MODEL_ID=\"${HF_MODEL_ID:-Qwen/Qwen3-Coder-30B-A3B-Instruct}\"",
            "GGUF_PATH=\"${GGUF_PATH:-$HOME/Models/gguf/Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf}\"",
            "\"$MISTRALRS\"",
            "serve",
            "-p", "1235",
            "--model-id", "\"$HF_MODEL_ID\"",
            "--format", "gguf",
            "--quantized-file", "\"$GGUF_PATH\""
        ]
        if let value = config.contextLength {
            parts += ["--max-seq-len", "\(value)"]
        }
        if let value = config.gpuLayers {
            parts += ["--gpu-layers", "\(value)"]
        }
        if let value = config.cpuThreads {
            parts += ["--cpu-threads", "\(value)"]
        }
        if let value = config.ropeFrequencyBase {
            parts += ["--rope-frequency-base", "\(value)"]
        }
        if config.flashAttention == true {
            parts.append("--flash-attn")
        }
        if let value = config.batchSize {
            parts += ["--batch-size", "\(value)"]
        }
        return parts.joined(separator: " ")
    }
}
