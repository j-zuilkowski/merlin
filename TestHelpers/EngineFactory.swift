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
    return AgenticEngine(proProvider: pro, flashProvider: flash,
                         visionProvider: LMStudioProvider(),
                         toolRouter: router, contextManager: ctx,
                         xcalibreClient: xcalibreClient)
}
