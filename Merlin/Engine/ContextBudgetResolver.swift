import Foundation

/// Reads/writes the durable per-provider context window. The production
/// implementation is backed by `ProviderConfig.budget` in `providers.json` - the
/// same field a manually entered budget uses.
protocol ContextBudgetStore: Sendable {
    func persistedContextTokens(for providerID: String) async -> Int?
    func persist(contextTokens: Int, for providerID: String) async
}

/// No-op store: returns nil, ignores writes. Default for callers/tests that do not
/// need persistence.
struct EphemeralBudgetStore: ContextBudgetStore {
    func persistedContextTokens(for providerID: String) async -> Int? { nil }
    func persist(contextTokens: Int, for providerID: String) async {}
}

struct PersistedProviderBudgetStore: ContextBudgetStore {
    func persistedContextTokens(for providerID: String) async -> Int? {
        ProviderRegistry.persistedBudget(for: baseID(providerID))?.maxInputTokens
    }

    func persist(contextTokens: Int, for providerID: String) async {
        ProviderRegistry.recordLearnedContextWindow(contextTokens, for: baseID(providerID))
    }

    private func baseID(_ providerID: String) -> String {
        providerID.split(separator: ":", maxSplits: 1).first.map(String.init) ?? providerID
    }
}

actor ContextBudgetResolver {
    static let shared = ContextBudgetResolver(
        store: PersistedProviderBudgetStore(),
        source: ContextBudgetResolver.productionSource
    )

    private struct CacheEntry: Sendable {
        var usableInputTokens: Int
        var resolvedAt: Date
    }

    private let reservedOutputTokens: Int
    private let conservativeContextTokens: Int
    private let ttl: TimeInterval
    private let store: any ContextBudgetStore
    private let source: @Sendable (any LLMProvider) async -> Int?
    private let floor = 2_000
    private var cache: [String: CacheEntry] = [:]

    init(reservedOutputTokens: Int = 4_096,
         conservativeContextTokens: Int = 32_000,
         ttl: TimeInterval = 300,
         store: any ContextBudgetStore = EphemeralBudgetStore(),
         source: @escaping @Sendable (any LLMProvider) async -> Int?) {
        self.reservedOutputTokens = reservedOutputTokens
        self.conservativeContextTokens = conservativeContextTokens
        self.ttl = ttl
        self.store = store
        self.source = source
    }

    func usableInputTokens(for provider: any LLMProvider) async -> Int {
        if ttl > 0,
           let cached = cache[provider.id],
           Date().timeIntervalSince(cached.resolvedAt) < ttl {
            return cached.usableInputTokens
        }

        let resolution = await resolveContextTokens(for: provider)
        let usable = usableInputTokens(contextTokens: resolution.contextTokens)
        cache[provider.id] = CacheEntry(usableInputTokens: usable, resolvedAt: Date())
        emitResolved(providerID: provider.id,
                     discovered: resolution.discovered,
                     usable: usable,
                     source: resolution.source)
        return usable
    }

    func recordObservedLimit(contextTokens: Int, for provider: any LLMProvider) async {
        await store.persist(contextTokens: contextTokens, for: provider.id)
        let usable = usableInputTokens(contextTokens: contextTokens)
        cache[provider.id] = CacheEntry(usableInputTokens: usable, resolvedAt: Date())
        TelemetryEmitter.shared.emit("engine.budget.learned", data: [
            "provider_id": provider.id,
            "context_tokens": contextTokens
        ])
    }

    private func resolveContextTokens(for provider: any LLMProvider) async -> (
        contextTokens: Int,
        discovered: Bool,
        source: String
    ) {
        if let discovered = await source(provider) {
            await store.persist(contextTokens: discovered, for: provider.id)
            return (discovered, true, sourceName(for: provider))
        }
        if let persisted = await store.persistedContextTokens(for: provider.id) {
            return (persisted, false, "store")
        }
        return (conservativeContextTokens, false, "fallback")
    }

    private func usableInputTokens(contextTokens: Int) -> Int {
        max(floor, contextTokens - reservedOutputTokens)
    }

    private func emitResolved(providerID: String, discovered: Bool, usable: Int, source: String) {
        TelemetryEmitter.shared.emit("engine.budget.resolved", data: [
            "provider_id": providerID,
            "discovered": discovered,
            "usable": usable,
            "source": source
        ])
    }

    private func sourceName(for provider: any LLMProvider) -> String {
        let id = provider.id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? provider.id
        return id == "openrouter" ? "openrouter" : "runner"
    }

    private static let productionSource: @Sendable (any LLMProvider) async -> Int? = { provider in
        let baseID = provider.id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? provider.id
        switch baseID {
        case "lmstudio":
            return await discoverLMStudioContext(provider: provider)
        case "ollama":
            return await discoverOllamaContext(provider: provider)
        case "openrouter":
            return await discoverOpenRouterContext(provider: provider)
        default:
            return nil
        }
    }

    private static func discoverLMStudioContext(provider: any LLMProvider) async -> Int? {
        let manager = LMStudioModelManager(baseURL: managementRoot(for: provider.baseURL))
        return try? await manager.loadedContextLength(modelID: provider.resolvedModelID)
    }

    private static func discoverOllamaContext(provider: any LLMProvider) async -> Int? {
        let root = managementRoot(for: provider.baseURL)
        let url = root.appendingPathComponent("api/show")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "name": provider.resolvedModelID
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct ShowResponse: Decodable {
                let modelInfo: [String: Int]?
                enum CodingKeys: String, CodingKey {
                    case modelInfo = "model_info"
                }
            }
            let decoded = try JSONDecoder().decode(ShowResponse.self, from: data)
            return decoded.modelInfo?["llama.context_length"]
                ?? decoded.modelInfo?["general.context_length"]
        } catch {
            return nil
        }
    }

    private static func discoverOpenRouterContext(provider: any LLMProvider) async -> Int? {
        let url = provider.baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            struct Model: Decodable {
                let id: String
                let contextLength: Int?
                enum CodingKeys: String, CodingKey {
                    case id
                    case contextLength = "context_length"
                }
            }
            struct ModelsResponse: Decodable {
                let data: [Model]
            }
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return decoded.data.first { $0.id == provider.resolvedModelID }?.contextLength
        } catch {
            return nil
        }
    }

    private static func managementRoot(for baseURL: URL) -> URL {
        baseURL.lastPathComponent == "v1" ? baseURL.deletingLastPathComponent() : baseURL
    }
}
