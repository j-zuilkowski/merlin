import Foundation

// MARK: - ProviderKind

enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case anthropic
}

// MARK: - ProviderConfig

struct ProviderConfig: Codable, Sendable, Identifiable {
    var id: String
    var displayName: String
    var baseURL: String
    var model: String
    var localModelManagerID: String?
    var isEnabled: Bool
    var isLocal: Bool
    var supportsThinking: Bool
    var supportsVision: Bool
    var kind: ProviderKind
    var systemPromptAddendum: String = ""

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case baseURL
        case model
        case localModelManagerID = "local_model_manager_id"
        case isEnabled
        case isLocal
        case supportsThinking
        case supportsVision
        case kind
        case systemPromptAddendum = "system_prompt_addendum"
    }

    init(
        id: String,
        displayName: String,
        baseURL: String,
        model: String,
        localModelManagerID: String? = nil,
        isEnabled: Bool,
        isLocal: Bool,
        supportsThinking: Bool,
        supportsVision: Bool,
        kind: ProviderKind,
        systemPromptAddendum: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.model = model
        self.localModelManagerID = localModelManagerID
        self.isEnabled = isEnabled
        self.isLocal = isLocal
        self.supportsThinking = supportsThinking
        self.supportsVision = supportsVision
        self.kind = kind
        self.systemPromptAddendum = systemPromptAddendum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
        localModelManagerID = try container.decodeIfPresent(String.self, forKey: .localModelManagerID)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isLocal = try container.decode(Bool.self, forKey: .isLocal)
        supportsThinking = try container.decode(Bool.self, forKey: .supportsThinking)
        supportsVision = try container.decode(Bool.self, forKey: .supportsVision)
        kind = try container.decode(ProviderKind.self, forKey: .kind)
        systemPromptAddendum = try container.decodeIfPresent(String.self, forKey: .systemPromptAddendum) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        if let localModelManagerID {
            try container.encode(localModelManagerID, forKey: .localModelManagerID)
        }
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isLocal, forKey: .isLocal)
        try container.encode(supportsThinking, forKey: .supportsThinking)
        try container.encode(supportsVision, forKey: .supportsVision)
        try container.encode(kind, forKey: .kind)
        if systemPromptAddendum.isEmpty == false {
            try container.encode(systemPromptAddendum, forKey: .systemPromptAddendum)
        }
    }
}

// MARK: - ProviderRegistry

@MainActor
final class ProviderRegistry: ObservableObject {

    @Published private(set) var providers: [ProviderConfig]
    @Published var activeProviderID: String {
        didSet { if oldValue != activeProviderID { persist() } }
    }
    @Published var availabilityByID: [String: Bool] = [:]
    @Published private(set) var modelsByProviderID: [String: [String]] = [:]
    @Published private(set) var keyedProviderIDs: Set<String> = []

    private var liveProviders: [String: any LLMProvider] = [:]
    private let persistURL: URL
    private let session: URLSession

