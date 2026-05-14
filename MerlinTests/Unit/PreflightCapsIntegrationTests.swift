import XCTest
@testable import Merlin

@MainActor
final class PreflightCapsIntegrationTests: XCTestCase {

    private final class AllowAllPresenter: AuthPresenter {
        func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
            .allow
        }
    }

    private final class StubProvider: LLMProvider, @unchecked Sendable {
        let id: String
        let baseURL: URL = URL(string: "http://localhost")!

        init(id: String = "stub-provider") {
            self.id = id
        }

        func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(CompletionChunk(delta: .init(content: "ok"), finishReason: "stop"))
                continuation.finish()
            }
        }
    }

    private func makeEngine(provider: StubProvider = StubProvider()) -> AgenticEngine {
        let gate = AuthGate(memory: AuthMemory(storePath: "/dev/null"), presenter: AllowAllPresenter())
        let router = ToolRouter(authGate: gate)
        let engine = AgenticEngine(
            slotAssignments: [:],
            registry: nil,
            toolRouter: router,
            contextManager: ContextManager()
        )
        engine.setRegistryForTesting(provider: provider)
        return engine
    }

    func testPreflightOkAfterWorkingSetCapsApplied() async throws {
        let provider = StubProvider()
        let engine = makeEngine(provider: provider)

        // Inflate context with many tool exchanges
        for i in 0..<20 {
            let call = ToolCall(id: "tc\(i)", type: "function",
                                function: FunctionCall(name: "read_file", arguments: "{}"))
            engine.contextManager.append(
                Message(role: .assistant, content: .text(""),
                        toolCalls: [call], timestamp: Date())
            )
            engine.contextManager.append(
                Message(role: .tool,
                        content: .text(String(repeating: "z", count: 3_000)),
                        toolCallId: "tc\(i)", timestamp: Date())
            )
        }

        // applyWorkingSetCapsBeforeSend compacts the context to fit the budget
        await engine.applyWorkingSetCapsBeforeSend(provider: provider)

        let request = CompletionRequest(
            model: "test",
            messages: engine.contextManager.messagesForProvider()
        )
        let outcome = try await engine.preflightCheck(request: request, provider: provider)
        XCTAssertEqual(outcome, .ok,
                       "Pre-flight must return .ok after working-set caps applied")
    }
}
