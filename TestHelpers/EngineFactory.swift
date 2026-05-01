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
    return AgenticEngine(proProvider: pro, flashProvider: flash,
                         visionProvider: vision,
                         toolRouter: router, contextManager: ctx,
                         xcalibreClient: xcalibreClient)
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
