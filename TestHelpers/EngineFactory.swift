import Foundation
@testable import Merlin

/// Top-level free function for tests that call `makeEngine(...)` directly.
@MainActor
func makeEngine(provider: MockProvider? = nil,
                proProvider: MockProvider? = nil,
                flashProvider: MockProvider? = nil,
                kagEngine: KAGEngine = .shared,
                xcalibreClient: (any XcalibreClientProtocol)? = nil) -> AgenticEngine {
    EngineFactory.make(
        provider: provider,
        proProvider: proProvider,
        flashProvider: flashProvider,
        kagEngine: kagEngine,
        xcalibreClient: xcalibreClient
    )
}

enum EngineFactory {
    /// Alias so existing call sites using `EngineFactory.makeEngine(...)` continue to work.
    @MainActor
    static func makeEngine(provider: MockProvider? = nil,
                           proProvider: MockProvider? = nil,
                           flashProvider: MockProvider? = nil,
                           xcalibreClient: (any XcalibreClientProtocol)? = nil) -> AgenticEngine {
        make(
            provider: provider,
            proProvider: proProvider,
            flashProvider: flashProvider,
            xcalibreClient: xcalibreClient
        )
    }

    /// Real implementation — all other helpers delegate here.
    @MainActor
    static func make(provider: MockProvider? = nil,
                     proProvider: MockProvider? = nil,
                     flashProvider: MockProvider? = nil,
                     kagEngine: KAGEngine = .shared,
                     xcalibreClient: (any XcalibreClientProtocol)? = nil) -> AgenticEngine {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let ctx = ContextManager()
        let pro = proProvider ?? provider ?? MockProvider(chunks: [])
        let flash = flashProvider ?? provider ?? MockProvider(chunks: [])
        let vision = provider ?? flash

        func makeConfig(for p: any LLMProvider) -> ProviderConfig {
            ProviderConfig(
                id: p.id,
                displayName: p.id,
                baseURL: p.baseURL.absoluteString,
                model: p.id,
                isEnabled: true,
                isLocal: true,
                supportsThinking: true,
                supportsVision: true,
                kind: .openAICompatible
            )
        }

        var configsByID: [String: ProviderConfig] = [:]
        [pro, flash, vision].forEach { p in configsByID[p.id] = makeConfig(for: p) }
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-engine-factory-\(UUID().uuidString).json"),
            initialProviders: Array(configsByID.values)
        )
        registry.add(pro)
        registry.add(flash)
        registry.add(vision)
        registry.activeProviderID = pro.id

        return AgenticEngine(
            slotAssignments: [.execute: flash.id, .reason: pro.id, .vision: vision.id],
            registry: registry,
            toolRouter: router,
            contextManager: ctx,
            xcalibreClient: xcalibreClient,
            kagEngine: kagEngine
        )
    }

    @MainActor
    static func make(sessionStore: SessionStore) -> AgenticEngine {
        let engine = make()
        engine.sessionStore = sessionStore
        return engine
    }

    /// Creates an engine with an injected ToolRouter for tool-dispatch tests.
    @MainActor
    static func make(toolRouter: ToolRouter) -> AgenticEngine {
        AgenticEngine(toolRouter: toolRouter, contextManager: ContextManager())
    }
}
