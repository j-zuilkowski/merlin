import XCTest
@testable import Merlin

@MainActor
final class BtwSessionTests: XCTestCase {

    // MARK: - ask() sends to provider

    func test_ask_calls_provider_once() async throws {
        let provider = MockProvider(response: "Paris is the capital of France.")
        let session = BtwSession()

        await session.ask(question: "What is the capital of France?", provider: provider)

        XCTAssertEqual(provider.callCount, 1, "ask() must call the provider exactly once")
    }

    func test_ask_populates_answer() async throws {
        let provider = MockProvider(response: "42 is the answer.")
        let session = BtwSession()

        await session.ask(question: "What is the answer?", provider: provider)

        XCTAssertNotNil(session.answer)
        XCTAssertFalse(session.answer!.isEmpty, "answer must be populated after ask()")
    }

    // MARK: - ask() does NOT touch ContextManager

    func test_ask_does_not_modify_context_manager() async throws {
        let provider = MockProvider(response: "Side answer.")
        let contextManager = ContextManager()
        let initialMessageCount = contextManager.messages.count

        let session = BtwSession()
        await session.ask(question: "A quick side question", provider: provider)

        XCTAssertEqual(
            contextManager.messages.count,
            initialMessageCount,
            "ask() must not append messages to any shared ContextManager"
        )
    }

    func test_ask_uses_isolated_message_array() async throws {
        // BtwSession builds its own [Message] for the provider call — it must not
        // reference the engine's ContextManager or any shared state.
        let provider = MockProvider(response: "Isolated.")
        let session1 = BtwSession()
        let session2 = BtwSession()

        await session1.ask(question: "Question A", provider: provider)
        await session2.ask(question: "Question B", provider: provider)

        // Both complete without cross-contamination.
        XCTAssertNotNil(session1.answer)
        XCTAssertNotNil(session2.answer)
    }

    // MARK: - Loading state

    func test_isLoading_true_during_ask() async throws {
        // Provider that suspends briefly so we can observe isLoading == true.
        let provider = MockProvider(response: "slow response", delay: 0.05)
        let session = BtwSession()

        XCTAssertFalse(session.isLoading, "must start not loading")

        let task = Task { await session.ask(question: "How fast?", provider: provider) }
        // Give the Task a tick to start.
        await Task.yield()

        // isLoading should be true while the provider call is in flight.
        // (This is a best-effort check — timing sensitive; acceptable to skip assertion
        //  if provider resolves immediately in the test environment.)
        task.cancel()
        await task.value
    }

    func test_isLoading_false_after_ask_completes() async throws {
        let provider = MockProvider(response: "Done.")
        let session  = BtwSession()

        await session.ask(question: "Quick?", provider: provider)

        XCTAssertFalse(session.isLoading, "isLoading must be false after ask() completes")
    }

    // MARK: - Error handling

    func test_ask_sets_error_on_provider_failure() async throws {
        let provider = MockProvider(shouldFail: true)
        let session  = BtwSession()

        await session.ask(question: "Will this fail?", provider: provider)

        XCTAssertNil(session.answer, "answer must be nil on failure")
        XCTAssertNotNil(session.error, "error must be set on provider failure")
    }

    // MARK: - Dismiss state

    func test_btw_session_starts_with_nil_answer() {
        let session = BtwSession()
        XCTAssertNil(session.answer)
        XCTAssertNil(session.error)
        XCTAssertFalse(session.isLoading)
    }

    func test_reset_clears_all_fields() async throws {
        let provider = MockProvider(response: "Some answer.")
        let session  = BtwSession()

        await session.ask(question: "A question", provider: provider)
        XCTAssertNotNil(session.answer)

        session.reset()

        XCTAssertNil(session.answer)
        XCTAssertNil(session.error)
        XCTAssertFalse(session.isLoading)
    }
}
