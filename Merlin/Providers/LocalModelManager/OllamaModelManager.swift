import Foundation

/// Ollama local model manager.
///
/// Strategy:
///   - Runtime "reload": generate a Modelfile variant that bakes in the new
///     load-time parameters, create the variant via POST /api/create, then
///     unload the old model.
///   - Request-time `options {}` are ignored here because this manager handles
///     persistent config through the Modelfile path instead.
///
/// Ollama REST endpoints:
///   GET  /api/tags          - list downloaded models
///   POST /api/show          - { "name": "<model>" } -> model info including params
///   POST /api/create        - { "name": "<name>", "modelfile": "<content>" }
///   POST /api/generate      - { "model": "...", "keep_alive": 0 } -> force unload
final class OllamaModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "ollama"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [
            .contextLength, .gpuLayers, .cpuThreads,
            .ropeFrequencyBase, .batchSize, .useMmap, .useMlock
        ]
    )
    // Ollama does not persist flashAttention in a Modelfile; that knob is request-time only.

    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - loadedModels

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }

        struct ModelEntry: Decodable { var name: String }
        struct TagsResponse: Decodable { var models: [ModelEntry] }

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map {
            LoadedModelInfo(modelID: $0.name, knownConfig: LocalModelConfig())
        }
    }

    // MARK: - reload

    func reload(modelID: String, config: LocalModelConfig) async throws {
        let variantName = "\(modelID)-merlin"
        let modelfile = buildModelfile(base: modelID, config: config)

        let createURL = baseURL.appendingPathComponent("api/create")
        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": variantName,
            "modelfile": modelfile
        ])

        let (_, createResponse) = try await URLSession.shared.data(for: request)
        guard (createResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Ollama model variant creation failed")
        }

        try await forceUnload(modelID: modelID)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil
    }

    // MARK: - Private helpers

    private func buildModelfile(base: String, config: LocalModelConfig) -> String {
        var lines = ["FROM \(base)"]
        // Ollama Modelfiles use one `PARAMETER <name> <value>` directive per persisted knob.
        if let value = config.contextLength { lines.append("PARAMETER num_ctx \(value)") }
        if let value = config.gpuLayers { lines.append("PARAMETER num_gpu \(value)") }
        if let value = config.cpuThreads { lines.append("PARAMETER num_thread \(value)") }
        if let value = config.ropeFrequencyBase { lines.append("PARAMETER rope_frequency_base \(value)") }
        if let value = config.batchSize { lines.append("PARAMETER num_batch \(value)") }
        if let value = config.useMmap { lines.append("PARAMETER use_mmap \(value)") }
        if let value = config.useMlock { lines.append("PARAMETER use_mlock \(value)") }
        return lines.joined(separator: "\n")
    }

    private func forceUnload(modelID: String) async throws {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "keep_alive": 0
        ])

        _ = try? await URLSession.shared.data(for: request)
    }
}
