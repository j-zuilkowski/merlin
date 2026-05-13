import XCTest
@testable import Merlin

final class ContextLengthRecoveryTests: XCTestCase {

    // MARK: - ProviderError.isContextLengthExceeded

    func test_isContextLengthExceeded_true_for_known_bodies() {
        let bodies = [
            "context_length_exceeded",
            "This model's maximum context length is 8192 tokens",
            "maximum context length exceeded",
            "input too long for context window",
            "prompt is too long: 9000 tokens, max is 8192",
        ]
        for body in bodies {
            let error = ProviderError.httpError(statusCode: 400, body: body, providerID: "test")
            XCTAssertTrue(
                error.isContextLengthExceeded,
                "expected isContextLengthExceeded for body: \(body)"
            )
        }
    }

    func test_isContextLengthExceeded_false_for_other_400s() {
        let bodies = [
            "invalid_api_key",
            "model not found",
            "bad request: missing field 'model'",
            "",
        ]
        for body in bodies {
            let error = ProviderError.httpError(statusCode: 400, body: body, providerID: "test")
            XCTAssertFalse(
                error.isContextLengthExceeded,
                "must not classify as context overflow: \(body)"
            )
        }
    }

    func test_isContextLengthExceeded_false_for_non_400() {
        let error500 = ProviderError.httpError(statusCode: 500, body: "context_length_exceeded", providerID: "test")
        XCTAssertFalse(error500.isContextLengthExceeded, "only 400 with matching body qualifies")

        let networkError = ProviderError.networkError(
            underlying: URLError(.timedOut),
            providerID: "test"
        )
        XCTAssertFalse(networkError.isContextLengthExceeded)
    }

    // MARK: - Engine retry after compaction

    func test_engine_compacts_and_retries_on_contextLengthExceeded() async throws {
        // Provider fails with context_length_exceeded on first call, succeeds on second.
        let provider = MockProvider(failFirstCallWith:
            ProviderError.httpError(statusCode: 400, body: "context_length_exceeded", providerID: "mock")
        )
        let engine = EngineFactory.makeEngine(provider: provider)

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "hello") {
            events.append(event)
        }

        // Engine must have called the provider at least twice (first fail, then retry).
        XCTAssertGreaterThanOrEqual(provider.callCount, 2, "must retry after compaction")

        // A systemNote about compaction must have been emitted.
        let notes = events.compactMap { if case .systemNote(let s) = $0 { return s } else { return nil } }
        XCTAssertTrue(
            notes.contains(where: { $0.lowercased().contains("compact") }),
            "must emit compaction note before retry; notes: \(notes)"
        )

        // Must not surface an error event to the caller.
        let errorEvents = events.filter { if case .error = $0 { return true } else { return false } }
        XCTAssertTrue(errorEvents.isEmpty, "context-length retry must not surface error; got: \(errorEvents)")
    }

    func test_engine_surfaces_error_if_retry_also_fails() async throws {
        // Both calls fail with context_length_exceeded — engine must eventually surface error.
        let provider = MockProvider(failAllCallsWith:
            ProviderError.httpError(statusCode: 400, body: "context_length_exceeded", providerID: "mock")
        )
        let engine = EngineFactory.makeEngine(provider: provider)

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "hello") {
            events.append(event)
        }

        let errorEvents = events.filter { if case .error = $0 { return true } else { return false } }
        XCTAssertFalse(errorEvents.isEmpty,
            "when retry also fails, engine must surface an error event")
    }
}
