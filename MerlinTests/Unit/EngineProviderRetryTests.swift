import XCTest
@testable import Merlin

@MainActor
final class EngineProviderRetryTests: XCTestCase {

    private func events(from engine: AgenticEngine) async -> [AgentEvent] {
        var result: [AgentEvent] = []
        for await event in engine.send(userMessage: "ping") {
            result.append(event)
        }
        return result
    }

    // MARK: - tests

    /// One transient 503 → engine emits a "retrying" systemNote then succeeds.
    func test_engineEmitsSystemNote_andResumes_onSingleTransientError() async throws {
        let provider = MockProvider(chunks: [.assistant("hello")])
        provider.stubbedErrors = [
            ProviderError.httpError(statusCode: 503, body: "unavailable", providerID: "mock")
        ]
        let engine = makeEngine(provider: provider)

        let evts = await events(from: engine)

        let notes = evts.compactMap { if case .systemNote(let s) = $0 { return s } else { return nil } }
        XCTAssertTrue(notes.contains(where: { $0.contains("retrying") }),
                      "Expected a retry systemNote; got: \(notes)")

        let texts = evts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        XCTAssertTrue(texts.joined().contains("hello"),
                      "Expected success text after retry; got: \(texts)")
    }

    /// Non-retriable 401 → engine hard-fails immediately, no retry note.
    func test_engineHardFails_onNonRetriableError() async throws {
        let provider = MockProvider(chunks: [])
        provider.stubbedErrors = [
            ProviderError.httpError(statusCode: 401, body: "unauthorized", providerID: "mock")
        ]
        let engine = makeEngine(provider: provider)

        let evts = await events(from: engine)

        let errors = evts.compactMap { if case .error(let e) = $0 { return e } else { return nil } }
        XCTAssertFalse(errors.isEmpty, "Expected error event for 401")

        let retryNotes = evts.compactMap {
            if case .systemNote(let s) = $0, s.contains("retrying") { return s } else { return nil }
        }
        XCTAssertTrue(retryNotes.isEmpty, "Should not retry a 401; got notes: \(retryNotes)")
    }

    /// Max retries exhausted → engine hard-fails after emitting exactly 2 retry notes (3 attempts).
    func test_engineHardFails_afterMaxRetries() async throws {
        let err = ProviderError.httpError(statusCode: 503, body: "down", providerID: "mock")
        let provider = MockProvider(chunks: [])
        provider.stubbedErrors = [err, err, err]  // 3 failures — exceeds 3-attempt limit
        let engine = makeEngine(provider: provider)

        let evts = await events(from: engine)

        let errors = evts.compactMap { if case .error(let e) = $0 { return e } else { return nil } }
        XCTAssertFalse(errors.isEmpty, "Expected error event after max retries")

        let retryNotes = evts.compactMap {
            if case .systemNote(let s) = $0, s.contains("retrying") { return s } else { return nil }
        }
        XCTAssertEqual(retryNotes.count, 2,
                       "Expected exactly 2 retry notes (3-attempt loop); got: \(retryNotes)")
    }
}
