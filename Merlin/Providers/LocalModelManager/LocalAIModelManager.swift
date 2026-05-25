import Foundation

/// LocalAI manager.
///
/// LocalAI cannot be reloaded safely at runtime in this task, so the manager
/// reports restart-only instructions that point to a server restart after YAML
/// config edits.
/// `@unchecked Sendable` rationale: stateless restart-instruction generator; no mutable shared state.
final class LocalAIModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "localai"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads, .ropeFrequencyBase, .batchSize, .useMmap]
    )

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = normalizedOpenAICompatibleBaseURL(baseURL).appendingPathComponent("models")
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }

        struct ModelEntry: Decodable { let id: String }
        struct Response: Decodable { let data: [ModelEntry] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.map {
            LoadedModelInfo(modelID: $0.id, knownConfig: LocalModelConfig(), exposure: .serverExposed)
        }
    }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        guard let instructions = restartInstructions(modelID: modelID, config: config) else {
            throw ModelManagerError.reloadFailed("LocalAI restart instructions unavailable for \(modelID)")
        }
        throw ModelManagerError.requiresRestart(instructions)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(
            shellCommand: buildShellCommand(config: config),
            configSnippet: yamlConfigSnippet(for: config),
            explanation: "LocalAI runs as a native macOS process in this repo. Update the model YAML if needed, then relaunch it with the native command below."
        )
    }

    private func buildShellCommand(config: LocalModelConfig) -> String {
        let contextSize = config.contextLength ?? 32_768
        return [
            "LOCALAI_BACKENDS_PATH=\"$HOME/.localai/backends\"",
            "LOCALAI_MODELS_PATH=\"$HOME/.localai/models\"",
            "/opt/homebrew/bin/local-ai run",
            "--backends-path \"$HOME/.localai/backends\"",
            "--models-path \"$HOME/.localai/models\"",
            "--address \":8080\"",
            "--context-size \(contextSize)",
            "--f16"
        ].joined(separator: " ")
    }

    private func yamlConfigSnippet(for config: LocalModelConfig) -> String? {
        var lines: [String] = []
        // Emit the YAML snippet as simple `key: value` pairs that can be pasted into LocalAI's config.
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
