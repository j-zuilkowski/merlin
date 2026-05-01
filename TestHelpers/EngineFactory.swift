import Foundation
@testable import Merlin

@MainActor
func makeEngine(provider: MockProvider? = nil,
                proProvider: MockProvider? = nil,
                flashProvider: MockProvider? = nil,
                xcalibreClient: (any XcalibreClientProtocol)? = nil) -> AgenticEngine {
    let memory = AuthMemory(storePath: "/dev/null")
    memory.addAllowPattern(tool: "*", pattern: "*")
    let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
    let router = ToolRouter(authGate: gate)
    let ctx = ContextManager()
    let pro = proProvider ?? provider ?? MockProvider(chunks: [])
    let flash = flashProvider ?? provider ?? MockProvider(chunks: [])
    let vision = provider ?? flash

    func makeConfig(for provider: any LLMProvider) -> ProviderConfig {
        ProviderConfig(
            id: provider.id,
            displayName: provider.id,
            baseURL: provider.baseURL.absoluteString,
            model: provider.id,
            isEnabled: true,
            isLocal: true,
            supportsThinking: true,
            supportsVision: true,
            kind: .openAICompatible
        )
    }

    var configsByID: [String: ProviderConfig] = [:]
    [pro, flash, vision].forEach { provider in
        configsByID[provider.id] = makeConfig(for: provider)
    }
    let registry = ProviderRegistry(
        persistURL: URL(fileURLWithPath: "/tmp/merlin-engine-factory-\(UUID().uuidString).json"),
        initialProviders: Array(configsByID.values)
    )
    registry.add(pro)
    registry.add(flash)
    registry.add(vision)
    registry.activeProviderID = pro.id

    return AgenticEngine(
        slotAssignments: [.execute: pro.id, .reason: flash.id, .vision: vision.id],
        registry: registry,
        toolRouter: router,
        contextManager: ctx,
        xcalibreClient: xcalibreClient
    )
}

enum EngineFactory {
    @MainActor
    static func make(provider: MockProvider? = nil,
                     proProvider: MockProvider? = nil,
                     flashProvider: MockProvider? = nil,
                     xcalibreClient: (any XcalibreClientProtocol)? = nil) -> AgenticEngine {
        makeEngine(
            provider: provider,
            proProvider: proProvider,
            flashProvider: flashProvider,
            xcalibreClient: xcalibreClient
        )
    }
}
