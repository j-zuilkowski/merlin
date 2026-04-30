import Foundation

/// Jan.ai local model manager.
///
/// Jan stores per-model configuration under `~/jan/models/<id>/model.json`,
/// but this manager talks to the OpenAI-compatible runtime endpoint and only
/// forwards the load-time fields Jan accepts at reload time.
final class JanModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "jan"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads]
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

        struct ModelEntry: Decodable {
            let id: String
        }

        struct Response: Decodable {
            let data: [ModelEntry]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.map { LoadedModelInfo(modelID: $0.id, knownConfig: LocalModelConfig()) }
    }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        let url = normalizedOpenAICompatibleBaseURL(baseURL)
            .appendingPathComponent("models")
            .appendingPathComponent(modelID)
            .appendingPathComponent("reload")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: reloadPayload(for: config))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Jan reload rejected for \(modelID)")
        }
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil
    }

    private func reloadPayload(for config: LocalModelConfig) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = config.contextLength { payload["contextLength"] = value }
        if let value = config.gpuLayers { payload["gpuLayers"] = value }
        if let value = config.cpuThreads { payload["cpuThreads"] = value }
        return payload
    }
}
