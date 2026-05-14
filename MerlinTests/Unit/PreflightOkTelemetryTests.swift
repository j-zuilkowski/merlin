import Foundation
import XCTest
@testable import Merlin

@MainActor
final class PreflightOkTelemetryTests: XCTestCase {

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

    func testWellBelowBudgetEmitsPreflightOk() async throws {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

        let provider = StubProvider()
        let engine = makeEngine(provider: provider)
        let request = CompletionRequest(
            model: "test-model",
            messages: [
                Message(role: .user, content: .text("hello"), timestamp: Date())
            ]
        )

        let outcome = try await engine.preflightCheck(request: request, provider: provider)
        XCTAssertEqual(outcome, .ok)
        XCTAssertTrue(recorder.events.contains { $0.event == "engine.preflight.ok" })
        XCTAssertFalse(recorder.events.contains { $0.event == "engine.preflight.overflow" })
        XCTAssertFalse(recorder.events.contains { $0.event == "engine.preflight.compacted" })
    }
}
