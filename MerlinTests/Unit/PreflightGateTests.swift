import Foundation
import XCTest
@testable import Merlin

@MainActor
final class PreflightGateTests: XCTestCase {

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

    func testOverflowCompactsThenThrowsPreflightOverflow() async throws {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

        let provider = StubProvider()
        let engine = makeEngine(provider: provider)
        for index in 0..<20 {
            engine.contextManager.append(
                Message(
                    role: .tool,
                    content: .text(String(repeating: "x", count: 3_500)),
                    toolCallId: "tc\(index)",
                    timestamp: Date()
                )
            )
        }

        let request = CompletionRequest(
            model: "test-model",
            messages: [
                Message(role: .user, content: .text(String(repeating: "y", count: 120_000)), timestamp: Date())
            ]
        )

        do {
            _ = try await engine.preflightCheck(request: request, provider: provider)
            XCTFail("Expected preflight to overflow")
        } catch let error as EngineError {
            switch error {
            case .preflightOverflow(let estimated, let budget):
                XCTAssertGreaterThan(estimated, budget)
            default:
                XCTFail("Expected preflightOverflow, got \(error)")
            }
        }

        XCTAssertTrue(recorder.events.contains { $0.event == "engine.preflight.overflow" })
    }
}
