import Foundation

// MARK: - ProviderKind

enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case anthropic
}

struct SlotPickerEntry: Identifiable, Equatable, Sendable {
    /// Plain provider ID or `"backendID:modelID"` for a virtual entry.
    let id: String
    let displayName: String
    /// `true` for virtual `"backendID:modelID"` entries derived from loaded local models.
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
    /// Per-provider output token cap sent as `max_tokens` in every request.
    /// When nil, falls back to the global `AppSettings.inferenceMaxTokens` or
    /// the UI-level `AppSettings.maxTokens` default (8 192).
    /// Set this to the model's documented maximum for long agentic tasks
    /// (e.g. 131_072 for DeepSeek V4, 16_384 for GPT-4o).
    var maxOutputTokens: Int?
    /// Input-token budget for the provider. When nil, the engine falls back to
    /// `ProviderBudget.conservative` (32 000 input / 4 096 reserved output).
    var budget: ProviderBudget?

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
        case maxOutputTokens = "max_output_tokens"
        case budget
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
        systemPromptAddendum: String = "",
        maxOutputTokens: Int? = nil,
        budget: ProviderBudget? = nil
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
        self.maxOutputTokens = maxOutputTokens
        self.budget = budget
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
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        budget = try container.decodeIfPresent(ProviderBudget.self, forKey: .budget)
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
        if let maxOutputTokens {
            try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
        }
        if let budget {
            try container.encode(budget, forKey: .budget)
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
    @Published private(set) var firstLaunchSetupCompleted: Bool = false

    private var liveProviders: [String: any LLMProvider] = [:]
    private var modelCacheByProviderID: [String: ModelListCacheEntry] = [:]
    private let persistURL: URL
    private let session: URLSession
    var modelListCacheTTL: TimeInterval = 10 * 60

    private struct ModelListCacheEntry: Codable {
        var models: [String]
        var fetchedAt: Date
    }

    nonisolated static var defaultPersistURL: URL {
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
            providers = Self.mergingMissingDefaults(into: loaded.providers)
            activeProviderID = loaded.activeProviderID
            firstLaunchSetupCompleted = loaded.firstLaunchSetupCompleted ?? false
            modelCacheByProviderID = loaded.modelCache ?? [:]
        } else {
            providers = Self.defaultProviders
            activeProviderID = "deepseek"
        }
        restoreFreshModelCache()
        // Populate keyedProviderIDs — any non-local provider with a stored key.
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
                       kind: .openAICompatible,
                       maxOutputTokens: 131_072,    // V4 supports 384K; 128K is a practical agentic cap
                       budget: ProviderBudget(maxInputTokens: 65_536, reservedOutputTokens: 8_192)),
        ProviderConfig(id: "openai",
                       displayName: "OpenAI",
                       baseURL: "https://api.openai.com/v1",
                       model: "gpt-4o",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: false,
                       supportsVision: true,
                       kind: .openAICompatible,
                       maxOutputTokens: 16_384,     // gpt-4o max output
                       budget: ProviderBudget(maxInputTokens: 128_000, reservedOutputTokens: 8_192)),
        ProviderConfig(id: "anthropic",
                       displayName: "Anthropic",
                       baseURL: "https://api.anthropic.com/v1",
                       model: "claude-opus-4-7",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: true,
                       supportsVision: true,
                       kind: .anthropic,
                       maxOutputTokens: 32_000,     // claude-opus-4 max output
                       budget: ProviderBudget(maxInputTokens: 200_000, reservedOutputTokens: 16_384)),
        ProviderConfig(id: "qwen",
                       displayName: "Qwen",
                       baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                       model: "qwen2.5-72b-instruct",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: false,
                       supportsVision: true,
                       kind: .openAICompatible,
                       maxOutputTokens: 8_192),     // qwen2.5 standard output
        ProviderConfig(id: "openrouter",
                       displayName: "OpenRouter",
                       baseURL: "https://openrouter.ai/api/v1",
                       model: "openai/gpt-4o",
                       isEnabled: false,
                       isLocal: false,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),    // nil — varies by routed model
        ProviderConfig(id: "ollama",
                       displayName: "Ollama",
                       baseURL: "http://localhost:11434/v1",
                       model: "",
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
                       supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "localai",
                       displayName: "LocalAI",
                       baseURL: "http://localhost:8080/v1",
                       model: "",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "mistralrs",
                       displayName: "Mistral.rs",
                       // Port 1235, not 1234 — LM Studio defaults to :1234 and the two
                       // would collide. mistralrs is invoked with `--port 1235` to match.
                       baseURL: "http://localhost:1235/v1",
                       model: "",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "vllm",
                       displayName: "vLLM-Metal",
                       baseURL: "http://localhost:8000/v1",
                       model: "",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "llamacpp",
                       displayName: "llama.cpp",
                       baseURL: "http://localhost:8081/v1",
                       model: "",
                       localModelManagerID: "llamacpp",
                       isEnabled: false,
                       isLocal: true,
                       supportsThinking: false,
                       supportsVision: true,
                       kind: .openAICompatible),
    ]

    private static func mergingMissingDefaults(into persisted: [ProviderConfig]) -> [ProviderConfig] {
        var merged = persisted
        let existingIDs = Set(persisted.map(\.id))
        for config in defaultProviders where existingIDs.contains(config.id) == false {
            merged.append(config)
        }
        return merged
    }

    // MARK: Static persistence helpers (used by MerlinCommands, which has no EnvironmentObject access)

    // Reads the currently enabled providers and active ID from disk without creating a full instance.
    // Falls back to defaultProviders if the file doesn't exist yet.
    static func persistedEnabledProviders() -> [ProviderConfig] {
        load(from: defaultPersistURL)?.providers.filter(\.isEnabled)
            ?? defaultProviders.filter(\.isEnabled)
    }

    nonisolated static func persistedBudget(for id: String) -> ProviderBudget? {
        persistedBudget(for: id, persistURL: defaultPersistURL)
    }

    nonisolated static func persistedBudget(for id: String, persistURL: URL) -> ProviderBudget? {
        load(from: persistURL)?.providers.first { $0.id == id }?.budget
    }

    nonisolated static func recordLearnedContextWindow(_ contextTokens: Int, for id: String) {
        recordLearnedContextWindow(contextTokens, for: id, persistURL: defaultPersistURL)
    }

    nonisolated static func recordLearnedContextWindow(
        _ contextTokens: Int,
        for id: String,
        persistURL: URL
    ) {
        guard var snapshot = load(from: persistURL),
              let index = snapshot.providers.firstIndex(where: { $0.id == id }) else { return }
        let existingReserved = snapshot.providers[index].budget?.reservedOutputTokens ?? 4_096
        let learned = ProviderBudget(
            maxInputTokens: contextTokens,
            reservedOutputTokens: existingReserved
        )
        // A learned context window must leave a positive usable input budget. LM Studio's
        // /api/v0/models reports loaded_context_length 0 for a model that is registered but
        // not yet fully loaded; persisting that writes a degenerate budget that overflows
        // every later preflight check and kills the run on its first request. Reject the
        // observation and keep whatever budget is already persisted.
        guard learned.usableInputTokens > 0 else { return }
        snapshot.providers[index].budget = learned
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: persistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: persistURL, options: .atomic)
    }

    static func persistedActiveProviderID() -> String {
        load(from: defaultPersistURL)?.activeProviderID ?? "deepseek"
    }

    // MARK: Computed

    var activeConfig: ProviderConfig? {
        guard let config = config(for: activeProviderID), config.isEnabled else { return nil }
        return config
    }

    var primaryProvider: (any LLMProvider)? {
        guard activeConfig != nil else { return nil }
        return provider(for: activeProviderID)
    }

    /// Providers ordered from largest usable input budget to smallest.
    /// Unconfigured providers still rank using the conservative default budget.
    func providersOrderedByBudget() -> [(id: String, budget: ProviderBudget)] {
        providers
            .map { config in
                (id: config.id, budget: config.budget ?? .conservative)
            }
            .sorted { lhs, rhs in
                let lhsUsable = lhs.budget.usableInputTokens
                let rhsUsable = rhs.budget.usableInputTokens
                if lhsUsable != rhsUsable {
                    return lhsUsable > rhsUsable
                }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
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
            let loadedModels = modelsByProviderID[config.id] ?? []
            let virtualEntries = loadedModels.sorted().map { model in
                let vid = "\(config.id):\(model)"
                let vname = "\(backendName) — \(model)"
                return SlotPickerEntry(id: vid, displayName: vname, isVirtual: true)
            }

            if config.isLocal && !loadedModels.isEmpty {
                virtual.append(contentsOf: virtualEntries)
            } else {
                plain.append(SlotPickerEntry(id: config.id, displayName: backendName, isVirtual: false))
                virtual.append(contentsOf: virtualEntries)
            }
        }

        return plain + virtual
    }

    func add(_ provider: any LLMProvider) {
        liveProviders[provider.id] = provider
    }

    /// Returns the `ProviderConfig` for a plain provider ID (not a virtual `"backend:model"` ID).
    func config(for id: String) -> ProviderConfig? {
        let baseID = id.contains(":") ? String(id.split(separator: ":", maxSplits: 1)[0]) : id
        return providers.first { $0.id == baseID }
    }

    func hasCredential(for id: String) -> Bool {
        guard let config = config(for: id), !config.isLocal else { return false }
        guard let apiKey = readAPIKey(for: config.id) else { return false }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func isReadyForUse(_ id: String) -> Bool {
        guard let config = config(for: id), config.isEnabled else { return false }

        if config.isLocal, availabilityByID[config.id] != true {
            return false
        }
        if !config.isLocal, !hasCredential(for: id) {
            return false
        }

        return hasUsableModelSelection(for: id)
    }

    func readyRemoteProviderIDs(excluding excludedID: String? = nil) -> [String] {
        providers
            .filter { !$0.isLocal && $0.id != excludedID && isReadyForUse($0.id) }
            .map(\.id)
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
            // A compound id (`backend:model`) must still authenticate: read the
            // backend's API key for non-local providers, exactly as makeLLMProvider
            // does. Passing `apiKey: nil` here built keyless remote providers — a
            // virtual/compound `deepseek:…` provider then 401'd ("Authentication
            // Fails"), which is what broke escalation routing to the reason slot.
            let apiKey = config.isLocal ? nil : readAPIKey(for: backendID)
            return OpenAICompatibleProvider(id: id, baseURL: url, apiKey: apiKey, modelID: modelID)
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

    private func hasUsableModelSelection(for id: String) -> Bool {
        if id.contains(":") {
            let parts = id.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return false }
            let backendID = String(parts[0])
            let modelID = String(parts[1])
            guard !modelID.isEmpty else { return false }
            if let knownModels = modelsByProviderID[backendID], !knownModels.isEmpty {
                return knownModels.contains(modelID)
            }
            return true
        }

        guard let config = providers.first(where: { $0.id == id }) else { return false }
        guard config.model.isEmpty == false else { return false }
        if let knownModels = modelsByProviderID[config.id], !knownModels.isEmpty {
            return knownModels.contains(config.model)
        }
        return true
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

    func updateMaxOutputTokens(_ tokens: Int?, for id: String) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].maxOutputTokens = tokens
        persist()
    }

    func updateBudget(_ budget: ProviderBudget?, for id: String) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].budget = budget
        persist()
    }

    func markFirstLaunchSetupCompleted() {
        firstLaunchSetupCompleted = true
        persist()
    }

    // MARK: Key Storage (Keychain)

    /// One-time migration: if `~/.merlin/api-keys.json` exists, copy each entry into
    /// the Keychain (skipping any that already have a Keychain entry), then delete the file.
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
        // Notify any other ProviderRegistry instances (e.g. Settings vs main window)
        // so they re-read from Keychain and update their keyedProviderIDs.
        NotificationCenter.default.post(name: .merlinProviderKeyDidChange, object: nil)
    }

    /// Re-reads all non-local providers from Keychain and refreshes keyedProviderIDs.
    /// Called when another registry instance writes a key via merlinProviderKeyDidChange.
    func refreshKeyedProviders() {
        keyedProviderIDs = Set(providers.filter { !$0.isLocal }
            .compactMap { KeychainManager.readAPIKey(for: $0.id) != nil ? $0.id : nil })
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
            // Remote providers get a dedicated URLSession so each provider has its
            // own HTTP/2 connection pool. Sharing URLSession.shared between the
            // planner (orchestrate slot) and the execute slot causes connection-reuse
            // conflicts on some servers (DeepSeek "governor" 401s).
            let session: URLSession = config.isLocal
                ? .shared
                : URLSession(configuration: .ephemeral)
            return OpenAICompatibleProvider(id: config.id, baseURL: url, apiKey: apiKey,
                                            modelID: config.model, session: session)
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey ?? "", modelID: config.model)
        }
    }

    // MARK: Dynamic model discovery / availability

    func fetchModels(for config: ProviderConfig, forceRefresh: Bool = false) async -> [String] {
        guard config.isEnabled else { return [] }
        if !forceRefresh, let cached = cachedModels(for: config.id) {
            return cached
        }
        if config.kind == .anthropic {
            let models = await fetchAnthropicModels(config: config)
            cache(models: models, for: config.id)
            return models
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
            let models = try JSONDecoder().decode(Response.self, from: data).data.map(\.id)
            cache(models: models, for: config.id)
            return models
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

    func fetchAllModels(includeRemote: Bool = true, providerIDs: Set<String>? = nil, forceRefresh: Bool = false) async {
        await withTaskGroup(of: (String, [String]).self) { group in
            for config in providers where config.isEnabled {
                if includeRemote == false, config.isLocal == false { continue }
                if let providerIDs, providerIDs.contains(config.id) == false { continue }
                group.addTask { [weak self] in
                    guard let self else { return (config.id, []) }
                    let models = await self.fetchModels(for: config, forceRefresh: forceRefresh)
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
    func probeAndFetchModels(providerIDs: Set<String>? = nil, forceRefresh: Bool = false) async {
        await withTaskGroup(of: (String, Bool, [String]).self) { group in
            for config in providers where config.isLocal && config.isEnabled {
                if let providerIDs, providerIDs.contains(config.id) == false { continue }
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
                    let models = available ? await self.fetchModels(for: config, forceRefresh: forceRefresh) : []
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

    private func cachedModels(for id: String) -> [String]? {
        guard let entry = modelCacheByProviderID[id],
              Date().timeIntervalSince(entry.fetchedAt) < modelListCacheTTL
        else { return nil }
        return entry.models
    }

    private func cache(models: [String], for id: String) {
        guard !models.isEmpty else { return }
        modelCacheByProviderID[id] = ModelListCacheEntry(models: models, fetchedAt: Date())
        modelsByProviderID[id] = models
        persist()
    }

    private func restoreFreshModelCache() {
        let fresh = modelCacheByProviderID.compactMapValues { entry -> [String]? in
            Date().timeIntervalSince(entry.fetchedAt) < modelListCacheTTL ? entry.models : nil
        }
        if !fresh.isEmpty {
            modelsByProviderID = fresh
        }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var providers: [ProviderConfig]
        var activeProviderID: String
        var firstLaunchSetupCompleted: Bool?
        var modelCache: [String: ModelListCacheEntry]?
    }

    nonisolated private static func load(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func persist() {
        let snapshot = Snapshot(
            providers: providers,
            activeProviderID: activeProviderID,
            firstLaunchSetupCompleted: firstLaunchSetupCompleted,
            modelCache: modelCacheByProviderID.isEmpty ? nil : modelCacheByProviderID
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: persistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: persistURL, options: .atomic)
    }
}
