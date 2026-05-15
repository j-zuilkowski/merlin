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
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("preflight-ok-telemetry-\(UUID().uuidString).jsonl")
            .path
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

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

        await TelemetryEmitter.shared.flushForTesting()
        let events = readTelemetryEvents(fromFile: tempPath)

        XCTAssertTrue(events.contains { $0["event"] as? String == "engine.preflight.ok" })
        XCTAssertFalse(events.contains { $0["event"] as? String == "engine.preflight.overflow" })
        XCTAssertFalse(events.contains { $0["event"] as? String == "engine.preflight.compacted" })
    }
}
