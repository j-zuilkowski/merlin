import XCTest
@testable import Merlin

@MainActor
final class RunLoopNoRecursionTests: XCTestCase {

    func testContextOverflowRecoveryDoesNotEmitRestartingAttemptNote() async throws {
        let provider = MockProvider(
            failFirstCallWith: ProviderError.httpError(
                statusCode: 400,
                body: "request body too large",
                providerID: "mock"
            )
        )
        let engine = makeEngine(provider: provider)

        let events = await collectEvents(from: engine)
        let notes = events.compactMap { event -> String? in
            if case .systemNote(let text) = event { return text }
            return nil
        }

        XCTAssertFalse(
            notes.contains(where: { $0.lowercased().contains("restarting attempt") }),
            "Legacy recursive recovery note must be removed; notes: \(notes)"
        )
    }

    private func collectEvents(from engine: AgenticEngine) async -> [AgentEvent] {
        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "hello") {
            events.append(event)
        }
        return events
    }
}
