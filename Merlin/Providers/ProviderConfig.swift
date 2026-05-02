import Foundation

// MARK: - ProviderKind

enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case anthropic
}

/// A single selectable entry in the role-slot assignment picker.
struct SlotPickerEntry: Identifiable, Equatable, Sendable {
    /// The provider ID stored in `slotAssignments` — either a plain ID or `"backendID:modelID"`.
    let id: String
    /// Human-readable label shown in the picker.
    let displayName: String
    /// True for virtual `"backendID:modelID"` entries derived from loaded local models.
    let isVirtual: Bool
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
    @Published var modelsByProviderID: [String: [String]] = [:]
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
        // Populate keyedProviderIDs from Keychain — any non-local provider with a stored key.
        keyedProviderIDs = Set(providers.filter { !$0.isLocal }
            .compactMap { KeychainManager.readAPIKey(for: $0.id) != nil ? $0.id : nil })
        // Migrate any legacy keys from ~/.merlin/api-keys.json into Keychain, then delete the file.
        Self.migrateFileKeysToKeychain(knownProviderIDs: Set(providers.map(\.id)))
        // Re-check after migration
        keyedProviderIDs = Set(providers.filter { !$0.isLocal }
            .compactMap { KeychainManager.readAPIKey(for: $0.id) != nil ? $0.id : nil })
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
        if let live = liveProviders[config.id] { return live }
        return makeLLMProvider(for: config)
    }

    /// All entries that can be assigned to a role slot.
    /// Plain provider IDs come first (alphabetical by display name), followed by virtual
    /// entries grouped by backend and sorted by model name.
    var allSlotPickerEntries: [SlotPickerEntry] {
        var plain: [SlotPickerEntry] = []
        var virtual: [SlotPickerEntry] = []

        let enabled = providers.filter(\.isEnabled)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        for config in enabled {
            let backendName = config.displayName.isEmpty ? config.id : config.displayName
            plain.append(SlotPickerEntry(id: config.id, displayName: backendName, isVirtual: false))

            if let models = modelsByProviderID[config.id], !models.isEmpty {
                for model in models.sorted() {
                    let vid = "\(config.id):\(model)"
                    let vname = "\(backendName) — \(model)"
                    virtual.append(SlotPickerEntry(id: vid, displayName: vname, isVirtual: true))
                }
            }
        }

        return plain + virtual
    }

    func add(_ provider: any LLMProvider) {
        liveProviders[provider.id] = provider
    }

    func provider(for id: String) -> (any LLMProvider)? {
        if let live = liveProviders[id] { return live }

        if id.contains(":") {
            let parts = id.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let backendID = String(parts[0])
            let modelID = String(parts[1])
            guard let config = providers.first(where: { $0.id == backendID && $0.isEnabled }),
                  let url = URL(string: config.baseURL) else { return nil }
            return OpenAICompatibleProvider(id: id, baseURL: url, apiKey: nil, modelID: modelID)
        }

        guard let config = providers.first(where: { $0.id == id }) else { return nil }
        return makeLLMProvider(for: config)
    }

    /// Returns all addressable provider IDs for a given backend ID.
    /// For a local backend with loaded models these are the base ID plus
    /// one virtual ID per loaded model: `["lmstudio", "lmstudio:phi-4", ...]`.
    func virtualProviderIDs(for backendID: String) -> [String] {
        guard providers.contains(where: { $0.id == backendID }) else { return [] }
        let models = modelsByProviderID[backendID] ?? []
        return [backendID] + models.map { "\(backendID):\($0)" }
    }

    /// Human-readable label for any provider ID, including virtual ones.
    /// `"lmstudio:phi-4"` → `"LM Studio — phi-4"`
    func displayName(for id: String) -> String {
        if id.contains(":") {
            let parts = id.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return id }
            let backendID = String(parts[0])
            let modelID = String(parts[1])
            let backendName = providers.first(where: { $0.id == backendID })?.displayName ?? backendID
            return "\(backendName) — \(modelID)"
        }
        return providers.first(where: { $0.id == id })?.displayName ?? id
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

    // MARK: Key Storage (Keychain)

    /// One-time migration: if `~/.merlin/api-keys.json` exists, copy each entry into
    /// the Keychain (skipping any that already have a Keychain entry), then delete the file.
    private static func migrateFileKeysToKeychain(knownProviderIDs: Set<String>) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let url = URL(fileURLWithPath: "\(home)/.merlin/api-keys.json")
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        for (id, key) in dict where !key.isEmpty {
            // Only migrate keys for known providers; skip placeholder test values.
            guard knownProviderIDs.contains(id) || id == "deepseek" || id == "anthropic" else { continue }
            if KeychainManager.readAPIKey(for: id) == nil {
                try? KeychainManager.writeAPIKey(key, for: id)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// When non-nil, key reads and writes use this in-memory dict instead of the
    /// Keychain. Set this in test setUp to prevent tests from touching the Keychain.
    var apiKeysOverride: [String: String]? = nil

    func setAPIKey(_ key: String, for id: String) {
        if apiKeysOverride != nil {
            apiKeysOverride![id] = key
        } else {
            try? KeychainManager.writeAPIKey(key, for: id)
        }
        keyedProviderIDs.insert(id)
    }

    func readAPIKey(for id: String) -> String? {
        if let override = apiKeysOverride { return override[id] }
        return KeychainManager.readAPIKey(for: id)
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
            return OpenAICompatibleProvider(id: config.id, baseURL: url, apiKey: apiKey,
                                            modelID: config.model)
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
