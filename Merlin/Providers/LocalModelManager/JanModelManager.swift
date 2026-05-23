import Foundation

/// Jan.ai local model manager.
///
/// Jan stores per-model configuration under `~/jan/models/<id>/model.json`,
/// but this manager talks to the OpenAI-compatible runtime endpoint and only
/// forwards the load-time fields Jan accepts at reload time.
/// `@unchecked Sendable` rationale: URLSession-backed REST client; mutable state confined to async tasks.
final class JanModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "jan"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads]
    )

    private let baseURL: URL
    private let janModelsDir: URL
    private let session: URLSession

    init(
        baseURL: URL,
        janModelsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("jan/models"),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.janModelsDir = janModelsDir
        self.session = session
    }

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = normalizedOpenAICompatibleBaseURL(baseURL).appendingPathComponent("models")
        let (data, response) = try await session.data(from: url)
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
        return decoded.data.map {
            LoadedModelInfo(modelID: $0.id, knownConfig: readKnownConfig(modelID: $0.id))
        }
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

        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Jan reload rejected for \(modelID)")
        }
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil
    }

    func ensureContextLength(modelID: String, minimumTokens: Int) async throws -> String {
        var config = readKnownConfig(modelID: modelID)
        let loaded = config.contextLength ?? 0
        guard loaded > 0, minimumTokens > loaded else { return modelID }
        config.contextLength = nextPowerOf2(minimumTokens)
        try await reload(modelID: modelID, config: config)
        return modelID
    }

    private func reloadPayload(for config: LocalModelConfig) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let value = config.contextLength { payload["contextLength"] = value }
        if let value = config.gpuLayers { payload["gpuLayers"] = value }
        if let value = config.cpuThreads { payload["cpuThreads"] = value }
        return payload
    }

    private func readKnownConfig(modelID: String) -> LocalModelConfig {
        let jsonURL = janModelsDir.appendingPathComponent(modelID).appendingPathComponent("model.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LocalModelConfig()
        }

        var config = LocalModelConfig()
        if let value = dict["ctx_len"] as? Int ?? dict["contextLength"] as? Int {
            config.contextLength = value
        }
        if let value = dict["ngl"] as? Int ?? dict["gpuLayers"] as? Int {
            config.gpuLayers = value
        }
        if let value = dict["cpu_threads"] as? Int ?? dict["cpuThreads"] as? Int {
            config.cpuThreads = value
        }
        return config
    }

    private func nextPowerOf2(_ n: Int) -> Int {
        guard n > 1 else { return 1 }
        var result = 1
        while result < n { result <<= 1 }
        return result
    }
}
