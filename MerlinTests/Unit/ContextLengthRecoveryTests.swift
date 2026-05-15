import XCTest
@testable import Merlin

@MainActor
final class ContextLengthRecoveryTests: XCTestCase {

    // MARK: - ProviderError.isContextLengthExceeded

    func test_isContextLengthExceeded_true_for_known_bodies() {
        let bodies = [
            "context_length_exceeded",
            "This model's maximum context length is 8192 tokens",
            "maximum context length exceeded",
            "input too long for context window",
            "prompt is too long: 9000 tokens, max is 8192",
            "request body too large",
            "payload too large",
            "request entity too large",
            "body size limit exceeded",
            "maximum request body size exceeded",
            "content length exceeded",
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
            ProviderError.httpError(statusCode: 400, body: "request body too large", providerID: "mock")
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

        let recoveryMessages = engine.contextManager.messages.filter {
            $0.role == .user && $0.content.plainText.contains("CONTEXT_OVERRUN_RECOVERY")
        }
        XCTAssertFalse(recoveryMessages.isEmpty, "must append a recovery directive to context")
        let recoveryText = recoveryMessages.map(\.content.plainText).joined(separator: "\n")
        XCTAssertTrue(recoveryText.lowercased().contains("continue from the interrupted task"))
        XCTAssertTrue(recoveryText.lowercased().contains("do not restart completed work"))

        // Must not surface an error event to the caller.
        let errorEvents = events.filter { if case .error = $0 { return true } else { return false } }
        XCTAssertTrue(errorEvents.isEmpty, "context-length retry must not surface error; got: \(errorEvents)")
    }

    func test_engine_bounds_retries_and_cleanStops_on_repeated_body_size_failures() async throws {
        // A provider that fails every call with a body-size 400. The engine must NOT
        // retry unboundedly — it must stop after a small finite number of attempts and
        // yield a terminal .cleanStop event (post-237 behaviour).
        let provider = MockProvider(failAllCallsWith:
            ProviderError.httpError(statusCode: 400, body: "maximum request body size exceeded", providerID: "mock")
        )
        let engine = EngineFactory.makeEngine(provider: provider)

        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: "hello") {
            events.append(event)
        }

        // Bounded: 199 calls is the bug. Any small finite cap proves the fix. The exact
        // count depends on planner refine calls; the contract is "finite and small".
        XCTAssertGreaterThanOrEqual(provider.callCount, 2,
            "engine must attempt at least one recovery retry")
        XCTAssertLessThanOrEqual(provider.callCount, 12,
            "repeated context-overrun must be bounded, not loop ~199 times; got \(provider.callCount)")

        // The turn must terminate with a clean stop.
        let cleanStops = events.compactMap { event -> String? in
            if case .cleanStop(let reason, _) = event { return reason }
            return nil
        }
        XCTAssertFalse(cleanStops.isEmpty,
            "repeated unrecoverable overrun must yield a .cleanStop terminal event")

        // A context-overrun system note must have surfaced.
        let notes = events.compactMap { event -> String? in
            if case .systemNote(let note) = event { return note }
            return nil
        }
        XCTAssertTrue(notes.contains(where: { $0.lowercased().contains("overrun") }),
            "must emit a context-overrun note; notes: \(notes)")
    }
}
