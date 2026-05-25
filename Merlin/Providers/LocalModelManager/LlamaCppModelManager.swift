import Foundation

/// llama.cpp manager backed by one router-mode `llama-server` process.
/// The manager can discover models from `/models` or `/v1/models` and uses
/// runtime load/unload endpoints when router mode is available.
final class LlamaCppModelManager: LocalModelManagerProtocol, @unchecked Sendable {

    let providerID = "llamacpp"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [
            .contextLength,
            .gpuLayers,
            .cpuThreads,
            .flashAttention,
            .cacheTypeK,
            .cacheTypeV,
            .ropeFrequencyBase,
            .batchSize,
            .useMmap,
            .useMlock,
        ],
        supportsRouterMode: true,
        supportsRuntimeModelLoad: true,
        supportsRuntimeModelUnload: true
    )

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func loadedModels() async throws -> [LoadedModelInfo] {
        if let routerEntries = try await fetchRouterCatalog() {
            return routerEntries.map { entry in
                LoadedModelInfo(
                    modelID: entry.id,
                    knownConfig: LocalModelConfig(),
                    exposure: entry.isRuntimeLoaded ? .runtimeLoaded : .catalogFallback
                )
            }
        }

        if let openAIEntries = try await fetchOpenAIModelList() {
            return openAIEntries.map {
                LoadedModelInfo(modelID: $0, knownConfig: LocalModelConfig(), exposure: .catalogFallback)
            }
        }

        throw ModelManagerError.providerUnavailable
    }

    func ensureModelLoaded(modelID: String) async throws {
        if let routerEntries = try await fetchRouterCatalog() {
            if routerEntries.contains(where: { $0.id == modelID && $0.isRuntimeLoaded }) {
                return
            }
            try await postRouterMutation(path: "models/load", modelID: modelID)
            return
        }

        if let openAIEntries = try await fetchOpenAIModelList(), openAIEntries.contains(modelID) {
            if let instructions = restartInstructions(modelID: modelID, config: LocalModelConfig()) {
                throw ModelManagerError.requiresRestart(instructions)
            }
            throw ModelManagerError.providerUnavailable
        }

        throw ModelManagerError.providerUnavailable
    }

    func unloadModel(modelID: String) async throws {
        do {
            try await postRouterMutation(path: "models/unload", modelID: modelID)
            return
        } catch {
            if let openAIEntries = try await fetchOpenAIModelList(), openAIEntries.contains(modelID),
               let instructions = restartInstructions(modelID: modelID, config: LocalModelConfig()) {
                throw ModelManagerError.requiresRestart(instructions)
            }
            throw error
        }
    }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        if config.hasExplicitValues {
            if let instructions = restartInstructions(modelID: modelID, config: config) {
                throw ModelManagerError.requiresRestart(instructions)
            }
            throw ModelManagerError.providerUnavailable
        }
        try await ensureModelLoaded(modelID: modelID)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        let command = [
            "LLAMA_SERVER=\"/opt/homebrew/bin/llama-server\"",
            "MODEL_DIR=\"${MODEL_DIR:-$HOME/Models/gguf}\"",
            "PRESET_FILE=\"${PRESET_FILE:-$HOME/.config/llama.cpp/router-preset.ini}\"",
            "\"$LLAMA_SERVER\"",
            "--host 127.0.0.1",
            "--port 8081",
            "--models-dir \"$MODEL_DIR\"",
            "--models-preset \"$PRESET_FILE\""
        ].joined(separator: " ")

        return RestartInstructions(
            shellCommand: command,
            configSnippet: nil,
            explanation: "llama.cpp runtime load/unload requires router mode. Relaunch one router-mode llama-server process on port 8081."
        )
    }

    private struct RouterCatalogEntry: Decodable {
        var id: String
        var state: String?
        var status: String?

        var isRuntimeLoaded: Bool {
            let value = (state ?? status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return value == "loaded" || value == "active"
        }
    }

    private struct RouterCatalogResponse: Decodable {
        var models: [RouterCatalogEntry]
    }

    private struct OpenAIModelEntry: Decodable {
        var id: String
    }

    private struct OpenAIModelsResponse: Decodable {
        var data: [OpenAIModelEntry]
    }

    private func fetchRouterCatalog() async throws -> [RouterCatalogEntry]? {
        let url = routerRootURL().appendingPathComponent("models")
        guard let data = try await getIfSuccess(url: url) else { return nil }
        return try JSONDecoder().decode(RouterCatalogResponse.self, from: data).models
    }

    private func fetchOpenAIModelList() async throws -> [String]? {
        let url = routerRootURL().appendingPathComponent("v1/models")
        guard let data = try await getIfSuccess(url: url) else { return nil }
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map(\.id)
    }

    private func postRouterMutation(path: String, modelID: String) async throws {
        let url = routerRootURL().appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["id": modelID])

        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("llama.cpp router endpoint rejected \(path) for \(modelID)")
        }
    }

    private func getIfSuccess(url: URL) async throws -> Data? {
        let (data, response) = try await session.data(from: url)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw ModelManagerError.providerUnavailable
        }
        guard status == 200 else { return nil }
        return data
    }

    private func routerRootURL() -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        var path = components.path
        if path.hasSuffix("/v1") {
            path = String(path.dropLast(3))
        }
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }
        components.path = path
        return components.url ?? baseURL
    }
}

private extension LocalModelConfig {
    var hasExplicitValues: Bool {
        contextLength != nil ||
        gpuLayers != nil ||
        cpuThreads != nil ||
        flashAttention != nil ||
        cacheTypeK != nil ||
        cacheTypeV != nil ||
        ropeFrequencyBase != nil ||
        batchSize != nil ||
        useMmap != nil ||
        useMlock != nil
    }
}
