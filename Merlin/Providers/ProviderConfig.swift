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
    var isEnabled: Bool
    var isLocal: Bool
    var supportsThinking: Bool
    var supportsVision: Bool
    var kind: ProviderKind
}

// MARK: - ProviderRegistry

@MainActor
final class ProviderRegistry: ObservableObject {

    @Published private(set) var providers: [ProviderConfig]
    @Published var activeProviderID: String {
        didSet { if oldValue != activeProviderID { persist() } }
    }
    @Published var availabilityByID: [String: Bool] = [:]
    @Published private(set) var keyedProviderIDs: Set<String> = []

    private let persistURL: URL

    static var defaultPersistURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Merlin/providers.json")
    }

    init(persistURL: URL = ProviderRegistry.defaultPersistURL) {
        self.persistURL = persistURL
        if let loaded = Self.load(from: persistURL) {
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

    // MARK: Known model lists (static metadata — not persisted)

    static let knownModels: [String: [String]] = [
        "deepseek": ["deepseek-v4-flash", "deepseek-v4-pro"],
        "openai": ["gpt-4o", "gpt-4o-mini", "o1", "o1-mini", "o3", "o3-mini", "o4-mini"],
        "anthropic": ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"],
        "qwen": ["qwen2.5-72b-instruct", "qwen2.5-32b-instruct",
                 "qwen2.5-14b-instruct", "qwen2.5-7b-instruct", "qwq-32b"],
    ]

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

    // MARK: Availability

    func probeLocalProviders() async {
        for config in providers where config.isLocal && config.isEnabled {
            guard let healthURL = URL(string: config.baseURL)?
                .deletingLastPathComponent()
                .appendingPathComponent("health") else { continue }
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 2
            let available: Bool
            if let result = try? await URLSession.shared.data(for: request) {
                let response = result.1
                if let http = response as? HTTPURLResponse {
                    available = (200...299).contains(http.statusCode)
                } else {
                    available = false
                }
            } else {
                available = false
            }
            availabilityByID[config.id] = available
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