    static var defaultPersistURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Merlin/providers.json")
    }

    init(persistURL: URL = ProviderRegistry.defaultPersistURL,
         session: URLSession = .shared,
         initialProviders: [ProviderConfig]? = nil) {
        self.persistURL = persistURL
        self.session = session
        if let initialProviders {
            providers = initialProviders
            activeProviderID = initialProviders.first?.id ?? "deepseek"
        } else if let loaded = Self.load(from: persistURL) {
            providers = loaded.providers
            activeProviderID = loaded.activeProviderID
        } else {
            providers = Self.defaultProviders
            activeProviderID = "deepseek"
        }
        keyedProviderIDs = Set(Self.loadKeys().keys)
        // Auto-enable any non-local provider that already has a key
        for id in keyedProviderIDs {
            if let i = providers.firstIndex(where: { $0.id == id && !$0.isLocal && !$0.isEnabled }) {
                providers[i].isEnabled = true
            }
        }
    }

    // MARK: Defaults

    static let defaultProviders: [ProviderConfig] = [
        ProviderConfig(id: "deepseek",
                       displayName: "DeepSeek",
                       baseURL: "https://api.deepseek.com/v1",
                       model: "deepseek-v4-flash",
                       isEnabled: true,
                       isLocal: false,
                       supportsThinking: true,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "openai",
                       displayName: "OpenAI",
                       baseURL: "https://api.openai.com/v1",
                       model: "gpt-4o",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: false,
                       supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "anthropic",
                       displayName: "Anthropic",
                       baseURL: "https://api.anthropic.com/v1",
                       model: "claude-opus-4-7",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: true,
                       supportsVision: true,
                       kind: .anthropic),
        ProviderConfig(id: "qwen",
                       displayName: "Qwen",
                       baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                       model: "qwen2.5-72b-instruct",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: false,
                       supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "openrouter",
                       displayName: "OpenRouter",
                       baseURL: "https://openrouter.ai/api/v1",
                       model: "openai/gpt-4o",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "ollama",
                       displayName: "Ollama",
                       baseURL: "http://localhost:11434/v1",
                       model: "llama3.3",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "lmstudio",
                       displayName: "LM Studio",
                       baseURL: "http://localhost:1234/v1",
                       model: "",
                       isEnabled: true,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "jan",
                       displayName: "Jan.ai",
                       baseURL: "http://localhost:1337/v1",
                       model: "",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "localai",
                       displayName: "LocalAI",
                       baseURL: "http://localhost:8080/v1",
                       model: "",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "mistralrs",
                       displayName: "Mistral.rs",
                       baseURL: "http://localhost:1234/v1",
                       model: "",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "vllm",
                       displayName: "vLLM",
                       baseURL: "http://localhost:8000/v1",
                       model: "",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
    ]

    // MARK: Static persistence helpers (used by MerlinCommands, which has no EnvironmentObject access)

    // Reads the currently enabled providers and active ID from disk without creating a full instance.
    // Falls back to defaultProviders if the file doesn't exist yet.
    static func persistedEnabledProviders() -> [ProviderConfig] {
        load(from: defaultPersistURL)?.providers.filter(\.isEnabled)
            ?? defaultProviders.filter(\.isEnabled)
    }

    static func persistedActiveProviderID() -> String {
        load(from: defaultPersistURL)?.activeProviderID ?? "deepseek"
    }

    // MARK: Computed

    var activeConfig: ProviderConfig? {
        providers.first { $0.id == activeProviderID && $0.isEnabled }
    }

    var primaryProvider: (any LLMProvider)? {
        guard let config = activeConfig else { return nil }
        return makeLLMProvider(for: config)
    }

    var visionProvider: (any LLMProvider)? {
        let candidate = providers.first { $0.isEnabled && $0.isLocal && $0.supportsVision }
            ?? providers.first { $0.isEnabled && $0.supportsVision }
        return candidate.map { makeLLMProvider(for: $0) }
    }

    func add(_ provider: any LLMProvider) {
        liveProviders[provider.id] = provider
    }

    func provider(for id: String) -> (any LLMProvider)? {
        if let live = liveProviders[id] {
            return live
        }
        guard let config = providers.first(where: { $0.id == id }) else {
            return nil
        }
        return makeLLMProvider(for: config)
    }

    // MARK: Mutation

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].isEnabled = enabled
        persist()
    }

    func updateBaseURL(_ url: String, for id: String) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].baseURL = url
        persist()
    }

    func updateModel(_ model: String, for id: String) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].model = model
        persist()
    }

    // MARK: Key Storage (~/.merlin/api-keys.json)

    private static var keysURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return URL(fileURLWithPath: "\(home)/.merlin/api-keys.json")
    }

    private static func loadKeys() -> [String: String] {
        guard let data = try? Data(contentsOf: keysURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func saveKeys(_ keys: [String: String]) {
        guard let data = try? JSONEncoder().encode(keys) else { return }
        let url = keysURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func setAPIKey(_ key: String, for id: String) {
        var keys = Self.loadKeys()
        keys[id] = key
        Self.saveKeys(keys)
        keyedProviderIDs.insert(id)
    }

    func readAPIKey(for id: String) -> String? {
        Self.loadKeys()[id]
    }

    // MARK: Factory

    func makeLLMProvider(for config: ProviderConfig) -> any LLMProvider {
        let apiKey: String? = config.isLocal ? nil : readAPIKey(for: config.id)
        guard let url = URL(string: config.baseURL) else {
            return OpenAICompatibleProvider(
                id: config.id,
                baseURL: URL(string: "http://localhost")!,
                apiKey: nil,
                modelID: config.model
            )
        }

        switch config.kind {
        case .openAICompatible:
            let modelID = config.model.isEmpty && config.id == "lmstudio"
                ? LMStudioProvider().model
                : config.model
            return OpenAICompatibleProvider(id: config.id, baseURL: url, apiKey: apiKey, modelID: modelID)
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey ?? "", modelID: config.model)
        }
    }

    // MARK: Dynamic model discovery / availability

    func fetchModels(for config: ProviderConfig) async -> [String] {
        guard config.isEnabled else { return [] }
        if config.kind == .anthropic {
            return await fetchAnthropicModels(config: config)
        }
        guard let url = URL(string: config.baseURL)?.appendingPathComponent("models") else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(config.id, forHTTPHeaderField: "X-Merlin-Provider-ID")
        if !config.isLocal, let key = readAPIKey(for: config.id), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            struct Model: Decodable { let id: String }
            struct Response: Decodable { let data: [Model] }
            return try JSONDecoder().decode(Response.self, from: data).data.map(\.id)
        } catch {
            return []
        }
    }

    private func fetchAnthropicModels(config: ProviderConfig) async -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(config.id, forHTTPHeaderField: "X-Merlin-Provider-ID")
        if let key = readAPIKey(for: config.id), !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicProvider.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            struct Model: Decodable { let id: String }
            struct Response: Decodable { let data: [Model] }
            return try JSONDecoder().decode(Response.self, from: data).data.map(\.id)
        } catch {
            return []
        }
    }

    func fetchAllModels() async {
        await withTaskGroup(of: (String, [String]).self) { group in
            for config in providers where config.isEnabled {
                group.addTask { [weak self] in
                    guard let self else { return (config.id, []) }
                    let models = await self.fetchModels(for: config)
                    return (config.id, models)
                }
            }
            for await (id, models) in group where !models.isEmpty {
                modelsByProviderID[id] = models
            }
        }
    }

    /// Probes availability and fetches the model list for every enabled local provider.
    /// Sets both `availabilityByID` and `modelsByProviderID`.
    func probeAndFetchModels() async {
        await withTaskGroup(of: (String, Bool, [String]).self) { group in
            for config in providers where config.isLocal && config.isEnabled {
                group.addTask { [weak self] in
                    guard let self else { return (config.id, false, []) }
                    let available: Bool
                    if let healthURL = URL(string: config.baseURL)?
                        .deletingLastPathComponent()
                        .appendingPathComponent("health") {
                        var request = URLRequest(url: healthURL)
                        request.timeoutInterval = 2
                        let status = (try? await self.session.data(for: request))
                            .flatMap { $0.1 as? HTTPURLResponse }?.statusCode
                        available = status.map { (200...299).contains($0) } ?? false
                    } else {
                        available = false
                    }
                    let models = available ? await self.fetchModels(for: config) : []
                    return (config.id, available, models)
                }
            }
            for await (id, available, models) in group {
                availabilityByID[id] = available
                if !models.isEmpty {
                    modelsByProviderID[id] = models
                }
            }
        }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var providers: [ProviderConfig]
        var activeProviderID: String
    }

    private static func load(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func persist() {
        let snapshot = Snapshot(providers: providers, activeProviderID: activeProviderID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: persistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: persistURL, options: .atomic)
    }
}
