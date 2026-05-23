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
///   GET  /api/ps            - list running/loaded models
///   GET  /api/tags          - fallback when /api/ps is unavailable
///   POST /api/show          - { "name": "<model>" } -> model info including params
///   POST /api/create        - { "name": "<name>", "modelfile": "<content>" }
///   POST /api/generate      - { "model": "...", "keep_alive": 0 } -> force unload
/// `@unchecked Sendable` rationale: URLSession-backed REST client; mutable state confined to async tasks.
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
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - loadedModels

    func loadedModels() async throws -> [LoadedModelInfo] {
        if let running = try await loadModels(from: "api/ps", enrichKnownConfig: true), !running.isEmpty {
            return running
        }
        if let tags = try await loadModels(from: "api/tags", enrichKnownConfig: false) {
            return tags
        }
        throw ModelManagerError.providerUnavailable
    }

    nonisolated func reloadedModelID(afterApplying config: LocalModelConfig, to modelID: String) -> String {
        variantName(for: modelID)
    }

    // MARK: - reload

    func reload(modelID: String, config: LocalModelConfig) async throws {
        let variantName = variantName(for: modelID)
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

        let (_, createResponse) = try await session.data(for: request)
        guard (createResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Ollama model variant creation failed")
        }

        try await forceUnload(modelID: modelID)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil
    }

    func ensureContextLength(modelID: String, minimumTokens: Int) async throws -> String {
        var config = try await showModelConfig(modelID: modelID)
        let loaded = config.contextLength ?? 0
        guard loaded > 0, minimumTokens > loaded else { return modelID }
        config.contextLength = nextPowerOf2(minimumTokens)
        try await reload(modelID: modelID, config: config)
        return reloadedModelID(afterApplying: config, to: modelID)
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

    private func variantName(for modelID: String) -> String {
        modelID.hasSuffix("-merlin") ? modelID : "\(modelID)-merlin"
    }

    private func loadModels(from path: String, enrichKnownConfig: Bool) async throws -> [LoadedModelInfo]? {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            return nil
        }
        guard status == 200 else {
            return nil
        }

        struct ModelEntry: Decodable { var name: String }
        struct TagsResponse: Decodable { var models: [ModelEntry] }

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return await decoded.models.asyncMap { entry in
            let knownConfig = enrichKnownConfig ? ((try? await showModelConfig(modelID: entry.name)) ?? LocalModelConfig()) : LocalModelConfig()
            return LoadedModelInfo(modelID: entry.name, knownConfig: knownConfig)
        }
    }

    private func showModelConfig(modelID: String) async throws -> LocalModelConfig {
        let url = baseURL.appendingPathComponent("api/show")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": modelID])

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }

        struct ShowResponse: Decodable {
            let parameters: String?
        }

        let decoded = try JSONDecoder().decode(ShowResponse.self, from: data)
        return parseParameters(decoded.parameters ?? "")
    }

    private func parseParameters(_ text: String) -> LocalModelConfig {
        var config = LocalModelConfig()

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "num_ctx":
                config.contextLength = Int(value)
            case "num_gpu":
                config.gpuLayers = Int(value)
            case "num_thread":
                config.cpuThreads = Int(value)
            case "rope_frequency_base":
                config.ropeFrequencyBase = Double(value)
            case "num_batch":
                config.batchSize = Int(value)
            case "use_mmap":
                config.useMmap = parseBool(value)
            case "use_mlock":
                config.useMlock = parseBool(value)
            default:
                continue
            }
        }

        return config
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "on", "yes":
            return true
        case "0", "false", "off", "no":
            return false
        default:
            return nil
        }
    }

    private func nextPowerOf2(_ n: Int) -> Int {
        guard n > 1 else { return 1 }
        var result = 1
        while result < n { result <<= 1 }
        return result
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

        _ = try? await session.data(for: request)
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
