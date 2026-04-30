import Foundation

/// Manages model loading for LM Studio via its management REST API.
/// Falls back to the `lms` CLI for params not accepted by the REST API.
///
/// REST endpoints (same host as the chat completions server):
///   GET  /api/v1/models            - list loaded models
///   POST /api/v1/unload            - { "identifier": "<model>" }
///   POST /api/v1/load              - { "identifier": "<model>", "config": { ... } }
final class LMStudioModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "lmstudio"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [
            .contextLength, .gpuLayers, .cpuThreads,
            .flashAttention, .cacheTypeK, .cacheTypeV,
            .ropeFrequencyBase, .batchSize
        ]
    )

    private let baseURL: URL
    private let token: String?
    private let shell: any ShellRunnerProtocol

    init(baseURL: URL, token: String? = nil, shell: any ShellRunnerProtocol = ProcessShellRunner()) {
        self.baseURL = baseURL
        self.token = token
        self.shell = shell
    }

    // MARK: - loadedModels

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = baseURL.appendingPathComponent("api/v1/models")
        var request = URLRequest(url: url)
        applyAuth(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }

        struct ModelEntry: Decodable { var identifier: String }
        struct Response: Decodable { var data: [ModelEntry] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.map {
            LoadedModelInfo(modelID: $0.identifier, knownConfig: LocalModelConfig())
        }
    }

    // MARK: - reload

    func reload(modelID: String, config: LocalModelConfig) async throws {
        try await unload(modelID: modelID)

        do {
            try await loadViaREST(modelID: modelID, config: config)
        } catch {
            try await loadViaCLI(modelID: modelID, config: config)
        }
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil
    }

    // MARK: - Private helpers

    private func unload(modelID: String) async throws {
        let url = baseURL.appendingPathComponent("api/v1/unload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["identifier": modelID])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Unload failed for \(modelID)")
        }
    }

    private func loadViaREST(modelID: String, config: LocalModelConfig) async throws {
        let url = baseURL.appendingPathComponent("api/v1/load")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        applyAuth(&request)

        var configDict: [String: Any] = [:]
        if let value = config.contextLength { configDict["contextLength"] = value }
        if let value = config.gpuLayers { configDict["gpuLayers"] = value }
        if let value = config.cpuThreads { configDict["cpuThreads"] = value }
        if let value = config.flashAttention { configDict["flashAttention"] = value }
        if let value = config.cacheTypeK { configDict["cacheTypeK"] = value }
        if let value = config.cacheTypeV { configDict["cacheTypeV"] = value }
        if let value = config.ropeFrequencyBase { configDict["ropeFrequencyBase"] = value }
        if let value = config.batchSize { configDict["numBatch"] = value }

        let body: [String: Any] = ["identifier": modelID, "config": configDict]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("REST load rejected for \(modelID)")
        }
    }

    private func loadViaCLI(modelID: String, config: LocalModelConfig) async throws {
        var args = ["lms", "load", modelID]
        if let value = config.contextLength { args += ["--context-length", "\(value)"] }
        if let value = config.gpuLayers { args += ["--gpu-layers", "\(value)"] }
        if let value = config.cpuThreads { args += ["--cpu-threads", "\(value)"] }
        if let value = config.flashAttention { args += ["--flash-attention", value ? "on" : "off"] }
        if let value = config.batchSize { args += ["--num-batch", "\(value)"] }

        let result = await shell.run(command: args.joined(separator: " "))
        guard result.exitCode == 0 else {
            throw ModelManagerError.reloadFailed("lms CLI load failed: \(result.errorOutput)")
        }
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let token, token.isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
