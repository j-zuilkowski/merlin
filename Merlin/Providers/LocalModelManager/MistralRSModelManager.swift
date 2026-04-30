import Foundation

/// Mistral.rs manager.
///
/// This provider is restart-only in phase 126b. The manager surfaces a CLI
/// command that captures the load-time flags supported by the runtime.
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
            explanation: "Mistral.rs is configured at startup and requires a restart to apply load-time model parameters."
        )
    }

    private func buildShellCommand(modelID: String, config: LocalModelConfig) -> String {
        var parts = [
            "mistralrs-server",
            "--model", shellQuote(modelID)
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
