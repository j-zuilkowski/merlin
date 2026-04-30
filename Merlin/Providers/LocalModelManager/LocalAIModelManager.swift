import Foundation

/// LocalAI manager.
///
/// LocalAI cannot be reloaded safely at runtime in this phase, so the manager
/// reports restart-only instructions that point to a server restart after YAML
/// config edits.
final class LocalAIModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "localai"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads, .ropeFrequencyBase, .batchSize, .useMmap]
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
            throw ModelManagerError.reloadFailed("LocalAI restart instructions unavailable for \(modelID)")
        }
        throw ModelManagerError.requiresRestart(instructions)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(
            shellCommand: "sudo systemctl restart local-ai",
            configSnippet: yamlConfigSnippet(for: config),
            explanation: "LocalAI requires a server restart after editing its YAML configuration."
        )
    }

    private func yamlConfigSnippet(for config: LocalModelConfig) -> String? {
        var lines: [String] = []
        if let value = config.contextLength {
            lines.append("context_size: \(value)")
        }
        if let value = config.gpuLayers {
            lines.append("gpu_layers: \(value)")
        }
        if let value = config.cpuThreads {
            lines.append("threads: \(value)")
        }
        if let value = config.ropeFrequencyBase {
            lines.append("rope_frequency_base: \(value)")
        }
        if let value = config.batchSize {
            lines.append("batch_size: \(value)")
        }
        if let value = config.useMmap {
            lines.append("use_mmap: \(value)")
        }

        guard lines.isEmpty == false else {
            return nil
        }
        return lines.joined(separator: "\n")
    }
}
