import Foundation

/// llama.cpp manager backed by one router-mode `llama-server` process.
/// The manager can discover models from `/models` or `/v1/models` and uses
/// runtime load/unload endpoints when router mode is available.
/// `@unchecked Sendable` rationale: immutable URL/runtime settings plus URLSession;
/// no mutable shared state is stored on the manager.
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
    private let runtimeSettings: LlamaCppRuntimeSettings

    init(
        baseURL: URL,
        runtimeSettings: LlamaCppRuntimeSettings = LlamaCppRuntimeSettings(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.runtimeSettings = runtimeSettings
        self.session = session
    }

    func loadedModels() async throws -> [LoadedModelInfo] {
        if let routerEntries = try await fetchRouterCatalog() {
            return routerEntries.map { entry in
                LoadedModelInfo(
                    modelID: entry.id,
                    knownConfig: entry.knownConfig,
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
        guard runtimeSettings.autoloadModels else { return }
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
        let command = runtimeSettings.routerEnabled
            ? routerLaunchCommand(config: config)
            : singleModelLaunchCommand(modelID: modelID, config: config)

        return RestartInstructions(
            shellCommand: command,
            configSnippet: runtimeSettings.routerEnabled ? routerPresetSnippet(modelID: modelID, config: config) : nil,
            explanation: runtimeSettings.routerEnabled
                ? "llama.cpp runtime load/unload requires one router-mode llama-server process on port 8081."
                : "This llama.cpp configuration is single-model mode. Restart llama-server to change the loaded model or load parameters."
        )
    }

    private struct RouterCatalogEntry: Decodable {
        var id: String
        var state: String?
        var status: Status?
        var legacyStatus: String?

        struct Status: Decodable {
            var value: String?
            var args: [String]?
        }

        enum CodingKeys: String, CodingKey {
            case id, state, status
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            state = try c.decodeIfPresent(String.self, forKey: .state)
            status = try c.decodeIfPresent(Status.self, forKey: .status)
            legacyStatus = try? c.decodeIfPresent(String.self, forKey: .status)
        }

        var isRuntimeLoaded: Bool {
            let value = (state ?? status?.value ?? legacyStatus ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return value == "loaded" || value == "active" || value == "sleeping"
        }

        var knownConfig: LocalModelConfig {
            var config = LocalModelConfig()
            guard let args = status?.args else { return config }
            for index in args.indices {
                let arg = args[index]
                let next = index + 1 < args.count ? args[index + 1] : nil
                switch arg {
                case "--ctx-size", "-c":
                    config.contextLength = next.flatMap(Int.init)
                case "--n-gpu-layers", "-ngl":
                    config.gpuLayers = next.flatMap(Int.init)
                case "--threads", "-t":
                    config.cpuThreads = next.flatMap(Int.init)
                case "--flash-attn", "-fa":
                    config.flashAttention = true
                case "--cache-type-k":
                    config.cacheTypeK = next
                case "--cache-type-v":
                    config.cacheTypeV = next
                case "--rope-freq-base":
                    config.ropeFrequencyBase = next.flatMap(Double.init)
                case "--batch-size", "-b":
                    config.batchSize = next.flatMap(Int.init)
                case "--ubatch-size", "-ub":
                    config.ubatchSize = next.flatMap(Int.init)
                case "--mmap":
                    config.useMmap = true
                case "--no-mmap":
                    config.useMmap = false
                case "--mlock":
                    config.useMlock = true
                default:
                    continue
                }
            }
            return config
        }
    }

    private struct RouterCatalogResponse: Decodable {
        var data: [RouterCatalogEntry]?
        var models: [RouterCatalogEntry]?

        var entries: [RouterCatalogEntry] {
            data ?? models ?? []
        }
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
        return try JSONDecoder().decode(RouterCatalogResponse.self, from: data).entries
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
        applyAuth(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": modelID])

        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("llama.cpp router endpoint rejected \(path) for \(modelID)")
        }
    }

    private func getIfSuccess(url: URL) async throws -> Data? {
        var request = URLRequest(url: url)
        applyAuth(to: &request)
        let (data, response) = try await session.data(for: request)
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

    private func applyAuth(to request: inout URLRequest) {
        guard !runtimeSettings.apiKey.isEmpty else { return }
        request.setValue("Bearer \(runtimeSettings.apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func routerLaunchCommand(config: LocalModelConfig) -> String {
        var parts = [
            "LLAMA_SERVER=\(shellQuote(runtimeSettings.serverPath))",
            "MODEL_DIR=\"${MODEL_DIR:-\(runtimeSettings.modelsDir)}\"",
            "PRESET_FILE=\"${PRESET_FILE:-\(runtimeSettings.modelsPresetPath)}\"",
            "\"$LLAMA_SERVER\"",
            "--host 127.0.0.1",
            "--port 8081",
            "--models-dir \"$MODEL_DIR\"",
            "--models-preset \"$PRESET_FILE\""
        ]
        appendCommonFlags(config: config, to: &parts)
        if let value = runtimeSettings.parallelSlots {
            parts.append("--parallel \(value)")
        }
        if let value = runtimeSettings.ubatchSize {
            parts.append("--ubatch-size \(value)")
        }
        if !runtimeSettings.chatTemplate.isEmpty {
            parts.append("--chat-template \(shellQuote(runtimeSettings.chatTemplate))")
        }
        if !runtimeSettings.autoloadModels {
            parts.append("--no-models-autoload")
        }
        return parts.joined(separator: " ")
    }

    private func singleModelLaunchCommand(modelID: String, config: LocalModelConfig) -> String {
        let model = runtimeSettings.modelPath.isEmpty ? modelID : runtimeSettings.modelPath
        var parts = [
            shellQuote(runtimeSettings.serverPath),
            "--host 127.0.0.1",
            "--port 8081",
            "--model \(shellQuote(model))"
        ]
        if !runtimeSettings.modelAlias.isEmpty {
            parts.append("--alias \(shellQuote(runtimeSettings.modelAlias))")
        }
        if !runtimeSettings.mmprojPath.isEmpty {
            parts.append("--mmproj \(shellQuote(runtimeSettings.mmprojPath))")
        }
        appendCommonFlags(config: config, to: &parts)
        return parts.joined(separator: " ")
    }

    private func appendCommonFlags(config: LocalModelConfig, to parts: inout [String]) {
        if let value = config.contextLength { parts.append("--ctx-size \(value)") }
        if let value = config.gpuLayers { parts.append("--n-gpu-layers \(value)") }
        if let value = config.cpuThreads { parts.append("--threads \(value)") }
        if config.flashAttention == true { parts.append("--flash-attn") }
        if let value = config.cacheTypeK { parts.append("--cache-type-k \(shellQuote(value))") }
        if let value = config.cacheTypeV { parts.append("--cache-type-v \(shellQuote(value))") }
        if let value = config.ropeFrequencyBase { parts.append("--rope-freq-base \(value)") }
        if let value = config.batchSize { parts.append("--batch-size \(value)") }
        if config.useMmap == true { parts.append("--mmap") }
        if config.useMmap == false { parts.append("--no-mmap") }
        if config.useMlock == true { parts.append("--mlock") }
    }

    private func routerPresetSnippet(modelID: String, config: LocalModelConfig) -> String {
        let sectionName = runtimeSettings.modelAlias.isEmpty ? modelID : runtimeSettings.modelAlias
        var lines = [
            "version = 1",
            "",
            "[*]"
        ]
        if let value = runtimeSettings.parallelSlots {
            lines.append("parallel = \(value)")
        }
        if let value = runtimeSettings.ubatchSize {
            lines.append("ubatch-size = \(value)")
        }
        if !runtimeSettings.chatTemplate.isEmpty {
            lines.append("chat-template = \(runtimeSettings.chatTemplate)")
        }
        lines.append(contentsOf: [
            "",
            "[\(sectionName)]",
            "model = \(runtimeSettings.modelPath.isEmpty ? "<path-to-\(modelID).gguf>" : runtimeSettings.modelPath)"
        ])
        if !runtimeSettings.mmprojPath.isEmpty {
            lines.append("mmproj = \(runtimeSettings.mmprojPath)")
        }
        if let value = config.contextLength { lines.append("c = \(value)") }
        if let value = config.gpuLayers { lines.append("n-gpu-layers = \(value)") }
        if let value = config.cpuThreads { lines.append("threads = \(value)") }
        if config.flashAttention == true { lines.append("flash-attn = on") }
        if let value = config.cacheTypeK { lines.append("cache-type-k = \(value)") }
        if let value = config.cacheTypeV { lines.append("cache-type-v = \(value)") }
        if let value = config.ropeFrequencyBase { lines.append("rope-freq-base = \(value)") }
        if let value = config.batchSize { lines.append("batch-size = \(value)") }
        if config.useMmap == true { lines.append("mmap = true") }
        if config.useMmap == false { lines.append("mmap = false") }
        if config.useMlock == true { lines.append("mlock = true") }
        return lines.joined(separator: "\n")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
        ubatchSize != nil ||
        useMmap != nil ||
        useMlock != nil
    }
}
